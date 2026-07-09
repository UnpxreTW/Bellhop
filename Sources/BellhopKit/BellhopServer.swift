//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP

/// 以 stdio transport 組裝並執行 Bellhop MCP server。
public enum BellhopServer {

	/// MCP handshake 時回報給 client 的 server 名稱。
	public static let name = "bellhop"

	/// Server 版本號，隨發佈遞增。
	public static let version = "0.1.0"

	/// 組裝設定完成的 server 並註冊 method handler。
	///
	/// - Returns: 可直接接上 transport 啟動的 `Server`。
	public static func makeServer() async -> Server {
		let server: Server = .init(
			name: name,
			version: version,
			instructions: """
				Operate macOS through purpose-built, typed tools. \
				Currently exposes Terminal.app window control and screen capture.
				""",
			capabilities: .init(tools: .init(listChanged: false))
		)
		await server.withMethodHandler(ListTools.self) { _ in
			ListTools.Result(tools: TerminalTools.all + ScreenTools.all)
		}
		await server.withMethodHandler(CallTool.self) { params in
			if ScreenTools.owns(params.name) {
				return await ScreenTools.handle(name: params.name, arguments: params.arguments)
			}
			return await TerminalTools.handle(name: params.name, arguments: params.arguments)
		}
		return server
	}

	/// 在 stdio 上啟動 server 並阻塞，直到連線關閉。
	public static func run() async throws {
		let server = await makeServer()
		let transport: StdioTransport = .init()
		try await server.start(transport: transport)
		await server.waitUntilCompleted()
	}
}
