//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - WindowFrame

/// 螢幕座標系的矩形（CG 全域座標：左上原點、y 向下），JSON 形為 `x`／`y`／`width`／`height`。
///
/// 快照面（CGWindowList、CGDisplayBounds）原生就是這個座標系。AppKit 側的
/// rect（`NSScreen.frame`／`visibleFrame`）是左下原點、y 向上，進到這個
/// 座標系前須經 ``init(appKitFrame:primaryDisplayHeight:)`` 翻轉——自算
/// 排列位置的 fallback 路徑（靠 `visibleFrame` 幾何）會用到。
struct WindowFrame: Codable, Equatable {

	/// 左上角 x。
	let originX: Int

	/// 左上角 y（CG 座標、向下為正）。
	let originY: Int

	/// 寬。
	let width: Int

	/// 高。
	let height: Int

	private enum CodingKeys: String, CodingKey {

		case originX = "x"
		case originY = "y"
		case width
		case height
	}

	/// 直接以 CG 座標建立。
	init(originX: Int, originY: Int, width: Int, height: Int) {
		self.originX = originX
		self.originY = originY
		self.width = width
		self.height = height
	}

	/// 從 AppKit 座標（左下原點）換算成 CG 座標（左上原點）。
	///
	/// - Parameter primaryDisplayHeight: 主螢幕高度——AppKit 與 CG 兩座標系
	///   的 y 軸翻轉軸心。
	init(appKitFrame: CGRect, primaryDisplayHeight: CGFloat) {
		originX = Int(appKitFrame.origin.x.rounded())
		originY = Int((primaryDisplayHeight - appKitFrame.maxY).rounded())
		width = Int(appKitFrame.width.rounded())
		height = Int(appKitFrame.height.rounded())
	}

	/// 與另一矩形的交集面積（無交集回 0）。
	func intersectionArea(with other: WindowFrame) -> Int {
		let overlapWidth: Int = min(originX + width, other.originX + other.width) - max(originX, other.originX)
		let overlapHeight: Int =
			min(originY + height, other.originY + other.height) - max(originY, other.originY)
		guard overlapWidth > 0, overlapHeight > 0 else { return 0 }
		return overlapWidth * overlapHeight
	}

	/// 把矩形夾進指定可視範圍：尺寸縮到塞得下、原點平移到不出界。
	///
	/// display 指紋不符時的 best-effort 策略——夾完照樣還原、但把
	/// `adjusted` 標給呼叫端註記，不默默假裝原樣。
	func clamped(into visible: WindowFrame) -> (frame: WindowFrame, adjusted: Bool) {
		let clampedWidth: Int = min(width, visible.width)
		let clampedHeight: Int = min(height, visible.height)
		var clampedX: Int = max(originX, visible.originX)
		var clampedY: Int = max(originY, visible.originY)
		if clampedX + clampedWidth > visible.originX + visible.width {
			clampedX = visible.originX + visible.width - clampedWidth
		}
		if clampedY + clampedHeight > visible.originY + visible.height {
			clampedY = visible.originY + visible.height - clampedHeight
		}
		let result: WindowFrame = .init(
			originX: clampedX, originY: clampedY, width: clampedWidth, height: clampedHeight
		)
		return (result, result != self)
	}
}
