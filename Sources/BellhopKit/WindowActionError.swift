//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import ApplicationServices
import Foundation

// MARK: - WindowActionError

/// 動作面（AX 整合）失敗。
enum WindowActionError: Error {

	/// 宿主 app 未授 macOS Accessibility 權限。
	case notTrusted

	/// 過濾字串找不到任何執行中的 app。
	case appNotFound(String)

	/// 過濾字串命中多個 app、無法收斂（附候選描述清單）。
	case ambiguousApp(String, [String])

	/// app 在當前 Space 沒有任何 AX 可及的視窗。
	case noWindows(String)

	/// 指定標題比對不到視窗（附可用標題清單）。
	case windowTitleNotFound(String, String, [String])

	/// AX 呼叫失敗（附操作描述與錯誤碼）。
	case axFailed(String, AXError)
}

// MARK: - + CustomStringConvertible

extension WindowActionError: CustomStringConvertible {

	var description: String {
		switch self {
		case .notTrusted:
			"""
			macOS Accessibility permission has not been granted to the app hosting \
			Bellhop (the MCP client that spawned it, such as Terminal or Claude \
			Desktop). Grant it in System Settings > Privacy & Security > \
			Accessibility, then try again.
			"""
		case let .appNotFound(filter):
			"No running app matches \"\(filter)\" — check window_list for app names and bundle ids."
		case let .ambiguousApp(filter, candidates):
			"""
			"\(filter)" matches more than one running app — use a more specific name \
			or a bundle id. Matches: \(candidates.joined(separator: ", ")).
			"""
		case let .noWindows(appName):
			"""
			\(appName) has no windows reachable via Accessibility on the current \
			Space (windows on other Spaces cannot be reached).
			"""
		case let .windowTitleNotFound(title, appName, available):
			"""
			No window of \(appName) has a title containing "\(title)". Available \
			titles: \(available.joined(separator: ", ")).
			"""
		case let .axFailed(operation, error):
			"Accessibility call failed while trying to \(operation) (AXError \(error.rawValue))."
		}
	}
}
