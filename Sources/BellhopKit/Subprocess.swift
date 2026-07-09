//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Subprocess

/// 共用的 subprocess 執行器。
///
/// 三個健壯性保證：stdout / stderr **並行 drain**（單邊塞爆 64KB pipe buffer 不會
/// deadlock）、**逾時終止**（子程序卡住——例如系統權限對話框擋在前面——不會無限阻塞
/// 整個 server）、以及**不佔用 Swift concurrency 合作執行緒**（阻塞等待落在 GCD 執行緒）。
enum Subprocess {

	// MARK: Internal

	/// 子程序執行結果。
	struct Output {

		let status: Int32
		let standardOutput: String
		let standardError: String
	}

	/// 預設逾時秒數。
	static let defaultTimeout: TimeInterval = 30

	/// 執行子程序並收齊輸出。
	///
	/// - Parameters:
	///   - executablePath: 執行檔絕對路徑。
	///   - arguments: 傳給執行檔的參數。
	///   - timeout: 逾時秒數，超過即送 SIGTERM（寬限後 SIGKILL）並丟 ``SubprocessError/timedOut(_:after:)``。
	static func run(
		_ executablePath: String,
		arguments: [String],
		timeout: TimeInterval = defaultTimeout
	) async throws -> Output {
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(with: Result {
					try runSync(executablePath, arguments: arguments, timeout: timeout)
				})
			}
		}
	}

	// MARK: Private

	/// 執行緒安全的輸出累積 buffer。
	private final class DataBuffer: @unchecked Sendable {

		var text: String {
			lock.lock()
			defer { lock.unlock() }
			return String(data: storage, encoding: .utf8) ?? ""
		}

		private let lock: NSLock = .init()
		private var storage: Data = .init()

		func append(_ data: Data) {
			lock.lock()
			storage.append(data)
			lock.unlock()
		}
	}

	/// SIGTERM 後等待子程序退出的寬限秒數，逾期升級 SIGKILL。
	private static let killGracePeriod: TimeInterval = 2

	/// 在呼叫端執行緒（GCD）上同步執行子程序；兩條 pipe 各以 readabilityHandler 並行 drain。
	private static func runSync(
		_ executablePath: String,
		arguments: [String],
		timeout: TimeInterval
	) throws -> Output {
		let process: Process = .init()
		process.executableURL = URL(fileURLWithPath: executablePath)
		process.arguments = arguments
		process.standardInput = FileHandle.nullDevice

		let stdout: Pipe = .init()
		let stderr: Pipe = .init()
		process.standardOutput = stdout
		process.standardError = stderr

		let drains: DispatchGroup = .init()
		let outBuffer = drain(stdout, group: drains)
		let errBuffer = drain(stderr, group: drains)

		let terminated: DispatchSemaphore = .init(value: 0)
		process.terminationHandler = { _ in terminated.signal() }

		try process.run()

		var timedOut = false
		if terminated.wait(timeout: .now() + timeout) == .timedOut {
			timedOut = true
			process.terminate()
			if terminated.wait(timeout: .now() + killGracePeriod) == .timedOut {
				kill(process.processIdentifier, SIGKILL)
				terminated.wait()
			}
		}
		_ = drains.wait(timeout: .now() + killGracePeriod)
		stdout.fileHandleForReading.readabilityHandler = nil
		stderr.fileHandleForReading.readabilityHandler = nil

		if timedOut {
			throw SubprocessError.timedOut(executablePath, after: timeout)
		}
		return Output(
			status: process.terminationStatus,
			standardOutput: outBuffer.text,
			standardError: errBuffer.text
		)
	}

	/// 持續讀空 pipe 直到 EOF；回傳累積輸出的 buffer。
	private static func drain(_ pipe: Pipe, group: DispatchGroup) -> DataBuffer {
		let buffer: DataBuffer = .init()
		group.enter()
		pipe.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			if data.isEmpty {
				handle.readabilityHandler = nil
				group.leave()
			} else {
				buffer.append(data)
			}
		}
		return buffer
	}
}

// MARK: - SubprocessError

/// 子程序執行失敗。
enum SubprocessError: Error {

	case timedOut(String, after: TimeInterval)
}

// MARK: - + CustomStringConvertible

extension SubprocessError: CustomStringConvertible {

	var description: String {
		switch self {
		case let .timedOut(executablePath, seconds):
			"""
			\(executablePath) timed out after \(Int(seconds))s and was terminated — \
			a blocked system permission prompt on the machine can cause this; grant the \
			permission to the app that launches Bellhop, then retry.
			"""
		}
	}
}
