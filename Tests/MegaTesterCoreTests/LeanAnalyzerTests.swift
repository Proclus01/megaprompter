import XCTest
@testable import MegaTesterCore

final class LeanAnalyzerTests: XCTestCase {

  func test_detects_defs_and_theorems() throws {
    let src = """
    def add1 (n : Nat) : Nat := n + 1
    theorem t : True := by
      trivial
    structure User where
      name : String
    """

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lean_analyze_\(UUID().uuidString).lean")
    try src.write(to: tmp, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let subjects = LeanAnalyzer.analyze(url: tmp, content: src)
    XCTAssertTrue(subjects.contains(where: { $0.name == "add1" && $0.language == "lean" }))
    XCTAssertTrue(subjects.contains(where: { $0.name == "t" && $0.language == "lean" }))
    XCTAssertTrue(subjects.contains(where: { $0.name == "User" && $0.language == "lean" }))
  }
}
