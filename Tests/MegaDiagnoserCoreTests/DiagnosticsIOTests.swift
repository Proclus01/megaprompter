import XCTest
@testable import MegaDiagnoserCore

final class DiagnosticsIOTests: XCTestCase {
  func test_write_artifact_visible() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadiag_artifact_test_vis_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let d = Diagnostic(tool: "swift build", language: "swift", file: "Sources/App/main.swift", line: 1, column: 1, code: nil, severity: .error, message: "x")
    let lang = LanguageDiagnostics(name: "swift", tool: "swift build", issues: [d])
    let rep = DiagnosticsReport(languages: [lang], generatedAt: "now")
    let xml = rep.toXML()
    let json = String(decoding: try JSONEncoder().encode(rep), as: UTF8.self)
    let prompt = FixPrompter.generateFixPrompt(from: rep, root: nil)

    let url = try DiagnosticsIO.writeArtifact(root: tmp, report: rep, xml: xml, json: json, prompt: prompt, visible: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(url.lastPathComponent.hasPrefix("MEGADIAG_"))
    let contents = try String(contentsOf: url)
    XCTAssertTrue(contents.contains("<diagnostics_artifact"))
  }

  func test_write_artifact_hidden() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadiag_artifact_test_hidden_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let d = Diagnostic(tool: "swift build", language: "swift", file: "Sources/App/main.swift", line: 1, column: 1, code: nil, severity: .error, message: "x")
    let lang = LanguageDiagnostics(name: "swift", tool: "swift build", issues: [d])
    let rep = DiagnosticsReport(languages: [lang], generatedAt: "now")
    let xml = rep.toXML()
    let json = String(decoding: try JSONEncoder().encode(rep), as: UTF8.self)
    let prompt = FixPrompter.generateFixPrompt(from: rep, root: nil)

    let url = try DiagnosticsIO.writeArtifact(root: tmp, report: rep, xml: xml, json: json, prompt: prompt, visible: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(url.lastPathComponent.hasPrefix(".MEGADIAG_"))
  }
}
