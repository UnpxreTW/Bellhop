//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - FileAccessAuditRecord

/// 稽核紀錄的一行：每次檔案工具呼叫一筆，允許與拒絕都記。
///
/// 只記存取的中繼資料——不記檔案內容，也不記列目錄得到的檔名。編碼為單行 JSON
/// （``jsonLine()``），鍵為 `time`、`tool`、`requested_path`、`real_path`（取得了才有）、
/// `result`（`allow`／`deny`）、`reason`（允許時為 `null`）。
internal struct FileAccessAuditRecord: Encodable, Equatable, Sendable {

	// MARK: Internal

	/// 存取結果。
	internal enum Outcome: String, Encodable, Sendable {

		/// 允許。
		case allow

		/// 拒絕。
		case deny
	}

	/// 呼叫時間。
	internal let time: Date

	/// 工具名。
	internal let tool: String

	/// client 送來的原始路徑。
	internal let requestedPath: String

	/// 開啟階段由 fd 取得的真實路徑；未走到開啟階段時為 nil。
	internal let realPath: String?

	/// 存取結果。
	internal let outcome: Outcome

	/// 拒絕原因；允許時為 nil。
	internal let reason: FileAccessReason?

	/// 依鍵名規格編碼；`reason` 一律輸出（允許時為 `null`），`real_path` 取得了才輸出。
	internal func encode(to encoder: any Encoder) throws {
		var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(time.formatted(.iso8601), forKey: .time)
		try container.encode(tool, forKey: .tool)
		try container.encode(requestedPath, forKey: .requestedPath)
		try container.encodeIfPresent(realPath, forKey: .realPath)
		try container.encode(outcome, forKey: .outcome)
		try container.encode(reason, forKey: .reason)
	}

	/// 編成單行 JSON（含結尾換行）。
	internal func jsonLine() throws -> Data {
		let encoder: JSONEncoder = .init()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		var data: Data = try encoder.encode(self)
		data.append(0x0A)
		return data
	}

	// MARK: Private

	/// 稽核紀錄 JSON 的鍵名（snake_case；`outcome` 對應 `result`）。
	private enum CodingKeys: String, CodingKey {
		case time
		case tool
		case requestedPath = "requested_path"
		case realPath = "real_path"
		case outcome = "result"
		case reason
	}
}
