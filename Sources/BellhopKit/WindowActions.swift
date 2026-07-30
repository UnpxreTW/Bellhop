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

// MARK: - WindowActions

/// 動作面的 AX（Accessibility）整合層：聚焦、搬移任意 App 的視窗，以及把
/// 具名 layout 快照批次寫回（還原見 `WindowActionsRestore.swift`）。
///
/// 全程直呼 `AXUIElement` C API、零 osascript——只吃 macOS Accessibility
/// 一種權限（TCC 掛在 spawn Bellhop 的宿主 app 頭上，如 Terminal.app 或
/// Claude Desktop），不另吃 Automation。結構性限制：AX 只搆得到**當前
/// Space** 的視窗；螢幕鎖定下無作用（unlock-only、與 `screen_capture`
/// 同艙位）。所有阻塞的 AX 呼叫都落在 GCD 執行緒（同 ``Subprocess`` 的
/// 隔離原則），並對 app element 設 ``messagingTimeout``——目標 app 無回應
/// 時逾時返回、不無限卡住 server。
///
/// 純比對邏輯（app／視窗挑選）分在 `WindowActionsMatching.swift`：那段不碰
/// AX、可自動化測；AX 呼叫本身需要實機 GUI session 與授權、測不到。
enum WindowActions {

	// MARK: Internal

	/// `setFrame` 的落定結果。
	struct SetFrameOutcome: Equatable, Sendable {

		/// 實際操作到的 app 顯示名。
		let appName: String

		/// 實際操作到的視窗標題；無標題視窗為 nil。
		let windowTitle: String?

		/// 要求的目標 frame。
		let requested: WindowFrame

		/// 二次覆寫後回讀的實際 frame——app 可能強制最小尺寸或尺寸級距
		/// （如 Terminal 以行高為單位），以回讀值為準、不假裝命中。
		let final: WindowFrame
	}

	/// 對目標 app 的 AX messaging 逾時秒數——無回應的 app 不拖垮 server。
	static let messagingTimeout: Float = 3.0

	/// 聚焦視窗：最小化先展開 → `AXRaise` 喚起 → 把 app 設為最前景。
	///
	/// - Returns: 人可讀的成功訊息（實際命中的視窗標題與 app 名）。
	static func focus(appFilter: String, windowTitle: String?) async throws -> String {
		try await runBlocking { try focusSync(appFilter: appFilter, windowTitle: windowTitle) }
	}

	/// 把視窗搬移／調整到指定 frame（CG 全域左上座標）。
	///
	/// 寫入後回讀驗收；不符（WindowServer 在跨螢幕搬移後的下一輪 redraw
	/// 會把 frame 糾正回原螢幕合法位置）就再覆寫一次，以第二次回讀為準。
	static func setFrame(
		appFilter: String,
		windowTitle: String?,
		target: WindowFrame
	) async throws -> SetFrameOutcome {
		try await runBlocking { try setFrameSync(appFilter: appFilter, windowTitle: windowTitle, target: target) }
	}

