//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP

// MARK: - FileTools

/// 唯讀檔案工具：`file_stat`、`file_list`、`file_read`。
///
/// 每次呼叫都重新載入 ``FileAccessPolicy``、經 ``FileAccessChecker`` 判定，並寫一行
/// 稽核紀錄（``FileAccessAuditRecord``）。允許的存取在回傳內容之前先寫紀錄；紀錄寫不進去
/// 時該次呼叫改判拒絕（``FileAccessReason/ioError``）。
///
/// 工具 schema 已定義於 ``plannedTools``，但**尚未註冊**進 ``BellhopServer``——
/// 對 client 曝光的工具面不含這三顆。工具層失敗依 MCP 慣例以 `isError: true` 回傳、
/// 不丟例外，訊息含原因碼與請求路徑、不含真實路徑。
///
/// 本檔＝分派與稽核；三顆工具的實作在 `FileToolsOperations.swift`、schema 在
/// `FileToolsSchemas.swift`。
internal enum FileTools {

	// MARK: Internal

	/// 允許時的回傳內容。
	internal struct Grant {

		/// fd 的真實路徑（寫進稽核紀錄）。
		internal let realPath: String

		/// 回給 client 的 JSON 文字。
		internal let text: String
	}

	/// 此工具群是否擁有某工具名（供 server 路由）。
	internal static func owns(_ name: String) -> Bool {
		name.hasPrefix("file_")
	}

	/// 將 tool 呼叫分派到對應實作，並寫稽核紀錄。
	///
	/// 未知的工具名不屬檔案存取、直接回 `isError`，不寫紀錄。
	///
	/// - Parameters:
	///   - name: 工具名。
	///   - arguments: 工具參數。
	///   - environment: 外部相依；預設為 ``FileToolsEnvironment/live()``。
	internal static func handle(
		name: String,
		arguments: [String: Value]?,
		environment: FileToolsEnvironment = .live()
	) -> CallTool.Result {
		guard plannedTools.contains(where: { $0.name == name }) else { return errorResult("Unknown tool: \(name)") }
		let requested: String = arguments?["path"]?.stringValue ?? ""
		let outcome: Result<Grant, FileAccessDenial> = evaluate(
			name: name,
			requested: requested,
			arguments: arguments,
			environment: environment
		)
		return finish(name: name, requested: requested, outcome: outcome, environment: environment)
	}

	/// 把拒絕組成回傳：`isError: true`、訊息含原因碼與請求路徑。
	internal static func denialResult(name: String, requested: String, reason: FileAccessReason) -> CallTool.Result {
		errorResult("Denied (\(reason.rawValue)): \(name) refused path \"\(requested)\".")
	}

	/// 組出 `isError: true` 的回傳。
	internal static func errorResult(_ message: String) -> CallTool.Result {
		.init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
	}

	// MARK: Private

	/// 載入政策、建立判定器，再交給對應的工具實作。
	private static func evaluate(
		name: String,
		requested: String,
		arguments: [String: Value]?,
		environment: FileToolsEnvironment
	) -> Result<Grant, FileAccessDenial> {
		guard let policy: FileAccessPolicy = FileAccessPolicy.load(from: environment.policyURL) else {
			return .failure(.init(.policyUnavailable))
		}
		let checker: FileAccessChecker = .init(policy: policy, homeDirectory: environment.homeDirectory)
		switch name {
		case "file_stat":
			return statItem(requested, checker: checker)
		case "file_list":
			return listDirectory(requested, checker: checker)
		default:
			return readText(requested, arguments: arguments, checker: checker)
		}
	}

	/// 寫稽核紀錄並組出最終回傳；允許但紀錄寫不進去時改判拒絕。
	private static func finish(
		name: String,
		requested: String,
		outcome: Result<Grant, FileAccessDenial>,
		environment: FileToolsEnvironment
	) -> CallTool.Result {
		switch outcome {
		case let .success(grant):
			let record: FileAccessAuditRecord = .init(
				time: environment.now(),
				tool: name,
				requestedPath: requested,
				realPath: grant.realPath,
				outcome: .allow,
				reason: nil
			)
			do {
				try environment.audit(record)
			} catch {
				return denialResult(name: name, requested: requested, reason: .ioError)
			}
			return .init(content: [.text(text: grant.text, annotations: nil, _meta: nil)], isError: false)
		case let .failure(denial):
			let record: FileAccessAuditRecord = .init(
				time: environment.now(),
				tool: name,
				requestedPath: requested,
				realPath: denial.realPath,
				outcome: .deny,
				reason: denial.reason
			)
			// 拒絕已是終局：紀錄寫不進去也不會改變結果，故不讓寫入錯誤蓋掉原本的原因碼。
			try? environment.audit(record)
			return denialResult(name: name, requested: requested, reason: denial.reason)
		}
	}
}
