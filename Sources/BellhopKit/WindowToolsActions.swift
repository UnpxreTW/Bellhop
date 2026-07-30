//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP

// MARK: - + 動作面工具

/// 需要 macOS Accessibility 權限的工具實作（`window_focus`／`window_set_frame`／
/// `window_restore_layout`）。
///
/// 與唯讀／快照面分檔的理由不只是長度：這三顆是唯一會改變系統狀態的工具，
/// 權限需求與失敗模式（未授權、鎖屏、目標 app 無回應）都與快照面不同一掛。
/// AX 整合本體見 ``WindowActions``。
extension WindowTools {

	// MARK: Internal
	//
	// 三顆實作是 internal 而非 private——分派入口 `handle(name:arguments:)` 在
	// `WindowTools.swift`，跨檔的 extension 搆不到 private。

	/// 把還原結果組成回報文字。
	///
	/// 「搬了幾個」單獨看會騙人——照順序猜的配對、被 app 收斂掉的尺寸、被夾過的
	/// frame、搆不到的視窗都要一起攤出來，呼叫端才判得出這次還原可不可信。
	static func describe(
		_ outcome: WindowActions.RestoreOutcome,
		layoutName: String,
		preflightSkipped: [String],
		displaysChanged: Bool
	) -> String {
		var lines: [String] = ["Restored layout \"\(layoutName)\": moved \(outcome.moved) window(s)."]
		if displaysChanged {
			lines.append(
				"The display setup differs from the snapshot — frames were clamped into the current screens."
			)
		}
		if outcome.matchedByOrder > 0 {
			lines.append("""
				\(outcome.matchedByOrder) window(s) were matched by front-to-back order \
				rather than by title (titles unreadable or changed), so they may have \
				landed on the wrong window.
				""")
		}
		if !outcome.settledElsewhere.isEmpty {
			lines.append("""
				Moved but settled at a different frame (the app enforces a minimum size \
				or size increments): \(outcome.settledElsewhere.joined(separator: ", ")).
				""")
		}
		if !outcome.adjusted.isEmpty {
			lines.append("Clamped to fit the current screens: \(outcome.adjusted.joined(separator: ", ")).")
		}
		let skipped: [String] = outcome.skipped + preflightSkipped
		if !skipped.isEmpty {
			lines.append("Skipped \(skipped.count): \(skipped.joined(separator: "; ")).")
		}
		lines.append("Window stacking order and Space assignment are not restored.")
		return lines.joined(separator: "\n")
	}

	/// `window_focus` 實作。
	static func focusWindow(arguments: [String: Value]?) async -> CallTool.Result {
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

	/// `window_set_frame` 實作。
	static func setWindowFrame(arguments: [String: Value]?) async -> CallTool.Result {
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

	/// `window_restore_layout` 實作。
	static func restoreLayout(arguments: [String: Value]?) async -> CallTool.Result {
		guard
			let rawName = arguments?["name"]?.stringValue,
			let name = WindowLayout.sanitizedName(rawName)
		else {
			return errorResult("Missing or invalid `name` — pass a layout name from window_layout_list.")
		}
		let layout: WindowLayout
		do {
			let file: URL = try WindowLayout.layoutsDirectory().appendingPathComponent("\(name).json")
			layout = try WindowLayout.decoder().decode(WindowLayout.self, from: Data(contentsOf: file))
		} catch {
			return errorResult("""
				Could not read layout "\(name)" — check window_layout_list for saved \
				names. (\(error))
				""")
		}
		guard layout.version == 1 else {
			return errorResult("""
				Layout "\(name)" was written with schema version \(layout.version), \
				which this version of Bellhop cannot restore.
				""")
		}
		let displays: [WindowFrame] = displayFrames()
		let displaysChanged: Bool = !WindowLayout.displaysMatch(
			layout.displays, displays.map { .init(frame: $0) }
		)
		let plan: WindowLayoutRestore.Plan = WindowLayoutRestore.plan(for: layout.windows)
		do {
			let outcome: WindowActions.RestoreOutcome = try await WindowActions.restore(
				groups: plan.groups, displays: displays, clampToDisplays: displaysChanged
			)
			let report: String = describe(
				outcome, layoutName: name, preflightSkipped: plan.skipped, displaysChanged: displaysChanged
			)
			return .init(content: [.text(text: report, annotations: nil, _meta: nil)], isError: false)
		} catch {
			return errorResult("\(error)")
		}
	}

	// MARK: Private

	/// frame 的人可讀形（回報訊息用）。
	private static func describe(_ frame: WindowFrame) -> String {
		"{x: \(frame.originX), y: \(frame.originY), width: \(frame.width), height: \(frame.height)}"
	}
}
