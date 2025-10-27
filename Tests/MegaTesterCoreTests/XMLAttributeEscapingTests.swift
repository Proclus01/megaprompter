import XCTest
@testable import MegaTesterCore

final class MegaTesterCoreXMLAttributeEscapingTests: XCTestCase {
  func test_attribute_escaping_amp_lt_gt_quote() throws {
    let sub = TestSubject(
      id: "id&1",
      kind: .function,
      language: "swift",
      name: #"N<&">"#,
      path: #"/tmp/a&b<>"#,
      signature: nil,
      exported: true,
      params: [],
      riskScore: 1,
      riskFactors: [],
      io: IOCapabilities(readsFS: false, writesFS: false, network: false, db: false, env: false, concurrency: false),
      meta: ["k&": #"v<>""#]
    )
    let sp = SubjectPlan(subject: sub, scenarios: [])
    let lp = LanguagePlan(name: "swift", frameworks: [], subjects: [sp], testFilesFound: 0)
    let plan = TestPlanReport(languages: [lp], generatedAt: "now", summary: PlanSummary(totalLanguages: 1, totalSubjects: 1, totalScenarios: 0))
    let xml = plan.toXML()
    XCTAssertTrue(xml.contains("&amp;"))
    XCTAssertTrue(xml.contains("&lt;"))
    XCTAssertTrue(xml.contains("&gt;"))
    XCTAssertTrue(xml.contains("&quot;"))
  }
}
