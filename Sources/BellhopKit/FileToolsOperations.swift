//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import MCP

// MARK: - + 工具實作

/// `file_stat`／`file_list`／`file_read` 的實作。
///
/// 三顆都先經 ``FileAccessChecker/open(_:accepting:)`` 取得 fd，之後只對這個 fd 操作。
extension FileTools {

	// MARK: Internal
	//
	// 三顆實作是 internal 而非 private——分派入口在 `FileTools.swift`，跨檔的 extension 搆不到 private。

	/// `file_list` 單次最多回傳的項目數。
	internal static let maximumListEntries: Int = 1000

	/// `file_read` 可讀的檔案大小上限（10 MiB）。
	internal static let maximumReadBytes: Int64 = 10 * 1024 * 1024

	/// `file_read` 單次最多回傳的行數，也是 `limit` 的預設值。
	internal static let maximumReadLines: Int = 2000

	/// `file_stat`：型別、大小、修改時間、真實路徑。
	internal static func statItem(
		_ requested: String,
		checker: FileAccessChecker
	) -> Result<Grant, FileAccessDenial> {
		checker.open(requested, accepting: [.file, .directory]).flatMap { item -> Result<Grant, FileAccessDenial> in
			let output: StatOutput = .init(
				type: item.kind,
				size: item.size,
				modified: item.modificationDate,
				realPath: item.realPath
			)
			return grant(output, realPath: item.realPath)
		}
	}

	/// `file_list`：單層項目，依名稱排序、超過上限截斷；不遞迴、不追蹤 symlink。
	///
	/// 名稱命中內建硬拒或 `denies` 的項目不列出——列目錄不洩漏被拒位置的檔名。
	internal static func listDirectory(
		_ requested: String,
		checker: FileAccessChecker
	) -> Result<Grant, FileAccessDenial> {
		checker.open(requested, accepting: [.directory]).flatMap { item -> Result<Grant, FileAccessDenial> in
			guard item.root.listable else { return .failure(.init(.notListable, realPath: item.realPath)) }
			guard let names: [String] = entryNames(of: item, checker: checker) else {
				return .failure(.init(.ioError, realPath: item.realPath))
			}
			let sorted: [String] = names.sorted()
			let entries: [ListEntry] = sorted.prefix(maximumListEntries).map { entry(named: $0, in: item.descriptor) }
			let output: ListOutput = .init(
				path: item.realPath,
				entries: entries,
				truncated: sorted.count > maximumListEntries
			)
			return grant(output, realPath: item.realPath)
		}
	}

	/// `file_read`：UTF-8 文字切行回傳，附總行數。
	///
	/// `offset`（起始行，1 起算，預設 1）小於 1 視為 1；`limit`（行數）收斂到 1…``maximumReadLines``。
	/// 行以 `\n` 切分，檔尾的換行不另算一行。
	internal static func readText(
		_ requested: String,
		arguments: [String: Value]?,
		checker: FileAccessChecker
	) -> Result<Grant, FileAccessDenial> {
		checker.open(requested, accepting: [.file]).flatMap { item -> Result<Grant, FileAccessDenial> in
			// 大小先於讀取判斷：超限的檔一個位元組都不讀。
			guard item.size <= maximumReadBytes else { return .failure(.init(.tooLarge, realPath: item.realPath)) }
			let data: Data
			switch readAll(item.descriptor) {
			case let .success(read):
				data = read
			case let .failure(reason):
				return .failure(.init(reason, realPath: item.realPath))
			}
			guard let text: String = String(data: data, encoding: .utf8) else {
				return .failure(.init(.notText, realPath: item.realPath))
			}
			let offset: Int = max(1, arguments?["offset"]?.intValue ?? 1)
			let limit: Int = min(max(1, arguments?["limit"]?.intValue ?? maximumReadLines), maximumReadLines)
			return grant(slice(text, offset: offset, limit: limit), realPath: item.realPath)
		}
	}

