//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - + 輸出形

/// 三顆工具回給 client 的 JSON 形（編碼時屬性名轉 snake_case，時間為 ISO 8601）。
extension FileTools {

	/// `file_stat` 的輸出。
	internal struct StatOutput: Encodable {

		/// `file` 或 `directory`。
		internal let type: FileAccessItemKind

		/// 位元組數。
		internal let size: Int64

		/// 最後修改時間。
		internal let modified: Date

		/// fd 的真實路徑。
		internal let realPath: String
	}

	/// `file_list` 的一個項目。
	internal struct ListEntry: Encodable, Equatable {

		/// 項目名稱（單層、不含路徑）。
		internal let name: String

		/// 型別；symlink 不追蹤、以 `symlink` 回報。
		internal let type: FileAccessItemKind

		/// 位元組數；`fstatat` 失敗（例如列出後即被刪除）時為 nil。
		internal let size: Int64?

		/// 最後修改時間；`fstatat` 失敗時為 nil。
		internal let modified: Date?
	}

	/// `file_list` 的輸出。
	internal struct ListOutput: Encodable {

		/// 目錄的真實路徑。
		internal let path: String

		/// 依名稱排序後的前 ``FileTools/maximumListEntries`` 筆項目。
		internal let entries: [ListEntry]

		/// 項目總數超過上限、只回傳了前段。
		internal let truncated: Bool
	}

	/// `file_read` 的輸出。
	internal struct ReadOutput: Encodable, Equatable {

		/// 切出的文字（行間以 `\n` 相接、末行不帶換行）。
		internal let content: String

		/// 起始行（1 起算）。
		internal let offset: Int

		/// 本次回傳的行數。
		internal let lineCount: Int

		/// 檔案總行數。
		internal let totalLines: Int
	}
}
