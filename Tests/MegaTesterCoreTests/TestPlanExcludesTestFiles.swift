import XCTest
import MegaprompterCore
@testable import MegaTesterCore

final class TestPlanExcludesTestFiles: XCTestCase {
  func test_subjects_do_not_include_test_files() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megatest_exclude_tests_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent("src"), withIntermediateDirectories: true)

    // JS project marker
    try #"{"name":"x"}"#.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

    // Source and test files
    let src = tmp.appendingPathComponent("src/util.ts")
    let tst = tmp.appendingPathComponent("src/util.test.ts")
    try """
    export function util(a: number) { return a + 1 }
    """.write(to: src, atomically: true, encoding: .utf8)
    try """
    import { util } from './util';
    test('util', () => expect(util(1)).toBe(2));
    """.write(to: tst, atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()

    // Build plan
    let planner = TestPlanner(root: tmp, ignoreNames: [], ignoreGlobs: [], limitSubjects: 50)
    let plan = try planner.buildPlan(profile: profile, files: files, levels: LevelSet(include: Set(TestLevel.allCases)))

    // Only the util.ts function should appear as a subject (not the test file)
    let allSubjects = plan.languages.flatMap { $0.subjects }.map { $0.subject }
    XCTAssertTrue(allSubjects.contains(where: { $0.name == "util" }), "Expected 'util' function subject")
    XCTAssertFalse(allSubjects.contains(where: { $0.path.hasSuffix("util.test.ts") }), "Test file should not be analyzed as a subject")
  }
}
