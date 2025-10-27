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
    "docker": ["Dockerfile"]
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
    ".sh": "shell", ".zsh": "shell", ".bash": "shell"
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
