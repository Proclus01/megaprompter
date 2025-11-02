#!/usr/bin/env bash
set -euo pipefail

# patch.sh — Add LaTeX (.tex) support to Megaprompter (detection + inclusion) and introduce tests.
# - Updates:
#   1) Sources/MegaprompterCore/Detection.swift  → recognize "latex" via markers and extensions
#   2) Sources/MegaprompterCore/Rules.swift      → allow .tex/.cls/.sty/.bib and force-include latexmkrc
#   3) Tests/MegaprompterTests/LatexSupportTests.swift → tests for detection + scanning of LaTeX projects
#
# Idempotent: running multiple times will overwrite the same files with the same contents.

echo "[patch] Applying LaTeX support for Megaprompter..."

# 1) Update Detection.swift to recognize LaTeX projects and files
mkdir -p "Sources/MegaprompterCore"
cat > "Sources/MegaprompterCore/Detection.swift" <<'EOF'
// Sources/MegaprompterCore/Detection.swift
import Foundation

/// Summary of the detected project.
public struct ProjectProfile {
  public let root: URL
  public let languages: Set<String>
  public let markers: Set<String>          // relative paths that proved existence
  public let isCodeProject: Bool
  public let why: [String]

  public var usesTypeScript: Bool { languages.contains("typescript") }
  public var usesJavaScript: Bool { languages.contains("javascript") }
}

/// Detects if a directory is a code project and which stacks are present.
/// Conservative by design to prevent accidental traversal of non-project trees.
public final class ProjectDetector {

  /// Marker files/directories indicating a project stack.
  private let markerFiles: [String: [String]] = [
    "typescript": ["tsconfig.json"],
    "javascript": ["package.json"],
    "python": ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py", "setup.cfg", "tox.ini"],
    "go": ["go.mod"],
    "rust": ["Cargo.toml"],
    "java": ["pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
    "kotlin": ["build.gradle.kts"],
    "csharp": ["*.sln", "*.csproj"],
    "cpp": ["CMakeLists.txt"],
    "php": ["composer.json"],
    "ruby": ["Gemfile"],
    "swift": ["Package.swift", "*.xcodeproj"],
    "terraform": ["*.tf"],
    "docker": ["Dockerfile"],

    // LaTeX projects: recognize common markers
    // - latexmkrc (build config)
    // - any .tex file (e.g., main.tex) — typical in LaTeX repos
    "latex": ["latexmkrc", "*.tex"]
  ]

  /// Extension → language map (used as heuristic if markers are absent).
  private let sourceExtToLang: [String: String] = [
    ".ts": "typescript", ".tsx": "typescript",
    ".js": "javascript", ".jsx": "javascript", ".mjs": "javascript", ".cjs": "javascript",
    ".py": "python",
    ".go": "go",
    ".rs": "rust",
    ".java": "java",
    ".kt": "kotlin", ".kts": "kotlin",
    ".c": "cpp", ".cc": "cpp", ".cpp": "cpp", ".cxx": "cpp", ".h": "cpp", ".hpp": "cpp", ".hh": "cpp",
    ".cs": "csharp",
    ".php": "php",
    ".rb": "ruby",
    ".swift": "swift",
    ".tf": "terraform",
    ".scala": "scala", ".sbt": "scala",
    ".scss": "styles", ".sass": "styles", ".less": "styles", ".css": "styles",
    ".html": "html",
    ".graphql": "graphql", ".gql": "graphql",
    ".sql": "sql",
    ".sh": "shell", ".zsh": "shell", ".bash": "shell",

    // LaTeX family
    ".tex": "latex",
    ".cls": "latex",
    ".sty": "latex",
    ".bib": "latex"
  ]

  public init() {}

  /// Main detection entrypoint.
  public func detect(at root: URL) throws -> ProjectProfile {
    precondition(root.isDirectory, "root must be a directory")

    var languages = Set<String>()
    var markers = Set<String>()
    var why: [String] = []

    // 1) Marker files/directories (globbed)
    for (lang, patterns) in markerFiles {
      for pat in patterns {
        for hit in Glob.findMatches(root: root, pattern: pat) {
          languages.insert(lang)
          markers.insert(hit.pathRelative(to: root))
          why.append("\(lang) marker: \(hit.pathRelative(to: root))")
        }
      }
    }

    // 2) Source file heuristic if markers are sparse
    var sourceFileCount = 0
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return ProjectProfile(root: root, languages: languages, markers: markers, isCodeProject: !markers.isEmpty, why: why)
    }

    while let item = enumerator.nextObject() as? URL {
      // Avoid descending into .git and similar VCS directories
      if item.lastPathComponent.hasPrefix(".git") {
        enumerator.skipDescendants()
        continue
      }
      if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false {
        let ext = item.pathExtension.isEmpty ? "" : ".\(item.pathExtension)".lowercased()
        if let lang = sourceExtToLang[ext] {
          languages.insert(lang)
          sourceFileCount += 1
        }
      }
    }

    let isProject = !markers.isEmpty || sourceFileCount >= 8
    if !isProject {
      why.append("source file count: \(sourceFileCount)")
    }

    return ProjectProfile(
      root: root,
      languages: languages,
      markers: markers,
      isCodeProject: isProject,
      why: why
    )
  }
}
EOF

