import XCTest
import MegaprompterCore
@testable import MegaTesterCore

final class CoverageFlaggingTests: XCTestCase {
  func test_subject_marked_done_when_tests_present() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megatest_cov_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent("src"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent("__tests__"), withIntermediateDirectories: true)

    // JS marker
    try #"{"name":"x"}"#.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

    // Source
    let src = tmp.appendingPathComponent("src/util.ts")
    try """
    export function util(a: number, b: string = "") {
      if (!b) throw new Error("empty");
      return a + b.length;
    }
    """.write(to: src, atomically: true, encoding: .utf8)

    // Tests: include multiple calls and edge keywords to drive green
    let tst = tmp.appendingPathComponent("__tests__/util.test.ts")
    try """
    import { util } from '../src/util'
    describe('util', () => {
      it('handles empty', () => expect(() => util(1, '')).toThrow(/empty/))
      it('invalid', () => expect(() => util(0, null as any)).toThrow())
      it('large', () => { expect(util(1000, 'x'.repeat(10000))).toBeGreaterThan(0) })
      it('ok', () => expect(util(3, 'ab')).toBe(5))
      it('more', () => { util(1,'a'); util(2,'bb'); util(3,'ccc'); util(4,'dddd'); util(5,'eeeee') })
    })
    """.write(to: tst, atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()

    let planner = TestPlanner(root: tmp, ignoreNames: [], ignoreGlobs: [], limitSubjects: 50)
    let plan = try planner.buildPlan(profile: profile, files: files, levels: LevelSet(include: Set(TestLevel.allCases)))

    let subjects = plan.languages.flatMap { $0.subjects }
    guard let sp = subjects.first(where: { $0.subject.name == "util" }) else {
      XCTFail("Expected 'util' subject"); return
    }
    XCTAssertEqual(sp.coverage.status, "DONE", "Expected coverage status DONE")
    XCTAssertTrue(sp.scenarios.isEmpty, "DONE subjects should suppress suggested scenarios")
  }
}
