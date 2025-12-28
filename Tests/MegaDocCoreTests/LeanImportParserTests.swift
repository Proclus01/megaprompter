import XCTest
@testable import MegaDocCore

final class LeanImportParserTests: XCTestCase {

  func test_lean_import_resolves_to_internal_file() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadoc_lean_import_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let fooDir = tmp.appendingPathComponent("Foo")
    try FileManager.default.createDirectory(at: fooDir, withIntermediateDirectories: true)

    let main = tmp.appendingPathComponent("Main.lean")
    let bar = fooDir.appendingPathComponent("Bar.lean")

    try """
    import Foo.Bar
    def main : Nat := 1
    """.write(to: main, atomically: true, encoding: .utf8)

    try """
    def bar : Nat := 2
    """.write(to: bar, atomically: true, encoding: .utf8)

    let (imports, _) = ImportGrapher.build(root: tmp, files: [main, bar], maxAnalyzeBytes: 50_000)

    guard let imp = imports.first(where: { $0.file == main.path && $0.language == "lean" && $0.raw == "Foo.Bar" }) else {
      XCTFail("Expected to find Lean import Foo.Bar")
      return
    }

    XCTAssertTrue(imp.isInternal, "Expected Foo.Bar to resolve as internal when Foo/Bar.lean exists")
    XCTAssertTrue(imp.resolvedPath?.hasSuffix("Foo/Bar.lean") ?? false, "Expected resolved path to end with Foo/Bar.lean")
  }
}
