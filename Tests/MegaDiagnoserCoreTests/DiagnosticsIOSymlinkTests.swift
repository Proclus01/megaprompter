import XCTest
@testable import MegaDiagnoserCore

final class DiagnosticsIOSymlinkTests: XCTestCase {
  func test_update_latest_symlink_visible_and_hidden() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadiag_symlink_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    // Prepare a trivial report and artifact
    let d = Diagnostic(tool: "t", language: "x", file: "f", line: 1, column: 1, code: nil, severity: .warning, message: "m")
    let lang = LanguageDiagnostics(name: "x", tool: "t", issues: [d])
    let rep = DiagnosticsReport(languages: [lang], generatedAt: "now")
    let xml = rep.toXML()
    let json = String(decoding: try JSONEncoder().encode(rep), as: UTF8.self)
    let prompt = FixPrompter.generateFixPrompt(from: rep, root: nil)

    // visible
    let artifact1 = try DiagnosticsIO.writeArtifact(root: tmp, report: rep, xml: xml, json: json, prompt: prompt, visible: true)
    let link1 = try DiagnosticsIO.updateLatestSymlink(root: tmp, artifactURL: artifact1, visible: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: link1.path))
    #if os(macOS) || os(Linux)
    let dest1 = try FileManager.default.destinationOfSymbolicLink(atPath: link1.path)
    XCTAssertTrue(dest1.hasSuffix(artifact1.lastPathComponent))
    #endif

    // hidden
    let artifact2 = try DiagnosticsIO.writeArtifact(root: tmp, report: rep, xml: xml, json: json, prompt: prompt, visible: false)
    let link2 = try DiagnosticsIO.updateLatestSymlink(root: tmp, artifactURL: artifact2, visible: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: link2.path))
    #if os(macOS) || os(Linux)
    let dest2 = try FileManager.default.destinationOfSymbolicLink(atPath: link2.path)
    XCTAssertTrue(dest2.hasSuffix(artifact2.lastPathComponent))
    #endif
  }
}

