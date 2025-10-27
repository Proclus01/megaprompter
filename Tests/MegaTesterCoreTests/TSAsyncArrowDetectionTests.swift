import XCTest
import MegaprompterCore
@testable import MegaTesterCore

final class TSAsyncArrowDetectionTests: XCTestCase {
  func test_detect_export_const_async_arrow() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ts_async_arrow_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    // marker
    try #"{"name":"x"}"#.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

    let file = tmp.appendingPathComponent("etl_orchestrator.ts")
    try """
    import { Request, Response } from 'express';
    export const orchestrateETL = async (req: Request, res: Response) => {
      res.status(200).send('ok');
    }
    """.write(to: file, atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()

    let planner = TestPlanner(root: tmp, ignoreNames: [], ignoreGlobs: [], limitSubjects: 50)
    let plan = try planner.buildPlan(profile: profile, files: files, levels: LevelSet(include: Set(TestLevel.allCases)))
    let subjects = plan.languages.flatMap { $0.subjects }.map { $0.subject }
    XCTAssertTrue(subjects.contains(where: { $0.name == "orchestrateETL" && $0.language == "typescript" }), "Expected to detect exported async arrow function orchestrateETL")
  }
}
