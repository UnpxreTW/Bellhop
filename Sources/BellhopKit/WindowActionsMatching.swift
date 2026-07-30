//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - + app／視窗挑選

/// 動作面的**純比對層**：從候選中挑出該操作哪個 app、哪個視窗。
///
/// 與 AX 呼叫分開放的理由：AX 需要實機 GUI session 與 Accessibility 授權、
/// 自動化測不到，但「使用者給的字串該對應到誰」這段判斷是誤操作的主要來源，
/// 必須可測。
extension WindowActions {

	/// app 候選（純比對形、AX 無關，供 ``selectApp(from:filter:)`` 測試）。
	struct AppCandidate: Equatable {

		/// app 顯示名（本地化值，中文系統上 Terminal 是「終端機」）。
		let name: String?

		/// bundle identifier。
		let bundleID: String?
	}

	/// app 比對結果。
	enum AppMatch: Equatable {

		/// 無任何候選命中。
		case none

		/// 唯一命中（候選索引）。
		case unique(Int)

		/// 多筆命中且無法以「完全相等」收斂（附候選描述清單）。
		case ambiguous([String])
	}

	/// 視窗比對結果。
	enum WindowMatch: Equatable {

		/// app 沒有任何可及視窗。
		case none

		/// 命中（視窗索引）。
		case unique(Int)

		/// 指定標題無命中（附可用標題清單）。
		case titleNotFound([String])
	}

	/// 以過濾字串挑唯一 app：不分大小寫子字串比對顯示名與 bundle id；
	/// 多筆命中時以「完全相等」收斂、仍多筆＝ambiguous。
	static func selectApp(from candidates: [AppCandidate], filter: String) -> AppMatch {
		let hits: [Int] = candidates.indices.filter { index in
			let candidate: AppCandidate = candidates[index]
			if candidate.name?.localizedCaseInsensitiveContains(filter) == true { return true }
			if candidate.bundleID?.localizedCaseInsensitiveContains(filter) == true { return true }
			return false
		}
		if hits.isEmpty { return .none }
		if hits.count == 1, let only = hits.first { return .unique(only) }
		let exact: [Int] = hits.filter { index in
			let candidate: AppCandidate = candidates[index]
			if candidate.name?.caseInsensitiveCompare(filter) == .orderedSame { return true }
			if candidate.bundleID?.caseInsensitiveCompare(filter) == .orderedSame { return true }
			return false
		}
		if exact.count == 1, let only = exact.first { return .unique(only) }
		let described: [String] = hits.map { index in
			let candidate: AppCandidate = candidates[index]
			return "\(candidate.name ?? "(unnamed)") (\(candidate.bundleID ?? "no bundle id"))"
		}
		return .ambiguous(described)
	}

	/// 以標題挑視窗：無標題參數＝取第一個（清單已把主視窗排最前）；
	/// 有標題＝不分大小寫子字串比對取第一個命中。
	static func selectWindow(titles: [String?], filter: String?) -> WindowMatch {
		guard !titles.isEmpty else { return .none }
		guard let filter, !filter.isEmpty else { return .unique(0) }
		if let index = titles.firstIndex(where: { $0?.localizedCaseInsensitiveContains(filter) == true }) {
			return .unique(index)
		}
		return .titleNotFound(titles.map { $0 ?? "(untitled)" })
	}
}
