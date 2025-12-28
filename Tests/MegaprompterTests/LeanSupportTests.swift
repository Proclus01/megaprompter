import XCTest
@testable import MegaprompterCore

final class LeanSupportTests: XCTestCase {

  func testDetectionRecognizesLeanProjectByLakefile() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mp_lean_detect_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    try """
    import Lake
    open Lake DSL
    package «X» where
    """.write(to: tmp.appendingPathComponent("lakefile.lean"), atomically: true, encoding: .utf8)

    try "import Init\n".write(to: tmp.appendingPathComponent("Main.lean"), atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)

    XCTAssertTrue(profile.languages.contains("lean"), "Expected 'lean' language to be detected.")
    XCTAssertTrue(profile.isCodeProject, "Expected Lean project to be recognized as a code project.")
  }

  func testScannerIncludesLeanFiles() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mp_lean_scan_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    try """
    import Lake
    open Lake DSL
    package «X» where
    """.write(to: tmp.appendingPathComponent("lakefile.lean"), atomically: true, encoding: .utf8)

    try """
    def add1 (n : Nat) : Nat := n + 1
    """.write(to: tmp.appendingPathComponent("Main.lean"), atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()
    let rels = Set(files.map { $0.pathRelative(to: tmp) })

    XCTAssertTrue(rels.contains("Main.lean"), "Scanner should include Lean source files.")
    XCTAssertTrue(rels.contains("lakefile.lean"), "Scanner should include lakefile.lean.")
  }
}
