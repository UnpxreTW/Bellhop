//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - WindowMenuNames

/// 原生「移動與調整大小」選單的內建名稱表（zh-TW＋en）。
///
/// 選單項尋址的 L1 資料：AppKit / WindowManager 的本地化字串不在磁碟的傳統
/// lproj 裡，無法離線抽表，所以內建人工維護的雙語名稱表——**兩種語言都試、
/// 不假設系統語言**（單一語言字面比對曾在中文系統上整批 miss）。zh-TW 字面
/// 照 Apple 支援頁（mchl9674d0b0）官方用字；en 字面照英文系統選單、待實機
/// 覆驗。其他系統語言不擴表，直接走自算 frame 的 fallback 路徑。
enum WindowMenuNames {

	/// 選單列「視窗」選單的標題候選。
	static let windowMenuTitles: [String] = ["視窗", "Window"]

	/// 「移動與調整大小」子選單的標題候選。
	static let moveAndResizeTitles: [String] = ["移動與調整大小", "Move & Resize"]

	/// 指定排列位置對應的選單項標題候選（zh-TW 在前、en 在後）。
	static func itemTitles(for position: WindowPosition) -> [String] {
		titleTable[position] ?? []
	}

	/// 位置對選單項標題的內建表；覆蓋完整性由測試鎖住（表查免 switch、避免分支複雜度）。
	private static let titleTable: [WindowPosition: [String]] = [
		.fill: ["填滿", "Fill"],
		.center: ["置中", "Center"],
		.left: ["左側", "Left"],
		.right: ["右側", "Right"],
		.top: ["上方", "Top"],
		.bottom: ["下方", "Bottom"],
		.topLeft: ["左上角", "Top Left"],
		.topRight: ["右上角", "Top Right"],
		.bottomLeft: ["左下角", "Bottom Left"],
		.bottomRight: ["右下角", "Bottom Right"],
		.restorePrevious: ["返回上一個大小", "Return to Previous Size"]
	]
}
