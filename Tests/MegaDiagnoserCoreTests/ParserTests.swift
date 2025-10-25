import XCTest
@testable import MegaDiagnoserCore

final class ParserTests: XCTestCase {

  func test_parse_swift() {
    let input = """
    /tmp/app/Sources/App/main.swift:12:5: error: cannot find 'Foo' in scope
    /tmp/app/Sources/App/util.swift:3:1: warning: 'bar' is deprecated
    """
    let diags = Parsers.parseSwift("", input)
    XCTAssertEqual(diags.count, 2)
    XCTAssertEqual(diags[0].file.hasSuffix("main.swift"), true)
    XCTAssertEqual(diags[0].line, 12)
    XCTAssertEqual(diags[0].column, 5)
    XCTAssertEqual(diags[0].severity, .error)
  }

  func test_parse_tsc() {
    let input = """
    src/index.ts:10:7 - error TS1234: Some message
    src/comp.tsx:3:12 - warning TS9999: Deprecated
    """
    let diags = Parsers.parseTypeScript(input, "")
    XCTAssertEqual(diags.count, 2)
    XCTAssertEqual(diags[0].code, "TS1234")
    XCTAssertEqual(diags[1].severity, .warning)
  }

  func test_parse_go() {
    let input = """
    pkg/foo/foo.go:27:2: undefined: X
    pkg/bar/bar.go:10: something else
    """
    let diags = Parsers.parseGo(input, "")
    XCTAssertEqual(diags.count, 2)
    XCTAssertEqual(diags[0].line, 27)
    XCTAssertEqual(diags[0].column, 2)
  }

  func test_parse_rust() {
    let input = """
    error[E0599]: no method named `wobble` found for struct `Thing` in the current scope
      --> src/main.rs:10:5
       |
    """
    let diags = Parsers.parseRust("", input)
    XCTAssertEqual(diags.count, 1)
    XCTAssertEqual(diags[0].code, "E0599")
    XCTAssertEqual(diags[0].file.hasSuffix("src/main.rs"), true)
    XCTAssertEqual(diags[0].line, 10)
    XCTAssertEqual(diags[0].column, 5)
  }

  func test_parse_python() {
    let input = """
      File "/app/foo.py", line 42
        def bad(
               ^
    SyntaxError: unexpected EOF while parsing
    """
    let diags = Parsers.parsePython("", input)
    XCTAssertEqual(diags.count, 1)
    XCTAssertEqual(diags[0].file.hasSuffix("foo.py"), true)
    XCTAssertEqual(diags[0].line, 42)
    XCTAssertEqual(diags[0].code, "SyntaxError")
  }

  func test_parse_java() {
    let input = """
    src/Main.java:12: error: cannot find symbol
    """
    let diags = Parsers.parseJava(input, "")
    XCTAssertEqual(diags.count, 1)
    XCTAssertEqual(diags[0].line, 12)
    XCTAssertEqual(diags[0].severity, .error)
  }

  func test_report_xml_contains_fix_prompt() throws {
    let d = Diagnostic(tool: "swift build", language: "swift", file: "Sources/App/main.swift", line: 1, column: 1, code: nil, severity: .error, message: "msg")
    let lang = LanguageDiagnostics(name: "swift", tool: "swift build", issues: [d])
    let rep = DiagnosticsReport(languages: [lang], generatedAt: "now")
    let xml = rep.toXML()
    XCTAssertTrue(xml.contains("<diagnostics>"))
    XCTAssertTrue(xml.contains("<fix_prompt>"))
  }
}
