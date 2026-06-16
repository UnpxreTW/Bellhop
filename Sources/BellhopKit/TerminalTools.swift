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
		),
		Tool(
			name: "set_terminal_bounds",
			description: """
				Resize and/or move a Terminal.app window. Works even when the screen \
				is locked. width/height are required; x/y default to the window's \
				current top-left; window_id defaults to the frontmost window. \
				Returns the resulting bounds.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"width": .object([
						"type": .string("integer"),
						"description": .string("New window width in points.")
					]),
					"height": .object([
						"type": .string("integer"),
						"description": .string("New window height in points.")
					]),
					"x": .object([
						"type": .string("integer"),
						"description": .string("New left position; defaults to current.")
					]),
					"y": .object([
						"type": .string("integer"),
						"description": .string("New top position; defaults to current.")
					]),
					"window_id": .object([
						"type": .string("integer"),
						"description": .string(
							"Target window id (from list_terminal_windows); defaults to frontmost."
						)
					])
				]),
				"required": .array([.string("width"), .string("height")])
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
			case "set_terminal_bounds":
				return try setTerminalBounds(arguments: arguments)
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

	private static func setTerminalBounds(arguments: [String: Value]?) throws -> CallTool.Result {
		guard let width = arguments?["width"]?.intValue, let height = arguments?["height"]?.intValue else {
			return .init(
				content: [.text(text: "Missing required arguments: width, height", annotations: nil, _meta: nil)],
				isError: true
			)
		}
		// 純數值參數、無字串注入面：window_id / x / y 不存在時以 AppleScript 變數補當前值。
		let windowRef = arguments?["window_id"]?.intValue.map { "window id \($0)" } ?? "front window"
		let leftExpr = arguments?["x"]?.intValue.map(String.init) ?? "l"
		let topExpr = arguments?["y"]?.intValue.map(String.init) ?? "t"
		let script = """
			tell application "Terminal"
			\tset theWindow to \(windowRef)
			\tset {l, t, r, b} to bounds of theWindow
			\tset bounds of theWindow to ¬
			\t\t{\(leftExpr), \(topExpr), (\(leftExpr)) + \(width), (\(topExpr)) + \(height)}
			\tset {nl, nt, nr, nb} to bounds of theWindow
			\treturn (nl as string) & ", " & (nt as string) & ", " & ¬
			\t\t(nr as string) & ", " & (nb as string)
			end tell
			"""
		let out = try runOsascript(script)
		return .init(content: [.text(text: out, annotations: nil, _meta: nil)], isError: false)
	}
}
