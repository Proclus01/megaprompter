import XCTest
@testable import MegaDiagnoserCore

final class UnixParserTests: XCTestCase {
  func test_parse_unix_style_eslint() {
    let input = """
    src/app.js:10:3: 'x' is defined but never used
    src/util.js:5:1: Unexpected var, use let or const instead
    """
    let diags = Parsers.parseUnixStyle(input, "", language: "javascript", tool: "eslint")
    XCTAssertEqual(diags.count, 2)
    XCTAssertEqual(diags[0].language, "javascript")
    XCTAssertEqual(diags[0].file.hasSuffix("src/app.js"), true)
    XCTAssertEqual(diags[0].line, 10)
    XCTAssertEqual(diags[0].column, 3)
    XCTAssertEqual(diags[0].severity, .warning)
  }
}
