//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - WindowLayoutRestore

/// 還原具名 layout 的**純比對層**：篩選、分組、配對、算目標 frame，全程不碰 AX。
///
/// 抽成純函式的理由與 ``WindowActions`` 的 app／視窗比對函式同構——AX 呼叫
/// 需要實機 GUI session 與 Accessibility 授權、自動化測不到，但「哪筆記錄該
/// 配到哪個視窗、frame 要不要夾」這段判斷就是還原正確性的全部，必須可測。
enum WindowLayoutRestore {

	// MARK: Internal

	/// 一個 app 的還原分組（同一個 bundle id 的儲存記錄）。
	///
	/// 以 bundle id 分組而非視窗編號：`window_number` 重開機／重啟 app 後不
	/// 穩定（見 ``WindowRecord/windowNumber``），bundle id 才是跨 session 穩定
	/// 的 app 身分。
	struct Group: Equatable {

		/// 該組的 bundle identifier（分組 key）。
		let bundleID: String

		/// 組內的儲存記錄，維持 layout 檔中的順序——快照走 CGWindowList，
		/// 其順序即當時的 z-order（前景在先），順序配對倚賴這點。
		let records: [WindowRecord]
	}

	/// 還原計畫：能送進 AX 的分組，以及還沒動手就先排除掉的記錄。
	struct Plan: Equatable {

		/// 依 bundle id 分好、可嘗試還原的分組。
		let groups: [Group]

		/// 還原前就排除的記錄描述（含原因），直接併進回報的 skipped。
		let skipped: [String]
	}

	/// 配對方式。回報時要讓呼叫端分得出「照標題認出來的」與「照順序猜的」——
	/// 後者在標題不可讀（宿主未授 Screen Recording）或標題已變時是唯一路徑，
	/// 但也可能配錯，不該與前者混為一談。
	enum Pairing: Equatable {

		/// 標題完全相符。
		case byTitle

		/// 標題無從比對，照 z-order 順序配。
		case byOrder
	}

	/// 一筆配對結果。
	struct Match: Equatable {

		/// 配到的現存視窗索引。
		///
		/// - Important: 這是**呼叫端傳給 ``pair(saved:live:)`` 的 `live` 陣列**的
		///   索引；取元素時必須用同一份陣列。呼叫端若先過濾候選（例如剔掉最小化
		///   的視窗）就得同步過濾自己拿來取值的那份，否則索引會指到別的視窗。
		let liveIndex: Int

		/// 這筆是怎麼配上的。
		let pairing: Pairing
	}

	/// 從快照記錄組出還原計畫：擋掉搆不到與不合用的記錄，其餘依 bundle id 分組。
	///
	/// 三種還原前就排除的情形：
	/// - **快照當下不在畫面上**（`on_screen: false` ＝最小化或在別的 Space）。AX 只
	///   碰得到當前 Space、且刻意不展開最小化的視窗，硬要配只會讓它去搶別的視窗的
	///   名額——寧可明講搆不到。
	/// - **frame 數值不合用**（非正的寬高、或量級大到會讓幾何運算溢位）。layout 檔是
	///   使用者改得動的 JSON，極端值若一路帶到交集面積相乘會 trap、整個 server 跟著
	///   掛，所以擋在門口而非信任輸入。
	/// - **沒有 bundle id**（快照時該 app 已退出等原因查不到），無從回推該操作誰。
	static func plan(for records: [WindowRecord]) -> Plan {
		var order: [String] = []
		var buckets: [String: [WindowRecord]] = [:]
		var skipped: [String] = []
		for record in records {
			guard record.onScreen else {
				skipped.append("\(label(for: record)) — it was not on screen when the layout was saved")
				continue
			}
			guard isUsable(record.frame) else {
				skipped.append("\(label(for: record)) — its saved frame is out of usable range")
				continue
			}
			guard let bundleID = record.bundleID else {
				skipped.append("\(label(for: record)) — the snapshot has no bundle id for it")
				continue
			}
			if buckets[bundleID] == nil { order.append(bundleID) }
			buckets[bundleID, default: []].append(record)
		}
		let groups: [Group] = order.map { Group(bundleID: $0, records: buckets[$0] ?? []) }
		return Plan(groups: groups, skipped: skipped)
	}

