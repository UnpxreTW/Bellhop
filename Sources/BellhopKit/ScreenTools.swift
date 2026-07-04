//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import MCP

// MARK: - ScreenTools

/// 螢幕截圖工具。
///
/// 走 `/usr/sbin/screencapture`，把截圖存成檔案、回傳路徑（不 inline 圖片、避開
/// base64 體積問題）。需 macOS Screen Recording 權限，且螢幕鎖定下截不到。
enum ScreenTools {

	// MARK: Internal

	/// 對 client 曝光的工具。
	static let all: [Tool] = [
		Tool(
			name: "screen_capture",
			description: """
				Capture a screenshot to a file and return the file path. Defaults to \
				the main display; pass `window_id` (from terminal_list_windows) to \
				capture just that Terminal window, `region` "x,y,width,height" for a \
				rectangle, or `display` for a specific display number. Requires macOS \
				Screen Recording permission and does NOT work while the screen is locked.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"path": .object([
						"type": .string("string"),
						"description": .string(
							"Absolute output path. Defaults to ~/Downloads/Bellhop-Screenshot-<timestamp>."
						)
					]),
					"window_id": .object([
						"type": .string("integer"),
						"description": .string(
							"Capture just this Terminal window (id from terminal_list_windows)."
						)
					]),
					"region": .object([
						"type": .string("string"),
						"description": .string("Capture a rectangle, format \"x,y,width,height\".")
					]),
					"display": .object([
						"type": .string("integer"),
						"description": .string("Capture a specific display by number (1 = main).")
					]),
					"format": .object([
						"type": .string("string"),
						"description": .string("Image format: \"png\" (default) or \"jpg\".")
					])
				])
			])
		)
	]

	/// 此工具群是否擁有某工具名（供 server 路由）。
	static func owns(_ name: String) -> Bool {
		name.hasPrefix("screen_")
	}

	/// 將 tool 呼叫分派到對應實作。
	static func handle(name: String, arguments: [String: Value]?) -> CallTool.Result {
		switch name {
		case "screen_capture":
			screenCapture(arguments: arguments)
		default:
			.init(
				content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)],
				isError: true
			)
		}
	}

	// MARK: Private

	/// Terminal 視窗的螢幕座標 bounds。
	private struct WindowBounds {
		var width: Int { right - left }
		var height: Int { bottom - top }

		let left: Int
		let top: Int
		let right: Int
		let bottom: Int
	}

	private static func screenCapture(arguments: [String: Value]?) -> CallTool.Result {
		let format = arguments?["format"]?.stringValue == "jpg" ? "jpg" : "png"
		let path = arguments?["path"]?.stringValue ?? defaultPath(format: format)
		var args = ["-x", "-t", format]
		var target = "main display"

		if let windowID = arguments?["window_id"]?.intValue {
			if let cgID = cgWindowID(forTerminalWindowID: windowID) {
				args += ["-o", "-l", String(cgID)]
				target = "Terminal window \(windowID)"
			} else if let region = terminalWindowRegion(windowID: windowID) {
				args += ["-R", region]
				target = "Terminal window \(windowID) (region fallback)"
			} else {
				return errorResult("Could not find Terminal window \(windowID).")
			}
		} else if let region = arguments?["region"]?.stringValue, !region.isEmpty {
			args += ["-R", region]
			target = "region \(region)"
		} else if let display = arguments?["display"]?.intValue {
			args += ["-D", String(display)]
			target = "display \(display)"
		} else {
			args.append("-m")
		}
		args.append(path)
		return runCapture(args: args, target: target, path: path)
	}

	/// 跑 screencapture、驗證產物、回傳結果。
	private static func runCapture(args: [String], target: String, path: String) -> CallTool.Result {
		do {
			let (status, stderr) = try runProcess("/usr/sbin/screencapture", args)
			if status != 0 {
				let hint = stderr.contains("could not create image")
					? """
						 — likely missing Screen Recording permission. Grant it to the app \
						that launches Bellhop in System Settings → Privacy & Security → Screen \
						Recording, then restart that app. (Also fails while the screen is locked.)
						"""
					: ""
				return errorResult("screencapture failed: \(stderr)\(hint)")
			}
			let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int ?? 0
			if size == 0 {
				return errorResult("""
					Screenshot is empty — check Screen Recording permission \
					(System Settings → Privacy & Security → Screen Recording) and that the screen is unlocked.
					""")
			}
			return .init(
				content: [
					.text(text: "Saved screenshot of \(target) to \(path) (\(size) bytes).", annotations: nil, _meta: nil)
				],
				isError: false
			)
		} catch {
			return errorResult("Error: \(error)")
		}
	}

	/// 把 Bellhop 的 Terminal AppleScript window id 映射到系統 CGWindowID（給 `screencapture -l`）。
	///
	/// 兩者不同源——以 owner 為 Terminal、且 bounds 相符的視窗比對出 CGWindowID。
	private static func cgWindowID(forTerminalWindowID windowID: Int) -> CGWindowID? {
		guard let target = terminalWindowBounds(windowID: windowID) else { return nil }
		let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
		guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
		for window in list {
			guard window[kCGWindowOwnerName as String] as? String == "Terminal" else { continue }
			guard let box = window[kCGWindowBounds as String] as? [String: Any] else { continue }
			let boxX = (box["X"] as? NSNumber)?.intValue ?? .min
			let boxY = (box["Y"] as? NSNumber)?.intValue ?? .min
			let boxW = (box["Width"] as? NSNumber)?.intValue ?? .min
			let boxH = (box["Height"] as? NSNumber)?.intValue ?? .min
			let matched =
				abs(boxX - target.left) <= 2 && abs(boxY - target.top) <= 2
					&& abs(boxW - target.width) <= 2 && abs(boxH - target.height) <= 2
			if matched {
				return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
			}
		}
		return nil
	}

	/// 取 Terminal 視窗的 bounds。
	private static func terminalWindowBounds(windowID: Int) -> WindowBounds? {
		let script = "tell application \"Terminal\" to get bounds of window id \(windowID)"
		guard let out = try? TerminalTools.runOsascript(script) else { return nil }
		let parts = out.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
		guard parts.count == 4 else { return nil }
		return WindowBounds(left: parts[0], top: parts[1], right: parts[2], bottom: parts[3])
	}

	/// 把 Terminal 視窗 bounds 轉成 screencapture `-R` 的 "x,y,width,height"。
	private static func terminalWindowRegion(windowID: Int) -> String? {
		guard let bounds = terminalWindowBounds(windowID: windowID) else { return nil }
		return "\(bounds.left),\(bounds.top),\(bounds.width),\(bounds.height)"
	}

	/// 預設輸出路徑 ~/Downloads/Bellhop-Screenshot-<timestamp>.<ext>。
	private static func defaultPath(format: String) -> String {
		let formatter: DateFormatter = .init()
		formatter.dateFormat = "yyyyMMdd-HHmmss"
		let name = "Bellhop-Screenshot-\(formatter.string(from: Date())).\(format)"
		return FileManager.default
			.homeDirectoryForCurrentUser
			.appendingPathComponent("Downloads")
			.appendingPathComponent(name)
			.path
	}

	private static func errorResult(_ message: String) -> CallTool.Result {
		.init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
	}

	/// 執行 subprocess，回傳 (exit status, 去頭尾空白的 stderr)。
	private static func runProcess(_ launchPath: String, _ args: [String]) throws -> (Int32, String) {
		let process: Process = .init()
		process.executableURL = URL(fileURLWithPath: launchPath)
		process.arguments = args
		let stderr: Pipe = .init()
		process.standardError = stderr
		process.standardOutput = Pipe()
		try process.run()
		let errData = stderr.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		let message =
			String(data: errData, encoding: .utf8)?
				.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return (process.terminationStatus, message)
	}
}
