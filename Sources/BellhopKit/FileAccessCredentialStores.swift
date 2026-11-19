//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - FileAccessCredentialStores

/// 內建硬拒清單：通用的憑證與金鑰位置，政策檔蓋不掉。
///
/// 本清單是下限、不是完整清單——使用者要再擋的位置寫進政策的 `denies`。比對一律
/// 不分大小寫、兩側先做 Unicode NFC 正規化；判定流程對字面正規化路徑與 fd 取得的
/// 真實路徑各檢查一次。
///
/// 三類規則：
/// - ``segmentNames``：任一路徑段等於其中之一。
/// - ``homeRelativePaths``：家目錄下的相對路徑，該路徑本身與其下所有內容。
/// - ``fileNamePatterns``：最末路徑段符合檔名樣式；`*` 只出現在樣式頭或尾。
internal enum FileAccessCredentialStores {

	// MARK: Internal

	/// 任一路徑段等於這些名稱即拒。
	internal static let segmentNames: [String] = [".ssh", ".gnupg", ".aws", ".azure", ".kube"]

	/// 家目錄下的這些相對路徑（含其下所有內容）一律拒。
	internal static let homeRelativePaths: [String] = [
		".docker/config.json",
		".config/gh",
		".config/gcloud",
		".netrc",
		".npmrc",
		".pypirc",
		".git-credentials",
		".claude.json",
		"Library/Keychains",
		"Library/Application Support/com.apple.TCC",
		"Library/Application Support/Bellhop"
	]

	/// 最末路徑段符合這些檔名樣式即拒；`*` 代表任意字元序列（含空字串）。
	internal static let fileNamePatterns: [String] = [
		".env",
		".env.*",
		"*.pem",
		"*.p12",
		"*.pfx",
		"*.p8",
		"*.key",
		"*.keychain",
		"*.keychain-db",
		"*.mobileprovision",
		"id_rsa*",
		"id_dsa*",
		"id_ecdsa*",
		"id_ed25519*"
	]

	/// 路徑是否命中內建硬拒清單。
	///
	/// - Parameters:
	///   - path: 已字面正規化的絕對路徑。
	///   - homeDirectories: 家目錄的各種形（字面路徑與真實路徑），相對路徑類規則對每一形都比對。
	internal static func contains(_ path: String, homeDirectories: [String]) -> Bool {
		let components: [String] = FileAccessPath.components(
			of: FileAccessPath.comparable(path, caseInsensitive: true)
		)
		let hitsSegment: Bool = components.contains { component in
			foldedSegmentNames.contains { FileAccessPath.sameBytes($0, component) }
		}
		if hitsSegment { return true }
		let name: String = components.last ?? ""
		if foldedFileNamePatterns.contains(where: { matches(name, pattern: $0) }) { return true }
		return homeDirectories.contains { home in
			homeRelativePaths.contains { relative in
				FileAccessPath.isWithin(path, ancestor: home + "/" + relative, caseInsensitive: true)
			}
		}
	}

	/// 檔名是否符合單一樣式；`*` 只支援出現在樣式頭（後綴比對）或尾（前綴比對）。
	///
	/// 以 UTF-8 位元組比對（理由見 ``FileAccessPath/sameBytes(_:_:)``）：`id_rsa` 後面接組合字元的檔名
	/// 照樣符合 `id_rsa*`。
	///
	/// - Parameters:
	///   - name: 已轉成比對形的檔名。
	///   - pattern: 已轉成比對形的樣式。
	internal static func matches(_ name: String, pattern: String) -> Bool {
		let nameBytes: [UInt8] = Array(name.utf8)
		if pattern.hasPrefix("*") {
			let suffix: [UInt8] = Array(pattern.utf8.dropFirst())
			return nameBytes.count >= suffix.count && nameBytes.suffix(suffix.count).elementsEqual(suffix)
		}
		if pattern.hasSuffix("*") { return nameBytes.starts(with: pattern.utf8.dropLast()) }
		return nameBytes.elementsEqual(pattern.utf8)
	}

	// MARK: Private

	/// ``segmentNames`` 的比對形（NFC＋小寫）。
	private static let foldedSegmentNames: [String] = segmentNames.map {
		FileAccessPath.comparable($0, caseInsensitive: true)
	}

	/// ``fileNamePatterns`` 的比對形（NFC＋小寫）。
	private static let foldedFileNamePatterns: [String] = fileNamePatterns.map {
		FileAccessPath.comparable($0, caseInsensitive: true)
	}
}
