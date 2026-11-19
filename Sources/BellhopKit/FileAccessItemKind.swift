//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Darwin

// MARK: - FileAccessItemKind

/// 檔案系統項目的型別；raw value 即工具輸出 JSON 的 `type` 欄。
internal enum FileAccessItemKind: String, Codable, Sendable {

	/// regular file。
	case file

	/// 目錄。
	case directory

	/// symbolic link（只出現在 `file_list` 的項目裡；列目錄時不追蹤連結）。
	case symlink

	/// FIFO、socket、device 等其他型別。
	case other

	/// 由 `stat` 的 `st_mode` 判型別。
	internal init(mode: mode_t) {
		switch mode & S_IFMT {
		case S_IFREG:
			self = .file
		case S_IFDIR:
			self = .directory
		case S_IFLNK:
			self = .symlink
		default:
			self = .other
		}
	}
}
