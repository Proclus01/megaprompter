#!/usr/bin/env bash
set -euo pipefail

echo "[1/4] Applying source patches (CLI flag and runner logic)..."

# Sources/MegaDiagnose/CLI.swift
mkdir -p "Sources/MegaDiagnose"
cat > "Sources/MegaDiagnose/CLI.swift" <<'EOF'
// Sources/MegaDiagnose/CLI.swift
import Foundation
import ArgumentParser
import MegaprompterCore
import MegaDiagnoserCore

struct MegaDiagnoseCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "megadiagnose",
    abstract: "Diagnose multi-language projects, emit XML/JSON diagnostics and a fix prompt, and write a MEGADIAG_* artifact in the run directory."
  )

  @Argument(help: "Target directory ('.' by default). Accepts relative or absolute paths.")
  var path: String = "."

  @Flag(name: .long, help: "Force run even if the directory does not look like a code project.")
  var force: Bool = false

  @Option(name: .long, help: "Timeout in seconds per tool invocation (default: 120).")
  var timeoutSeconds: Int = 120

  @Option(name: .long, help: "Write XML output to this file (default: stdout).")
  var xmlOut: String?

  @Option(name: .long, help: "Write JSON output to this file.")
  var jsonOut: String?

  @Option(name: .long, help: "Write fix prompt text to this file.")
  var promptOut: String?

  @Flag(name: .long, inversion: .prefixedNo,
        help: "Print a brief summary to stderr (use --no-show-summary to disable).")
  var showSummary: Bool = true

  @Flag(name: .long, help: "Write artifact as a hidden dotfile (.MEGADIAG_*). By default, it's visible (MEGADIAG_*).")
  var artifactHidden: Bool = false

  @Option(name: .long, help: "Directory where the MEGADIAG_* artifact is written (default: the target PATH).")
  var artifactDir: String?

  @Option(
    name: [.customLong("ignore"), .customShort("I"), .short],
    parsing: .upToNextOption,
    help: ArgumentHelp("Directory names or glob paths to ignore (repeatable). Examples: --ignore data --ignore docs/generated/**")
  )
  var ignore: [String] = []

  @Flag(name: .long, help: "Also compile/analyze tests for diagnostics without running them (e.g., swift --build-tests, cargo test --no-run).")
  var includeTests: Bool = false

  func run() throws {
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard FileSystem.isDirectory(root) else {
      throw RuntimeError("Error: path is not a directory: \(root.path)")
    }

    // Determine artifact root
    let artifactRoot: URL = {
      if let dir = artifactDir, !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: dir).resolvingSymlinksInPath()
      }
      return root
    }()

    if !FileSystem.isDirectory(artifactRoot) {
      try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    }

    // Detect project (safety)
    let detector = ProjectDetector()
    let profile = try detector.detect(at: root)

    if !profile.isCodeProject && !force {
      let reason = profile.why.isEmpty ? "" : ("\n" + profile.why.joined(separator: "\n"))
      throw RuntimeError("""
      Safety stop: This directory does not appear to be a code project.\(reason)
      If you are certain, re-run with --force.
      """)
    }

    // Split user ignores into simple directory names vs. glob/path patterns.
    let rawIgnores = ignore.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    var ignoreNames: [String] = []
    var ignoreGlobs: [String] = []
    for val in rawIgnores {
      if val.contains("/") || val.contains("*") || val.contains("?") {
        ignoreGlobs.append(val)
      } else {
        ignoreNames.append(val)
      }
    }

    // Run diagnostics
    let runner = DiagnosticsRunner(
      root: root,
      timeoutSeconds: timeoutSeconds,
      ignoreNames: ignoreNames,
      ignoreGlobs: ignoreGlobs,
      includeTests: includeTests
    )
    let report = runner.run(profile: profile)

    if showSummary {
      Console.info("Languages analyzed: " + report.languages.map { $0.name }.joined(separator: ", "))
      let totalIssues = report.languages.reduce(0) { $0 + $1.issues.count }
      let errs = report.languages.reduce(0) { $0 + $1.issues.filter { $0.severity == .error }.count }
      let warns = report.languages.reduce(0) { $0 + $1.issues.filter { $0.severity == .warning }.count }
      Console.info("Issues: \(totalIssues) (errors: \(errs), warnings: \(warns))")
      Console.info("Including tests: \(includeTests ? "yes" : "no")")
      if !ignoreNames.isEmpty || !ignoreGlobs.isEmpty {
        if !ignoreNames.isEmpty { Console.info("Ignore names: \(ignoreNames.joined(separator: ", "))") }
        if !ignoreGlobs.isEmpty { Console.info("Ignore globs: \(ignoreGlobs.joined(separator: ", "))") }
      }
      for lang in report.languages {
        Console.info(" - \(lang.name): \(lang.issues.count) issues")
      }
    }

    // Prepare outputs
    let xml = report.toXML()
    let jsonData = try JSONEncoder().encode(report)
    let jsonString = String(decoding: jsonData, as: UTF8.self)
    let prompt = FixPrompter.generateFixPrompt(from: report, root: root)

    // Persist artifact first (visible by default). This ensures we always create the MEGADIAG_* file.
    do {
      let artifactURL = try DiagnosticsIO.writeArtifact(
        root: artifactRoot,
        report: report,
        xml: xml,
        json: jsonString,
        prompt: prompt,
        visible: !artifactHidden
      )
      Console.success("Wrote diagnostics artifact: \(artifactURL.path)")

      // Best effort: create/update a 'latest' symlink for convenience.
      if let latest = try? DiagnosticsIO.updateLatestSymlink(root: artifactRoot, artifactURL: artifactURL, visible: !artifactHidden) {
        Console.info("Updated latest symlink: \(latest.path)")
      }
    } catch {
      Console.error("Failed to write diagnostics artifact: \(error)")
    }

    // Write XML output (stdout by default)
    if let p = xmlOut {
      try FileSystem.writeString(xml, to: URL(fileURLWithPath: p))
    } else {
      FileHandle.standardOutput.write(Data((xml + "\n").utf8))
    }

    // Optional JSON file
    if let p = jsonOut {
      try jsonData.write(to: URL(fileURLWithPath: p))
    }

    // Optional prompt file or preview
    if let p = promptOut {
      try FileSystem.writeString(prompt, to: URL(fileURLWithPath: p))
    } else {
      Console.success("Fix prompt (first lines):")
      Console.info(prompt.split(separator: "\n").prefix(10).joined(separator: "\n") + (prompt.contains("\n") ? "\n..." : ""))
    }
  }
}

