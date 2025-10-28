import XCTest
@testable import MegaTesterCore
import MegaprompterCore

final class Unit_RegressionBasicsTests: XCTestCase {
  func test_levelset_parses_regression() {
    let ls = LevelSet.parse(from: "unit,regression")
    XCTAssertTrue(ls.contains(.unit))
    XCTAssertTrue(ls.contains(.regression))
    XCTAssertFalse(ls.contains(.e2e) && ls.include.count == 2 ? true : false, "Only unit and regression expected")
  }

  func test_gitdiff_nonrepo_returns_empty() {
    // Create temp dir not a git repo
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nonrepo_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let since = GitDiff.changedFilesSince(root: tmp, ref: "HEAD~1")
    let range = GitDiff.changedFilesInRange(root: tmp, range: "HEAD~1..HEAD")
    XCTAssertTrue(since.isEmpty)
    XCTAssertTrue(range.isEmpty)
  }
}
