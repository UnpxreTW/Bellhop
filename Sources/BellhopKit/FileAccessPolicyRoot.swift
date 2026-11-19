//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - FileAccessPolicyRoot

/// 政策中的一個可服務資料夾（``FileAccessPolicy/roots`` 的元素）。
internal struct FileAccessPolicyRoot: Codable, Equatable, Sendable {

	// MARK: Lifecycle

	/// 逐欄建立。
	internal init(path: String, listable: Bool) {
		self.path = path
		self.listable = listable
	}

	/// 自 JSON 解碼；`path` 必填，`listable` 缺省為 `false`（較嚴的一側）。
	internal init(from decoder: any Decoder) throws {
		let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
		path = try container.decode(String.self, forKey: .path)
		listable = try container.decodeIfPresent(Bool.self, forKey: .listable) ?? false
	}

	// MARK: Internal

	/// 絕對路徑或以 `~` 開頭的路徑。
	internal let path: String

	/// 是否允許列出此 root 之下的目錄；`false` 時只能對已知路徑查屬性與讀取。
	internal let listable: Bool

	// MARK: Private

	/// 對應 root JSON 物件的鍵名。
	private enum CodingKeys: String, CodingKey {
		case path
		case listable
	}
}
