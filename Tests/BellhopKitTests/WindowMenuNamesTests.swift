//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Testing

@testable import BellhopKit

struct WindowMenuNamesTests {

	@Test("名稱表覆蓋全部位置、每項都有 zh-TW 與 en 兩個候選")
	func tableCoversEveryPositionInBothLanguages() {
		for position in WindowPosition.allCases {
			let titles = WindowMenuNames.itemTitles(for: position)
			#expect(titles.count == 2, "\(position) 應有 zh-TW＋en 兩個候選")
			#expect(titles.allSatisfy { !$0.isEmpty })
		}
	}

	@Test("zh-TW 字面照官方支援頁：半屏是「左側」不是「左半部」")
	func zhTWTitlesFollowOfficialWording() {
		#expect(WindowMenuNames.itemTitles(for: .left).first == "左側")
		#expect(WindowMenuNames.itemTitles(for: .fill).first == "填滿")
		#expect(WindowMenuNames.itemTitles(for: .center).first == "置中")
		#expect(WindowMenuNames.itemTitles(for: .restorePrevious).first == "返回上一個大小")
	}

	@Test("選單路徑候選含 zh-TW 與 en")
	func menuPathTitlesIncludeBothLanguages() {
		#expect(WindowMenuNames.windowMenuTitles == ["視窗", "Window"])
		#expect(WindowMenuNames.moveAndResizeTitles == ["移動與調整大小", "Move & Resize"])
	}
}
