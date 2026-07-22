//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Testing

@testable import BellhopKit

struct WindowActionsTests {

	private let candidates: [WindowActions.AppCandidate] = [
		.init(name: "終端機", bundleID: "com.apple.Terminal"),
		.init(name: "Safari", bundleID: "com.apple.Safari"),
		.init(name: "Safari Technology Preview", bundleID: "com.apple.SafariTechnologyPreview"),
		.init(name: nil, bundleID: "com.example.headless")
	]

	@Test("selectApp 無命中回 none")
	func selectAppReturnsNoneWithoutHit() {
		#expect(WindowActions.selectApp(from: candidates, filter: "xcode") == .none)
	}

	@Test("selectApp 唯一命中回索引、名稱與 bundle id 皆可比對且不分大小寫")
	func selectAppMatchesNameAndBundleIDCaseInsensitively() {
		#expect(WindowActions.selectApp(from: candidates, filter: "終端") == .unique(0))
		#expect(WindowActions.selectApp(from: candidates, filter: "com.apple.terminal") == .unique(0))
		#expect(WindowActions.selectApp(from: candidates, filter: "headless") == .unique(3))
	}

	@Test("selectApp 多筆命中時以完全相等收斂")
	func selectAppPrefersExactMatchAmongMultipleHits() {
		#expect(WindowActions.selectApp(from: candidates, filter: "Safari") == .unique(1))
	}

	@Test("selectApp 多筆命中且無完全相等者回 ambiguous 候選清單")
	func selectAppReportsAmbiguousHits() {
		let match: WindowActions.AppMatch = WindowActions.selectApp(from: candidates, filter: "apple")
		guard case let .ambiguous(described) = match else {
			Issue.record("expected ambiguous, got \(match)")
			return
		}
		#expect(described.count == 3)
		#expect(described.contains { $0.contains("com.apple.Safari") })
	}

	@Test("selectWindow 無標題參數取第一個、空清單回 none")
	func selectWindowDefaultsToFirst() {
		#expect(WindowActions.selectWindow(titles: ["A", "B"], filter: nil) == .unique(0))
		#expect(WindowActions.selectWindow(titles: [], filter: nil) == .none)
		#expect(WindowActions.selectWindow(titles: [], filter: "任何") == .none)
	}

	@Test("selectWindow 標題不分大小寫子字串比對、取第一個命中")
	func selectWindowMatchesTitleSubstring() {
		let titles: [String?] = ["README.md — 專案", nil, "release notes"]
		#expect(WindowActions.selectWindow(titles: titles, filter: "readme") == .unique(0))
		#expect(WindowActions.selectWindow(titles: titles, filter: "NOTES") == .unique(2))
	}

	@Test("selectWindow 標題無命中回可用標題清單、nil 標題以 untitled 佔位")
	func selectWindowReportsAvailableTitles() {
		let titles: [String?] = ["首頁", nil]
		let match: WindowActions.WindowMatch = WindowActions.selectWindow(titles: titles, filter: "設定")
		#expect(match == .titleNotFound(["首頁", "(untitled)"]))
	}
}
