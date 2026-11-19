//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - FileToolsEnvironment

/// ``FileTools`` 的外部相依：政策來源、家目錄、稽核紀錄寫入端、時鐘。
///
/// 全部可注入——測試以暫存目錄的政策檔、假家目錄、記憶體內的紀錄端與固定時鐘取代，
/// 不碰真實家目錄下的任何位置。
internal struct FileToolsEnvironment: Sendable {

	// MARK: Lifecycle

	/// 逐欄建立。
	///
	/// - Parameters:
	///   - policyURL: 政策檔位置；每次工具呼叫都重新讀取。
	///   - homeDirectory: 家目錄，用於展開 `~` 與比對家目錄相對的硬拒路徑。
	///   - audit: 稽核紀錄寫入端；丟錯＝紀錄寫不進去。
	///   - now: 時鐘。
	internal init(
		policyURL: URL,
		homeDirectory: String,
		audit: @escaping @Sendable (FileAccessAuditRecord) throws -> Void,
		now: @escaping @Sendable () -> Date
	) {
		self.policyURL = policyURL
		self.homeDirectory = homeDirectory
		self.audit = audit
		self.now = now
	}

	// MARK: Internal

	/// 政策檔位置。
	internal let policyURL: URL

	/// 家目錄。
	internal let homeDirectory: String

	/// 稽核紀錄寫入端。
	internal let audit: @Sendable (FileAccessAuditRecord) throws -> Void

	/// 時鐘。
	internal let now: @Sendable () -> Date

	/// 實際執行用的環境：目前使用者的家目錄、預設的政策檔與稽核紀錄位置、系統時鐘。
	internal static func live() -> FileToolsEnvironment {
		let home: URL = FileManager.default.homeDirectoryForCurrentUser
		let log: FileAccessAuditLog = .init(
			fileURL: home.appendingPathComponent(FileAccessAuditLog.defaultRelativePath)
		)
		return .init(
			policyURL: home.appendingPathComponent(FileAccessPolicy.defaultRelativePath),
			homeDirectory: home.path,
			audit: { try log.append($0) },
			now: { Date() }
		)
	}
}
