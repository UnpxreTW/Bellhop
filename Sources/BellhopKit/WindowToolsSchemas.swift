//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP

// MARK: - + 工具 schema

extension WindowTools {

	/// 對 client 曝光的工具，依列出順序。
	static let all: [Tool] = [
		Tool(
			name: "window_list",
			description: """
				List windows across all running apps: app name, bundle id, frame \
				(global top-left coordinates), which display it is on, and whether it \
				is currently on screen (off screen = minimized or on another Space). \
				Read-only, needs no extra permission; window titles appear only when \
				the host app has macOS Screen Recording permission.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"app": .object([
						"type": .string("string"),
						"description": .string(
							"Only include windows whose app name or bundle id contains this text (case-insensitive)."
						)
					]),
					"include_offscreen": .object([
						"type": .string("boolean"),
						"description": .string(
							"Include windows that are minimized or on another Space. Defaults to true."
						)
					])
				])
			])
		),
		Tool(
			name: "window_save_layout",
			description: """
				Save a named snapshot of the current window arrangement (all apps, \
				including windows on other Spaces) to Application Support/Bellhop/layouts/. \
				Window titles are included only when the host app has Screen Recording \
				permission; without titles, restoring later matches windows per app only.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"name": .object([
						"type": .string("string"),
						"description": .string(
							"Layout name (plain file name, no path separators; max 64 characters)."
						)
					])
				]),
				"required": .array([.string("name")])
			])
		),
		Tool(
			name: "window_layout_list",
			description: """
				List saved window layouts with when each was saved and how many \
				windows it recorded.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([:])
			])
		),
		Tool(
			name: "window_focus",
			description: """
				Bring a window to the front and focus its app. Requires macOS \
				Accessibility permission; does not work while the screen is locked.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"app": .object([
						"type": .string("string"),
						"description": .string("App to focus (name or bundle id).")
					]),
					"window_title": .object([
						"type": .string("string"),
						"description": .string(
							"Title of the window to raise. Defaults to the app's front window."
						)
					])
				]),
				"required": .array([.string("app")])
			])
		),
		Tool(
			name: "window_set_frame",
			description: """
				Move and resize a window to an exact frame in global top-left \
				coordinates. Requires macOS Accessibility permission; does not work \
				while the screen is locked.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"app": .object([
						"type": .string("string"),
						"description": .string("App owning the window (name or bundle id).")
					]),
					"window_title": .object([
						"type": .string("string"),
						"description": .string(
							"Title of the window to move. Defaults to the app's front window."
						)
					]),
					"x": .object(["type": .string("integer"), "description": .string("Top-left x.")]),
					"y": .object(["type": .string("integer"), "description": .string("Top-left y.")]),
					"width": .object(["type": .string("integer"), "description": .string("Window width.")]),
					"height": .object(["type": .string("integer"), "description": .string("Window height.")])
				]),
				"required": .array([
					.string("app"), .string("x"), .string("y"), .string("width"), .string("height")
				])
			])
		)
	]

	/// 已定型但**尚未曝光**的動作面工具（需原生選單尋址實機驗證後接上）。
	///
	/// 先定 schema 的用意：把 client 可見的介面形狀先 review 定案，後續
	/// 只補實作、不再動介面。
	static let plannedTools: [Tool] = [
		Tool(
			name: "window_arrange",
			description: """
				Arrange a window using the native macOS "Move & Resize" positions \
				(fill, halves, quarters, center, or restore previous size). Falls back \
				to computed frames when the native menu is unavailable. Requires \
				macOS Accessibility permission; does not work while the screen is locked.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"position": .object([
						"type": .string("string"),
						"enum": .array(WindowPosition.allCases.map { .string($0.rawValue) }),
						"description": .string("Target position for the window.")
					]),
					"app": .object([
						"type": .string("string"),
						"description": .string(
							"App to act on (name or bundle id). Defaults to the frontmost app."
						)
					]),
					"window_title": .object([
						"type": .string("string"),
						"description": .string(
							"Title of the window to act on. Defaults to the app's front window."
						)
					])
				]),
				"required": .array([.string("position")])
			])
		),
		Tool(
			name: "window_restore_layout",
			description: """
				Restore a saved window layout. Only windows on the current Space can \
				be moved (macOS Accessibility limitation); windows it cannot reach are \
				reported as skipped. When the display setup differs from the snapshot, \
				frames are clamped into the current screens and annotated. Requires \
				macOS Accessibility permission; does not work while the screen is locked.
				""",
			inputSchema: .object([
				"type": .string("object"),
				"properties": .object([
					"name": .object([
						"type": .string("string"),
						"description": .string("Name of the saved layout (from window_layout_list).")
					])
				]),
				"required": .array([.string("name")])
			])
		)
	]
}
