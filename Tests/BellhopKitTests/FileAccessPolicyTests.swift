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

struct FileAccessPolicyTests {

	@Test("政策檔不存在＝空政策：全拒、原因碼 disabled")
	func missingPolicyFileDeniesEverything() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt")
		#expect(FileAccessPolicy.load(from: fixture.policyURL) == .empty)
		expectDenied(fixture.call("file_read", file), .disabled)
	}

	@Test("enabled 為 false：root 內的檔也拒、原因碼 disabled")
	func disabledPolicyDeniesEverything() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt")
		try fixture.writePolicy(.init(enabled: false, roots: [.init(path: fixture.root, listable: true)], denies: []))
		expectDenied(fixture.call("file_read", file), .disabled)
		expectDenied(fixture.call("file_stat", file), .disabled)
		expectDenied(fixture.call("file_list", fixture.root), .disabled)
	}

	@Test("政策檔損壞、缺 enabled、路徑欄不合法或有未知的鍵：全拒、原因碼 policyUnavailable")
	func malformedPolicyIsUnavailable() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt")
		let bodies: [String] = [
			"{ not json",
			#"{"roots": [{"path": "\#(fixture.root)", "listable": true}]}"#,
			#"{"enabled": true, "roots": [{"path": "relative/dir"}]}"#,
			#"{"enabled": true, "roots": [{"path": "\#(fixture.root)"}], "denies": ["relative"]}"#,
			#"{"enabled": "yes"}"#,
			#"{"enabled": true, "roots": [{"path": "\#(fixture.root)"}], "deny": ["/x"]}"#,
			#"{"enabled": true, "roots": [{"path": "\#(fixture.root)", "listabel": true}]}"#
		]
		for body in bodies {
			try Data(body.utf8).write(to: fixture.policyURL)
			#expect(FileAccessPolicy.load(from: fixture.policyURL) == nil, "\(body)")
			expectDenied(fixture.call("file_read", file), .policyUnavailable)
		}
	}

	@Test("listable 缺省為 false；roots、denies 缺省為空")
	func optionalFieldsDefaultToStrictSide() throws {
		let fixture: FileAccessFixture = try .init()
		try Data(#"{"enabled": true, "roots": [{"path": "~/Documents"}]}"#.utf8).write(to: fixture.policyURL)
		let policy: FileAccessPolicy = try #require(FileAccessPolicy.load(from: fixture.policyURL))
		#expect(policy.roots == [.init(path: "~/Documents", listable: false)])
		#expect(policy.denies.isEmpty)
	}

	@Test("每次呼叫重新載入政策：改政策檔後下一次呼叫立即生效")
	func policyIsReloadedOnEveryCall() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt")
		try fixture.writeDefaultPolicy()
		try expectAllowed(fixture.call("file_read", file))
		try fixture.writePolicy(.init(enabled: false, roots: [.init(path: fixture.root, listable: true)], denies: []))
		expectDenied(fixture.call("file_read", file), .disabled)
	}

	@Test("root 設為 /、家目錄、家目錄的祖先：該 root 無效，root 內的檔照樣拒")
	func rootCoveringHomeIsInvalid() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.home + "/notes.txt")
		let invalidRoots: [String] = ["/", fixture.home, fixture.base, "~", fixture.realBase + "/home"]
		for path in invalidRoots {
			try fixture.writePolicy(.init(enabled: true, roots: [.init(path: path, listable: true)], denies: []))
			#expect(try fixture.checker().roots.isEmpty, "\(path)")
			expectDenied(fixture.call("file_read", file), .outsideRoots)
		}
	}

	@Test("root 不存在：該 root 無效、不報錯；其他有效 root 照常")
	func missingRootIsSkipped() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt")
		try fixture.writePolicy(
			.init(
				enabled: true,
				roots: [.init(path: fixture.base + "/nowhere", listable: true), .init(path: fixture.root, listable: true)],
				denies: []
			)
		)
		#expect(try fixture.checker().roots.map(\.literalPath) == [fixture.root])
		try expectAllowed(fixture.call("file_read", file))
	}

	@Test("輸入檢查：相對路徑、空字串、含 NUL 皆拒、原因碼 invalidPath")
	func invalidRequestPathsAreRejected() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.writeDefaultPolicy()
		for path in ["", "Documents/a.txt", "a.txt", fixture.root + "/a\u{0}.txt"] {
			expectDenied(fixture.call("file_read", path), .invalidPath)
		}
		expectDenied(FileTools.handle(name: "file_read", arguments: [:], environment: fixture.environment()), .invalidPath)
	}

	@Test("~/… 展開為注入的家目錄，允許並回報真實路徑")
	func tildeRequestExpandsToInjectedHome() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.write(fixture.root + "/a.txt")
		try fixture.writeDefaultPolicy()
		let stat: [String: Any] = try expectAllowed(fixture.call("file_stat", "~/Documents/a.txt"))
		#expect(stat["real_path"] as? String == fixture.realBase + "/home/Documents/a.txt")
		#expect(stat["type"] as? String == "file")
		#expect(stat["size"] as? Int == 6)
	}

	@Test("政策中的 root 可用 ~ 開頭")
	func rootMayStartWithTilde() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/a.txt")
		try fixture.writePolicy(.init(enabled: true, roots: [.init(path: "~/Documents", listable: true)], denies: []))
		try expectAllowed(fixture.call("file_read", file))
	}

	@Test("以 Data 卷形寫的 denies 與 root 仍比得上 fd 回報的路徑")
	func dataVolumeSpellingsStillMatch() throws {
		let fixture: FileAccessFixture = try .init()
		let dataBase: String = "/System/Volumes/Data" + fixture.realBase
		try #require(FileManager.default.fileExists(atPath: dataBase))
		let file: String = try fixture.write(fixture.root + "/private/a.txt")
		try fixture.writeDefaultPolicy(denies: [dataBase + "/home/Documents/private"])
		expectDenied(fixture.call("file_read", file), .userDenied)
		try fixture.writePolicy(.init(enabled: true, roots: [.init(path: dataBase, listable: true)], denies: []))
		#expect(try fixture.checker().roots.isEmpty)
		try fixture.writePolicy(
			.init(enabled: true, roots: [.init(path: dataBase + "/home/Documents", listable: true)], denies: [])
		)
		// 字面階段不碰檔案系統：請求要以 fd 回報的同一形送入（/var 形的字面請求會在字面階段被拒＝fail-closed）。
		try expectAllowed(fixture.call("file_read", fixture.realBase + "/home/Documents/private/a.txt"))
	}

	@Test("多個 root 重疊：任一個不可列，該處即不可列（即使較深的 root 可列）")
	func overlappingRootsPreferUnlistable() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.write(fixture.root + "/inner/a.txt")
		try fixture.writePolicy(
			.init(
				enabled: true,
				roots: [.init(path: fixture.root, listable: false), .init(path: fixture.root + "/inner", listable: true)],
				denies: []
			)
		)
		expectDenied(fixture.call("file_list", fixture.root + "/inner"), .notListable)
		try expectAllowed(fixture.call("file_read", fixture.root + "/inner/a.txt"))
	}

	@Test("Data 卷形的拒絕前綴指向只有搜尋權的目錄：仍比得上 fd 回報的路徑")
	func dataVolumeDenyOnSearchOnlyDirectory() throws {
		let fixture: FileAccessFixture = try .init()
		let dataBase: String = "/System/Volumes/Data" + fixture.realBase
		try #require(FileManager.default.fileExists(atPath: dataBase))
		let file: String = try fixture.write(fixture.root + "/locked/known.txt")
		let locked: String = fixture.root + "/locked"
		#expect(chmod(locked, 0o311) == 0)
		// 夾具釋放時要刪整個目錄，權限須先還原；延長夾具生命期到還原之後。
		defer { withExtendedLifetime(fixture) { _ = chmod(locked, 0o755) } }
		try fixture.writeDefaultPolicy(denies: [dataBase + "/home/Documents/locked"])
		expectDenied(fixture.call("file_read", file), .userDenied)
	}
}
