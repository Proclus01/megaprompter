import XCTest
import MegaprompterCore
@testable import MegaTesterCore

final class Int_Regress_CrossLanguageTests: XCTestCase {
  func test_cross_language_regression_scenarios() throws {
    // Skip if git not present
    let probe = try? GitSandbox(testName: "probe")
    guard let _ = probe else { throw XCTSkip("git not found; skipping") }

    try runCase_TS()
    try runCase_Python()
    try runCase_Go()
    try runCase_Swift()
    try runCase_Rust()
    try runCase_Java()
    try runCase_Kotlin()
  }

  // MARK: - Individual language cases

  private func runCase_TS() throws {
    let repo = try GitSandbox(testName: "ts")
    try repo.commit(files: [
      "package.json": #"{"name":"x"}"#,
      "src/util.ts": """
      export function sumIfPositive(n: number) {
        if (n > 0) return n;
        return 0;
      }
      """
    ], message: "v1")
    try repo.commit(files: [
      "src/util.ts": """
      export function sumIfPositive(n: number) {
        if (n >= 0) return n;
        return 0;
      }
      """
    ], message: "v2")
    try assertRegressionPresent(root: repo.root, language: "typescript", subjectName: "sumIfPositive")
  }

  private func runCase_Python() throws {
    let repo = try GitSandbox(testName: "py")
    try repo.commit(files: [
      "requirements.txt": "pytest\n",
      "app.py": """
      def normalize_email(s):
          return s.strip().lower()
      """
    ], message: "v1")
    try repo.commit(files: [
      "app.py": """
      def normalize_email(s):
          if not s:
              return ""
          return s.strip().lower()
      """
    ], message: "v2")
    try assertRegressionPresent(root: repo.root, language: "python", subjectName: "normalize_email")
  }

  private func runCase_Go() throws {
    let repo = try GitSandbox(testName: "go")
    try repo.commit(files: [
      "go.mod": "module example.com/x\n\ngo 1.20\n",
      "pkg/limit/limit.go": """
      package limit
      func Within(n int) bool { return n < 100 }
      """
    ], message: "v1")
    try repo.commit(files: [
      "pkg/limit/limit.go": """
      package limit
      func Within(n int) bool { return n < 256 }
      """
    ], message: "v2")
    try assertRegressionPresent(root: repo.root, language: "go", subjectName: "Within")
  }

  private func runCase_Swift() throws {
    let repo = try GitSandbox(testName: "swift")
    try repo.commit(files: [
      "Package.swift": """
      // swift-tools-version: 6.0
      import PackageDescription
      let package = Package(name: "S", targets: [.target(name:"S")])
      """,
      "Sources/S/Clamp.swift": """
      public func clamp(_ x:Int, min:Int, max:Int) -> Int {
        if x < min { return min }
        if x > max { return max }
        return x
      }
      """
    ], message: "v1")
    try repo.commit(files: [
      "Sources/S/Clamp.swift": """
      public func clamp(_ x:Int, min:Int, max:Int) -> Int {
        if min > max { return min } // new guard
        if x < min { return min }
        if x > max { return max }
        return x
      }
      """
    ], message: "v2")
    try assertRegressionPresent(root: repo.root, language: "swift", subjectName: "clamp")
  }

  private func runCase_Rust() throws {
    let repo = try GitSandbox(testName: "rust")
    try repo.commit(files: [
      "Cargo.toml": """
      [package]
      name="x"
      version="0.1.0"
      edition="2021"
      """,
      "src/lib.rs": """
      pub fn is_even(n:i32) -> bool { n % 2 == 0 }
      """
    ], message: "v1")
    try repo.commit(files: [
      "src/lib.rs": """
      pub fn is_even(n:i32) -> bool { (n & 1) == 0 } // changed impl
      """
    ], message: "v2")
    try assertRegressionPresent(root: repo.root, language: "rust", subjectName: "is_even")
  }

  private func runCase_Java() throws {
    let repo = try GitSandbox(testName: "java")
    try repo.commit(files: [
      "build.gradle": "plugins { id 'java' }",
      "src/main/java/App.java": """
      public class App {
        public static int abs(int n) { return n >= 0 ? n : -n; }
      }
      """
    ], message: "v1")
    try repo.commit(files: [
      "src/main/java/App.java": """
      public class App {
        public static int abs(int n) {
          if (n == Integer.MIN_VALUE) return Integer.MAX_VALUE; // guard
          return n >= 0 ? n : -n;
        }
      }
      """
    ], message: "v2")
    try assertRegressionPresent(root: repo.root, language: "java", subjectName: "abs")
  }

  private func runCase_Kotlin() throws {
    let repo = try GitSandbox(testName: "kotlin")
    try repo.commit(files: [
      "build.gradle.kts": "plugins { kotlin(\"jvm\") version \"1.9.0\" }",
      "src/main/kotlin/App.kt": """
      fun greet(name: String): String = "Hi " + name
      """
    ], message: "v1")
    try repo.commit(files: [
      "src/main/kotlin/App.kt": """
      fun greet(name: String): String {
        if (name.isEmpty()) return "Hi (empty)"
        return "Hi " + name
      }
      """
    ], message: "v2")
    try assertRegressionPresent(root: repo.root, language: "kotlin", subjectName: "greet")
  }

  // MARK: - Shared assertion

  private func assertRegressionPresent(root: URL, language: String, subjectName: String) throws {
    let detector = ProjectDetector()
    let profile = try detector.detect(at: root)
    let scanner = ProjectScanner(profile: profile, maxFileBytes: 1_500_000)
    let files = try scanner.collectFiles()

    let planner = TestPlanner(root: root, ignoreNames: [], ignoreGlobs: [], limitSubjects: 100)
    let plan = try planner.buildPlan(profile: profile, files: files, levels: LevelSet(include: Set(TestLevel.allCases)), regression: RegressionConfig(mode: .since("HEAD~1")))

    guard let lp = plan.languages.first(where: { $0.name == language }) else {
      XCTFail("Missing language plan for \(language)")
      return
    }
    guard let sp = lp.subjects.first(where: { $0.subject.name == subjectName }) else {
      XCTFail("Missing subject \(subjectName) in language \(language)")
      return
    }
    let hasRegression = sp.scenarios.contains(where: { $0.level == .regression })
    XCTAssertTrue(hasRegression, "Expected a regression scenario for \(language) \(subjectName)")
  }
}
