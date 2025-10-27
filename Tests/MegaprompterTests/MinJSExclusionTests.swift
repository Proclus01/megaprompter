import XCTest
import Foundation
@testable import MegaprompterCore

final class MinJSExclusionTests: XCTestCase {
  func test_min_js_is_excluded() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("minjs_exclude_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    // JS marker
    try #"{"name":"x"}"#.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    let a = tmp.appendingPathComponent("foo.js")
    let b = tmp.appendingPathComponent("foo.min.js")
    try "console.log(1)".write(to: a, atomically: true, encoding: .utf8)
    try "console.log(1)".write(to: b, atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()

    let rels = files.map { $0.pathRelative(to: tmp) }
    XCTAssertTrue(rels.contains("foo.js"))
    XCTAssertFalse(rels.contains("foo.min.js"), "foo.min.js should be excluded")
  }
}
