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

    // Fast probe: avoid running "git diff" in non-repos (prevents huge usage output).
    if !isGitWorkTree(gitPath: git, root: root) {
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
      let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      let trimmed = err.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        // Keep logs readable: truncate to first ~12 lines.
        let head = trimmed.split(separator: "\n").prefix(12).joined(separator: "\n")
        Console.warn("git \(args.joined(separator: " ")) failed: \(head)")
      }
      return []
    }

    let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let lines = out
      .split(separator: "\n")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    // Normalize to POSIX relative paths
    return lines.map { $0.replacingOccurrences(of: "\\", with: "/") }
  }

  private static func isGitWorkTree(gitPath: String, root: URL) -> Bool {
    let p = Process()
    p.currentDirectoryURL = root
    p.executableURL = URL(fileURLWithPath: gitPath)
    p.arguments = ["rev-parse", "--is-inside-work-tree"]

    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe

    do {
      try p.run()
    } catch {
      return false
    }
    p.waitUntilExit()
    return p.terminationStatus == 0
  }
}
