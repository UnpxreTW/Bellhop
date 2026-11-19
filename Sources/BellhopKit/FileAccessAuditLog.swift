//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

// MARK: - FileAccessAuditLog

/// 稽核紀錄的預設寫入端：JSON Lines 檔，以附加方式寫入。
///
/// 預設位置 `~/Library/Application Support/Bellhop/file-access-audit.jsonl`；新建的目錄
/// 權限 0700、檔案 0600。開檔帶 `O_NOFOLLOW`，紀錄檔位置被換成 symlink 時寫入失敗、
/// 該次工具呼叫即被拒，而不是把紀錄寫到別處。
internal struct FileAccessAuditLog: Sendable {

	// MARK: Internal

	/// 寫入失敗。
	internal enum WriteError: Error {

		/// 開檔失敗（附 `errno`）。
		case openFailed(Int32)

		/// 寫入失敗或只寫進一部分（附 `errno`）。
		case writeFailed(Int32)
	}

	/// 紀錄檔相對於家目錄的預設位置。
	internal static let defaultRelativePath: String = "Library/Application Support/Bellhop/file-access-audit.jsonl"

	/// 紀錄檔位置。
	internal let fileURL: URL

	/// 附加一筆紀錄；目錄不存在時以 0700 建立，檔案不存在時以 0600 建立。
	internal func append(_ record: FileAccessAuditRecord) throws {
		let line: Data = try record.jsonLine()
		try FileManager.default.createDirectory(
			at: fileURL.deletingLastPathComponent(),
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		let descriptor: Int32 = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
		guard descriptor >= 0 else { throw WriteError.openFailed(errno) }
		defer { close(descriptor) }
		let written: Int = line.withUnsafeBytes { buffer in
			write(descriptor, buffer.baseAddress, buffer.count)
		}
		guard written == line.count else { throw WriteError.writeFailed(errno) }
	}
}
