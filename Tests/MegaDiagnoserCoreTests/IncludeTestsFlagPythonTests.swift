import XCTest
import MegaprompterCore
@testable import MegaDiagnoserCore

final class IncludeTestsFlagPythonTests: XCTestCase {
  func test_python_tests_only_scanned_with_flag() throws {
    // Skip if no python present
    guard Exec.which("python3") != nil || Exec.which("python") != nil else {
      throw XCTSkip("python not found; skipping")
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadiag_py_tests_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    // simple non-test file (valid)
    try "print('ok')\n".write(to: tmp.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
    // test file with syntax error
    let testsDir = tmp.appendingPathComponent("tests")
    try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
    try """
    def bad(
    """.write(to: testsDir.appendingPathComponent("test_bad.py"), atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)

    // Without include-tests: no issues expected (we exclude tests by default)
    let runnerNo = DiagnosticsRunner(root: tmp, timeoutSeconds: 30, includeTests: false)
    let reportNo = runnerNo.run(profile: profile)
    let countNo = reportNo.languages.reduce(0) { $0 + $1.issues.count }
    XCTAssertEqual(countNo, 0, "No diagnostics expected when excluding tests")

    // With include-tests: the syntax error is reported
    let runnerYes = DiagnosticsRunner(root: tmp, timeoutSeconds: 30, includeTests: true)
    let reportYes = runnerYes.run(profile: profile)
    let total = reportYes.languages.reduce(0) { $0 + $1.issues.count }
    XCTAssertGreaterThan(total, 0, "Expected diagnostics from test file when include-tests is on")
    let hasTestBad = reportYes.languages.flatMap { $0.issues }.contains { $0.file.hasSuffix("test_bad.py") }
    XCTAssertTrue(hasTestBad, "Expected test_bad.py to be reported")
  }
}
