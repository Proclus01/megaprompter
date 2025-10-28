import Foundation
import MegaprompterCore

public struct RegressionConfig: Codable {
  public enum Mode: Codable {
    case disabled
    case since(String)
    case range(String)
  }
  public let mode: Mode
  public init(mode: Mode) {
    self.mode = mode
  }
  public var description: String {
    switch mode {
      case .disabled: return "disabled"
      case .since(let r): return "since \(r)"
      case .range(let rr): return rr
    }
  }
}

enum GitDiff {
  static func changedFilesSince(root: URL, ref: String) -> [String] {
    return runNameOnly(root: root, args: ["diff", "--name-only", "\(ref)..HEAD"])
  }

  static func changedFilesInRange(root: URL, range: String) -> [String] {
    // Accept "A..B" or "A...B"
    return runNameOnly(root: root, args: ["diff", "--name-only", range])
  }

  private static func runNameOnly(root: URL, args: [String]) -> [String] {
    guard let git = FileSystem.which("git") else {
      Console.warn("git not found; regression detection disabled")
      return []
    }
    let p = Process()
    p.currentDirectoryURL = root
    p.executableURL = URL(fileURLWithPath: git)
    p.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe

    do {
      try p.run()
    } catch {
      Console.warn("failed to start git: \(error)")
      return []
    }
    p.waitUntilExit()
    if p.terminationStatus != 0 {
      // Not a repo or bad ref; best-effort log
      let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      if !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Console.warn("git \(args.joined(separator: " ")) failed: \(err)")
      }
      return []
    }
    let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let lines = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    // Normalize to POSIX relative paths
    return lines.map { $0.replacingOccurrences(of: "\\", with: "/") }
  }
}
