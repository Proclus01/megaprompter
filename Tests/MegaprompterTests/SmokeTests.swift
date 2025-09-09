import XCTest
@testable import MegaprompterCore

final class SmokeTests: XCTestCase {
  func test_path_relative() throws {
    let base = URL(fileURLWithPath: "/tmp/root")
    let file = URL(fileURLWithPath: "/tmp/root/src/main.swift")
    XCTAssertEqual(file.pathRelative(to: base), "src/main.swift")
  }

  func test_glob_regex() throws {
    XCTAssertTrue(Glob.match(relPath: ".github/workflows/ci.yml", pattern: ".github/workflows/*.yml"))
    XCTAssertTrue(Glob.match(relPath: ".github/actions/foo/bar/action.yml", pattern: ".github/actions/**/*.yml"))
    XCTAssertFalse(Glob.match(relPath: ".github/workflows/ci.yaml", pattern: ".github/workflows/*.yml"))
  }
}