# 2) Update Rules.swift to include LaTeX-related extensions and a common LaTeX config file
mkdir -p "Sources/MegaprompterCore"
cat > "Sources/MegaprompterCore/Rules.swift" <<'EOF'
// Sources/MegaprompterCore/Rules.swift
import Foundation

/// Include/exclude rules derived from a detected project profile.
public struct IncludeRules {
  public let allowedExts: Set<String>
  public let forceIncludeNames: Set<String>
  public let forceIncludeGlobs: [String]
  public let pruneDirs: Set<String>
  public let excludeNames: Set<String>
  public let excludeExts: Set<String>
}

/// Factory that builds language-aware include rules.
public enum RulesFactory {

  // Directories to prune from traversal entirely.
  // NOTE: Keep this list conservative but comprehensive for common build/cache/vendor dirs.
  private static let basePruneDirs: Set<String> = [
    // User's original + expansions
    "vendor", ".expo", "node_modules", "app-example", ".git", ".next",
    "env", "venv", ".env", ".venv",
    "__pycache__", ".mypy_cache", ".pytest_cache", "lightning_logs",

    // New: Swift/SwiftPM/Xcode/SPM build/caches
    ".build",               // SwiftPM build output
    ".swiftpm",             // SwiftPM workspace state
    "Build",                // Xcode local build dir inside project
    "builds",               // generic plural variant seen in some repos

    // IDE / tooling caches
    ".idea", ".vscode", ".gradle", ".cache", ".parcel-cache", ".turbo",
    ".sass-cache", ".nyc_output", ".coverage", "coverage",

    // Common language build outputs
    "dist", "build", "out", "target", "bin", "obj",

    // Python
    ".tox", ".ruff_cache",

    // Terraform
    ".terraform", "terraform.d",

    // Static site / doc tools
    ".docusaurus", ".vitepress", ".astro",

    // Web frameworks
    ".nuxt", ".svelte-kit",

    // Package managers
    ".yarn", ".pnpm-store",

    // Misc history
    ".history",

    // Apple / Cocoa
    "Pods", "DerivedData",

    // Other VCS
    ".hg", ".svn",

    // Maven / direnv
    ".mvn", ".direnv"
  ]

  // File extensions that are considered "source or config".
  private static let baseAllowedExts: Set<String> = [
    // source
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
    ".py", ".go", ".rs", ".java", ".kt", ".kts",
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".hh", ".cs",
    ".php", ".rb", ".swift",

    // IaC / data / query
    ".tf", ".graphql", ".gql", ".sql",

    // shell
    ".sh", ".bash", ".zsh",

    // structured configs
    ".yml", ".yaml", ".json", ".toml", ".ini", ".cfg", ".conf",

    // web assets as code
    ".html", ".css", ".scss", ".sass", ".less",

    // docs & xml-ish
    ".md", ".xml",

    // build config fragments
    ".gradle",

    // LaTeX family (now supported in Megaprompter)
    ".tex", ".cls", ".sty", ".bib"
  ]

  // Specific filenames to exclude even if they match allowed extensions.
  private static let baseExcludeNames: Set<String> = [
    // lockfiles / noise
    "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "go.sum", "Cargo.lock",
    "Package.resolved",

    // platform noise
    ".DS_Store",

    // NEW: explicitly ignore .gitignore per user request
    ".gitignore"
  ]

  // Extensions to exclude regardless of other rules.
  private static let baseExcludeExts: Set<String> = [
    // compiled/minified/bundled
    ".min.js", ".map",

    // secrets / certificates
    ".pem", ".crt", ".key",

    // binaries / assets / docs not useful for code prompts
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".pdf",

    // archives
    ".zip", ".tar", ".gz", ".tgz", ".xz", ".7z", ".rar",

    // runtime artifacts
    ".so", ".dylib", ".dll", ".class", ".jar", ".war", ".wasm"
  ]

