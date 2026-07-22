//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - WindowRecord

/// 快照當下的一個視窗（`window_list` 輸出與 ``WindowLayout`` 的視窗記錄共用形）。
struct WindowRecord: Codable, Equatable {

	/// 擁有此視窗的 app bundle identifier；process 已退出等原因查不到時為 nil。
	let bundleID: String?

	/// 擁有此視窗的 app 顯示名。**本地化值**（中文系統上 Terminal 是「終端機」），
	/// 只供人讀、不當比對 key。
	let ownerName: String

	/// 視窗標題；宿主 app 未授 Screen Recording 權限時 CGWindowList 不給、為 nil。
	let title: String?

	/// 視窗 frame（CG 全域座標）。
	let frame: WindowFrame

	/// 快照當下是否在畫面上（`false` ＝最小化或位於其他 Space，CGWindowList 分不出是哪種）。
	let onScreen: Bool

	/// 是否最小化；CGWindowList 無法與「他 Space」區分，AX 整合前一律存 nil（未知）。
	let minimized: Bool?

	/// 視窗主要落在哪個螢幕（layout `displays` 的索引）；與所有螢幕皆無交集時為 nil。
	let displayIndex: Int?

	/// 快照當下的 CG window number。**僅 debug 附註**——重開機／重啟 app 後
	/// 不穩定，還原比對不用它。
	let windowNumber: Int?

	private enum CodingKeys: String, CodingKey {

		case bundleID = "bundle_id"
		case ownerName = "owner_name"
		case title
		case frame
		case onScreen = "on_screen"
		case minimized
		case displayIndex = "display_index"
		case windowNumber = "window_number"
	}
}
