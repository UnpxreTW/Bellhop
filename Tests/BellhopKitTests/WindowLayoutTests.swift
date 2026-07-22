//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import BellhopKit

struct WindowLayoutTests {

	/// 供多個測試共用的樣本 layout。
	private static func sampleLayout() -> WindowLayout {
		WindowLayout(
			version: 1,
			savedAt: Date(timeIntervalSince1970: 1_784_000_000),
			displays: [.init(frame: .init(originX: 0, originY: 0, width: 1440, height: 900))],
			windows: [
				WindowRecord(
					bundleID: "com.apple.Terminal",
					ownerName: "終端機",
					title: "zsh",
					frame: .init(originX: 8, originY: 38, width: 1424, height: 854),
					onScreen: true,
					minimized: nil,
					displayIndex: 0,
					windowNumber: 60
				)
			]
		)
	}

	@Test("layout 編解碼 roundtrip 等值")
	func layoutRoundTripsThroughJSON() throws {
		let layout = Self.sampleLayout()
		let data = try WindowLayout.encoder().encode(layout)
		let decoded = try WindowLayout.decoder().decode(WindowLayout.self, from: data)
		#expect(decoded == layout)
	}

	@Test("JSON 鍵名走 snake_case、frame 走 x/y（schema v1 對外形狀）")
	func jsonUsesSchemaV1Keys() throws {
		let data = try WindowLayout.encoder().encode(Self.sampleLayout())
		let json = String(data: data, encoding: .utf8) ?? ""
		#expect(json.contains("\"saved_at\""))
		#expect(json.contains("\"bundle_id\""))
		#expect(json.contains("\"owner_name\""))
		#expect(json.contains("\"on_screen\""))
		#expect(json.contains("\"display_index\""))
		#expect(json.contains("\"window_number\""))
		#expect(json.contains("\"x\""))
		#expect(json.contains("\"y\""))
		#expect(!json.contains("originX"))
		#expect(json.contains("\"version\" : 1"))
	}

	@Test("sanitizedName 收合法名、去頭尾空白")
	func sanitizedNameAcceptsPlainNames() {
		#expect(WindowLayout.sanitizedName("work") == "work")
		#expect(WindowLayout.sanitizedName("雙螢幕配置") == "雙螢幕配置")
		#expect(WindowLayout.sanitizedName("  desk 2  ") == "desk 2")
	}

	@Test("sanitizedName 拒空字串、路徑穿越與控制字元")
	func sanitizedNameRejectsUnsafeNames() {
		#expect(WindowLayout.sanitizedName("") == nil)
		#expect(WindowLayout.sanitizedName("   ") == nil)
		#expect(WindowLayout.sanitizedName("a/b") == nil)
		#expect(WindowLayout.sanitizedName("..") == nil)
		#expect(WindowLayout.sanitizedName(".hidden") == nil)
		#expect(WindowLayout.sanitizedName("a:b") == nil)
		#expect(WindowLayout.sanitizedName("a\nb") == nil)
		#expect(WindowLayout.sanitizedName(String(repeating: "x", count: 65)) == nil)
	}

	@Test("AppKit 座標翻轉成 CG 左上原點")
	func appKitFrameConvertsToTopLeftOrigin() {
		let primaryHeight: CGFloat = 900
		let fullScreen = WindowFrame(
			appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), primaryDisplayHeight: primaryHeight
		)
		#expect(fullScreen == WindowFrame(originX: 0, originY: 0, width: 1440, height: 900))
		let window = WindowFrame(
			appKitFrame: CGRect(x: 100, y: 100, width: 400, height: 200), primaryDisplayHeight: primaryHeight
		)
		#expect(window == WindowFrame(originX: 100, originY: 600, width: 400, height: 200))
		let screenAbove = WindowFrame(
			appKitFrame: CGRect(x: 0, y: 900, width: 1440, height: 900), primaryDisplayHeight: primaryHeight
		)
		#expect(screenAbove == WindowFrame(originX: 0, originY: -900, width: 1440, height: 900))
	}

	@Test("clamp 塞得下就原樣、出界就平移縮小並標註")
	func clampAdjustsOnlyWhenNeeded() {
		let visible = WindowFrame(originX: 0, originY: 25, width: 1440, height: 875)
		let fits = WindowFrame(originX: 100, originY: 100, width: 400, height: 300)
		let fitted = fits.clamped(into: visible)
		#expect(fitted.frame == fits)
		#expect(!fitted.adjusted)
		let oversized = WindowFrame(originX: -50, originY: 0, width: 2000, height: 1200)
		let shrunk = oversized.clamped(into: visible)
		#expect(shrunk.frame == visible)
		#expect(shrunk.adjusted)
		let offRight = WindowFrame(originX: 1200, originY: 100, width: 400, height: 300)
		let shifted = offRight.clamped(into: visible)
		#expect(shifted.frame == WindowFrame(originX: 1040, originY: 100, width: 400, height: 300))
		#expect(shifted.adjusted)
	}

	@Test("displayIndex 取交集面積最大的螢幕、皆無交集回 nil")
	func displayIndexPicksLargestOverlap() {
		let displays: [WindowFrame] = [
			.init(originX: 0, originY: 0, width: 1440, height: 900),
			.init(originX: 1440, originY: 0, width: 1920, height: 1080)
		]
		let mostlySecond = WindowFrame(originX: 1400, originY: 100, width: 800, height: 600)
		#expect(WindowLayout.displayIndex(for: mostlySecond, in: displays) == 1)
		let onFirst = WindowFrame(originX: 10, originY: 10, width: 500, height: 500)
		#expect(WindowLayout.displayIndex(for: onFirst, in: displays) == 0)
		let outside = WindowFrame(originX: -5000, originY: -5000, width: 100, height: 100)
		#expect(WindowLayout.displayIndex(for: outside, in: displays) == nil)
	}

	@Test("displaysMatch 忽略順序、內容不同即不符")
	func displaysMatchIgnoresOrder() {
		let first = WindowLayout.Display(frame: .init(originX: 0, originY: 0, width: 1440, height: 900))
		let second = WindowLayout.Display(frame: .init(originX: 1440, originY: 0, width: 1920, height: 1080))
		#expect(WindowLayout.displaysMatch([first, second], [second, first]))
		#expect(!WindowLayout.displaysMatch([first], [second]))
		#expect(!WindowLayout.displaysMatch([first, second], [first]))
	}

	@Test("intersectionArea 無交集回 0")
	func intersectionAreaIsZeroWhenDisjoint() {
		let base = WindowFrame(originX: 0, originY: 0, width: 100, height: 100)
		#expect(base.intersectionArea(with: .init(originX: 200, originY: 200, width: 50, height: 50)) == 0)
		#expect(base.intersectionArea(with: .init(originX: 50, originY: 50, width: 100, height: 100)) == 2500)
	}
}
