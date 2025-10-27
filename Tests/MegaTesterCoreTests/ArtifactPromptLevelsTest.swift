import XCTest
@testable import MegaTesterCore

final class ArtifactPromptLevelsTest: XCTestCase {
  func test_artifact_embeds_cli_selected_prompt() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megatest_artifact_prompt_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let lp = LanguagePlan(name: "swift", frameworks: [], subjects: [], testFilesFound: 0)
    let plan = TestPlanReport(languages: [lp], generatedAt: "now", summary: PlanSummary(totalLanguages: 1, totalSubjects: 0, totalScenarios: 0))
    let xml = plan.toXML()
    let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
    let prompt = "LEVELS: unit,integration" // simulating CLI-supplied prompt with selected levels

    let url = try TestPlanIO.writeArtifact(root: tmp, plan: plan, xml: xml, json: json, prompt: prompt, visible: true)
    let contents = try String(contentsOf: url)
    XCTAssertTrue(contents.contains(prompt))
  }
}
