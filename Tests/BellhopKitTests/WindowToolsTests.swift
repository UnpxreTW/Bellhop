//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Testing

@testable import BellhopKit

struct WindowToolsTests {

	@Test("owns 只認 window_ 前綴")
	func ownsMatchesWindowPrefixOnly() {
		#expect(WindowTools.owns("window_list"))
		#expect(WindowTools.owns("window_save_layout"))
		#expect(!WindowTools.owns("terminal_open"))
		#expect(!WindowTools.owns("screen_capture"))
	}

	@Test("曝光面＝唯讀三顆＋動作面 primitive 兩顆、選單類留在 plannedTools")
	func exposedToolsAreReadOnlyThreePlusActionPrimitives() {
		#expect(
			WindowTools.all.map(\.name) == [
				"window_list", "window_save_layout", "window_layout_list",
				"window_focus", "window_set_frame"
			]
		)
		#expect(WindowTools.plannedTools.map(\.name) == ["window_arrange", "window_restore_layout"])
		let exposed = Set(WindowTools.all.map(\.name))
		#expect(exposed.isDisjoint(with: WindowTools.plannedTools.map(\.name)))
	}

	@Test("window_focus 缺 app 參數回 isError、不進 AX 層")
	func focusWithoutAppReportsError() async {
		let result = await WindowTools.handle(name: "window_focus", arguments: nil)
		#expect(result.isError == true)
		if case let .text(text, _, _) = result.content.first {
			#expect(text.contains("`app`"))
		} else {
			Issue.record("expected text content")
		}
	}

	@Test("window_set_frame 缺座標參數回 isError、不進 AX 層")
	func setFrameWithoutCoordinatesReportsError() async {
		let result = await WindowTools.handle(
			name: "window_set_frame", arguments: ["app": .string("Safari")]
		)
		#expect(result.isError == true)
		if case let .text(text, _, _) = result.content.first {
			#expect(text.contains("`x`/`y`/`width`/`height`"))
		} else {
			Issue.record("expected text content")
		}
	}

	@Test("window_set_frame 拒絕非正的寬高")
	func setFrameRejectsNonPositiveSize() async {
		let result = await WindowTools.handle(
			name: "window_set_frame",
			arguments: [
				"app": .string("Safari"), "x": .int(0), "y": .int(0), "width": .int(0), "height": .int(600)
			]
		)
		#expect(result.isError == true)
		if case let .text(text, _, _) = result.content.first {
			#expect(text.contains("positive"))
		} else {
			Issue.record("expected text content")
		}
	}

	@Test("未接上的動作面工具回 isError、點名缺 Accessibility 整合")
	func plannedToolsReportUnavailable() async {
		for name in WindowTools.plannedTools.map(\.name) {
			let result = await WindowTools.handle(name: name, arguments: nil)
			#expect(result.isError == true)
			if case let .text(text, _, _) = result.content.first {
				#expect(text.contains("not available yet"))
				#expect(text.contains("Accessibility"))
			} else {
				Issue.record("expected text content for \(name)")
			}
		}
	}

	@Test("未知工具名回 isError")
	func unknownToolReportsError() async {
		let result = await WindowTools.handle(name: "window_bogus", arguments: nil)
		#expect(result.isError == true)
	}

	@Test("window_arrange 的 position enum 覆蓋全部 11 位置")
	func arrangePositionEnumCoversAllPositions() {
		#expect(WindowPosition.allCases.count == 11)
		#expect(WindowPosition.topLeft.rawValue == "top_left")
		#expect(WindowPosition.restorePrevious.rawValue == "restore_previous")
	}

	@Test("matchesApp 不分大小寫比對 app 名與 bundle id")
	func matchesAppIsCaseInsensitive() {
		let record = WindowRecord(
			bundleID: "com.apple.Terminal",
			ownerName: "終端機",
			title: nil,
			frame: .init(originX: 0, originY: 0, width: 100, height: 100),
			onScreen: true,
			minimized: nil,
			displayIndex: 0,
			windowNumber: nil
		)
		#expect(WindowTools.matchesApp(record, filter: "terminal"))
		#expect(WindowTools.matchesApp(record, filter: "終端"))
		#expect(!WindowTools.matchesApp(record, filter: "safari"))
	}

	@Test("encodeRecords 輸出 snake_case JSON")
	func encodeRecordsUsesSnakeCaseKeys() throws {
		let record = WindowRecord(
			bundleID: "com.apple.Safari",
			ownerName: "Safari",
			title: "Start Page",
			frame: .init(originX: 0, originY: 25, width: 1200, height: 800),
			onScreen: true,
			minimized: nil,
			displayIndex: 0,
			windowNumber: 42
		)
		let json = try WindowTools.encodeRecords([record])
		#expect(json.contains("\"bundle_id\""))
		#expect(json.contains("\"owner_name\""))
		#expect(json.contains("\"on_screen\""))
		#expect(json.contains("\"window_number\" : 42"))
	}
}