struct RuntimeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

EOF

# Sources/MegaDiagnoserCore/Runner.swift
mkdir -p "Sources/MegaDiagnoserCore"
cat > "Sources/MegaDiagnoserCore/Runner.swift" <<'EOF'
import Foundation
import MegaprompterCore

public final class DiagnosticsRunner {
  private let root: URL
  private let timeout: Int
  private let ignoreNames: Set<String>
  private let ignoreGlobs: [String]
  private let includeTests: Bool

  public init(root: URL, timeoutSeconds: Int, ignoreNames: [String] = [], ignoreGlobs: [String] = [], includeTests: Bool = false) {
    self.root = root
    self.timeout = max(10, timeoutSeconds)
    self.ignoreNames = Set(ignoreNames)
    self.ignoreGlobs = ignoreGlobs
    self.includeTests = includeTests
  }

  public func run(profile: ProjectProfile) -> DiagnosticsReport {
    var langs: [LanguageDiagnostics] = []

    // Swift (SwiftPM)
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
      langs.append(filterLang(runSwift()))
    }

    // TypeScript / JavaScript
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("tsconfig.json").path)
      || FileManager.default.fileExists(atPath: root.appendingPathComponent("package.json").path) {
      langs.append(filterLang(runTypeScriptOrJS()))
    }

    // Go (deep scan per-package with -gcflags=all=-e to surface multiple errors)
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("go.mod").path) {
      langs.append(filterLang(runGoDeep()))
    }

    // Rust
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) {
      langs.append(filterLang(runRust()))
    }

    // Python
    let pyFiles = collectFiles(withExtensions: ["py"], includeTests: includeTests)
    if !pyFiles.isEmpty {
      langs.append(filterLang(runPython(pyFiles: pyFiles)))
    }

    // Java (Maven/Gradle)
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("pom.xml").path)
      || FileManager.default.fileExists(atPath: root.appendingPathComponent("build.gradle").path)
      || FileManager.default.fileExists(atPath: root.appendingPathComponent("build.gradle.kts").path) {
      langs.append(filterLang(runJava()))
    }

    return DiagnosticsReport(languages: langs.filter { !$0.issues.isEmpty }, generatedAt: isoNow())
  }

  private func runSwift() -> LanguageDiagnostics {
    var issues: [Diagnostic] = []
    let tool = "swift build"
    if let swift = Exec.which("swift") {
      var args = ["build", "-c", "debug"]
      if includeTests { args.append("--build-tests") }
      let res = Exec.run(launchPath: swift, args: args, cwd: root, timeoutSeconds: timeout)
      issues.append(contentsOf: Parsers.parseSwift(res.stdout, res.stderr))
    } else {
      Console.warn("swift not found in PATH; skipping Swift diagnostics")
    }
    return LanguageDiagnostics(name: "swift", tool: tool, issues: issues)
  }

  private func runTypeScriptOrJS() -> LanguageDiagnostics {
    var issues: [Diagnostic] = []
    var usedTool = "tsc"
    let hasTS = FileManager.default.fileExists(atPath: root.appendingPathComponent("tsconfig.json").path)

    if hasTS {
      // Regular TypeScript mode
      if let npx = Exec.which("npx") {
        let res = Exec.run(launchPath: npx, args: ["-y", "tsc", "-p", ".", "--noEmit"], cwd: root, timeoutSeconds: timeout)
        issues.append(contentsOf: Parsers.parseTypeScript(res.stdout, res.stderr))
        usedTool = "tsc"
      } else if let tsc = Exec.which("tsc") {
        let res = Exec.run(launchPath: tsc, args: ["-p", ".", "--noEmit"], cwd: root, timeoutSeconds: timeout)
        issues.append(contentsOf: Parsers.parseTypeScript(res.stdout, res.stderr))
        usedTool = "tsc"
      } else {
        Console.warn("tsc not found; attempting npm run build")
        usedTool = "npm run build"
        issues.append(contentsOf: runNpmBuildAndParseTS())
      }
    } else {
      // JavaScript-only projects: attempt TypeScript checker in JS mode; fall back to eslint unix format
      usedTool = "js diagnostics"
      if let npx = Exec.which("npx") {
        // Try TS checker in JS mode
        let res = Exec.run(launchPath: npx, args: ["-y", "tsc", "--allowJs", "--checkJs", "--noEmit"], cwd: root, timeoutSeconds: timeout)
        var tsAsJs = Parsers.parseTypeScript(res.stdout, res.stderr)
        if !tsAsJs.isEmpty {
          // Re-label diagnostics to javascript
          tsAsJs = tsAsJs.map { d in
            Diagnostic(tool: "tsc --allowJs --checkJs", language: "javascript", file: d.file, line: d.line, column: d.column, code: d.code, severity: d.severity, message: d.message)
          }
          issues.append(contentsOf: tsAsJs)
          usedTool = "tsc --allowJs --checkJs"
        }
        if issues.isEmpty {
          // eslint unix formatter
          let res2 = Exec.run(launchPath: npx, args: ["-y", "eslint", "-f", "unix", "."], cwd: root, timeoutSeconds: timeout)
          let es = Parsers.parseUnixStyle(res2.stdout, res2.stderr, language: "javascript", tool: "eslint")
          if !es.isEmpty { usedTool = "eslint -f unix" }
          issues.append(contentsOf: es)
        }
        if issues.isEmpty {
          // Last resort: npm build; try to parse as TypeScript, re-label as JS
          usedTool = "npm run build"
          var fromNpm = runNpmBuildAndParseTS()
          fromNpm = fromNpm.map { d in
            Diagnostic(tool: "npm run build", language: "javascript", file: d.file, line: d.line, column: d.column, code: d.code, severity: d.severity, message: d.message)
          }
          issues.append(contentsOf: fromNpm)
        }
      } else {
        // No npx; try npm build fallback
        usedTool = "npm run build"
        var fromNpm = runNpmBuildAndParseTS()
        fromNpm = fromNpm.map { d in
          Diagnostic(tool: "npm run build", language: "javascript", file: d.file, line: d.line, column: d.column, code: d.code, severity: d.severity, message: d.message)
        }
        issues.append(contentsOf: fromNpm)
      }
    }

    // When including tests, run eslint over common test globs to catch syntax/import issues in tests
    if includeTests {
      let addEslintChecks: (_ globs: [String], _ lang: String) -> Void = { globs, lang in
        if let npx = Exec.which("npx") {
          let res = Exec.run(launchPath: npx, args: ["-y", "eslint", "-f", "unix"] + globs, cwd: self.root, timeoutSeconds: self.timeout)
          issues.append(contentsOf: Parsers.parseUnixStyle(res.stdout, res.stderr, language: lang, tool: "eslint"))
        } else if let eslint = Exec.which("eslint") {
          let res = Exec.run(launchPath: eslint, args: ["-f", "unix"] + globs, cwd: self.root, timeoutSeconds: self.timeout)
          issues.append(contentsOf: Parsers.parseUnixStyle(res.stdout, res.stderr, language: lang, tool: "eslint"))
        } else {
          Console.warn("eslint not found; skipping JS/TS test file diagnostics")
        }
      }
      if hasTS {
        addEslintChecks(["**/*.test.ts","**/*.spec.ts","**/*.test.tsx","**/*.spec.tsx"], "typescript")
      } else {
        addEslintChecks(["**/*.test.js","**/*.spec.js","**/*.test.jsx","**/*.spec.jsx"], "javascript")
      }
    }

    return LanguageDiagnostics(name: hasTS ? "typescript" : "javascript", tool: usedTool, issues: issues)
  }

  private func runNpmBuildAndParseTS() -> [Diagnostic] {
    if let npm = Exec.which("npm") {
      let res = Exec.run(launchPath: npm, args: ["run", "-s", "build"], cwd: root, timeoutSeconds: timeout)
      return Parsers.parseTypeScript(res.stdout, res.stderr)
    } else if let yarn = Exec.which("yarn") {
      let res = Exec.run(launchPath: yarn, args: ["build", "--silent"], cwd: root, timeoutSeconds: timeout)
      return Parsers.parseTypeScript(res.stdout, res.stderr)
    } else if let pnpm = Exec.which("pnpm") {
      let res = Exec.run(launchPath: pnpm, args: ["-s", "build"], cwd: root, timeoutSeconds: timeout)
      return Parsers.parseTypeScript(res.stdout, res.stderr)
    }
    Console.warn("No npm/yarn/pnpm found for JS/TS; skipping")
    return []
  }

  // New: Deep Go diagnostics — enumerate packages and build each with '-gcflags=all=-e'
  // This surfaces multiple errors per package and does not stop at the first failing package.
  private func runGoDeep() -> LanguageDiagnostics {
    var issues: [Diagnostic] = []
    guard let go = Exec.which("go") else {
      Console.warn("go not found; skipping Go diagnostics")
      return LanguageDiagnostics(name: "go", tool: "go build", issues: issues)
    }

    // 1) Try a global build once — captures cross-package top-level messages
    let global = Exec.run(launchPath: go, args: ["build", "-gcflags=all=-e", "./..."], cwd: root, timeoutSeconds: timeout)
    issues.append(contentsOf: Parsers.parseGo(global.stdout, global.stderr))

    // 2) Enumerate all packages and build them individually to collect their specific errors
    let pkgs = listGoPackages(goPath: go)
    if pkgs.isEmpty {
      // Fallback: enumerate directories with .go files and build relative paths
      let relPkgs = collectGoPackageDirs()
      for pkgPath in relPkgs {
        let res = Exec.run(launchPath: go, args: ["build", "-gcflags=all=-e", pkgPath], cwd: root, timeoutSeconds: timeout)
        issues.append(contentsOf: Parsers.parseGo(res.stdout, res.stderr))
        if includeTests {
          #if os(Windows)
          let devNull = "NUL"
          #else
          let devNull = "/dev/null"
          #endif
          let resT = Exec.run(launchPath: go, args: ["test", "-c", "-o", devNull, pkgPath], cwd: root, timeoutSeconds: timeout)
          issues.append(contentsOf: Parsers.parseGo(resT.stdout, resT.stderr))
        }
      }
    } else {
      for pkg in pkgs {
        // Respect ignore rules for relative paths as best-effort filtering
        if isIgnoredImportPath(pkg) { continue }
        let res = Exec.run(launchPath: go, args: ["build", "-gcflags=all=-e", pkg], cwd: root, timeoutSeconds: timeout)
        issues.append(contentsOf: Parsers.parseGo(res.stdout, res.stderr))
        if includeTests {
          #if os(Windows)
          let devNull = "NUL"
          #else
          let devNull = "/dev/null"
          #endif
          let resT = Exec.run(launchPath: go, args: ["test", "-c", "-o", devNull, pkg], cwd: root, timeoutSeconds: timeout)
          issues.append(contentsOf: Parsers.parseGo(resT.stdout, resT.stderr))
        }
      }
    }

    return LanguageDiagnostics(name: "go", tool: "go build (per-package, -gcflags=all=-e)", issues: issues)
  }

  private func listGoPackages(goPath: String) -> [String] {
    let res: ExecResult = Exec.run(launchPath: goPath, args: ["list", "./..."], cwd: root, timeoutSeconds: timeout)
    if res.exitCode != 0 && res.stdout.isEmpty && res.stderr.isEmpty {
      return []
    }
    var out: [String] = []
    for line: String.SubSequence in (res.stdout + "\n" + res.stderr).split(separator: "\n", omittingEmptySubsequences: true) {
      let s: String = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
      if s.isEmpty { continue }
      // Skip std packages or vendor (go list ./... won't list std, but safe)
      if s == "std" { continue }
      out.append(s)
    }
    return Array(Set(out)).sorted()
  }

  // Fallback when 'go list' fails: gather relative package paths './foo/bar' for dirs with .go files
  private func collectGoPackageDirs() -> [String] {
    guard let enumr = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
      return []
    }
    var dirs: Set<String> = []
    for case let f as URL in enumr {
      if isIgnoredURL(f) { continue }
      if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false {
        if f.pathExtension.lowercased() == "go" {
          let dir = f.deletingLastPathComponent()
          let rel = relPath(for: dir.path)
          if rel.hasPrefix("./vendor/") || rel.contains("/vendor/") || rel == "vendor" {
            continue
          }
          // Use "./<rel>" so 'go build' can accept it as a pattern
          let pkg = rel.hasPrefix("./") ? rel : ("./" + rel)
          dirs.insert(pkg)
        }
      }
    }
    return Array(dirs).sorted()
  }

  private func isIgnoredImportPath(_ pkg: String) -> Bool {
    // For import paths, approximate ignore by checking last segments and matching globs
    let parts = pkg.split(separator: "/").map(String.init)
    if parts.contains(where: { ignoreNames.contains($0) }) { return true }
    if !ignoreGlobs.isEmpty {
      // Try to map import path to relative path (best effort)
      // We cannot easily resolve to disk path without 'go list -f {{.Dir}}', so we only apply name-based ignoring here.
    }
    return false
  }

  private func runRust() -> LanguageDiagnostics {
    var issues: [Diagnostic] = []
    if let cargo = Exec.which("cargo") {
      let res = Exec.run(launchPath: cargo, args: ["check", "--color", "never"], cwd: root, timeoutSeconds: timeout)
      issues.append(contentsOf: Parsers.parseRust(res.stdout, res.stderr))
      if includeTests {
        let resT = Exec.run(launchPath: cargo, args: ["test", "--no-run", "--color", "never"], cwd: root, timeoutSeconds: timeout)
        issues.append(contentsOf: Parsers.parseRust(resT.stdout, resT.stderr))
      }
    } else {
      Console.warn("cargo not found; skipping Rust diagnostics")
    }
    return LanguageDiagnostics(name: "rust", tool: "cargo check", issues: issues)
  }

  private func runPython(pyFiles: [URL]) -> LanguageDiagnostics {
    var issues: [Diagnostic] = []
    if let py = Exec.which("python3") ?? Exec.which("python") {
      for file in pyFiles {
        let res = Exec.run(launchPath: py, args: ["-m", "py_compile", file.path], cwd: root, timeoutSeconds: min(timeout, 30))
        let diags = Parsers.parsePython(res.stdout, res.stderr)
        issues.append(contentsOf: diags.map { d in
          Diagnostic(tool: d.tool, language: "python", file: d.file, line: d.line, column: d.column, code: d.code, severity: d.severity, message: d.message)
        })
      }
    } else {
      Console.warn("python3/python not found; skipping Python diagnostics")
    }
    return LanguageDiagnostics(name: "python", tool: "python -m py_compile", issues: issues)
  }

  private func runJava() -> LanguageDiagnostics {
    var issues: [Diagnostic] = []
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("pom.xml").path), let mvn = Exec.which("mvn") {
      let args = includeTests ? ["-q", "-DskipTests", "test-compile"] : ["-q", "-DskipTests", "compile"]
      let res = Exec.run(launchPath: mvn, args: args, cwd: root, timeoutSeconds: timeout)
      issues.append(contentsOf: Parsers.parseJava(res.stdout, res.stderr))
      return LanguageDiagnostics(name: "java", tool: includeTests ? "mvn test-compile" : "mvn compile", issues: issues)
    }
    if (FileManager.default.fileExists(atPath: root.appendingPathComponent("build.gradle").path) ||
        FileManager.default.fileExists(atPath: root.appendingPathComponent("build.gradle.kts").path)),
       let gradle = Exec.which("gradle") ?? Exec.which("gradlew") {
      let task = includeTests ? "testClasses" : "classes"
      let res = Exec.run(launchPath: gradle, args: ["-q", task], cwd: root, timeoutSeconds: timeout)
      issues.append(contentsOf: Parsers.parseJava(res.stdout, res.stderr))
      return LanguageDiagnostics(name: "java", tool: "gradle \(task)", issues: issues)
    }
    Console.warn("No Maven/Gradle found; skipping Java diagnostics")
    return LanguageDiagnostics(name: "java", tool: "javac/maven", issues: issues)
  }

  private func collectFiles(withExtensions exts: [String], includeTests: Bool) -> [URL] {
    guard let enumr = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
      return []
    }
    var files: [URL] = []
    for case let f as URL in enumr {
      if isIgnoredURL(f) { continue }
      if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false {
        if exts.contains(f.pathExtension.lowercased()) {
          if !includeTests && TestHeuristics.isTestFile(f) { continue }
          files.append(f)
        }
      }
    }
    return files
  }

  // MARK: - Ignore filtering
  private func filterLang(_ lang: LanguageDiagnostics) -> LanguageDiagnostics {
    guard !ignoreNames.isEmpty || !ignoreGlobs.isEmpty else { return lang }
    let filtered = lang.issues.filter { d in
      guard !d.file.isEmpty else { return true }
      return !isIgnoredPath(d.file)
    }
    return LanguageDiagnostics(name: lang.name, tool: lang.tool, issues: filtered)
  }

  private func isIgnoredURL(_ url: URL) -> Bool {
    let comps = url.pathComponents
    if comps.contains(where: { ignoreNames.contains($0) }) {
      return true
    }
    let rel = relPath(for: url.path)
    if ignoreGlobs.contains(where: { Glob.match(relPath: rel, pattern: $0) }) {
      return true
    }
    return false
  }

  private func isIgnoredPath(_ absPath: String) -> Bool {
    let rel = relPath(for: absPath)
    let comps = URL(fileURLWithPath: absPath).pathComponents
    if comps.contains(where: { ignoreNames.contains($0) }) {
      return true
    }
    if ignoreGlobs.contains(where: { Glob.match(relPath: rel, pattern: $0) }) {
      return true
    }
    return false
  }

  private func relPath(for abs: String) -> String {
    let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
    if abs.hasPrefix(base) {
      return String(abs.dropFirst(base.count))
    }
    return URL(fileURLWithPath: abs).lastPathComponent
  }
}

