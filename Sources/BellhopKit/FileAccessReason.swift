//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - FileAccessReason

/// 檔案存取被拒的原因碼。
///
/// raw value 即工具錯誤訊息與稽核紀錄裡出現的字串；集合固定，判定流程中任何
/// 未預期的狀況都收斂到其中一個值，不另造新碼。
internal enum FileAccessReason: String, Error, Codable, Sendable, CaseIterable {

	/// 政策檔存在但讀不到、不是合法 JSON，或欄位值不合法（fail-closed）。
	case policyUnavailable

	/// 政策的 `enabled` 為 `false`；政策檔不存在時的空政策也落在這裡。
	case disabled

	/// 請求路徑為空字串、含 NUL，或不是絕對路徑也不以 `~` 開頭。
	case invalidPath

	/// 路徑命中內建硬拒清單（``FileAccessCredentialStores``）。
	case credentialStore

	/// 路徑落在政策 `denies` 的某個前綴之下。
	case userDenied

	/// 路徑不在任何有效 root 之下。
	case outsideRoots

	/// 所屬 root 的 `listable` 為 `false`，不可列目錄。
	case notListable

	/// 型別不符工具要求（讀取要 regular file、列目錄要 directory），或是 FIFO、device 等其他型別。
	case unsupportedFileType

	/// 檔案大小超過讀取上限。
	case tooLarge

	/// 檔案內容不是合法 UTF-8。
	case notText

	/// 系統呼叫失敗（含路徑不存在），或稽核紀錄寫不進去。
	case ioError
}
