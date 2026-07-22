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

// MARK: - WindowTools

/// 跨 App 通用視窗工具。
///
/// 曝光面兩類：**零新權限**的唯讀／快照面（`window_list`／`window_save_layout`／
/// `window_layout_list`）＋需要 macOS Accessibility 權限的動作面 primitive
/// （`window_focus`／`window_set_frame`，AX 整合見 ``WindowActions``）。
/// 走原生選單的 `window_arrange` 與 `window_restore_layout` 的 typed schema
/// 已定義於 ``plannedTools`` 但尚未曝光——等選單尋址（AXIdentifier 有無）
/// 實機驗證完成後接上。視窗標題僅在宿主 app 已授 Screen Recording 權限時
/// 可讀（幾何與 owner 資訊免權限）。工具 schema 本體見 `WindowToolsSchemas.swift`。
enum WindowTools {

	// MARK: Internal

	/// 此工具群是否擁有某工具名（供 server 路由）。
	static func owns(_ name: String) -> Bool {
		name.hasPrefix("window_")
	}

	/// 將 tool 呼叫分派到對應實作。
	///
	/// 工具層失敗依 MCP 慣例以 `isError: true` 回傳、不丟例外。
	static func handle(name: String, arguments: [String: Value]?) async -> CallTool.Result {
		switch name {
		case "window_list":
			windowList(arguments: arguments)
		case "window_save_layout":
			saveLayout(arguments: arguments)
		case "window_layout_list":
			layoutList()
		case "window_focus":
			await focusWindow(arguments: arguments)
		case "window_set_frame":
			await setWindowFrame(arguments: arguments)
		case "window_arrange", "window_restore_layout":
			errorResult("""
				\(name) is not available yet — its Accessibility-based implementation \
				(native menu addressing for arrange, window matching for layout \
				restore) has not landed. Currently available: window_list, \
				window_save_layout, window_layout_list, window_focus, window_set_frame.
				""")
		default:
			errorResult("Unknown tool: \(name)")
		}
	}

	/// 視窗記錄是否命中 app 過濾字串（app 顯示名或 bundle id 的不分大小寫子字串）。
	static func matchesApp(_ record: WindowRecord, filter: String) -> Bool {
		if record.ownerName.localizedCaseInsensitiveContains(filter) { return true }
		if let bundleID = record.bundleID, bundleID.localizedCaseInsensitiveContains(filter) { return true }
		return false
	}

	/// 把視窗記錄編成 JSON 字串（`window_list` 的輸出形）。
	static func encodeRecords(_ records: [WindowRecord]) throws -> String {
		let data: Data = try WindowLayout.encoder().encode(records)
		return String(data: data, encoding: .utf8) ?? ""
	}

	// MARK: Private

	/// 快照當下的螢幕排列（CGDisplayBounds 原生即 CG 全域左上座標、與視窗 frame 同座標系）。
	///
	/// 走 CoreGraphics 而非 `NSScreen`：Bellhop 是 client spawn 的 stdio process、
	/// 沒有 NSApplication 生命週期，handler 又跑在任意執行緒——AppKit 的螢幕
	/// 列舉在這種環境下無行為保證，CG API 則明確可用。
	private static func displayFrames() -> [WindowFrame] {
		var displayCount: UInt32 = 0
		guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { return [] }
		var displayIDs: [CGDirectDisplayID] = .init(repeating: 0, count: Int(displayCount))
		guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else { return [] }
		return displayIDs.prefix(Int(displayCount)).map { displayID in
			let bounds: CGRect = CGDisplayBounds(displayID)
			return WindowFrame(
				originX: Int(bounds.origin.x.rounded()),
				originY: Int(bounds.origin.y.rounded()),
				width: Int(bounds.width.rounded()),
				height: Int(bounds.height.rounded())
			)
		}
	}

