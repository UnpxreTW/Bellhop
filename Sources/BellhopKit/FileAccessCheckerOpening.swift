//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Darwin

// MARK: - + 開啟階段

/// 判定流程的開啟階段：唯一碰檔案系統取得 fd 的地方。
///
/// 與字面階段分檔：字面階段是純字串運算、可在不碰檔案系統的情況下單獨測；開啟階段
/// 的失敗模式（路徑不存在、權限、型別）屬系統呼叫一側。
extension FileAccessChecker {

	// MARK: Internal

	/// 判定並開啟一條路徑：字面階段通過後開啟、以 fd 的真實路徑重驗、再判型別。
	///
	/// 開啟帶 `O_NONBLOCK`，所以 FIFO 不會在 `open(2)` 卡住，之後由型別檢查拒絕。
	///
	/// - Parameters:
	///   - requested: client 送來的原始路徑。
	///   - accepting: 可接受的型別（只認 ``FileAccessItemKind/file`` 與 ``FileAccessItemKind/directory``）。
	/// - Returns: 通過時為持有 fd 的 ``FileAccessOpenedItem``；不過時為拒絕原因與已取得的真實路徑。
	internal func open(
		_ requested: String,
		accepting: Set<FileAccessItemKind>
	) -> Result<FileAccessOpenedItem, FileAccessDenial> {
		let normalized: String
		switch checkLiteral(requested) {
		case let .success(path):
			normalized = path
		case let .failure(reason):
			return .failure(.init(reason))
		}
		let descriptor: Int32 = Darwin.open(normalized, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
		guard descriptor >= 0 else { return .failure(.init(.ioError)) }
		let result: Result<FileAccessOpenedItem, FileAccessDenial> = inspect(descriptor: descriptor, accepting: accepting)
		if case .failure = result { close(descriptor) }
		return result
	}

	// MARK: Private

	/// 開啟後的檢查：真實路徑重驗三項、`fstat` 判型別。失敗時 fd 由呼叫端關閉。
	private func inspect(
		descriptor: Int32,
		accepting: Set<FileAccessItemKind>
	) -> Result<FileAccessOpenedItem, FileAccessDenial> {
		guard let realPath: String = FileAccessPath.path(ofDescriptor: descriptor) else { return .failure(.init(.ioError)) }
		let root: FileAccessResolvedRoot
		switch check(realPath) {
		case let .success(matched):
			root = matched
		case let .failure(reason):
			return .failure(.init(reason, realPath: realPath))
		}
		var status: stat = .init()
		guard fstat(descriptor, &status) == 0 else { return .failure(.init(.ioError, realPath: realPath)) }
		let kind: FileAccessItemKind = .init(mode: status.st_mode)
		guard
			kind == .file || kind == .directory,
			accepting.contains(kind)
		else { return .failure(.init(.unsupportedFileType, realPath: realPath)) }
		return .success(.init(descriptor: descriptor, realPath: realPath, root: root, status: status))
	}
}
