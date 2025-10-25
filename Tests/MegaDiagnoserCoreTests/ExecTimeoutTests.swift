import XCTest
@testable import MegaDiagnoserCore

final class ExecTimeoutTests: XCTestCase {
  func test_timeout_returns_124_and_does_not_hang() throws {
    // Ensure /bin/sleep exists; otherwise skip.
    let sleepPath = "/bin/sleep"
    guard FileManager.default.isExecutableFile(atPath: sleepPath) else {
      throw XCTSkip("sleep not found at \(sleepPath); skipping timeout test")
    }
    let res = Exec.run(launchPath: sleepPath, args: ["5"], cwd: URL(fileURLWithPath: "/"), timeoutSeconds: 1)
    XCTAssertEqual(res.exitCode, 124, "Expected timeout exit code 124, got \(res.exitCode)")
  }
}
