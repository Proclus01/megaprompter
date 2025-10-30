import XCTest
@testable import MegaDocCore

final class MegaDocArtifactTests: XCTestCase {
  func test_write_artifact_visible_and_symlink() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadoc_artifact_vis_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let rep = MegaDocReport(
      generatedAt: "now",
      mode: .local,
      rootPath: "/x",
      languages: ["swift"],
      directoryTree: "x\ny",
      importGraph: "a -> b",
      imports: [],
      externalDependencies: [:],
      purposeSummary: "ok",
      fetchedDocs: []
    )
    let xml = rep.toXML()
    let json = String(decoding: try JSONEncoder().encode(rep), as: UTF8.self)
    let prompt = "doc prompt"

    let url = try MegaDocIO.writeArtifact(root: tmp, report: rep, xml: xml, json: json, prompt: prompt, visible: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(url.lastPathComponent.hasPrefix("MEGADOC_"))

    let link = try MegaDocIO.updateLatestSymlink(root: tmp, artifactURL: url, visible: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
  }

  func test_write_artifact_hidden() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadoc_artifact_hidden_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let rep = MegaDocReport(
      generatedAt: "now",
      mode: .fetch,
      rootPath: "",
      languages: [],
      directoryTree: "",
      importGraph: "",
      imports: [],
      externalDependencies: [:],
      purposeSummary: "none",
      fetchedDocs: []
    )
    let xml = rep.toXML()
    let json = String(decoding: try JSONEncoder().encode(rep), as: UTF8.self)
    let prompt = "prompt"

    let url = try MegaDocIO.writeArtifact(root: tmp, report: rep, xml: xml, json: json, prompt: prompt, visible: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(url.lastPathComponent.hasPrefix(".MEGADOC_"))
  }
}