	/// 把同步阻塞的 AX 流程隔離到 GCD 執行緒（不佔 Swift concurrency 合作池）。
	static func runBlocking<Value: Sendable>(
		_ work: @escaping @Sendable () throws -> Value
	) async throws -> Value {
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(with: Result { try work() })
			}
		}
	}

	/// 取 app 經 AX 可及的視窗清單（順序即 z-order、前景在先）。
	///
	/// AX 只看得到**當前 Space** 的視窗，其他 Space 的窗在此一律不存在——
	/// 跨 Space 要靠私有 API，不做。
	static func windowList(of appElement: AXUIElement, appName: String) throws -> [AXUIElement] {
		var value: CFTypeRef?
		let error: AXError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
		guard error == .success else {
			throw WindowActionError.axFailed("list windows of \(appName)", error)
		}
		let windows: [AXUIElement] = value as? [AXUIElement] ?? []
		// !!!: messaging timeout 是 per-element 設定、不隨 app element 繼承——
		// 視窗上的後續呼叫也要自己設，否則吃系統預設逾時。
		for window in windows { AXUIElementSetMessagingTimeout(window, messagingTimeout) }
		return windows
	}

	/// 讀視窗標題；讀不到（app 不給或逾時）回 nil。
	static func title(of window: AXUIElement) -> String? {
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
			return nil
		}
		return value as? String
	}

	/// 寫入 frame 後回讀驗收；不符就再覆寫一次，回傳第二次回讀的值。
	///
	/// 重寫一次的理由：WindowServer 在跨螢幕搬移後的下一輪 redraw 會把 frame
	/// 糾正回原螢幕的合法位置。回讀值可能仍與要求不同（app 強制最小尺寸或尺寸
	/// 級距），以回讀為準、不假裝命中。
	static func applyVerified(_ target: WindowFrame, to window: AXUIElement) throws -> WindowFrame {
		try apply(target, to: window)
		let settled: WindowFrame = try frame(of: window)
		guard settled != target else { return settled }
		try apply(target, to: window)
		return try frame(of: window)
	}

	/// 在暫時關掉目標 app `AXEnhancedUserInterface` 的狀態下寫入 frame（做完還原）。
	///
	/// 該屬性為 true 時輔助功能的動畫會干擾 set frame、造成回彈；業界標準解法就是
	/// 寫入前後夾一層開關。原本為 false 的 app 不動它。
	static func withEnhancedUISuppressed<Value>(
		on appElement: AXUIElement,
		_ work: () throws -> Value
	) rethrows -> Value {
		var enhanced: CFTypeRef?
		let suppress: Bool = AXUIElementCopyAttributeValue(
			appElement, enhancedUserInterfaceAttribute as CFString, &enhanced
		) == .success && enhanced as? Bool == true
		if suppress {
			try? setAttribute(
				enhancedUserInterfaceAttribute, kCFBooleanFalse, on: appElement,
				operation: "suspend enhanced UI"
			)
		}
		defer {
			if suppress {
				try? setAttribute(
					enhancedUserInterfaceAttribute, kCFBooleanTrue, on: appElement,
					operation: "restore enhanced UI"
				)
			}
		}
		return try work()
	}

	// MARK: Private

	/// `AXEnhancedUserInterface` 屬性名（無 SDK 常數）。目標 app 此屬性為
	/// true 時 set frame 會被輔助動畫干擾、產生回彈，業界標準解法是
	/// 設定前暫時關掉、設完還原。
	private static let enhancedUserInterfaceAttribute: String = "AXEnhancedUserInterface"

	private static func focusSync(appFilter: String, windowTitle: String?) throws -> String {
		let (appElement, appName) = try resolveApp(filter: appFilter)
		let (window, title) = try resolveWindow(in: appElement, appName: appName, title: windowTitle)
		var minimized: CFTypeRef?
		if
			AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
			minimized as? Bool == true {
			try setAttribute(
				kAXMinimizedAttribute, kCFBooleanFalse, on: window, operation: "unminimize the window"
			)
		}
		let raise: AXError = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
		guard raise == .success else { throw WindowActionError.axFailed("raise the window", raise) }
		try setAttribute(
			kAXFrontmostAttribute, kCFBooleanTrue, on: appElement, operation: "bring \(appName) to front"
		)
		return "Focused \"\(title ?? "(untitled)")\" of \(appName)."
	}

	private static func setFrameSync(
		appFilter: String,
		windowTitle: String?,
		target: WindowFrame
	) throws -> SetFrameOutcome {
		let (appElement, appName) = try resolveApp(filter: appFilter)
		let (window, title) = try resolveWindow(in: appElement, appName: appName, title: windowTitle)
		let final: WindowFrame = try withEnhancedUISuppressed(on: appElement) {
			try applyVerified(target, to: window)
		}
		return SetFrameOutcome(appName: appName, windowTitle: title, requested: target, final: final)
	}

	/// 解析 app 過濾字串成 AX app element（含 Accessibility 授權檢查）。
	private static func resolveApp(filter: String) throws -> (element: AXUIElement, name: String) {
		guard AXIsProcessTrusted() else { throw WindowActionError.notTrusted }
		let running: [NSRunningApplication] = NSWorkspace.shared.runningApplications
			.filter { $0.activationPolicy == .regular }
		let candidates: [AppCandidate] = running.map {
			AppCandidate(name: $0.localizedName, bundleID: $0.bundleIdentifier)
		}
		switch selectApp(from: candidates, filter: filter) {
		case .none:
			throw WindowActionError.appNotFound(filter)
		case let .ambiguous(described):
			throw WindowActionError.ambiguousApp(filter, described)
		case let .unique(index):
			let app: NSRunningApplication = running[index]
			let element: AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
			AXUIElementSetMessagingTimeout(element, messagingTimeout)
			let name: String = app.localizedName ?? app.bundleIdentifier ?? filter
			return (element, name)
		}
	}

	/// 解析目標視窗（主視窗排最前、標題比對見 ``selectWindow(titles:filter:)``）。
	private static func resolveWindow(
		in appElement: AXUIElement,
		appName: String,
		title filterTitle: String?
	) throws -> (window: AXUIElement, title: String?) {
		var windows: [AXUIElement] = try windowList(of: appElement, appName: appName)
		var main: CFTypeRef?
		if
			AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &main) == .success,
			let mainWindow = main,
			let index = windows.firstIndex(where: { CFEqual($0, mainWindow) }),
			index > 0 {
			let window: AXUIElement = windows.remove(at: index)
			windows.insert(window, at: 0)
		}
		let titles: [String?] = windows.map { title(of: $0) }
		switch selectWindow(titles: titles, filter: filterTitle) {
		case .none:
			throw WindowActionError.noWindows(appName)
		case let .titleNotFound(available):
			throw WindowActionError.windowTitleNotFound(filterTitle ?? "", appName, available)
		case let .unique(index):
			return (windows[index], titles[index])
		}
	}

	/// 讀回視窗當前 frame（AX position／size 原生即 CG 全域左上座標）。
	private static func frame(of window: AXUIElement) throws -> WindowFrame {
		var point: CGPoint = .zero
		var size: CGSize = .zero
		var rawPosition: CFTypeRef?
		var rawSize: CFTypeRef?
		guard
			AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition) == .success,
			AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawSize) == .success,
			let positionRaw = rawPosition, CFGetTypeID(positionRaw) == AXValueGetTypeID(),
			let sizeRaw = rawSize, CFGetTypeID(sizeRaw) == AXValueGetTypeID(),
			// !!!: CF 型別在 Swift 無條件式 downcast（編譯器視為恆成立）——上兩行以
			// CFGetTypeID 驗明實際型別後才 unsafeDowncast，非未檢查轉型。
			AXValueGetValue(unsafeDowncast(positionRaw, to: AXValue.self), .cgPoint, &point),
			AXValueGetValue(unsafeDowncast(sizeRaw, to: AXValue.self), .cgSize, &size)
		else { throw WindowActionError.axFailed("read the window frame back", .failure) }
		return WindowFrame(
			originX: Int(point.x.rounded()),
			originY: Int(point.y.rounded()),
			width: Int(size.width.rounded()),
			height: Int(size.height.rounded())
		)
	}

	/// 寫入 frame：先 position 再 size——先落位讓視窗歸屬目標螢幕、再調尺寸。
	private static func apply(_ target: WindowFrame, to window: AXUIElement) throws {
		var point: CGPoint = .init(x: CGFloat(target.originX), y: CGFloat(target.originY))
		var size: CGSize = .init(width: CGFloat(target.width), height: CGFloat(target.height))
		guard
			let positionValue = AXValueCreate(.cgPoint, &point),
			let sizeValue = AXValueCreate(.cgSize, &size)
		else { throw WindowActionError.axFailed("encode the target frame", .failure) }
		try setAttribute(kAXPositionAttribute, positionValue, on: window, operation: "set the window position")
		try setAttribute(kAXSizeAttribute, sizeValue, on: window, operation: "set the window size")
	}

	private static func setAttribute(
		_ attribute: String,
		_ value: CFTypeRef,
		on element: AXUIElement,
		operation: String
	) throws {
		let error: AXError = AXUIElementSetAttributeValue(element, attribute as CFString, value)
		guard error == .success else { throw WindowActionError.axFailed(operation, error) }
	}
}
