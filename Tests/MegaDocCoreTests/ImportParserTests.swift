import XCTest
@testable import MegaDocCore

final class ImportParserTests: XCTestCase {
  func test_js_ts_imports() throws {
    let src = """
    import x from 'react'
    import {y} from "./util"
    const z = require('fs')
    async function a() { await import('node:crypto') }
    """
    let file = try tempFile("a.ts", src)
    let (imports, _) = ImportGrapher.build(root: file.deletingLastPathComponent(), files: [file], maxAnalyzeBytes: 10000)
    XCTAssertTrue(imports.contains(where: { $0.raw == "react" }))
    XCTAssertTrue(imports.contains(where: { $0.raw == "./util" }))
    XCTAssertTrue(imports.contains(where: { $0.raw == "fs" || $0.raw == "node:crypto" }))
  }

  func test_python_imports() throws {
    let src = """
    import os
    from mypkg.sub import thing
    """
    let file = try tempFile("a.py", src)
    let (imports, _) = ImportGrapher.build(root: file.deletingLastPathComponent(), files: [file], maxAnalyzeBytes: 10000)
    XCTAssertTrue(imports.contains(where: { $0.raw == "os" }))
    XCTAssertTrue(imports.contains(where: { $0.raw == "mypkg.sub" }))
  }

  // MARK: - Helpers
  private func tempFile(_ name: String, _ content: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)_\(name)")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
