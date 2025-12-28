import XCTest
@testable import MegaDocCore

final class MegaDocIOAttributeEscapingTests: XCTestCase {

  func test_artifact_generatedAt_is_escaped() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadoc_escape_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let rep = MegaDocReport(
      generatedAt: #"now<&">"#,
      mode: .local,
      rootPath: "/x",
      languages: ["swift"],
      directoryTree: "x",
      importGraph: "g",
      imports: [],
      externalDependencies: [:],
      purposeSummary: "p",
      fetchedDocs: [],
      umlAscii: nil,
      umlPlantUML: nil
    )
    let xml = rep.toXML()
    let json = String(decoding: try JSONEncoder().encode(rep), as: UTF8.self)
    let prompt = "prompt"

    let url = try MegaDocIO.writeArtifact(root: tmp, report: rep, xml: xml, json: json, prompt: prompt, visible: true)
    let contents = try String(contentsOf: url)

    XCTAssertTrue(contents.contains("&amp;"), "Expected & to be escaped in artifact attributes")
    XCTAssertTrue(contents.contains("&lt;"), "Expected < to be escaped in artifact attributes")
    XCTAssertTrue(contents.contains("&gt;"), "Expected > to be escaped in artifact attributes")
    XCTAssertTrue(contents.contains("&quot;"), "Expected \" to be escaped in artifact attributes")
  }
}
