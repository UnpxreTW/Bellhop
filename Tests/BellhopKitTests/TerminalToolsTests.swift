//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import MCP
import Testing

@testable import BellhopKit

struct TerminalToolsTests {

	@Test("appleScriptEscape 先跳脫反斜線再跳脫引號")
	func appleScriptEscapeHandlesBackslashesAndQuotes() {
		#expect(TerminalTools.appleScriptEscape(#"back\slash "quote""#) == #"back\\slash \"quote\""#)
		#expect(TerminalTools.appleScriptEscape("plain") == "plain")
	}

	@Test("shellQuote 包單引號並跳脫內嵌單引號")
	func shellQuoteWrapsAndEscapes() {
		#expect(TerminalTools.shellQuote("/tmp/some dir") == "'/tmp/some dir'")
		#expect(TerminalTools.shellQuote("it's") == #"'it'\''s'"#)
	}

	@Test("openPayload 組合 cd 與命令")
	func openPayloadComposesCdAndCommand() {
		#expect(TerminalTools.openPayload(command: "", cwd: "").isEmpty)
		#expect(TerminalTools.openPayload(command: "claude", cwd: "") == "claude")
		#expect(TerminalTools.openPayload(command: "", cwd: "/tmp") == "cd '/tmp'")
		#expect(
			TerminalTools.openPayload(command: "claude --remote-control", cwd: "/tmp/my dir")
				== "cd '/tmp/my dir' && claude --remote-control"
		)
	}

	@Test("工具名依宣告順序曝光")
	func toolNamesFollowDeclarationOrder() {
		#expect(TerminalTools.all.map(\.name) == ["terminal_open", "terminal_run", "terminal_list_windows"])
	}

	@Test("terminal_run 對忙碌視窗拒跑並回 isError 附改挑建議")
	func runInWindowRefusesBusyWindow() async {
		let result = await TerminalTools.handle(
			name: "terminal_run",
			arguments: ["command": .string("echo hi"), "window_id": .int(42)],
			osascriptRunner: { _ in "BUSY" }
		)
		#expect(result.isError == true)
		#expect(text(of: result)?.contains("Window 42 is busy") == true)
	}

	@Test("terminal_run 對閒置視窗放行並原樣回傳輸出")
	func runInWindowPassesThroughIdleWindowOutput() async {
		let result = await TerminalTools.handle(
			name: "terminal_run",
			arguments: ["command": .string("echo hi"), "window_id": .int(7)],
			osascriptRunner: { _ in "hi" }
		)
		#expect(result.isError == false)
		#expect(text(of: result) == "hi")
	}

	@Test("terminal_run 缺 window_id 回 isError 不呼叫 osascript")
	func runInWindowRejectsMissingWindowID() async {
		let result = await TerminalTools.handle(
			name: "terminal_run",
			arguments: ["command": .string("echo hi")],
			osascriptRunner: { script in
				Issue.record("osascriptRunner 不應被呼叫（缺 window_id 應提前擋下）")
				return script
			}
		)
		#expect(result.isError == true)
		#expect(text(of: result)?.contains("Missing required arguments") == true)
	}

	@Test("terminal_open 組出的 script 送進 osascript runner 且輸出原樣回傳")
	func openTerminalPassesScriptAndReturnsOutput() async {
		let result = await TerminalTools.handle(
			name: "terminal_open",
			arguments: ["command": .string("ls"), "cwd": .string("/tmp")],
			osascriptRunner: { script in script }
		)
		#expect(result.isError == false)
		#expect(text(of: result)?.contains("cd '/tmp' && ls") == true)
	}

	@Test("terminal_list_windows 空輸出轉友善提示、非空輸出原樣回傳")
	func listTerminalWindowsFormatsEmptyAndNonEmptyOutput() async {
		let empty = await TerminalTools.handle(
			name: "terminal_list_windows",
			arguments: nil,
			osascriptRunner: { _ in "" }
		)
		#expect(text(of: empty) == "(no Terminal windows open)")

		let nonEmpty = await TerminalTools.handle(
			name: "terminal_list_windows",
			arguments: nil,
			osascriptRunner: { _ in "window 1 busy=false: bash\n" }
		)
		#expect(text(of: nonEmpty) == "window 1 busy=false: bash\n")
	}

	@Test("未知工具名回 isError 附工具名")
	func handleRejectsUnknownToolName() async {
		let result = await TerminalTools.handle(
			name: "terminal_teleport",
			arguments: nil,
			osascriptRunner: { _ in "" }
		)
		#expect(result.isError == true)
		#expect(text(of: result)?.contains("terminal_teleport") == true)
	}

	@Test("osascript runner 拋錯時 handle 收斂成 isError 而非讓例外冒穿")
	func handleCollapsesThrownErrorToIsError() async {
		let result = await TerminalTools.handle(
			name: "terminal_open",
			arguments: nil,
			osascriptRunner: { _ in throw TerminalError.osascriptFailed("boom") }
		)
		#expect(result.isError == true)
		#expect(text(of: result)?.contains("boom") == true)
	}
}

/// 取 `CallTool.Result` 第一段 text content 的內容，非 text content 回 nil。
private func text(of result: CallTool.Result) -> String? {
	guard case let .text(text, _, _) = result.content.first else { return nil }
	return text
}
