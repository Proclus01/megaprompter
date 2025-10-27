import XCTest
@testable import MegaDiagnoserCore

final class MegaDiagnoserCoreXMLAttributeEscapingTests: XCTestCase {
  func test_attribute_escaping_amp_lt_gt_quote() throws {
    let d = Diagnostic(
      tool: #"T<&">"#,
      language: "x",
      file: #"/tmp/a&b<>"#,
      line: 1,
      column: 1,
      code: #"C<&">"#,
      severity: .warning,
      message: "m"
    )
    let lang = LanguageDiagnostics(name: #"n<&">"#, tool: #"T<&">"#, issues: [d])
    let rep = DiagnosticsReport(languages: [lang], generatedAt: #"now<&">"#)
    let xml = rep.toXML()
    XCTAssertTrue(xml.contains("&amp;"))
    XCTAssertTrue(xml.contains("&lt;"))
    XCTAssertTrue(xml.contains("&gt;"))
    XCTAssertTrue(xml.contains("&quot;"))
  }
}
