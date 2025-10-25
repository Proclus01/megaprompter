import XCTest
@testable import MegaDiagnoserCore

final class GoParserMoreTests: XCTestCase {
  func test_parse_go_with_appended_classifier() {
    let input = """
    internal/jobs/jobs.go:672:12: s.Mu undefined (type *store.ChatStore has no field or method Mu)compilerMissingFieldOrMethod
    """
    let diags = Parsers.parseGo(input, "")
    XCTAssertEqual(diags.count, 1)
    XCTAssertEqual(diags[0].file.hasSuffix("internal/jobs/jobs.go"), true)
    XCTAssertEqual(diags[0].line, 672)
    XCTAssertEqual(diags[0].column, 12)
    XCTAssertTrue(diags[0].message.contains("compilerMissingFieldOrMethod"))
  }
}
