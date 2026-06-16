//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - TerminalError

/// osascript 執行失敗。
enum TerminalError: Error {

	case osascriptFailed(String)
}

// MARK: - + CustomStringConvertible

extension TerminalError: CustomStringConvertible {

	var description: String {
		switch self {
		case let .osascriptFailed(message):
			"osascript failed: \(message)"
		}
	}
}
