//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - FileAccessChecker

/// 對單次請求套用 ``FileAccessPolicy`` 的判定器。
///
/// 判定流程（任一步不過即拒，判不出即拒）：
/// 1. 政策路徑欄不合法 → ``FileAccessReason/policyUnavailable``；`enabled` 為 `false` → ``FileAccessReason/disabled``。
/// 2. 輸入檢查：空字串、含 NUL、相對路徑 → ``FileAccessReason/invalidPath``；`~`、`~/…` 展開為家目錄。
/// 3. 字面階段（不碰檔案系統）：字面正規化 → 內建硬拒 → `denies` → 必須落在某個有效 root 之下。
/// 4. 開啟階段（``open(_:accepting:)``）：以 `O_RDONLY | O_CLOEXEC | O_NONBLOCK` 開啟 →
///    `F_GETPATH` 取 fd 的真實路徑 → 對真實路徑重做內建硬拒、`denies`、root 三項 → `fstat` 判型別。
///    之後的讀取一律用這個 fd，不再以路徑重新開啟。
///
/// root 的有效條件：路徑存在，且字面路徑、`realpath(3)` 形、`F_GETPATH` 形都不是 `/`、
/// 家目錄本身或家目錄的祖先（家目錄同樣取這三形比對）。不合條件的 root 直接略過、不報錯。
///
/// 大小寫的處理刻意不對稱：內建硬拒與 `denies` 不分大小寫（拒的一側放寬），root 前綴
/// 分大小寫（允許的一側收緊）。兩側皆先做 Unicode NFC 正規化。
internal struct FileAccessChecker: Sendable {

	// MARK: Lifecycle

	/// 以政策與家目錄建立判定器；root 與 `denies` 於此展開並解析真實路徑。
	///
	/// - Parameters:
	///   - policy: 本次呼叫載入的政策。
	///   - homeDirectory: 家目錄（可注入，測試用假家目錄）。
	internal init(policy: FileAccessPolicy, homeDirectory: String) {
		let home: String = FileAccessPath.lexicallyNormalized(homeDirectory)
		let homeForms: [String] = FileAccessPath.forms(of: home)
		self.enabled = policy.enabled
		self.wellFormed = policy.hasValidPaths
		self.homeDirectory = home
		self.homeForms = homeForms
		self.roots = policy.roots.compactMap { Self.resolveRoot($0, home: home, homeForms: homeForms) }
		self.denyPrefixes = policy.denies.flatMap { deny -> [String] in
			guard let expanded: String = FileAccessPath.expand(deny, homeDirectory: home) else { return [] }
			return FileAccessPath.forms(of: FileAccessPath.lexicallyNormalized(expanded))
		}
	}

	// MARK: Internal

	/// 政策總開關。
	internal let enabled: Bool

	/// 政策的 `roots`、`denies` 路徑是否都合法；不合法時一律拒（不靜默略過任何一條 deny）。
	internal let wellFormed: Bool

	/// 字面正規化後的家目錄。
	internal let homeDirectory: String

	/// 有效的 root（無效者已略過）。
	internal let roots: [FileAccessResolvedRoot]

	/// 家目錄的字面形、`realpath(3)` 形與 `F_GETPATH` 形（去重）。
	internal let homeForms: [String]

	/// `denies` 展開後的字面形，以及存在時的 `realpath(3)` 形與 `F_GETPATH` 形。
	internal let denyPrefixes: [String]

	/// 字面階段：輸入檢查、字面正規化、內建硬拒、`denies`、root。
	///
	/// - Parameter requested: client 送來的原始路徑。
	/// - Returns: 通過時為字面正規化後的路徑；不過時為原因碼。
	internal func checkLiteral(_ requested: String) -> Result<String, FileAccessReason> {
		guard wellFormed else { return .failure(.policyUnavailable) }
		guard enabled else { return .failure(.disabled) }
		guard let expanded: String = FileAccessPath.expand(requested, homeDirectory: homeDirectory) else {
			return .failure(.invalidPath)
		}
		let normalized: String = FileAccessPath.lexicallyNormalized(expanded)
		return check(normalized).map { _ in normalized }
	}

	/// 對一條已正規化的路徑做內建硬拒、`denies`、root 三項檢查。
	///
	/// 字面階段與開啟階段（真實路徑）共用。
	///
	/// - Returns: 通過時為命中的 root；同一路徑落在多個 root 之下時，任一個不可列目錄即回
	///   那一個（不可列優先），否則回最深的一個。
	internal func check(_ path: String) -> Result<FileAccessResolvedRoot, FileAccessReason> {
		if FileAccessCredentialStores.contains(path, homeDirectories: homeForms) { return .failure(.credentialStore) }
		if denyPrefixes.contains(where: { FileAccessPath.isWithin(path, ancestor: $0, caseInsensitive: true) }) {
			return .failure(.userDenied)
		}
		let matching: [FileAccessResolvedRoot] = roots.filter { root in
			root.paths.contains { FileAccessPath.isWithin(path, ancestor: $0, caseInsensitive: false) }
		}
		if let unlisted: FileAccessResolvedRoot = matching.first(where: { !$0.listable }) { return .success(unlisted) }
		guard let deepest: FileAccessResolvedRoot = matching.max(by: { $0.realPath.count < $1.realPath.count }) else {
			return .failure(.outsideRoots)
		}
		return .success(deepest)
	}

	// MARK: Private

	/// 展開並驗證一個 root；無效回 nil。
	private static func resolveRoot(
		_ root: FileAccessPolicyRoot,
		home: String,
		homeForms: [String]
	) -> FileAccessResolvedRoot? {
		guard let expanded: String = FileAccessPath.expand(root.path, homeDirectory: home) else { return nil }
		let literal: String = FileAccessPath.lexicallyNormalized(expanded)
		// 存在與否以 realpath(3) 判（只需搜尋權）；F_GETPATH 形對不存在的路徑也會接出結果，不能拿來判存在。
		guard let resolved: String = FileAccessPath.resolved(literal) else { return nil }
		let real: String = FileAccessPath.descriptorResolved(literal) ?? resolved
		let paths: [String] = FileAccessPath.forms(of: literal)
		// root 等於家目錄或為其祖先（含 `/`）即無效：任一形的家目錄落在任一形的 root 之下就算。
		let coversHome: Bool = paths.contains { candidate in
			homeForms.contains { FileAccessPath.isWithin($0, ancestor: candidate, caseInsensitive: true) }
		}
		guard !coversHome else { return nil }
		return .init(literalPath: literal, realPath: real, paths: paths, listable: root.listable)
	}
}