  // Filenames we *always* include if present (important configs).
  // NOTE: Removed `.gitignore` here per user request to ignore it.
  private static let baseForceIncludeNames: Set<String> = [
    "package.json",
    "pyproject.toml", "requirements.txt", "Pipfile", "setup.py", "setup.cfg", "tox.ini", "mypy.ini",
    "go.mod",
    "Cargo.toml",
    "pom.xml",
    "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
    "Dockerfile", "docker-compose.yml", "docker-compose.yaml",
    ".gitattributes",
    "tsconfig.json", "jsconfig.json",
    "next.config.js", "next.config.mjs", "next.config.ts",
    "vite.config.ts", "vite.config.js", "vite.config.mjs",
    "webpack.config.js", "webpack.config.ts",
    "babel.config.js", "babel.config.ts",
    "eslint.config.js", "eslint.config.mjs", ".eslintrc", ".eslintrc.js", ".eslintrc.cjs",
    ".eslintrc.json", ".eslintrc.yaml", ".eslintrc.yml",
    ".prettierrc", ".prettierrc.json", ".prettierrc.yaml", ".prettierrc.yml",
    ".prettierrc.js", ".prettierrc.cjs", "prettier.config.js", "prettier.config.cjs", "prettier.config.ts",
    "Makefile", "CMakeLists.txt",
    "Pipfile.lock",

    // LaTeX build configuration (no extension)
    "latexmkrc"
  ]

  // Glob patterns we *always* include (notably GitHub Actions and CI).
  private static let baseForceIncludeGlobs: [String] = [
    ".github/workflows/*.yml",
    ".github/workflows/*.yaml",
    ".github/actions/**/*.yml",
    ".github/actions/**/*.yaml",
    ".circleci/config.yml",
    ".circleci/config.yaml",
    ".gitlab-ci.yml",
    "azure-pipelines.yml",
    ".github/dependabot.yml"
  ]

  public static func build(for languages: Set<String>) -> IncludeRules {
    var allowed = baseAllowedExts
    let excludeExts = baseExcludeExts
    var prune = basePruneDirs
    let excludeNames = baseExcludeNames
    let forceNames = baseForceIncludeNames
    let forceGlobs = baseForceIncludeGlobs

    // Prefer TypeScript over .js/.jsx; keep .mjs/.cjs for Node configs
    if languages.contains("typescript") {
      allowed.remove(".js")
      allowed.remove(".jsx")
    }

    // Language-specific prunes (in addition to base)
    if languages.contains("python") {
      prune.formUnion(["site-packages"])
    }
    if languages.contains("java") {
      prune.formUnion(["target", "build", ".gradle"])
    }
    if languages.contains("csharp") {
      prune.formUnion(["bin", "obj"])
    }
    if languages.contains("cpp") {
      prune.formUnion(["build", "cmake-build-debug", "cmake-build-release"])
    }
    if languages.contains("rust") {
      prune.formUnion(["target"])
    }
    if languages.contains("go") {
      prune.formUnion(["vendor"])
    }

    return IncludeRules(
      allowedExts: allowed,
      forceIncludeNames: forceNames,
      forceIncludeGlobs: forceGlobs,
      pruneDirs: prune,
      excludeNames: excludeNames,
      excludeExts: excludeExts
    )
  }
}

/// Common test file patterns treated as real code.
public enum TestHeuristics {
  public static func isTestFile(_ url: URL) -> Bool {
    let lower = url.lastPathComponent.lowercased()
    if lower.contains(".test.") || lower.contains(".spec.") ||
       lower.contains("_test.") || lower.contains("-test.") ||
       lower.hasPrefix("test_") || lower.contains("_spec.") {
      return true
    }
    let parts = url.pathComponents.map { $0.lowercased() }
    return parts.contains(where: { ["test", "tests", "__tests__", "spec", "specs"].contains($0) })
  }
}
EOF

# 3) Add tests for LaTeX support
mkdir -p "Tests/MegaprompterTests"
cat > "Tests/MegaprompterTests/LatexSupportTests.swift" <<'EOF'
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
EOF

# 4) Build and run tests to validate changes
echo "[patch] Building project..."
swift build -c release

echo "[patch] Running tests..."
swift test

echo "[patch] All done. LaTeX support added to Megaprompter (detection + inclusion), with tests."

# 5) Verification — ensure the forbidden positional-parameter pattern is not present in this script
pattern_count=$(awk '/\$@/ && $0 !~ /SELF-CHECK-ALLOW/ {c++} END {print c+0}' "patch.sh") # SELF-CHECK-ALLOW
if [ "${pattern_count}" -eq 0 ]; then
  echo "Verification OK: no forbidden positional-parameter pattern detected in patch.sh (excluding the self-check line)."
else
  echo "ERROR: Forbidden positional-parameter pattern detected in patch.sh"
  exit 1
fi