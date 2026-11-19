//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

// MARK: - FileAccessOpenedItem

/// 通過開啟階段的檔案或目錄：持有 fd，釋放時關閉。
///
/// 後續的讀取與列目錄一律經這個 fd，不再以路徑重新開啟——檢查與使用之間路徑被換掉
/// （例如換成 symlink）也碰不到檢查過的對象以外的東西。
internal final class FileAccessOpenedItem {

	// MARK: Lifecycle

	/// 接手一個已開啟的 fd 與其檢查結果；之後由本物件負責關閉。
	///
	/// - Parameters:
	///   - descriptor: 開啟階段取得的 fd。
	///   - realPath: `F_GETPATH` 取得的真實路徑。
	///   - root: 命中的 root。
	///   - status: `fstat` 結果。
	internal init(descriptor: Int32, realPath: String, root: FileAccessResolvedRoot, status: stat) {
		self.descriptor = descriptor
		self.realPath = realPath
		self.root = root
		self.kind = FileAccessItemKind(mode: status.st_mode)
		self.size = Int64(status.st_size)
		self.modificationDate = Self.date(from: status.st_mtimespec)
	}

	/// 關閉持有的 fd。
	deinit {
		close(descriptor)
	}

	// MARK: Internal

	/// 開啟中的 fd。
	internal let descriptor: Int32

	/// fd 的真實路徑。
	internal let realPath: String

	/// 命中的 root。
	internal let root: FileAccessResolvedRoot

	/// 型別（開啟階段只放行 file 與 directory）。
	internal let kind: FileAccessItemKind

	/// 位元組數。
	internal let size: Int64

	/// 最後修改時間。
	internal let modificationDate: Date

	/// 把 `stat` 的 `timespec` 換成 `Date`。
	internal static func date(from time: timespec) -> Date {
		Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
	}
}
