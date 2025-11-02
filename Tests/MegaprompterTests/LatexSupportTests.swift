import XCTest
@testable import MegaprompterCore

final class LatexSupportTests: XCTestCase {

  func testDetectionRecognizesLatexProjectByMainTex() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mp_latex_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tmp)
    }

    let mainTex = tmp.appendingPathComponent("main.tex")
    let body = """
    \\documentclass{article}
    \\begin{document}
    Hello LaTeX!
    \\end{document}
    """
    try body.write(to: mainTex, atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)

    XCTAssertTrue(profile.languages.contains("latex"), "Expected 'latex' language to be detected.")
    XCTAssertTrue(profile.isCodeProject, "Expected LaTeX project to be recognized as a code project.")
  }

  func testScannerIncludesTexFiles() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mp_latex_scan_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tmp)
    }

    // Create a small LaTeX project with .tex and .bib
    let mainTex = tmp.appendingPathComponent("main.tex")
    let bibFile = tmp.appendingPathComponent("refs.bib")

    let texBody = """
    \\documentclass{article}
    \\begin{document}
    Cite~\\cite{knuth1984texbook}
    \\end{document}
    """
    try texBody.write(to: mainTex, atomically: true, encoding: .utf8)

    let bibBody = """
    @book{knuth1984texbook,
      title={The TeXbook},
      author={Knuth, Donald E},
      year={1984},
      publisher={Addison-Wesley}
    }
    """
    try bibBody.write(to: bibFile, atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()

    let names = Set(files.map { $0.lastPathComponent })
    XCTAssertTrue(names.contains("main.tex"), "Scanner should include main.tex")
    XCTAssertTrue(names.contains("refs.bib"), "Scanner should include refs.bib")
  }
}
