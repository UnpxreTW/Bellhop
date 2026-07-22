//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - WindowPosition

/// 單一視窗的排列位置，對應 macOS 15+ 原生「視窗 > 移動與調整大小」選單的單窗 11 項。
///
/// raw value 即 `window_arrange` 工具 `position` 參數的字串形。多窗排列組合
/// （左側與右側、四等分⋯）刻意不收：其語義綁著「接著選第二個視窗」的互動流程，
/// 單一 MCP 呼叫表達不順。
enum WindowPosition: String, CaseIterable {

	/// 填滿整個可用區域。
	case fill

	/// 置中（不改變視窗大小）。
	case center

	/// 佔左半邊。官方字面是「左側」、不是「左半部」。
	case left

	/// 佔右半邊。
	case right

	/// 佔上半邊。
	case top

	/// 佔下半邊。
	case bottom

	/// 佔左上四分之一。
	case topLeft = "top_left"

	/// 佔右上四分之一。
	case topRight = "top_right"

	/// 佔左下四分之一。
	case bottomLeft = "bottom_left"

	/// 佔右下四分之一。
	case bottomRight = "bottom_right"

	/// 返回上一個大小——原生選單附帶的免費 undo。
	case restorePrevious = "restore_previous"
}
