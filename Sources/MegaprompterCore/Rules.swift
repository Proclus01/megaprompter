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
    ".gradle"
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
    "Pipfile.lock"
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
