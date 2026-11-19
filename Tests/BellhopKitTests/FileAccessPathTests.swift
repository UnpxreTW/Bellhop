//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Testing

@testable import BellhopKit

struct FileAccessPathTests {

	/// 假家目錄（純字串運算，不建實體目錄）。
	private let home: String = "/Users/someone"

	@Test("expand 拒空字串、含 NUL、相對路徑與 ~user 形，展開 ~ 與 ~/…")
	func expandRejectsInvalidAndExpandsTilde() {
		#expect(FileAccessPath.expand("", homeDirectory: home) == nil)
		#expect(FileAccessPath.expand("/a\u{0}b", homeDirectory: home) == nil)
		#expect(FileAccessPath.expand("relative/path", homeDirectory: home) == nil)
		#expect(FileAccessPath.expand("./x", homeDirectory: home) == nil)
		#expect(FileAccessPath.expand("~other/x", homeDirectory: home) == nil)
		#expect(FileAccessPath.expand("~", homeDirectory: home) == "/Users/someone")
		#expect(FileAccessPath.expand("~/Documents/a.txt", homeDirectory: home) == "/Users/someone/Documents/a.txt")
		#expect(FileAccessPath.expand("/var/data", homeDirectory: home) == "/var/data")
	}

	@Test("字面正規化消去 .、..、重複斜線，.. 越過根目錄停在 /")
	func lexicalNormalizationCollapsesDotsAndSlashes() {
		#expect(FileAccessPath.lexicallyNormalized("/a//b/./c/") == "/a/b/c")
		#expect(FileAccessPath.lexicallyNormalized("/a/b/../c") == "/a/c")
		#expect(FileAccessPath.lexicallyNormalized("/a/../../..") == "/")
		#expect(FileAccessPath.lexicallyNormalized("/") == "/")
	}

	@Test("前綴比對以路徑段為單位：兄弟前綴不算在內")
	func prefixMatchIsSegmentWise() {
		#expect(FileAccessPath.isWithin("/a/Documents/x", ancestor: "/a/Documents", caseInsensitive: false))
		#expect(FileAccessPath.isWithin("/a/Documents", ancestor: "/a/Documents", caseInsensitive: false))
		#expect(!FileAccessPath.isWithin("/a/Documents2", ancestor: "/a/Documents", caseInsensitive: false))
		#expect(!FileAccessPath.isWithin("/a/Documents2/x", ancestor: "/a/Documents", caseInsensitive: false))
		#expect(FileAccessPath.isWithin("/anything", ancestor: "/", caseInsensitive: false))
		#expect(!FileAccessPath.isWithin("/a/documents/x", ancestor: "/a/Documents", caseInsensitive: false))
		#expect(FileAccessPath.isWithin("/a/documents/x", ancestor: "/a/Documents", caseInsensitive: true))
	}

	@Test("硬拒：每個路徑段名稱都會擋，含不同大小寫與巢在深處")
	func everySegmentNameIsDenied() {
		let expected: [String] = [".ssh", ".gnupg", ".aws", ".azure", ".kube"]
		#expect(Set(FileAccessCredentialStores.segmentNames) == Set(expected))
		for name in expected {
			#expect(FileAccessCredentialStores.contains("/data/proj/\(name)/x", homeDirectories: [home]), "\(name)")
			#expect(FileAccessCredentialStores.contains("/data/\(name.uppercased())", homeDirectories: [home]), "\(name)")
		}
		#expect(!FileAccessCredentialStores.contains("/data/ssh/x", homeDirectories: [home]))
		#expect(!FileAccessCredentialStores.contains("/data/.sshkeys/x", homeDirectories: [home]))
	}

