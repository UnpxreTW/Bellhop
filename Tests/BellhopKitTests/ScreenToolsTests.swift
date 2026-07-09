//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Testing

@testable import BellhopKit

struct ScreenToolsTests {

	@Test("WindowBounds 解析 AppleScript bounds 輸出")
	func windowBoundsParsesAppleScriptOutput() {
		let bounds = WindowBounds(appleScriptBounds: "8, 38, 1432, 892")
		#expect(bounds == WindowBounds(left: 8, top: 38, right: 1432, bottom: 892))
		#expect(bounds?.width == 1424)
		#expect(bounds?.height == 854)
	}

	@Test("WindowBounds 拒絕格式不符輸出")
	func windowBoundsRejectsMalformedOutput() {
		#expect(WindowBounds(appleScriptBounds: "") == nil)
		#expect(WindowBounds(appleScriptBounds: "1, 2, 3") == nil)
		#expect(WindowBounds(appleScriptBounds: "a, b, c, d") == nil)
	}

	@Test("region 轉為原點加尺寸字串")
	func regionUsesOriginAndSize() {
		#expect(WindowBounds(left: 8, top: 38, right: 1432, bottom: 892).region == "8,38,1424,854")
	}

	@Test("matches 容差內相符、超出即拒")
	func matchesRespectsTolerance() {
		let bounds = WindowBounds(left: 8, top: 38, right: 1432, bottom: 892)
		#expect(bounds.matches(originX: 8, originY: 38, width: 1424, height: 854))
		#expect(bounds.matches(originX: 10, originY: 36, width: 1426, height: 852))
		#expect(!bounds.matches(originX: 11, originY: 38, width: 1424, height: 854))
		#expect(!bounds.matches(originX: 8, originY: 38, width: 1424, height: 860))
	}

	@Test("owns 只認 screen_ 前綴")
	func ownsMatchesScreenPrefixOnly() {
		#expect(ScreenTools.owns("screen_capture"))
		#expect(!ScreenTools.owns("terminal_open"))
	}
}
