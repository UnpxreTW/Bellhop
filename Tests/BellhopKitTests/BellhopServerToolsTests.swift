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

struct BellhopServerToolsTests {

	@Test("server 實際列出的工具＝既有清單，不含 file_*；呼叫 file_read 回未知工具", .timeLimit(.minutes(1)))
	func serverDoesNotExposeFileTools() async throws {
		let server: Server = await BellhopServer.makeServer()
		let transports: (client: InMemoryTransport, server: InMemoryTransport) =
			await InMemoryTransport.createConnectedPair()
		try await server.start(transport: transports.server)
		let client: Client = .init(name: "bellhop-tests", version: "0")
		_ = try await client.connect(transport: transports.client)
		let listed: [String] = try await client.listTools().tools.map(\.name)
		#expect(
			listed == [
				"terminal_open", "terminal_run", "terminal_list_windows",
				"screen_capture",
				"window_list", "window_save_layout", "window_layout_list",
				"window_focus", "window_set_frame", "window_restore_layout"
			]
		)
		#expect(listed.allSatisfy { !$0.hasPrefix("file_") })
		let call: (content: [Tool.Content], isError: Bool?) = try await client.callTool(
			name: "file_read",
			arguments: ["path": .string("/")]
		)
		#expect(call.isError == true)
		if case let .text(text, _, _) = call.content.first {
			#expect(text.contains("Unknown tool: file_read"))
		} else {
			Issue.record("expected text content")
		}
		await client.disconnect()
		await server.stop()
	}

	@Test("FileTools 的 schema 名稱與 owns 前綴")
	func fileToolNamesAndOwnership() {
		#expect(FileTools.plannedTools.map(\.name) == ["file_stat", "file_list", "file_read"])
		#expect(FileTools.owns("file_read"))
		#expect(!FileTools.owns("window_list"))
	}
}