	/// 依 `offset`／`limit` 切行。
	internal static func slice(_ text: String, offset: Int, limit: Int) -> ReadOutput {
		var lines: [String] = text.components(separatedBy: "\n")
		if lines.last?.isEmpty == true { lines.removeLast() }
		let start: Int = min(offset - 1, lines.count)
		let end: Int = min(start + limit, lines.count)
		let selected: ArraySlice<String> = lines[start ..< end]
		return .init(
			content: selected.joined(separator: "\n"),
			offset: offset,
			lineCount: selected.count,
			totalLines: lines.count
		)
	}

	// MARK: Private

	/// 把輸出編成 JSON 文字；編碼失敗收斂為 ``FileAccessReason/ioError``。
	private static func grant(_ output: some Encodable, realPath: String) -> Result<Grant, FileAccessDenial> {
		let encoder: JSONEncoder = .init()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .iso8601
		encoder.keyEncodingStrategy = .convertToSnakeCase
		// 編碼失敗的細節對 client 無用（輸出型別全由本模組定義），一律收斂為 ioError。
		guard
			let data: Data = try? encoder.encode(output),
			let text: String = String(data: data, encoding: .utf8)
		else { return .failure(.init(.ioError, realPath: realPath)) }
		return .success(.init(realPath: realPath, text: text))
	}

	/// 讀完整個 fd；讀到的量超過上限時回 ``FileAccessReason/tooLarge``（檔案在檢查後變大的情況）。
	private static func readAll(_ descriptor: Int32) -> Result<Data, FileAccessReason> {
		var data: Data = .init()
		var buffer: [UInt8] = .init(repeating: 0, count: 64 * 1024)
		while true {
			let count: Int = Darwin.read(descriptor, &buffer, buffer.count)
			if count == 0 { return .success(data) }
			if count < 0 {
				if errno == EINTR { continue }
				return .failure(.ioError)
			}
			data.append(contentsOf: buffer[0 ..< count])
			if Int64(data.count) > maximumReadBytes { return .failure(.tooLarge) }
		}
	}

	/// 列出目錄 fd 下的項目名稱（略過 `.`、`..` 與命中硬拒或 `denies` 者）；失敗回 nil。
	///
	/// `fdopendir(3)` 會接管傳入的 fd，所以交給它的是 `dup(2)` 出來的副本，原 fd 仍由
	/// ``FileAccessOpenedItem`` 負責關閉。
	private static func entryNames(of item: FileAccessOpenedItem, checker: FileAccessChecker) -> [String]? {
		let duplicate: Int32 = dup(item.descriptor)
		guard duplicate >= 0 else { return nil }
		guard let stream: UnsafeMutablePointer<DIR> = fdopendir(duplicate) else {
			close(duplicate)
			return nil
		}
		defer { closedir(stream) }
		var names: [String] = []
		while let entry: UnsafeMutablePointer<dirent> = readdir(stream) {
			let length: Int = .init(entry.pointee.d_namlen)
			let bytes: Data = withUnsafeBytes(of: entry.pointee.d_name) { Data($0.prefix(length)) }
			guard
				let name: String = String(data: bytes, encoding: .utf8),
				name != ".",
				name != ".."
			else { continue }
			if case .success = checker.check(item.realPath + "/" + name) { names.append(name) }
		}
		return names
	}

	/// 以 `fstatat(2)`（不追蹤 symlink）取一個項目的型別、大小與修改時間。
	private static func entry(named name: String, in descriptor: Int32) -> ListEntry {
		var status: Darwin.stat = .init()
		guard fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
			return .init(name: name, type: .other, size: nil, modified: nil)
		}
		return .init(
			name: name,
			type: FileAccessItemKind(mode: status.st_mode),
			size: Int64(status.st_size),
			modified: FileAccessOpenedItem.date(from: status.st_mtimespec)
		)
	}
}