	@Test("硬拒：每個家目錄相對路徑本身與其下內容都會擋，家目錄外的同名路徑不擋")
	func everyHomeRelativePathIsDenied() {
		let expected: [String] = [
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
		#expect(Set(FileAccessCredentialStores.homeRelativePaths) == Set(expected))
		for relative in expected {
			let path: String = home + "/" + relative
			#expect(FileAccessCredentialStores.contains(path, homeDirectories: [home]), "\(relative)")
			#expect(FileAccessCredentialStores.contains(path + "/inner", homeDirectories: [home]), "\(relative)")
			#expect(FileAccessCredentialStores.contains(path.uppercased(), homeDirectories: [home]), "\(relative)")
			#expect(!FileAccessCredentialStores.contains("/elsewhere/" + relative, homeDirectories: [home]), "\(relative)")
		}
	}

	@Test("硬拒：家目錄相對路徑對每一種家目錄形都比對")
	func homeRelativePathsUseEveryHomeForm() {
		let forms: [String] = ["/tmp/home", "/private/tmp/home"]
		#expect(FileAccessCredentialStores.contains("/tmp/home/.netrc", homeDirectories: forms))
		#expect(FileAccessCredentialStores.contains("/private/tmp/home/.netrc", homeDirectories: forms))
		#expect(!FileAccessCredentialStores.contains("/private/tmp/home/.netrc", homeDirectories: ["/tmp/home"]))
	}

	@Test("硬拒：每個檔名樣式都有命中與未命中的樣本")
	func everyFileNamePatternIsDenied() {
		let samples: [String: (hit: String, miss: String)] = [
			".env": (".env", "env"),
			".env.*": (".env.local", ".envrc"),
			"*.pem": ("server.pem", "server.pem.txt"),
			"*.p12": ("cert.p12", "cert.p13"),
			"*.pfx": ("cert.pfx", "certpfx"),
			"*.p8": ("AuthKey.p8", "AuthKey.p80"),
			"*.key": ("tls.key", "tls.keys"),
			"*.keychain": ("login.keychain", "keychain.txt"),
			"*.keychain-db": ("login.keychain-db", "login.keychain-db.bak"),
			"*.mobileprovision": ("app.mobileprovision", "app.provision"),
			"id_rsa*": ("id_rsa.pub", "my_id_rsa"),
			"id_dsa*": ("id_dsa", "xid_dsa"),
			"id_ecdsa*": ("id_ecdsa_sk", "ecdsa"),
			"id_ed25519*": ("id_ed25519", "ed25519")
		]
		#expect(Set(samples.keys) == Set(FileAccessCredentialStores.fileNamePatterns))
		for (pattern, sample) in samples {
			#expect(FileAccessCredentialStores.contains("/data/\(sample.hit)", homeDirectories: [home]), "\(pattern)")
			#expect(!FileAccessCredentialStores.contains("/data/\(sample.miss)", homeDirectories: [home]), "\(pattern)")
		}
	}

	@Test("硬拒：大小寫變體 .SSH、ID_RSA、X.PEM 皆擋")
	func caseVariantsAreDenied() {
		#expect(FileAccessCredentialStores.contains("/data/.SSH/config", homeDirectories: [home]))
		#expect(FileAccessCredentialStores.contains("/data/ID_RSA", homeDirectories: [home]))
		#expect(FileAccessCredentialStores.contains("/data/X.PEM", homeDirectories: [home]))
	}

	@Test("路徑段以位元組 / 切分：/ 後接組合字元時照樣是分隔符")
	func separatorFollowedByCombiningMarkStillSplits() {
		#expect(FileAccessPath.components(of: "/data/.ssh/\u{301}id") == ["data", ".ssh", "\u{301}id"])
		#expect(FileAccessPath.lexicallyNormalized("/a/.ssh/\u{301}id") == "/a/.ssh/\u{301}id")
		#expect(FileAccessCredentialStores.contains("/data/proj/.ssh/\u{301}id", homeDirectories: [home]))
		#expect(FileAccessPath.isWithin("/a/private/\u{301}x", ancestor: "/a/private", caseInsensitive: true))
	}

	@Test("NFC 與 NFD 兩形的段名比對結果一致")
	func normalizationFormsCompareEqual() {
		#expect(FileAccessPath.isWithin("/a/\u{304C}/x", ancestor: "/a/\u{304B}\u{3099}", caseInsensitive: false))
		#expect(FileAccessPath.isWithin("/a/\u{304B}\u{3099}/x", ancestor: "/a/\u{304C}", caseInsensitive: true))
	}
}
