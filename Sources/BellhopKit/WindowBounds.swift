//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - WindowBounds

/// Terminal 視窗的螢幕座標 bounds（AppleScript `bounds` 的 left / top / right / bottom 形）。
///
/// AppleScript 的 `bounds` 與 `kCGWindowBounds` 實測同源：皆為全域螢幕座標、
/// 左上原點、含標題列——所以可直接與 CG 視窗 frame 比對。
struct WindowBounds: Equatable {

	var width: Int { right - left }
	var height: Int { bottom - top }

	/// screencapture `-R` 參數用的 "x,y,width,height" 字串。
	var region: String { "\(left),\(top),\(width),\(height)" }

	let left: Int
	let top: Int
	let right: Int
	let bottom: Int

	/// 與 CG 視窗 frame（原點＋尺寸）是否在容差內相符。
	func matches(originX: Int, originY: Int, width matchWidth: Int, height matchHeight: Int, tolerance: Int = 2) -> Bool {
		abs(originX - left) <= tolerance && abs(originY - top) <= tolerance
			&& abs(matchWidth - width) <= tolerance && abs(matchHeight - height) <= tolerance
	}
}

// MARK: - + AppleScript 解析

extension WindowBounds {

	/// 從 AppleScript `get bounds` 輸出（如 `"8, 38, 1432, 892"`）解析；格式不符回 nil。
	init?(appleScriptBounds: String) {
		let parts = appleScriptBounds
			.split(separator: ",")
			.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
		guard parts.count == 4 else { return nil }
		self.init(left: parts[0], top: parts[1], right: parts[2], bottom: parts[3])
	}
}
