import XCTest
@testable import MegaprompterCore

final class NonUTF8SkipTests: XCTestCase {
  func test_builder_skips_non_utf8_file() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nonutf8_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let bad = tmp.appendingPathComponent("bad.bin")
    let bytes: [UInt8] = [0xFF, 0xFE, 0xFA, 0xF0] // invalid UTF-8
    let data = Data(bytes)
    try data.write(to: bad)

    let builder = MegapromptBuilder(root: tmp)
    let blob = try builder.build(files: [bad])

    // Should not include <bad.bin> element
    XCTAssertFalse(blob.contains("<bad.bin>"), "Non-UTF8 file should be skipped in megaprompt output")
  }
}
