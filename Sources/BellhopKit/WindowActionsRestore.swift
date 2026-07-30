//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import Foundation

// MARK: - + layout 還原

/// 把具名 layout 快照經 AX 寫回現存視窗。
///
/// 配對與夾邊界的判斷全在 ``WindowLayoutRestore``（純函式、可測）；本段只負責
/// 解析 app、取視窗、寫 frame，以及把「哪些沒還原成、為什麼」如實累加起來。
extension WindowActions {

	// MARK: Internal

	/// `restore` 的彙總結果。
	struct RestoreOutcome: Equatable, Sendable {

		/// 寫入後回讀確認落在目標 frame 的視窗數。
		let moved: Int

		/// 因標題無從比對而照 z-order 順序配對的視窗數——可能配錯，回報時要點出來。
		let matchedByOrder: Int

		/// 因螢幕組態與快照不同而被夾進現有螢幕的視窗描述。
		let adjusted: [String]

		/// 搬動了、但 app 把 frame 收斂到別的值（強制最小尺寸或尺寸級距）的描述。
		let settledElsewhere: [String]

		/// 未能還原的視窗描述（含原因）。
		let skipped: [String]
	}

	/// 還原一份 layout 快照：逐 app 分組把儲存的 frame 寫回對應視窗。
	///
	/// 只碰**當前 Space** 且**不展開最小化的視窗**——AX 的 `kAXWindowsAttribute`
	/// 看不到其他 Space 的視窗，而還原排列不該把使用者收起來的視窗掀開。這兩類
	/// 一律進 `skipped` 回報、不假裝還原成功。
	///
	/// 本呼叫是唯一會一次改動多個 app 視窗的動作，故支援取消：client 送
	/// `notifications/cancelled` 後不再繼續寫下一個視窗（已寫的不回捲）。
	///
	/// - Parameters:
	///   - groups: 依 bundle id 分好的儲存記錄（見 ``WindowLayoutRestore/plan(for:)``）。
	///   - displays: 現在的螢幕 frame，夾邊界用。
	///   - clampToDisplays: 螢幕組態與快照不同時傳 true——逐窗夾進現有螢幕並標註。
	static func restore(
		groups: [WindowLayoutRestore.Group],
		displays: [WindowFrame],
		clampToDisplays: Bool
	) async throws -> RestoreOutcome {
		let cancellation: CancellationFlag = .init()
		return try await withTaskCancellationHandler {
			try await runBlocking {
				try restoreSync(
					groups: groups, displays: displays,
					screensChanged: clampToDisplays, cancellation: cancellation
				)
			}
		} onCancel: {
			cancellation.cancel()
		}
	}

	// MARK: Private

	/// 跨隔離域的取消旗標。
	///
	/// AX 批次跑在 GCD 執行緒上，看不到 Swift concurrency 的取消狀態；由取消
	/// handler 翻旗、批次自己在每筆之間讀。`@unchecked Sendable` 的正當性來自
	/// 內部狀態全程由這把鎖保護。
	private final class CancellationFlag: @unchecked Sendable {

		/// 是否已被要求取消。
		var isCancelled: Bool {
			lock.withLock { cancelled }
		}

		/// 保護 ``cancelled`` 的鎖。
		private let lock: NSLock = .init()

		/// 取消狀態本體，只透過 ``lock`` 讀寫。
		private var cancelled: Bool = false

		/// 翻旗（取消 handler 呼叫，可能來自任意執行緒）。
		func cancel() {
			lock.withLock { cancelled = true }
		}
	}

	/// 還原的螢幕上下文——分組層與逐窗層都要用，打包成一個值傳。
	private struct Screens {

		/// 現在的螢幕 frame（夾邊界用）。
		let displays: [WindowFrame]

		/// 螢幕組態與快照不同、需逐窗夾進現有螢幕。
		let clamp: Bool
	}

	/// 還原過程的累加器（跨分組共用，最後收成 ``RestoreOutcome``）。
	private struct Tally {

		/// 回讀確認落在目標 frame 的視窗數。
		var moved: Int = 0

		/// 照 z-order 順序（非標題）配上的視窗數。
		var matchedByOrder: Int = 0

		/// 被夾進現有螢幕的視窗描述。
		var adjusted: [String] = []

		/// 搬了但 app 收斂到別的 frame 的描述。
		var settledElsewhere: [String] = []

		/// 未還原的視窗描述（含原因）。
		var skipped: [String] = []
	}

	/// 一個現存的候選視窗。
	///
	/// 連 app element 一起帶著：`AXEnhancedUserInterface` 這個開關掛在 app 上、
	/// 不在視窗上，寫 frame 前要拿得到它。
	private struct Candidate {

		/// 擁有此視窗的 app element。
		let appElement: AXUIElement

		/// 視窗元素本體。
		let window: AXUIElement

		/// 視窗標題（配對用）。
		let title: String?
	}

