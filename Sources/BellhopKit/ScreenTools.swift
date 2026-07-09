//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import AppKit
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
	static func handle(name: String, arguments: [String: Value]?) async -> CallTool.Result {
		switch name {
		case "screen_capture":
			await screenCapture(arguments: arguments)
		default:
			.init(
				content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)],
				isError: true
			)
		}
	}

	// MARK: Private

	/// CG 視窗清單裡的一筆 Terminal 視窗。
	private struct CGWindowEntry {

		let number: CGWindowID
		let originX: Int
		let originY: Int
		let width: Int
		let height: Int
	}

	private static func screenCapture(arguments: [String: Value]?) async -> CallTool.Result {
		let format = arguments?["format"]?.stringValue == "jpg" ? "jpg" : "png"
		let path = arguments?["path"]?.stringValue ?? defaultPath(format: format)
		var args = ["-x", "-t", format]
		var target = "main display"

		if let windowID = arguments?["window_id"]?.intValue {
			if let cgID = await cgWindowID(forTerminalWindowID: windowID) {
				args += ["-o", "-l", String(cgID)]
				target = "Terminal window \(windowID)"
			} else if let region = await terminalWindowRegion(windowID: windowID) {
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
		return await runCapture(args: args, target: target, path: path)
	}

	/// 跑 screencapture、驗證產物、回傳結果。
	private static func runCapture(args: [String], target: String, path: String) async -> CallTool.Result {
		do {
			let output = try await Subprocess.run("/usr/sbin/screencapture", arguments: args)
			let stderr = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
			if output.status != 0 {
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
	/// 實測（macOS 27）Terminal 的 AppleScript window id 與 `kCGWindowNumber` 同號
	/// （含最小化視窗），所以先直接驗證同號視窗存在；不成立時退回 bounds 比對
	/// （兩套座標實測同源對齊，見 ``WindowBounds``）。
	private static func cgWindowID(forTerminalWindowID windowID: Int) async -> CGWindowID? {
		let windows = terminalCGWindows()
		if windowID > 0, windows.contains(where: { $0.number == CGWindowID(windowID) }) {
			return CGWindowID(windowID)
		}
		guard let target = await terminalWindowBounds(windowID: windowID) else { return nil }
		return windows.first {
			target.matches(originX: $0.originX, originY: $0.originY, width: $0.width, height: $0.height)
		}?.number
	}

	/// 列出 Terminal 擁有的一般層級 CG 視窗（含最小化與其他 Space 的）。
	///
	/// 以 owner PID 過濾——`kCGWindowOwnerName` 是**本地化**的 app 顯示名
	/// （如中文系統上是「終端機」），不能拿 "Terminal" 字面比對。
	private static func terminalCGWindows() -> [CGWindowEntry] {
		let pids = Set(
			NSRunningApplication
				.runningApplications(withBundleIdentifier: "com.apple.Terminal")
				.map { Int($0.processIdentifier) }
		)
		guard
			!pids.isEmpty,
			let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
		else { return [] }
		return list.compactMap { window in
			guard
				let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
				pids.contains(pid),
				(window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
				let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
				let box = window[kCGWindowBounds as String] as? [String: Any],
				let originX = (box["X"] as? NSNumber)?.intValue,
				let originY = (box["Y"] as? NSNumber)?.intValue,
				let width = (box["Width"] as? NSNumber)?.intValue,
				let height = (box["Height"] as? NSNumber)?.intValue
			else { return nil }
			return CGWindowEntry(
				number: CGWindowID(number), originX: originX, originY: originY, width: width, height: height
			)
		}
	}

	/// 取 Terminal 視窗的 bounds。
	private static func terminalWindowBounds(windowID: Int) async -> WindowBounds? {
		let script = "tell application \"Terminal\" to get bounds of window id \(windowID)"
		guard let out = try? await TerminalTools.runOsascript(script) else { return nil }
		return WindowBounds(appleScriptBounds: out)
	}

	/// 把 Terminal 視窗 bounds 轉成 screencapture `-R` 的 "x,y,width,height"。
	private static func terminalWindowRegion(windowID: Int) async -> String? {
		await terminalWindowBounds(windowID: windowID)?.region
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
}
