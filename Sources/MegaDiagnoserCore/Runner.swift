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

    // Lean 4 (Lake)
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("lakefile.lean").path)
      || FileManager.default.fileExists(atPath: root.appendingPathComponent("lean-toolchain").path) {
      langs.append(filterLang(runLean()))
    }

    // Keep all attempted languages (even with 0 issues) for consistent UX.
    return DiagnosticsReport(languages: langs, generatedAt: isoNow())
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

  private func runLean() -> LanguageDiagnostics {
    var issues: [Diagnostic] = []
    let tool = "lake build"
    if let lake = Exec.which("lake") {
      // `lake build` is the standard Lean 4 compilation check.
      // This may download toolchains/packages if not present; that's expected for first runs.
      let res = Exec.run(launchPath: lake, args: ["build"], cwd: root, timeoutSeconds: timeout)
      issues.append(contentsOf: Parsers.parseLean(res.stdout, res.stderr))
    } else {
      Console.warn("lake not found in PATH; skipping Lean diagnostics (install Lean 4 via elan, which provides `lake`)")
    }
    return LanguageDiagnostics(name: "lean", tool: tool, issues: issues)
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
      if s == "std" { continue }
      out.append(s)
    }
    return Array(Set(out)).sorted()
  }

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
          let pkg = rel.hasPrefix("./") ? rel : ("./" + rel)
          dirs.insert(pkg)
        }
      }
    }
    return Array(dirs).sorted()
  }

  private func isIgnoredImportPath(_ pkg: String) -> Bool {
    let parts = pkg.split(separator: "/").map(String.init)
    if parts.contains(where: { ignoreNames.contains($0) }) { return true }
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
