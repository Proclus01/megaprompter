import XCTest
@testable import MegaDocCore

final class ImportGraphExternalClassificationTests: XCTestCase {

  func test_scoped_npm_packages_are_external() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import_graph_external_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let util = tmp.appendingPathComponent("util.ts")
    let app = tmp.appendingPathComponent("app.ts")

    try """
    export function localUtil() { return 1; }
    """.write(to: util, atomically: true, encoding: .utf8)

    try """
    import x from '@scope/pkg'
    import { localUtil } from './util'

    export function run() { return localUtil(); }
    """.write(to: app, atomically: true, encoding: .utf8)

    let (_, ascii) = ImportGrapher.build(root: tmp, files: [app, util], maxAnalyzeBytes: 50_000)

    XCTAssertTrue(ascii.contains("@scope/pkg (external)"), "Expected scoped package to be labeled external")
    XCTAssertTrue(ascii.contains("util.ts (internal)") || ascii.contains("util.ts) (internal)"),
                  "Expected local ./util import to be labeled internal")
  }
}
