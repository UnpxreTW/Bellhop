//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP
import Testing

@testable import BellhopKit

struct FileAccessAuditTests {

	@Test("允許與拒絕各寫一行，欄位齊全")
	func allowAndDenyEachWriteOneRecord() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt", "body text\n")
		try fixture.writeDefaultPolicy()
		let recorder: AuditRecorder = .init()
		try expectAllowed(fixture.call("file_read", file, recorder: recorder))
		expectDenied(fixture.call("file_read", "relative", recorder: recorder), .invalidPath)
		let records: [FileAccessAuditRecord] = recorder.records
		#expect(
			records == [
				.init(
					time: Date(timeIntervalSince1970: 1_800_000_000),
					tool: "file_read",
					requestedPath: file,
					realPath: fixture.realBase + "/home/Documents/a.txt",
					outcome: .allow,
					reason: nil
				),
				.init(
					time: Date(timeIntervalSince1970: 1_800_000_000),
					tool: "file_read",
					requestedPath: "relative",
					realPath: nil,
					outcome: .deny,
					reason: .invalidPath
				)
			]
		)
	}

	@Test("JSON 行：鍵名與值照規格，允許時 reason 為 null、未取得真實路徑時不出現 real_path")
	func jsonLineCarriesSpecifiedKeys() throws {
		let allow: FileAccessAuditRecord = .init(
			time: Date(timeIntervalSince1970: 1_800_000_000),
			tool: "file_stat",
			requestedPath: "~/Documents/a.txt",
			realPath: "/Users/someone/Documents/a.txt",
			outcome: .allow,
			reason: nil
		)
		let line: String = try #require(String(data: allow.jsonLine(), encoding: .utf8))
		#expect(
			line
				== #"{"real_path":"/Users/someone/Documents/a.txt","reason":null,"requested_path":"~/Documents/a.txt","#
				+ #""result":"allow","time":"2027-01-15T08:00:00Z","tool":"file_stat"}"# + "\n"
		)
		let deny: FileAccessAuditRecord = .init(
			time: Date(timeIntervalSince1970: 1_800_000_000),
			tool: "file_read",
			requestedPath: "x",
			realPath: nil,
			outcome: .deny,
			reason: .invalidPath
		)
		let denyLine: String = try #require(String(data: deny.jsonLine(), encoding: .utf8))
		#expect(!denyLine.contains("real_path"))
		#expect(denyLine.contains(#""reason":"invalidPath""#))
	}

	@Test("紀錄不含檔案內容，也不含列目錄得到的檔名")
	func recordsCarryNoContentOrListedNames() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt", "CONTENT-MARKER\n")
		try fixture.write(fixture.root + "/listed-name-marker.txt")
		try fixture.writeDefaultPolicy()
		let directory: String = fixture.base + "/log"
		let log: FileAccessAuditLog = .init(fileURL: URL(fileURLWithPath: directory + "/audit.jsonl"))
		let environment: FileToolsEnvironment = .init(
			policyURL: fixture.policyURL,
			homeDirectory: fixture.home,
			audit: { try log.append($0) },
			now: { Date(timeIntervalSince1970: 1_800_000_000) }
		)
		_ = FileTools.handle(name: "file_read", arguments: ["path": .string(file)], environment: environment)
		_ = FileTools.handle(name: "file_list", arguments: ["path": .string(fixture.root)], environment: environment)
		let written: String = try String(contentsOfFile: directory + "/audit.jsonl", encoding: .utf8)
		#expect(written.split(separator: "\n").count == 2)
		#expect(!written.contains("CONTENT-MARKER"))
		#expect(!written.contains("listed-name-marker"))
	}

	@Test("寫入端失敗：允許的存取改判拒絕（ioError），不回傳內容")
	func auditFailureTurnsAllowIntoDeny() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt", "CONTENT-MARKER\n")
		try fixture.writeDefaultPolicy()
		let result: CallTool.Result = fixture.call("file_read", file, recorder: AuditRecorder(failing: true))
		expectDenied(result, .ioError)
		#expect(resultText(result)?.contains("CONTENT-MARKER") == false)
	}

	@Test("預設寫入端：新建目錄 0700、檔案 0600，第二筆以附加方式寫入")
	func defaultLogUsesRestrictivePermissionsAndAppends() throws {
		let fixture: FileAccessFixture = try .init()
		let directory: String = fixture.base + "/state/Bellhop"
		let log: FileAccessAuditLog = .init(fileURL: URL(fileURLWithPath: directory + "/audit.jsonl"))
		let record: FileAccessAuditRecord = .init(
			time: Date(timeIntervalSince1970: 1_800_000_000),
			tool: "file_stat",
			requestedPath: "x",
			realPath: nil,
			outcome: .deny,
			reason: .invalidPath
		)
		try log.append(record)
		try log.append(record)
		let manager: FileManager = .default
		let directoryMode: Int = try #require(manager.attributesOfItem(atPath: directory)[.posixPermissions] as? Int)
		let fileMode: Int = try #require(
			manager.attributesOfItem(atPath: directory + "/audit.jsonl")[.posixPermissions] as? Int
		)
		#expect(directoryMode == 0o700)
		#expect(fileMode == 0o600)
		let written: String = try String(contentsOfFile: directory + "/audit.jsonl", encoding: .utf8)
		#expect(written.split(separator: "\n").count == 2)
	}

	@Test("預設寫入端：紀錄檔位置是 symlink 時寫入失敗、不寫到連結目標")
	func defaultLogRefusesSymlinkedFile() throws {
		let fixture: FileAccessFixture = try .init()
		let target: String = try fixture.write(fixture.outside + "/target.txt", "")
		try fixture.link(fixture.base + "/audit.jsonl", to: target)
		let log: FileAccessAuditLog = .init(fileURL: URL(fileURLWithPath: fixture.base + "/audit.jsonl"))
		let record: FileAccessAuditRecord = .init(
			time: Date(timeIntervalSince1970: 1_800_000_000),
			tool: "file_stat",
			requestedPath: "x",
			realPath: nil,
			outcome: .deny,
			reason: .invalidPath
		)
		#expect(throws: FileAccessAuditLog.WriteError.self) { try log.append(record) }
		#expect(try String(contentsOfFile: target, encoding: .utf8).isEmpty)
	}
}
