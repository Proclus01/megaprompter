import Foundation
import XCTest

/// Tiny git sandbox to create ephemeral repositories for regression tests.
/// This version uses a labeled first parameter for `commit(files:message:)` so
/// call sites like `try repo.commit(files: [...], message: "v1")` compile cleanly.
struct GitSandbox {
  let root: URL

  init(testName: String = UUID().uuidString) throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megatest_regress_\(testName)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    self.root = tmp
    try run(["init", "."])
    _ = try? run(["config", "user.email", "ci@example.com"])
    _ = try? run(["config", "user.name", "CI"])
  }

  func write(_ rel: String, _ content: String) throws {
    let url = root.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  @discardableResult
  func run(_ args: [String]) throws -> (code: Int32, out: String, err: String) {
    guard let git = whichGit() else { throw XCTSkip("git not found; skipping") }
    let p = Process()
    p.currentDirectoryURL = root
    p.executableURL = URL(fileURLWithPath: git)
    p.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    try p.run()
    p.waitUntilExit()
    let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return (p.terminationStatus, out, err)
  }

  /// Labeled first parameter to match call sites:
  ///   try repo.commit(files: ["a": "b"], message: "m")
  func commit(files: [String: String], message: String) throws {
    for (rel, content) in files {
      try write(rel, content)
    }
    _ = try run(["add", "."])
    let res = try run(["commit", "-m", message])
    if res.code != 0 {
      throw NSError(domain: "GitSandbox", code: Int(res.code), userInfo: [NSLocalizedDescriptionKey: "git commit failed: \(res.err)"])
    }
  }

  private func whichGit() -> String? {
    let env = ProcessInfo.processInfo.environment
    let path = (env["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin")
    for dir in path.split(separator: ":") {
      let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("git").path
      if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
  }
}
