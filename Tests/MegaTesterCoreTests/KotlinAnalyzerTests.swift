import XCTest
import MegaprompterCore
@testable import MegaTesterCore

final class KotlinAnalyzerTests: XCTestCase {
  func test_kotlin_fun_detected() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megatest_kt_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent("src/main/kotlin"), withIntermediateDirectories: true)
    // Kotlin marker (Gradle Kotlin DSL)
    try "plugins {}".write(to: tmp.appendingPathComponent("build.gradle.kts"), atomically: true, encoding: .utf8)

    let kt = tmp.appendingPathComponent("src/main/kotlin/App.kt")
    try """
    data class User(val name: String)
    fun greet(name: String): String { return "Hi " + name }
    """.write(to: kt, atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()

    let planner = TestPlanner(root: tmp, ignoreNames: [], ignoreGlobs: [], limitSubjects: 50)
    let plan = try planner.buildPlan(profile: profile, files: files, levels: LevelSet(include: Set(TestLevel.allCases)))

    let subjects = plan.languages.flatMap { $0.subjects }.map { $0.subject }
    XCTAssertTrue(subjects.contains(where: { $0.language == "kotlin" }), "Expected at least one Kotlin subject")
  }
}