	/// 快照當下的螢幕排列與全部一般層級視窗（跨 Space、含最小化）。
	private static func snapshot() -> (displays: [WindowLayout.Display], windows: [WindowRecord]) {
		let frames: [WindowFrame] = displayFrames()
		let displays: [WindowLayout.Display] = frames.map { .init(frame: $0) }
		guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
			return (displays, [])
		}
		var bundleIDCache: [Int: String?] = [:]
		let windows: [WindowRecord] = list.compactMap { window in
			guard
				(window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
				let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
				let box = window[kCGWindowBounds as String] as? [String: Any],
				let originX = (box["X"] as? NSNumber)?.intValue,
				let originY = (box["Y"] as? NSNumber)?.intValue,
				let width = (box["Width"] as? NSNumber)?.intValue,
				let height = (box["Height"] as? NSNumber)?.intValue,
				width > 0, height > 0
			else { return nil }
			let bundleID: String? = bundleIDCache[
				pid, default: NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
			]
			bundleIDCache[pid] = bundleID
			let frame: WindowFrame = .init(originX: originX, originY: originY, width: width, height: height)
			return WindowRecord(
				bundleID: bundleID,
				ownerName: window[kCGWindowOwnerName as String] as? String ?? "(unknown)",
				title: window[kCGWindowName as String] as? String,
				frame: frame,
				onScreen: (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
				minimized: nil,
				displayIndex: WindowLayout.displayIndex(for: frame, in: frames),
				windowNumber: (window[kCGWindowNumber as String] as? NSNumber)?.intValue
			)
		}
		return (displays, windows)
	}

	private static func windowList(arguments: [String: Value]?) -> CallTool.Result {
		let filter: String = arguments?["app"]?.stringValue ?? ""
		let includeOffscreen: Bool = arguments?["include_offscreen"]?.boolValue ?? true
		var records: [WindowRecord] = snapshot().windows
		if !includeOffscreen { records = records.filter(\.onScreen) }
		if !filter.isEmpty { records = records.filter { matchesApp($0, filter: filter) } }
		guard !records.isEmpty else {
			return .init(
				content: [.text(text: "(no matching windows)", annotations: nil, _meta: nil)],
				isError: false
			)
		}
		do {
			let json: String = try encodeRecords(records)
			return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
		} catch {
			return errorResult("Error: \(error)")
		}
	}

	private static func saveLayout(arguments: [String: Value]?) -> CallTool.Result {
		guard
			let rawName = arguments?["name"]?.stringValue,
			let name = WindowLayout.sanitizedName(rawName)
		else {
			return errorResult(
				"Missing or invalid `name` — use a plain file name (no path separators, max 64 characters)."
			)
		}
		let (displays, windows) = snapshot()
		guard !windows.isEmpty else { return errorResult("No windows found to save.") }
		let layout: WindowLayout = .init(version: 1, savedAt: Date(), displays: displays, windows: windows)
		do {
			let directory: URL = try WindowLayout.layoutsDirectory()
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			let file: URL = directory.appendingPathComponent("\(name).json")
			try WindowLayout.encoder().encode(layout).write(to: file, options: .atomic)
			return .init(
				content: [
					.text(
						text: """
							Saved layout "\(name)" (\(windows.count) windows across \
							\(displays.count) displays) to \(file.path).
							""",
						annotations: nil, _meta: nil
					)
				],
				isError: false
			)
		} catch {
			return errorResult("Error: \(error)")
		}
	}

	private static func layoutList() -> CallTool.Result {
		do {
			let directory: URL = try WindowLayout.layoutsDirectory()
			let files: [URL] = ((try? FileManager.default.contentsOfDirectory(
				at: directory, includingPropertiesForKeys: nil
			)) ?? [])
				.filter { $0.pathExtension == "json" }
				.sorted { $0.lastPathComponent < $1.lastPathComponent }
			guard !files.isEmpty else {
				return .init(
					content: [.text(text: "(no saved layouts)", annotations: nil, _meta: nil)],
					isError: false
				)
			}
			let formatter: ISO8601DateFormatter = .init()
			let lines: [String] = files.map { file in
				let name: String = file.deletingPathExtension().lastPathComponent
				guard
					let data = try? Data(contentsOf: file),
					let layout = try? WindowLayout.decoder().decode(WindowLayout.self, from: data)
				else { return "\(name) — (unreadable)" }
				return "\(name) — saved \(formatter.string(from: layout.savedAt)), \(layout.windows.count) windows"
			}
			return .init(
				content: [.text(text: lines.joined(separator: "\n"), annotations: nil, _meta: nil)],
				isError: false
			)
		} catch {
			return errorResult("Error: \(error)")
		}
	}

	private static func focusWindow(arguments: [String: Value]?) async -> CallTool.Result {
		guard let app = arguments?["app"]?.stringValue, !app.isEmpty else {
			return errorResult("Missing `app` — the app to focus (name or bundle id).")
		}
		let windowTitle: String? = arguments?["window_title"]?.stringValue
		do {
			let message: String = try await WindowActions.focus(appFilter: app, windowTitle: windowTitle)
			return .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: false)
		} catch {
			return errorResult("\(error)")
		}
	}

	private static func setWindowFrame(arguments: [String: Value]?) async -> CallTool.Result {
		guard let app = arguments?["app"]?.stringValue, !app.isEmpty else {
			return errorResult("Missing `app` — the app owning the window (name or bundle id).")
		}
		guard
			let originX = arguments?["x"]?.intValue,
			let originY = arguments?["y"]?.intValue,
			let width = arguments?["width"]?.intValue,
			let height = arguments?["height"]?.intValue
		else {
			return errorResult("Missing or non-integer `x`/`y`/`width`/`height` — all four are required.")
		}
		guard width > 0, height > 0 else {
			return errorResult("`width` and `height` must be positive.")
		}
		let target: WindowFrame = .init(originX: originX, originY: originY, width: width, height: height)
		let windowTitle: String? = arguments?["window_title"]?.stringValue
		do {
			let outcome: WindowActions.SetFrameOutcome = try await WindowActions.setFrame(
				appFilter: app, windowTitle: windowTitle, target: target
			)
			let windowLabel: String = "\"\(outcome.windowTitle ?? "(untitled)")\" of \(outcome.appName)"
			guard outcome.final == outcome.requested else {
				return .init(
					content: [
						.text(
							text: """
								Moved \(windowLabel) — the app settled at \
								\(describe(outcome.final)) instead of the requested \
								\(describe(outcome.requested)) (apps may enforce minimum \
								sizes or size increments).
								""",
							annotations: nil, _meta: nil
						)
					],
					isError: false
				)
			}
			return .init(
				content: [
					.text(
						text: "Moved \(windowLabel) to \(describe(outcome.final)).",
						annotations: nil, _meta: nil
					)
				],
				isError: false
			)
		} catch {
			return errorResult("\(error)")
		}
	}

	/// frame 的人可讀形（回報訊息用）。
	private static func describe(_ frame: WindowFrame) -> String {
		"{x: \(frame.originX), y: \(frame.originY), width: \(frame.width), height: \(frame.height)}"
	}

	private static func errorResult(_ message: String) -> CallTool.Result {
		.init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
	}
}
