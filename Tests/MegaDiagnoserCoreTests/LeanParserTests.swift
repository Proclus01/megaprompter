import XCTest
@testable import MegaDiagnoserCore

final class LeanParserTests: XCTestCase {

  func test_parse_lean_error_line() throws {
    let input = """
    ./Foo/Bar.lean:12:3: error: unknown identifier 'x'
    ./Foo/Baz.lean:5:10: warning: unused variable
    """
    let diags = Parsers.parseLean(input, "")
    XCTAssertEqual(diags.count, 2)
    XCTAssertEqual(diags[0].language, "lean")
    XCTAssertTrue(diags[0].file.contains("Foo/Bar.lean"))
    XCTAssertEqual(diags[0].line, 12)
    XCTAssertEqual(diags[0].column, 3)
    XCTAssertEqual(diags[0].severity, .error)
    XCTAssertEqual(diags[1].severity, .warning)
  }
}