	/// 把一組儲存標題配對到該 app 現存的視窗標題。
	///
	/// 兩輪：先以**標題完全相等**認人（一個現存視窗只能被認領一次），剩下的
	/// 再照**順序**配。「該 app 只有一個視窗」是順序輪的退化情形、不另立分支。
	/// 標題比對用完全相等而非子字串——還原是批次動作，子字串會讓「Untitled」
	/// 這類前綴標題互相竄位。
	///
	/// - Returns: 與 `saved` 等長；配不到（現存視窗數少於儲存記錄數，例如視窗
	///   在其他 Space 或已關閉）的位置為 nil。索引語義見 ``Match/liveIndex``。
	static func pair(saved: [String?], live: [String?]) -> [Match?] {
		var matches: [Match?] = .init(repeating: nil, count: saved.count)
		var claimed: Set<Int> = []
		for (savedIndex, savedTitle) in saved.enumerated() {
			guard let savedTitle, !savedTitle.isEmpty else { continue }
			let hit: Int? = live.indices.first { !claimed.contains($0) && live[$0] == savedTitle }
			guard let hit else { continue }
			claimed.insert(hit)
			matches[savedIndex] = Match(liveIndex: hit, pairing: .byTitle)
		}
		var remaining: [Int] = live.indices.filter { !claimed.contains($0) }
		for savedIndex in saved.indices where matches[savedIndex] == nil {
			guard !remaining.isEmpty else { break }
			matches[savedIndex] = Match(liveIndex: remaining.removeFirst(), pairing: .byOrder)
		}
		return matches
	}

	/// 算還原的目標 frame。
	///
	/// 螢幕組態與快照當時相同 → 照原值還原。不同 → 夾進交集面積最大的現有
	/// 螢幕（皆無交集就退第一個螢幕）並標註 `adjusted`，不默默假裝原樣還原。
	///
	/// - Note: 夾的界線走 `CGDisplayBounds` 全域 frame、不是 AppKit 的
	///   `visibleFrame`——與 `window_save_layout` 的螢幕列舉同一個理由：Bellhop
	///   是 client spawn 的 stdio process、沒有 NSApplication 生命週期，AppKit
	///   的螢幕查詢在此無行為保證。實務上影響有限：還原的座標是先前合法擺過的。
	static func targetFrame(
		for saved: WindowFrame,
		displays: [WindowFrame],
		clamp: Bool
	) -> (frame: WindowFrame, adjusted: Bool) {
		guard clamp, !displays.isEmpty else { return (saved, false) }
		let index: Int = WindowLayout.displayIndex(for: saved, in: displays) ?? 0
		return saved.clamped(into: displays[index])
	}

	/// 儲存記錄的人可讀標籤（回報訊息用）。
	///
	/// 標題經 ``sanitized(title:)`` 清洗：視窗標題的內容由該 app 開了什麼決定
	/// （網頁標題、文件名），等於外部可控字串，而回報是給 LLM 讀的散文。
	static func label(for record: WindowRecord) -> String {
		"\"\(sanitized(title: record.title) ?? "(untitled)")\" of \(sanitized(title: record.ownerName) ?? "?")"
	}

	// MARK: Private

	/// frame 座標與尺寸的合理上限。
	///
	/// 上限本身不精確、只要遠小於讓 `width * height` 溢位的量級即可（本值平方
	/// 仍在 `Int` 範圍內數個數量級之下），真正的目的是讓外部 JSON 進不了會 trap
	/// 的算式。
	private static let coordinateLimit: Int = 1_000_000

	/// 回報文字裡單一標題的長度上限（超出截斷）。
	private static let titleLimit: Int = 80

	/// frame 數值是否可用（寬高為正、量級在 ``coordinateLimit`` 內）。
	///
	/// - Note: 座標用上下界各比一次、**不寫 `abs(originX) <= limit`**——`abs(Int.min)`
	///   本身就會溢位 trap，那正是這個把關要防的事。
	private static func isUsable(_ frame: WindowFrame) -> Bool {
		guard frame.width > 0, frame.height > 0 else { return false }
		guard frame.width <= coordinateLimit, frame.height <= coordinateLimit else { return false }
		guard frame.originX >= -coordinateLimit, frame.originX <= coordinateLimit else { return false }
		return frame.originY >= -coordinateLimit && frame.originY <= coordinateLimit
	}

	/// 清洗要放進散文回報的外部字串：拿掉換行與分隔用的標點、過長截斷。
	///
	/// 回報是以 `; ` 與 `, ` 串成的條列句，標題若自帶這些字元或換行就能假造出
	/// 額外條目、把「跳過 N 個」的敘事結構弄假。空字串視為無標題（回 nil）。
	private static func sanitized(title: String?) -> String? {
		guard let title else { return nil }
		let cleaned: String = title
			.components(separatedBy: .controlCharacters).joined(separator: " ")
			.replacingOccurrences(of: ";", with: " ")
			.trimmingCharacters(in: .whitespaces)
		guard !cleaned.isEmpty else { return nil }
		guard cleaned.count > titleLimit else { return cleaned }
		return cleaned.prefix(titleLimit) + "…"
	}
}
