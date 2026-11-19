//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Testing

@testable import BellhopKit

struct FileToolsReadTests {

	@Test("對目錄 file_read、對檔案 file_list：拒（unsupportedFileType）")
	func wrongItemTypeIsUnsupported() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt")
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", fixture.root), .unsupportedFileType)
		expectDenied(fixture.call("file_list", file), .unsupportedFileType)
	}

	@Test("FIFO：三顆工具都拒且不阻塞", .timeLimit(.minutes(1)))
	func fifoIsRejectedWithoutBlocking() throws {
		let fixture: FileAccessFixture = try .init()
		let fifo: String = fixture.root + "/pipe"
		#expect(mkfifo(fifo, 0o600) == 0)
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", fifo), .unsupportedFileType)
		expectDenied(fixture.call("file_stat", fifo), .unsupportedFileType)
		expectDenied(fixture.call("file_list", fifo), .unsupportedFileType)
	}

	@Test("超過 10 MiB：拒（tooLarge）；剛好 10 MiB 不因大小被拒")
	func oversizedFileIsRejected() throws {
		let fixture: FileAccessFixture = try .init()
		let big: String = try fixture.write(fixture.root + "/big.txt", "")
		let exact: String = try fixture.write(fixture.root + "/exact.txt", "")
		#expect(truncate(big, 10 * 1024 * 1024 + 1) == 0)
		#expect(truncate(exact, 10 * 1024 * 1024) == 0)
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", big), .tooLarge)
		let read: [String: Any] = try expectAllowed(fixture.call("file_read", exact))
		#expect(read["total_lines"] as? Int == 1)
	}

	@Test("內容不是合法 UTF-8：拒（notText）")
	func invalidUTF8IsRejected() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.writeData(fixture.root + "/blob.bin", Data([0x68, 0x69, 0xFF, 0xFE, 0x0A]))
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", file), .notText)
	}

	@Test("offset／limit 切行：起始行 1 起算、limit 上限 2000、檔尾換行不另算一行")
	func offsetAndLimitSliceLines() throws {
		let fixture: FileAccessFixture = try .init()
		let numbered: String = (1 ... 2_500).map { "line \($0)" }.joined(separator: "\n") + "\n"
		let file: String = try fixture.write(fixture.root + "/lines.txt", numbered)
		try fixture.writeDefaultPolicy()
		let middle: [String: Any] = try expectAllowed(
			fixture.call("file_read", file, extra: ["offset": .int(3), "limit": .int(2)])
		)
		#expect(middle["content"] as? String == "line 3\nline 4")
		#expect(middle["line_count"] as? Int == 2)
		#expect(middle["total_lines"] as? Int == 2_500)
		let capped: [String: Any] = try expectAllowed(fixture.call("file_read", file, extra: ["limit": .int(9_999)]))
		#expect(capped["line_count"] as? Int == 2_000)
		#expect((capped["content"] as? String)?.hasSuffix("\nline 2000") == true)
		let tail: [String: Any] = try expectAllowed(fixture.call("file_read", file, extra: ["offset": .int(2_499)]))
		#expect(tail["content"] as? String == "line 2499\nline 2500")
		let beyond: [String: Any] = try expectAllowed(fixture.call("file_read", file, extra: ["offset": .int(3_000)]))
		#expect(beyond["line_count"] as? Int == 0)
	}

	@Test("slice：空檔 0 行、無結尾換行的末行照算、offset 小於 1 視為 1")
	func sliceEdgeCases() {
		#expect(FileTools.slice("", offset: 1, limit: 10) == .init(content: "", offset: 1, lineCount: 0, totalLines: 0))
		#expect(FileTools.slice("a\nb", offset: 2, limit: 10) == .init(content: "b", offset: 2, lineCount: 1, totalLines: 2))
		#expect(FileTools.slice("a\r\nb\r\n", offset: 1, limit: 1).content == "a\r")
	}

	@Test("file_list：單層、依名稱排序、帶型別，symlink 不追蹤")
	func listReturnsSortedSingleLevel() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.write(fixture.root + "/b.txt", "bb\n")
		try fixture.write(fixture.root + "/a/inner.txt")
		try fixture.link(fixture.root + "/c-link", to: fixture.outside)
		try fixture.writeDefaultPolicy()
		let list: [String: Any] = try expectAllowed(fixture.call("file_list", fixture.root))
		let entries: [[String: Any]] = try #require(list["entries"] as? [[String: Any]])
		#expect(entries.compactMap { $0["name"] as? String } == ["a", "b.txt", "c-link"])
		#expect(entries.compactMap { $0["type"] as? String } == ["directory", "file", "symlink"])
		#expect(entries[1]["size"] as? Int == 3)
		#expect(list["truncated"] as? Bool == false)
	}

	@Test("file_list：命中硬拒或 denies 的項目不列出")
	func listHidesDeniedEntries() throws {
		let fixture: FileAccessFixture = try .init()
		for name in ["keep.txt", ".env", "server.pem", "private/x"] {
			try fixture.write(fixture.root + "/" + name)
		}
		try fixture.writeDefaultPolicy(denies: ["~/Documents/private"])
		let list: [String: Any] = try expectAllowed(fixture.call("file_list", fixture.root))
		let entries: [[String: Any]] = try #require(list["entries"] as? [[String: Any]])
		#expect(entries.compactMap { $0["name"] as? String } == ["keep.txt"])
	}

	@Test("file_list 超過 1000 筆：只回前 1000 筆（依名稱）並標示截斷")
	func listTruncatesAtLimit() throws {
		let fixture: FileAccessFixture = try .init()
		for index in 0 ..< 1_005 {
			FileManager.default.createFile(atPath: fixture.root + String(format: "/f%04d", index), contents: nil)
		}
		try fixture.writeDefaultPolicy()
		let list: [String: Any] = try expectAllowed(fixture.call("file_list", fixture.root))
		let entries: [[String: Any]] = try #require(list["entries"] as? [[String: Any]])
		#expect(entries.count == 1_000)
		#expect(entries.first?["name"] as? String == "f0000")
		#expect(entries.last?["name"] as? String == "f0999")
		#expect(list["truncated"] as? Bool == true)
	}

	@Test("路徑不存在：拒（ioError）")
	func missingFileIsIOError() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", fixture.root + "/nothing.txt"), .ioError)
	}
}
