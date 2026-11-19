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

// MARK: - FileAccessFixture

/// 檔案存取測試的暫存夾具：假家目錄、root 與政策檔都建在一個新的暫存目錄裡，釋放時整個刪除。
///
/// 目錄形：`<base>/home`（假家目錄）、`<base>/home/Documents`（預設 root）、
/// `<base>/outside`（root 之外）、`<base>/policy.json`。測試不碰真實家目錄。
internal final class FileAccessFixture {

	// MARK: Lifecycle

	/// 在 `parent` 下建一個新的夾具目錄。
	///
	/// - Parameter parent: 夾具的上層目錄；預設為系統暫存目錄，傳 `/tmp` 可測 symlink 形的上層。
	internal init(parent: String = NSTemporaryDirectory()) throws {
		base = FileAccessPath.lexicallyNormalized(parent + "/bellhop-file-access-\(UUID().uuidString)")
		for directory in [home, root, outside] {
			try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
		}
	}

	/// 刪除整個夾具目錄。
	deinit {
		// 清理失敗只會留下暫存檔、不影響測試結果，故不讓錯誤冒出 deinit。
		try? FileManager.default.removeItem(atPath: base)
	}

	// MARK: Internal

	/// 夾具根目錄（字面路徑，可能含 symlink 段）。
	internal let base: String

	/// 假家目錄。
	internal var home: String { base + "/home" }

	/// 預設 root。
	internal var root: String { home + "/Documents" }

	/// root 之外的目錄。
	internal var outside: String { base + "/outside" }

	/// 政策檔位置。
	internal var policyURL: URL { URL(fileURLWithPath: base + "/policy.json") }

	/// 夾具根目錄的真實路徑。
	internal var realBase: String { FileAccessPath.resolved(base) ?? base }

	/// 在 `path` 寫一個文字檔（中間目錄自動建立），回傳該路徑。
	@discardableResult
	internal func write(_ path: String, _ text: String = "hello\n") throws -> String {
		try writeData(path, Data(text.utf8))
	}

	/// 在 `path` 寫一個二進位檔（中間目錄自動建立），回傳該路徑。
	@discardableResult
	internal func writeData(_ path: String, _ data: Data) throws -> String {
		let directory: String = (path as NSString).deletingLastPathComponent
		try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
		try data.write(to: URL(fileURLWithPath: path))
		return path
	}

	/// 建一個 symlink：`path` 指向 `destination`。
	internal func link(_ path: String, to destination: String) throws {
		try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
	}

	/// 寫政策檔。
	internal func writePolicy(_ policy: FileAccessPolicy) throws {
		try JSONEncoder().encode(policy).write(to: policyURL)
	}

	/// 寫政策檔：預設 root（可列）＋可選的 `denies`。
	internal func writeDefaultPolicy(listable: Bool = true, denies: [String] = []) throws {
		try writePolicy(.init(enabled: true, roots: [.init(path: root, listable: listable)], denies: denies))
	}

	/// 以本夾具組出工具環境；稽核紀錄寫進 `recorder`。
	internal func environment(recorder: AuditRecorder = .init()) -> FileToolsEnvironment {
		.init(
			policyURL: policyURL,
			homeDirectory: home,
			audit: { try recorder.record($0) },
			now: { Date(timeIntervalSince1970: 1_800_000_000) }
		)
	}

	/// 以目前的政策檔建判定器。
	internal func checker() throws -> FileAccessChecker {
		let policy: FileAccessPolicy = try #require(FileAccessPolicy.load(from: policyURL))
		return .init(policy: policy, homeDirectory: home)
	}

	/// 呼叫工具並回傳結果。
	internal func call(
		_ name: String,
		_ path: String,
		extra: [String: Value] = [:],
		recorder: AuditRecorder = .init()
	) -> CallTool.Result {
		var arguments: [String: Value] = extra
		arguments["path"] = .string(path)
		return FileTools.handle(name: name, arguments: arguments, environment: environment(recorder: recorder))
	}
}

// MARK: - AuditRecorder

/// 記憶體內的稽核紀錄寫入端；`failing` 為 `true` 時每次寫入都丟錯。
internal final class AuditRecorder: @unchecked Sendable {

	// MARK: Lifecycle

	/// 建立寫入端。
	internal init(failing: Bool = false) {
		self.failing = failing
	}

	// MARK: Internal

	/// 寫入失敗時丟出的錯誤。
	internal struct Failure: Error {}

	/// 是否模擬寫入失敗。
	internal let failing: Bool

	/// 目前收到的紀錄。
	internal var records: [FileAccessAuditRecord] {
		lock.withLock { stored }
	}

	/// 收下一筆紀錄。
	internal func record(_ record: FileAccessAuditRecord) throws {
		if failing { throw Failure() }
		lock.withLock { stored.append(record) }
	}

	// MARK: Private

	/// 保護 ``stored`` 的鎖（`@unchecked Sendable` 的依據）。
	private let lock: NSLock = .init()

	/// 已收到的紀錄。
	private var stored: [FileAccessAuditRecord] = []
}

// MARK: - 測試輔助函式

/// 取 `CallTool.Result` 第一段 text content；非 text 回 nil。
internal func resultText(_ result: CallTool.Result) -> String? {
	guard case let .text(text, _, _) = result.content.first else { return nil }
	return text
}

/// 斷言結果為拒絕且訊息帶指定原因碼。
internal func expectDenied(
	_ result: CallTool.Result,
	_ reason: FileAccessReason,
	sourceLocation: SourceLocation = #_sourceLocation
) {
	#expect(result.isError == true, sourceLocation: sourceLocation)
	#expect(
		resultText(result)?.contains("Denied (\(reason.rawValue))") == true,
		"\(resultText(result) ?? "<no text>")",
		sourceLocation: sourceLocation
	)
}

/// 斷言結果為允許，回傳解出的 JSON 物件。
@discardableResult
internal func expectAllowed(
	_ result: CallTool.Result,
	sourceLocation: SourceLocation = #_sourceLocation
) throws -> [String: Any] {
	#expect(result.isError == false, "\(resultText(result) ?? "<no text>")", sourceLocation: sourceLocation)
	let text: String = try #require(resultText(result), sourceLocation: sourceLocation)
	let object: Any = try JSONSerialization.jsonObject(with: Data(text.utf8))
	return try #require(object as? [String: Any], sourceLocation: sourceLocation)
}
