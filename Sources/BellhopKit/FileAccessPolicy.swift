//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - FileAccessPolicy

/// 檔案存取政策：預設全拒，只服務明列的 root。
///
/// 政策檔為 JSON，預設位置 `~/Library/Application Support/Bellhop/file-access-policy.json`
/// （該目錄本身在內建硬拒清單內，工具讀不到自己的政策與稽核紀錄）：
///
/// ```json
/// {
///   "enabled": true,
///   "roots": [
///     { "path": "~/Documents/Notes", "listable": true },
///     { "path": "/Volumes/Shared/Reports", "listable": false }
///   ],
///   "denies": ["~/Documents/Notes/private"]
/// }
/// ```
///
/// - `enabled` 必填；`false` 為全拒。
/// - `roots` 選填（預設空）；`listable` 選填（預設 `false`）。`listable` 為 `false` 的 root
///   只能對已知路徑查屬性與讀取，不能列目錄。
/// - `denies` 選填（預設空）；使用者自訂的拒絕前綴。
///
/// 載入規則（``load(from:)``）：檔不存在＝空政策＝全拒；讀檔失敗、JSON 不合法、出現未知的鍵、或 `roots`／
/// `denies` 中有路徑不是絕對路徑也不以 `~` 開頭＝``FileAccessReason/policyUnavailable``。
/// 工具每次呼叫都重新載入，不跨呼叫快取允許結果。
internal struct FileAccessPolicy: Codable, Equatable, Sendable {

	// MARK: Lifecycle

	/// 逐欄建立。
	internal init(enabled: Bool, roots: [FileAccessPolicyRoot], denies: [String]) {
		self.enabled = enabled
		self.roots = roots
		self.denies = denies
	}

	/// 自 JSON 解碼；`enabled` 必填，`roots`、`denies` 缺省為空陣列。
	internal init(from decoder: any Decoder) throws {
		let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
		enabled = try container.decode(Bool.self, forKey: .enabled)
		roots = try container.decodeIfPresent([FileAccessPolicyRoot].self, forKey: .roots) ?? []
		denies = try container.decodeIfPresent([String].self, forKey: .denies) ?? []
	}

	// MARK: Internal

	/// 政策檔不存在時採用的空政策（全拒）。
	internal static let empty: FileAccessPolicy = .init(enabled: false, roots: [], denies: [])

	/// 政策檔相對於家目錄的預設位置。
	internal static let defaultRelativePath: String = "Library/Application Support/Bellhop/file-access-policy.json"

	/// 總開關；`false` 為全拒。
	internal let enabled: Bool

	/// 可服務的資料夾。
	internal let roots: [FileAccessPolicyRoot]

	/// 使用者自訂的拒絕前綴。
	internal let denies: [String]

	/// 自政策檔載入。
	///
	/// - Parameter url: 政策檔位置（呼叫端注入）。
	/// - Returns: 載入的政策；檔不存在回 ``empty``。讀檔失敗、解析失敗或欄位不合法回 nil，
	///   呼叫端以 ``FileAccessReason/policyUnavailable`` 拒絕。
	internal static func load(from url: URL) -> FileAccessPolicy? {
		let data: Data
		do {
			data = try Data(contentsOf: url)
		} catch CocoaError.fileReadNoSuchFile {
			return empty
		} catch {
			return nil
		}
		// 解析失敗的原因不影響處置（一律 policyUnavailable），故以 try? 收斂、不保留錯誤細節。
		guard let policy: FileAccessPolicy = try? JSONDecoder().decode(FileAccessPolicy.self, from: data) else { return nil }
		return policy.hasValidPaths && hasOnlyKnownKeys(data) ? policy : nil
	}

	/// `roots` 與 `denies` 的每個路徑是否都是絕對路徑或以 `~` 開頭（不含 NUL）。
	internal var hasValidPaths: Bool {
		let paths: [String] = roots.map(\.path) + denies
		return paths.allSatisfy { FileAccessPath.expand($0, homeDirectory: "/") != nil }
	}

	// MARK: Private

	/// 對應政策 JSON 的鍵名。
	private enum CodingKeys: String, CodingKey {
		case enabled
		case roots
		case denies
	}

	/// 政策 JSON 是否只用到已知的鍵（頂層與每個 root）。
	///
	/// 拼錯的鍵（例如把 `denies` 打成 `deny`）會讓該欄落回缺省值、少擋東西，所以未知鍵一律視為不合法。
	private static func hasOnlyKnownKeys(_ data: Data) -> Bool {
		// 解析失敗的細節不影響處置（一律視為不合法），故以 try? 收斂。
		guard let object: [String: Any] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
			return false
		}
		guard Set(object.keys).isSubset(of: ["enabled", "roots", "denies"]) else { return false }
		let roots: [Any] = object["roots"] as? [Any] ?? []
		return roots.allSatisfy { root in
			guard let fields: [String: Any] = root as? [String: Any] else { return false }
			return Set(fields.keys).isSubset(of: ["path", "listable"])
		}
	}
}
