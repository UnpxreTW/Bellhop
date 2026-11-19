//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import BellhopKit

struct FileToolsAccessTests {

	@Test("root 之外拒（outsideRoots）、root 之內允許")
	func insideRootIsAllowedOutsideIsDenied() throws {
		let fixture: FileAccessFixture = try .init()
		let inside: String = try fixture.write(fixture.root + "/a.txt")
		let outside: String = try fixture.write(fixture.outside + "/b.txt")
		try fixture.writeDefaultPolicy()
		try expectAllowed(fixture.call("file_read", inside))
		expectDenied(fixture.call("file_read", outside), .outsideRoots)
	}

	@Test("兄弟前綴 Documents2 不在 root Documents 之下")
	func siblingPrefixIsOutside() throws {
		let fixture: FileAccessFixture = try .init()
		let sibling: String = try fixture.write(fixture.home + "/Documents2/a.txt")
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", sibling), .outsideRoots)
	}

	@Test("以 .. 穿越到 root 外的 .ssh 被拒")
	func dotDotTraversalIsDenied() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.write(fixture.home + "/.ssh/config", "Host *\n")
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", fixture.root + "/../.ssh/config"), .credentialStore)
		expectDenied(fixture.call("file_read", fixture.root + "/../outside-file"), .outsideRoots)
	}

	@Test("root 內的 symlink 指向 root 外：拒，稽核紀錄帶真實路徑")
	func symlinkEscapingRootIsDenied() throws {
		let fixture: FileAccessFixture = try .init()
		let target: String = try fixture.write(fixture.outside + "/secret.txt")
		try fixture.link(fixture.root + "/escape.txt", to: target)
		try fixture.writeDefaultPolicy()
		let recorder: AuditRecorder = .init()
		expectDenied(fixture.call("file_read", fixture.root + "/escape.txt", recorder: recorder), .outsideRoots)
		#expect(recorder.records.first?.realPath == fixture.realBase + "/outside/secret.txt")
	}

	@Test("root 內的 symlink 指向 root 內另一檔：允許")
	func symlinkWithinRootIsAllowed() throws {
		let fixture: FileAccessFixture = try .init()
		let target: String = try fixture.write(fixture.root + "/real.txt", "inner\n")
		try fixture.link(fixture.root + "/alias.txt", to: target)
		try fixture.writeDefaultPolicy()
		let read: [String: Any] = try expectAllowed(fixture.call("file_read", fixture.root + "/alias.txt"))
		#expect(read["content"] as? String == "inner")
	}

	@Test("root 內的目錄 symlink 指向 root 外：經由它的路徑也被拒")
	func directorySymlinkEscapingRootIsDenied() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.write(fixture.outside + "/inner/a.txt")
		try fixture.link(fixture.root + "/door", to: fixture.outside + "/inner")
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", fixture.root + "/door/a.txt"), .outsideRoots)
		expectDenied(fixture.call("file_list", fixture.root + "/door"), .outsideRoots)
	}

	@Test("root 外的 symlink 指向 root 內：拒")
	func symlinkFromOutsideIntoRootIsDenied() throws {
		let fixture: FileAccessFixture = try .init()
		let target: String = try fixture.write(fixture.root + "/a.txt")
		try fixture.link(fixture.outside + "/shortcut.txt", to: target)
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", fixture.outside + "/shortcut.txt"), .outsideRoots)
	}

	@Test("root 內命中內建硬拒：.env、sub/id_ed25519、x.pem、proj/.ssh/config 皆拒")
	func credentialStoresInsideRootAreDenied() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.writeDefaultPolicy()
		for relative in [".env", "sub/id_ed25519", "x.pem", "proj/.ssh/config"] {
			let path: String = try fixture.write(fixture.root + "/" + relative, "value\n")
			expectDenied(fixture.call("file_read", path), .credentialStore)
			expectDenied(fixture.call("file_stat", path), .credentialStore)
		}
	}

	@Test("硬拒的大小寫變體 .SSH、ID_RSA、X.PEM 在 root 內也拒")
	func credentialStoreCaseVariantsAreDenied() throws {
		let fixture: FileAccessFixture = try .init()
		try fixture.writeDefaultPolicy()
		for relative in [".SSH/config", "ID_RSA", "X.PEM"] {
			let path: String = try fixture.write(fixture.root + "/" + relative, "value\n")
			expectDenied(fixture.call("file_read", path), .credentialStore)
		}
	}

	@Test("root 內指向硬拒位置的 symlink 以真實路徑擋下")
	func symlinkToCredentialStoreIsDenied() throws {
		let fixture: FileAccessFixture = try .init()
		let target: String = try fixture.write(fixture.root + "/keys/server.pem", "value\n")
		try fixture.link(fixture.root + "/innocent.txt", to: target)
		try fixture.writeDefaultPolicy()
		expectDenied(fixture.call("file_read", fixture.root + "/innocent.txt"), .credentialStore)
	}

	@Test("含 CJK 的檔名以 NFC 與 NFD 請求：判定一致")
	func unicodeNormalizationFormsAgree() throws {
		let fixture: FileAccessFixture = try .init()
		let composed: String = "\u{304C}\u{30D5}\u{30A1}\u{30A4}\u{30EB}.txt"
		let decomposed: String = "\u{304B}\u{3099}\u{30D5}\u{30A1}\u{30A4}\u{30EB}.txt"
		#expect(Array(composed.utf8) != Array(decomposed.utf8))
		try fixture.write(fixture.root + "/" + composed, "kana\n")
		try fixture.writeDefaultPolicy()
		let viaComposed: [String: Any] = try expectAllowed(fixture.call("file_stat", fixture.root + "/" + composed))
		let viaDecomposed: [String: Any] = try expectAllowed(fixture.call("file_stat", fixture.root + "/" + decomposed))
		#expect(viaComposed["size"] as? Int == viaDecomposed["size"] as? Int)
		#expect(viaComposed["type"] as? String == viaDecomposed["type"] as? String)
	}

	@Test("含 CJK 的拒絕前綴以 NFD 寫入政策、NFC 請求：照樣拒")
	func unicodeNormalizationAppliesToDenies() throws {
		let fixture: FileAccessFixture = try .init()
		let composed: String = "\u{304C}"
		let decomposed: String = "\u{304B}\u{3099}"
		let file: String = try fixture.write(fixture.root + "/" + composed + "/a.txt")
		try fixture.writeDefaultPolicy(denies: [fixture.root + "/" + decomposed])
		expectDenied(fixture.call("file_read", file), .userDenied)
	}

	@Test("denies 命中 root 內的子目錄：拒（userDenied），大小寫變體也拒")
	func userDeniedSubdirectoryIsDenied() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/private/a.txt")
		let other: String = try fixture.write(fixture.root + "/public/a.txt")
		try fixture.writeDefaultPolicy(denies: ["~/Documents/private"])
		expectDenied(fixture.call("file_read", file), .userDenied)
		expectDenied(fixture.call("file_read", fixture.root + "/PRIVATE/a.txt"), .userDenied)
		try expectAllowed(fixture.call("file_read", other))
	}

	@Test("listable 為 false 的 root：file_list 拒，file_stat 與 file_read 對已知檔名允許")
	func unlistableRootAllowsOnlyKnownPaths() throws {
		let fixture: FileAccessFixture = try .init()
		let file: String = try fixture.write(fixture.root + "/known.txt", "known\n")
		try fixture.writeDefaultPolicy(listable: false)
		expectDenied(fixture.call("file_list", fixture.root), .notListable)
		try expectAllowed(fixture.call("file_stat", file))
		let read: [String: Any] = try expectAllowed(fixture.call("file_read", file))
		#expect(read["content"] as? String == "known")
	}

	@Test("/tmp 形的上層：字面路徑與真實路徑兩形請求都允許")
	func symlinkedParentWorksInBothForms() throws {
		let fixture: FileAccessFixture = try .init(parent: "/tmp")
		let file: String = try fixture.write(fixture.root + "/a.txt")
		try fixture.writeDefaultPolicy()
		#expect(fixture.realBase != fixture.base)
		try expectAllowed(fixture.call("file_read", file))
		try expectAllowed(fixture.call("file_read", fixture.realBase + "/home/Documents/a.txt"))
		expectDenied(fixture.call("file_read", fixture.realBase + "/outside/x"), .outsideRoots)
	}
}
