//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP

// MARK: - TerminalTools

/// Terminal.app 視窗控制工具。
///
/// 走 `osascript`（Apple Event）直達 Terminal process、不經 GUI automation，
/// 所以螢幕鎖定下 `do script` 照樣可達——click 式 computer-use 會因 frontmost
/// 變成 loginwindow 而失敗。
enum TerminalTools {

	// MARK: Internal

	/// 對 client 曝光的工具，依列出順序。
	static let all: [Tool] = [
		Tool(
			name: "open_terminal",
			description: """
				Open a new Terminal.app window, optionally cd-ing into a directory \
				and running a command. Works even when the screen is locked. \
				Returns the new tab identifier (e.g. "tab 1 of window id 2311").
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"command": .object([
						"type": .string("string"),
						"description": .string(
							"Shell command to run in the new window. Empty opens a plain shell."
						)
					]),
					"cwd": .object([
						"type": .string("string"),
						"description": .string(
							"Directory to cd into before running the command."
						)
					])
				])
			])
		),
		Tool(
			name: "run_in_front_terminal",
			description: """
				Run a command in the current (frontmost) Terminal window instead of \
				opening a new one. Fails if no Terminal window is open.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"command": .object([
						"type": .string("string"),
						"description": .string("Shell command to run in the frontmost window.")
					])
				]),
				"required": .array([.string("command")])
			])
		),
		Tool(
			name: "list_terminal_windows",
			description: "List open Terminal.app windows with their ids and titles.",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([:])
			])
		)
	]

	/// 將 tool 呼叫分派到對應實作。
	///
	/// 工具層失敗依 MCP 慣例以 `isError: true` 回傳、不丟例外。
	static func handle(name: String, arguments: [String: Value]?) -> CallTool.Result {
		do {
			switch name {
			case "open_terminal":
				return try openTerminal(arguments: arguments)
			case "run_in_front_terminal":
				return try runInFrontTerminal(arguments: arguments)
			case "list_terminal_windows":
				return try listTerminalWindows()
			default:
				return .init(
					content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)],
					isError: true
				)
			}
		} catch {
			return .init(
				content: [.text(text: "Error: \(error)", annotations: nil, _meta: nil)],
				isError: true
			)
		}
	}

	/// 以 `osascript` 執行 AppleScript，回傳去除頭尾空白的 stdout。
	static func runOsascript(_ script: String) throws -> String {
		let process: Process = .init()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
		process.arguments = ["-e", script]

		let stdout: Pipe = .init()
		let stderr: Pipe = .init()
		process.standardOutput = stdout
		process.standardError = stderr

		try process.run()
		let outData = stdout.fileHandleForReading.readDataToEndOfFile()
		let errData = stderr.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()

		if process.terminationStatus != 0 {
			let message =
				String(data: errData, encoding: .utf8)?
					.trimmingCharacters(in: .whitespacesAndNewlines) ?? "osascript failed"
			throw TerminalError.osascriptFailed(message)
		}
		return String(data: outData, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
	}

	/// 把字串 escape 成可嵌入 AppleScript `"..."` 字面值的形式。
	static func appleScriptEscape(_ string: String) -> String {
		string.replacing("\\", with: "\\\\")
			.replacing("\"", with: "\\\"")
	}

	/// 以單引號包裝字串、使其成為安全的單一 POSIX shell word。
	static func shellQuote(_ string: String) -> String {
		"'" + string.replacing("'", with: "'\\''") + "'"
	}

	// MARK: Private

	private static func openTerminal(arguments: [String: Value]?) throws -> CallTool.Result {
		let command = arguments?["command"]?.stringValue ?? ""
		let cwd = arguments?["cwd"]?.stringValue ?? ""
		var parts: [String] = []
		if !cwd.isEmpty { parts.append("cd \(shellQuote(cwd))") }
		if !command.isEmpty { parts.append(command) }
		let payload = parts.joined(separator: " && ")
		let script =
			"tell application \"Terminal\" to do script \"\(appleScriptEscape(payload))\""
		let out = try runOsascript(script)
		return .init(content: [.text(text: out, annotations: nil, _meta: nil)], isError: false)
	}

	private static func runInFrontTerminal(arguments: [String: Value]?) throws -> CallTool.Result {
		guard let command = arguments?["command"]?.stringValue, !command.isEmpty else {
			return .init(
				content: [.text(text: "Missing required argument: command", annotations: nil, _meta: nil)],
				isError: true
			)
		}
		let script =
			"tell application \"Terminal\" to do script \"\(appleScriptEscape(command))\" in front window"
		let out = try runOsascript(script)
		return .init(content: [.text(text: out, annotations: nil, _meta: nil)], isError: false)
	}

	private static func listTerminalWindows() throws -> CallTool.Result {
		let script = """
			tell application "Terminal"
			\tset out to ""
			\trepeat with w in windows
			\t\tset out to out & "window " & (id of w) & ": " & (name of w) & linefeed
			\tend repeat
			\treturn out
			end tell
			"""
		let out = try runOsascript(script)
		return .init(
			content: [
				.text(
					text: out.isEmpty ? "(no Terminal windows open)" : out,
					annotations: nil, _meta: nil
				)
			],
			isError: false
		)
	}
}
