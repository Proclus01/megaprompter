import XCTest
import MegaprompterCore
@testable import MegaDiagnoserCore

final class RunnerIncludesLanguagesEvenWhenNoIssuesTests: XCTestCase {

  func test_python_language_present_when_no_issues() throws {
    // Skip if Python isn't available in PATH.
    guard Exec.which("python3") != nil || Exec.which("python") != nil else {
      throw XCTSkip("python not found; skipping")
    }

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadiag_langs_empty_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    // Marker + simple valid python file.
    try "pytest\n".write(to: tmp.appendingPathComponent("requirements.txt"), atomically: true, encoding: .utf8)
    try "print('ok')\n".write(to: tmp.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)

    let runner = DiagnosticsRunner(root: tmp, timeoutSeconds: 30, includeTests: false)
    let report = runner.run(profile: profile)

    XCTAssertTrue(report.languages.contains(where: { $0.name == "python" }),
                  "Expected python language entry even when there are zero diagnostics.")
  }
}
