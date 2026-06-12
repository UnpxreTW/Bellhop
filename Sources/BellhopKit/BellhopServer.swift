//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the MIT License. See LICENSE for details.
//
//  SPDX-License-Identifier: MIT

import Foundation
import MCP

/// Assembles and runs the Bellhop MCP server over stdio.
public enum BellhopServer {

	public static let name = "bellhop"

	public static let version = "0.1.0"

	/// Build a configured server with all tool handlers registered.
	public static func makeServer() async -> Server {
		let server: Server = .init(
			name: name,
			version: version,
			instructions: "Operate macOS through purpose-built, typed tools.",
			capabilities: .init(tools: .init(listChanged: false))
		)

		await server.withMethodHandler(ListTools.self) { _ in
			ListTools.Result(tools: [])
		}

		return server
	}

	/// Start the server on stdio and block until the connection closes.
	public static func run() async throws {
		let server = await makeServer()
		let transport: StdioTransport = .init()
		try await server.start(transport: transport)
		await server.waitUntilCompleted()
	}
}
