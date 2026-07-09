//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

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
}
