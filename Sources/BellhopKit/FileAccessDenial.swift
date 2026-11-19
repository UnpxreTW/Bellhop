//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - FileAccessDenial

/// 一次被拒的檔案存取：原因碼，加上拒絕當下已取得的真實路徑。
///
/// 真實路徑只寫進稽核紀錄、不回給 client——回給 client 的錯誤訊息只帶原因碼與請求路徑。
internal struct FileAccessDenial: Error, Equatable, Sendable {

	/// 拒絕原因。
	internal let reason: FileAccessReason

	/// 開啟階段由 fd 取得的真實路徑；在字面階段就被拒時為 nil。
	internal let realPath: String?

	/// 逐欄建立；真實路徑預設為 nil（字面階段的拒絕）。
	internal init(_ reason: FileAccessReason, realPath: String? = nil) {
		self.reason = reason
		self.realPath = realPath
	}
}