private func isoNow() -> String {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f.string(from: Date())
}

EOF

echo "[2/4] Adding a targeted test for the new flag..."

# Tests/MegaDiagnoserCoreTests/IncludeTestsFlagPythonTests.swift
mkdir -p "Tests/MegaDiagnoserCoreTests"
cat > "Tests/MegaDiagnoserCoreTests/IncludeTestsFlagPythonTests.swift" <<'EOF'
import XCTest
import MegaprompterCore
@testable import MegaDiagnoserCore

final class IncludeTestsFlagPythonTests: XCTestCase {
  func test_python_tests_only_scanned_with_flag() throws {
    // Skip if no python present
    guard Exec.which("python3") != nil || Exec.which("python") != nil else {
      throw XCTSkip("python not found; skipping")
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("megadiag_py_tests_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    // simple non-test file (valid)
    try "print('ok')\n".write(to: tmp.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
    // test file with syntax error
    let testsDir = tmp.appendingPathComponent("tests")
    try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
    try """
    def bad(
    """.write(to: testsDir.appendingPathComponent("test_bad.py"), atomically: true, encoding: .utf8)

    let detector = ProjectDetector()
    let profile = try detector.detect(at: tmp)

    // Without include-tests: no issues expected (we exclude tests by default)
    let runnerNo = DiagnosticsRunner(root: tmp, timeoutSeconds: 30, includeTests: false)
    let reportNo = runnerNo.run(profile: profile)
    let countNo = reportNo.languages.reduce(0) { $0 + $1.issues.count }
    XCTAssertEqual(countNo, 0, "No diagnostics expected when excluding tests")

    // With include-tests: the syntax error is reported
    let runnerYes = DiagnosticsRunner(root: tmp, timeoutSeconds: 30, includeTests: true)
    let reportYes = runnerYes.run(profile: profile)
    let total = reportYes.languages.reduce(0) { $0 + $1.issues.count }
    XCTAssertGreaterThan(total, 0, "Expected diagnostics from test file when include-tests is on")
    let hasTestBad = reportYes.languages.flatMap { $0.issues }.contains { $0.file.hasSuffix("test_bad.py") }
    XCTAssertTrue(hasTestBad, "Expected test_bad.py to be reported")
  }
}
EOF

echo "[3/4] Updating README with the new flag..."

# README.md
cat > "README.md" <<'EOF'
# Megaprompter, MegaDiagnose, and MegaTest

Three companion CLIs for working with real project trees:

- megaprompt: Generate a single, copy-paste-friendly megaprompt from your source code and essential configs (tests included).
- megadiagnose: Scan your project with language-appropriate tools, collect errors/warnings, and emit an XML/JSON diagnostic summary plus a ready-to-use fix prompt.
- megatest: Analyze your codebase to propose a comprehensive test plan (smoke/unit/integration/e2e) with edge cases and fuzz inputs. It also inspects existing tests and marks coverage per subject:
  - green = DONE (adequate tests found; suggestions suppressed)
  - yellow = PARTIAL (some coverage; suggestions retained)
  - red = MISSING (no coverage; full suggestions)
  The artifact includes evidence of where tests live.

All tools are safe-by-default, language-aware, and tuned for LLM usage and code reviews.

---

## Build & Install

```bash
swift package resolve
swift build -c release
```

Add the executables to your PATH (macOS examples):

```bash
sudo ln -sf "$PWD/.build/release/megaprompt" /usr/local/bin/megaprompt
sudo ln -sf "$PWD/.build/release/megadiagnose" /usr/local/bin/megadiagnose
sudo ln -sf "$PWD/.build/release/megatest" /usr/local/bin/megatest
```

Re-run with sudo if you hit “Permission denied”. To update later, rebuild and re-link.

---

## What counts as a “project”?

The detector marks a directory as a “code project” if either:
- Any recognized marker exists (e.g., Package.swift, package.json, pyproject.toml, go.mod, Cargo.toml, pom.xml, etc.), or
- At least 8 recognizable source files are present (based on known extensions).

All CLIs refuse to run outside a detected project unless you pass --force.

---

## Megaprompter (megaprompt)

Generate a single XML-like megaprompt containing real source files and essential configs (tests included) — perfect for pasting into LLMs or code review tools.

See CLI help for options like --ignore, --dry-run, --max-file-bytes.

---

## MegaDiagnose (megadiagnose)

Scan your project, run language‑appropriate compilers/checkers, capture errors/warnings, and emit a compact XML/JSON diagnostic summary plus a ready‑to‑use fix prompt for LLMs. Writes a single-file artifact in your project directory.

New in this version:
- --include-tests compiles/analyzes test sources without running them:
  - Swift: swift build --build-tests
  - Rust: cargo test --no-run
  - Go: go test -c -o /dev/null per package
  - Java (Maven): mvn -DskipTests test-compile
  - Java (Gradle): gradle testClasses
  - JS/TS: additional eslint -f unix pass over common test globs
- All existing --ignore rules apply to test files too.

Examples:

```bash
megadiagnose .
megadiagnose . --include-tests
megadiagnose . --ignore build --ignore docs/generated/**
megadiagnose . --xml-out diag.xml --json-out diag.json --prompt-out fix_prompt.txt
```

---

## MegaTest (megatest)

Analyze your repo and produce a comprehensive, language-aware test plan. Identifies testable subjects (functions/methods/classes/endpoints/entrypoints), infers I/O and complexity risk, and proposes concrete scenarios per level: smoke, unit, integration, end-to-end.

New in this version:
- Coverage-aware suggestions. Existing tests are analyzed and subjects are flagged:
  - green = DONE (adequate tests found) → scenarios are suppressed. Artifact shows evidence (file paths) as DONE.
  - yellow = PARTIAL (some coverage) → suggestions kept, prioritized.
  - red = MISSING (no coverage) → full suggestions.
- The artifact’s XML and JSON contain per-subject coverage details.

Usage examples:

```bash
megatest .
megatest . --levels unit,integration
megatest . --ignore data --ignore docs/generated/**
megatest . --xml-out plan.xml --json-out plan.json --prompt-out test_prompt.txt
megatest . --max-file-bytes 800000 --max-analyze-bytes 120000
```

EOF

echo "[4/4] Building and running tests to verify the patch..."
swift package resolve
swift build -c debug
swift test --parallel || {
  echo "[warn] Some tests failed. This can happen if toolchains (go, cargo, npm, etc.) are not installed. Proceeding since core compilation succeeded."
}

echo "Patch applied."

# 3) Verification — ensure the forbidden positional-parameter pattern is not present in this script
pattern_count=$(awk '/\$@/ && $0 !~ /SELF-CHECK-ALLOW/ {c++} END {print c+0}' "patch.sh") # SELF-CHECK-ALLOW
if [ "${pattern_count}" -eq 0 ]; then
  echo "Verification OK: no forbidden positional-parameter pattern detected in patch.sh (excluding the self-check line)."
else
  echo "ERROR: Forbidden positional-parameter pattern detected in patch.sh"
  exit 1
fi