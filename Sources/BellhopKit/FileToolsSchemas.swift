//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import MCP

// MARK: - + 工具 schema

/// 三顆檔案工具的 schema。
extension FileTools {

	/// 已定型但**尚未註冊**進 ``BellhopServer`` 的工具。
	///
	/// schema 與實作已定型，可單獨審查 client 可見的介面形狀；對外工具面不含這三顆。
	internal static let plannedTools: [Tool] = [
		Tool(
			name: "file_stat",
			description: """
				Get the type (file or directory), size, modification time, and resolved \
				path of an item inside a folder allowed by the file access policy. \
				Access outside the allowed folders is refused (isError).
				""",
			inputSchema: pathOnlySchema(description: "Absolute path, or a path starting with ~.")
		),
		Tool(
			name: "file_list",
			description: """
				List the immediate entries of a directory inside a listable allowed folder: \
				name, type, size, and modification time, sorted by name. Not recursive; \
				symbolic links are reported, not followed. At most 1000 entries are \
				returned; `truncated` is true when more exist.
				""",
			inputSchema: pathOnlySchema(description: "Absolute directory path, or a path starting with ~.")
		),
		Tool(
			name: "file_read",
			description: """
				Read a UTF-8 text file inside an allowed folder. Returns the selected lines \
				and the total line count. Files larger than 10 MiB or not valid UTF-8 are \
				refused (isError).
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"path": .object([
						"type": .string("string"),
						"description": .string("Absolute file path, or a path starting with ~.")
					]),
					"offset": .object([
						"type": .string("integer"),
						"description": .string("First line to return, 1-based. Defaults to 1.")
					]),
					"limit": .object([
						"type": .string("integer"),
						"description": .string("Number of lines to return. Defaults to and capped at 2000.")
					])
				]),
				"required": .array([.string("path")])
			])
		)
	]

	/// 只有一個必填 `path` 參數的 schema。
	private static func pathOnlySchema(description: String) -> Value {
		.object([
			"type": .string("object"),
			"properties": .object([
				"path": .object([
					"type": .string("string"),
					"description": .string(description)
				])
			]),
			"required": .array([.string("path")])
		])
	}
}
