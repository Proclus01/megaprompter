import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ExecResult {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String
}

public enum Exec {
  public static func which(_ name: String) -> String? {
    let env = ProcessInfo.processInfo.environment
    let path = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin")
    for dir in path.split(separator: ":") {
      let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  /// Run a process with a timeout. Uses readability handlers, but accumulates output in a
  /// concurrency-safe accumulator to satisfy Swift 6 strict concurrency checks.
  /// - Parameters:
  ///   - launchPath: Absolute path to the executable (no shell expansion).
  ///   - args: Arguments array.
  ///   - cwd: Working directory URL.
  ///   - timeoutSeconds: Max seconds before the process is terminated (returns exitCode=124).
  public static func run(launchPath: String, args: [String], cwd: URL, timeoutSeconds: Int) -> ExecResult {
    let proc = Process()
    proc.currentDirectoryURL = cwd
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = args

    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe

    // Use concurrency-safe accumulators instead of mutating captured vars.
    let outAcc = ConcurrentDataAccumulator()
    let errAcc = ConcurrentDataAccumulator()
    let outFH = outPipe.fileHandleForReading
    let errFH = errPipe.fileHandleForReading

    outFH.readabilityHandler = { handle in
      let chunk = handle.availableData
      if !chunk.isEmpty {
        outAcc.append(chunk)
      }
    }
    errFH.readabilityHandler = { handle in
      let chunk = handle.availableData
      if !chunk.isEmpty {
        errAcc.append(chunk)
      }
    }

    do {
      try proc.run()
    } catch {
      outFH.readabilityHandler = nil
      errFH.readabilityHandler = nil
      _ = try? outFH.readToEnd()
      _ = try? errFH.readToEnd()
      return ExecResult(exitCode: -1, stdout: "", stderr: "Failed to start \(launchPath): \(error)")
    }

    // Wait for completion with a semaphore to avoid mutating captured vars.
    let sema = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
      proc.waitUntilExit()
      sema.signal()
    }

    let timeout = DispatchTime.now() + .seconds(max(1, timeoutSeconds))
    let waitResult = sema.wait(timeout: timeout)

    let exitCode: Int32
    if waitResult == .timedOut {
      // Timeout → terminate, then kill if necessary; return conventional 124 code
      proc.terminate()
      usleep(250_000)
      if proc.isRunning {
        proc.kill()
      }
      exitCode = 124
    } else {
      exitCode = proc.terminationStatus
    }

    // Cleanup handlers and drain any remaining bytes.
    outFH.readabilityHandler = nil
    errFH.readabilityHandler = nil
    if let leftover = try? outFH.readToEnd(), !leftover.isEmpty {
      outAcc.append(leftover)
    }
    if let leftover = try? errFH.readToEnd(), !leftover.isEmpty {
      errAcc.append(leftover)
    }

    let outStr = outAcc.stringUTF8()
    let errStr = errAcc.stringUTF8()
    return ExecResult(exitCode: exitCode, stdout: outStr, stderr: errStr)
  }
}

/// A simple, thread-safe Data accumulator. We mark it @unchecked Sendable because
/// we protect internal mutations with an NSLock. This allows closures that may
/// execute concurrently to capture and call its methods under Swift 6 strict checks.
public final class ConcurrentDataAccumulator: @unchecked Sendable {
  private var buffer = Data()
  private let lock = NSLock()

  public init() {}

  public func append(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.lock()
    buffer.append(data)
    lock.unlock()
  }

  public func snapshot() -> Data {
    lock.lock()
    let copy = buffer
    lock.unlock()
    return copy
  }

  public func stringUTF8() -> String {
    let d = snapshot()
    return String(decoding: d, as: UTF8.self)
  }
}

private extension Process {
  func kill() {
    #if canImport(Darwin)
    let pid = self.processIdentifier
    _ = Darwin.kill(pid, SIGKILL)
    #elseif canImport(Glibc)
    let pid = self.processIdentifier
    _ = Glibc.kill(pid, SIGKILL)
    #endif
  }
}
