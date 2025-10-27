import XCTest
@testable import MegaTesterCore

final class TestPlanIOTests: XCTestCase {
  func test_write_artifact_visible_and_symlink() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megatest_artifact_vis_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let sub = TestSubject(
      id: "id",
      kind: .function,
      language: "swift",
      name: "f",
      path: tmp.appendingPathComponent("f.swift").path,
      signature: "func f()",
      exported: true,
      params: [],
      riskScore: 2,
      riskFactors: ["branches ~1"],
      io: IOCapabilities(readsFS: false, writesFS: false, network: false, db: false, env: false, concurrency: false),
      meta: [:]
    )
    let sc = ScenarioSuggestion(level: .unit, title: "t", rationale: "r", steps: [], inputs: [], assertions: [])
    let lp = LanguagePlan(name: "swift", frameworks: ["XCTest"], subjects: [SubjectPlan(subject: sub, scenarios: [sc])], testFilesFound: 0)
    let plan = TestPlanReport(languages: [lp], generatedAt: "now", summary: PlanSummary(totalLanguages: 1, totalSubjects: 1, totalScenarios: 1))

    let xml = plan.toXML()
    let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
    let prompt = TestPrompter.generateTestPrompt(from: plan, root: nil, levels: LevelSet(include: Set(TestLevel.allCases)))

    let url = try TestPlanIO.writeArtifact(root: tmp, plan: plan, xml: xml, json: json, prompt: prompt, visible: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(url.lastPathComponent.hasPrefix("MEGATEST_"))
    let contents = try String(contentsOf: url)
    XCTAssertTrue(contents.contains("<test_plan_artifact"))

    let link = try TestPlanIO.updateLatestSymlink(root: tmp, artifactURL: url, visible: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
  }

  func test_write_artifact_hidden() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megatest_artifact_hidden_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let lp = LanguagePlan(name: "swift", frameworks: [], subjects: [], testFilesFound: 0)
    let plan = TestPlanReport(languages: [lp], generatedAt: "now", summary: PlanSummary(totalLanguages: 1, totalSubjects: 0, totalScenarios: 0))
    let xml = plan.toXML()
    let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
    let prompt = "x"

    let url = try TestPlanIO.writeArtifact(root: tmp, plan: plan, xml: xml, json: json, prompt: prompt, visible: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(url.lastPathComponent.hasPrefix(".MEGATEST_"))
  }
}