	private static func restoreSync(
		groups: [WindowLayoutRestore.Group],
		displays: [WindowFrame],
		screensChanged: Bool,
		cancellation: CancellationFlag
	) throws -> RestoreOutcome {
		guard AXIsProcessTrusted() else { throw WindowActionError.notTrusted }
		let running: [String: [NSRunningApplication]] = runningAppsByBundleID()
		let screens: Screens = .init(displays: displays, clamp: screensChanged)
		var tally: Tally = .init()
		for group in groups {
			guard !cancellation.isCancelled else {
				tally.skipped += group.records.map {
					"\(WindowLayoutRestore.label(for: $0)) — the request was cancelled"
				}
				continue
			}
			restore(group: group, in: running, screens: screens, into: &tally)
		}
		return RestoreOutcome(
			moved: tally.moved,
			matchedByOrder: tally.matchedByOrder,
			adjusted: tally.adjusted,
			settledElsewhere: tally.settledElsewhere,
			skipped: tally.skipped
		)
	}

	/// 執行中的 app 依 bundle id 索引；同一個 bundle id 開了多份就全收。
	///
	/// 不濾 `activationPolicy`：快照端（CGWindowList）只濾視窗層級、不看 app
	/// 類型，選單列常駐工具（`.accessory`）的設定視窗照樣會被存進 layout。這裡
	/// 若跟著 ``resolveApp(filter:)`` 濾 `.regular`，那些 app 就會被誤報成沒在跑。
	private static func runningAppsByBundleID() -> [String: [NSRunningApplication]] {
		var running: [String: [NSRunningApplication]] = [:]
		for app in NSWorkspace.shared.runningApplications {
			guard let bundleID = app.bundleIdentifier else { continue }
			running[bundleID, default: []].append(app)
		}
		return running
	}

	/// 還原單一 app 的分組；整組拿不到（app 沒跑、無候選視窗）就整組進 skipped。
	private static func restore(
		group: WindowLayoutRestore.Group,
		in running: [String: [NSRunningApplication]],
		screens: Screens,
		into tally: inout Tally
	) {
		let instances: [NSRunningApplication] = running[group.bundleID] ?? []
		guard !instances.isEmpty else {
			tally.skipped += group.records.map {
				"\(WindowLayoutRestore.label(for: $0)) — \(group.bundleID) is not running"
			}
			return
		}
		let candidates: [Candidate] = self.candidates(of: instances, appName: group.bundleID)
		guard !candidates.isEmpty else {
			tally.skipped += group.records.map {
				"""
				\(WindowLayoutRestore.label(for: $0)) — \(group.bundleID) has no window \
				available on the current Space (other Spaces are out of reach and \
				minimized windows are left alone)
				"""
			}
			return
		}
		let matches: [WindowLayoutRestore.Match?] = WindowLayoutRestore.pair(
			saved: group.records.map(\.title), live: candidates.map(\.title)
		)
		for (recordIndex, record) in group.records.enumerated() {
			restore(
				record: record, onto: matches[recordIndex], of: candidates,
				screens: screens, into: &tally
			)
		}
	}

	/// 收集該 bundle id 各實例可用的候選視窗——剔掉最小化的。
	///
	/// 最小化的視窗不當候選（而不只是不展開）：它照樣列在 AX 清單裡，留著就會在
	/// 順序配對時吃掉一個名額，讓本該還原的可見視窗被判成搆不到。
	private static func candidates(
		of instances: [NSRunningApplication],
		appName: String
	) -> [Candidate] {
		var candidates: [Candidate] = []
		for instance in instances {
			let appElement: AXUIElement = AXUIElementCreateApplication(instance.processIdentifier)
			AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
			let listed: [AXUIElement] = (try? windowList(of: appElement, appName: appName)) ?? []
			candidates += listed
				.filter { !isMinimized($0) }
				.map { Candidate(appElement: appElement, window: $0, title: title(of: $0)) }
		}
		return candidates
	}

	/// 視窗是否為最小化狀態；讀不到屬性時當作沒有最小化。
	private static func isMinimized(_ window: AXUIElement) -> Bool {
		var value: CFTypeRef?
		guard
			AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
		else { return false }
		return value as? Bool == true
	}

	/// 把單筆記錄寫回配到的視窗；配不到或 AX 寫入失敗就記進 skipped、繼續下一筆。
	private static func restore(
		record: WindowRecord,
		onto match: WindowLayoutRestore.Match?,
		of candidates: [Candidate],
		screens: Screens,
		into tally: inout Tally
	) {
		let label: String = WindowLayoutRestore.label(for: record)
		guard let match else {
			tally.skipped.append("\(label) — no window left to restore it onto on the current Space")
			return
		}
		let candidate: Candidate = candidates[match.liveIndex]
		let target: (frame: WindowFrame, adjusted: Bool) = WindowLayoutRestore.targetFrame(
			for: record.frame, displays: screens.displays, clamp: screens.clamp
		)
		let settled: WindowFrame
		do {
			// 逐窗開關 enhanced UI（而非整組一次）：同一個 bundle id 可能有多個
			// 實例，各自的 app element 不同，逐窗才保證抑制的是正確那一個。
			settled = try withEnhancedUISuppressed(on: candidate.appElement) {
				try applyVerified(target.frame, to: candidate.window)
			}
		} catch {
			tally.skipped.append("\(label) — \(error) (it may have been partially moved)")
			return
		}
		if match.pairing == .byOrder { tally.matchedByOrder += 1 }
		if target.adjusted { tally.adjusted.append(label) }
		guard settled == target.frame else {
			tally.settledElsewhere.append(label)
			return
		}
		tally.moved += 1
	}
}
