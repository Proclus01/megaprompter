// Sources/MegaprompterCore/Scanner.swift
import Foundation

/// Traverses the project tree and selects eligible source/config files for the megaprompt.
/// Robust pruning: skips any file or directory if **any path segment** matches a pruned name
/// (e.g., `.build`, `.swiftpm`, `.vscode`, `.git`, `node_modules`, etc.), preventing deep
/// traversal into dependency checkouts like `.build/checkouts/...`.
public final class ProjectScanner {
  private let profile: ProjectProfile
  private let rules: IncludeRules
  private let maxFileBytes: UInt64

  public init(profile: ProjectProfile, maxFileBytes: Int) {
    self.profile = profile
    self.rules = RulesFactory.build(for: profile.languages)
    self.maxFileBytes = UInt64(maxFileBytes)
  }

  public func collectFiles() throws -> [URL] {
    var selected: [URL] = []
    let root = profile.root

    // Use a strongly-typed enumerator to avoid conditional-cast warnings.
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
      options: [.skipsPackageDescendants],
      errorHandler: { url, err in
        Console.warn("Error enumerating \(url.path): \(err.localizedDescription)")
        return true
      }
    ) as? FileManager.DirectoryEnumerator else {
      return []
    }

    while let item = enumerator.nextObject() as? URL {
      // --- Global prune: if ANY path component is a pruned directory, skip it entirely.
      if isInPrunedPath(item) {
        // If it's a directory, stop descending; if it's a file, just skip it.
        if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false {
          enumerator.skipDescendants()
        }
        continue
      }

      // Skip directories (files only)
      if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false {
        continue
      }

      if !_shouldConsiderFile(item) { continue }
      if _shouldInclude(item) { selected.append(item) }
    }

    // Stable order for determinism
    selected.sort { $0.pathRelative(to: root) < $1.pathRelative(to: root) }
    return selected
  }

  // MARK: - Helpers

  /// True if any path segment of `url` matches a pruned directory name.
  /// This catches deep paths like `.build/checkouts/.../Sources/...`.
  private func isInPrunedPath(_ url: URL) -> Bool {
    let comps = url.pathComponents
    // Fast path: if the repo root itself is in the list (shouldn't be), ignore that element
    return comps.contains(where: { rules.pruneDirs.contains($0) })
  }

  // MARK: - Filters

  private func _shouldConsiderFile(_ url: URL) -> Bool {
    guard ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) else {
      return false
    }

    let name = url.lastPathComponent
    let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)".lowercased()

    // Skip secrets/noise/locks explicitly
    if rules.excludeNames.contains(name) { return false }
    if rules.excludeExts.contains(ext) { return false }

    // Explicitly skip .env* files
    if name.hasPrefix(".env") { return false }

    // Size guardrail
    if let size = FileSystem.fileSize(url), size > maxFileBytes { return false }

    return true
  }

  private func _shouldInclude(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)".lowercased()
    let rel = url.pathRelative(to: profile.root)

    // Force include by exact name
    if rules.forceIncludeNames.contains(name) { return true }

    // Force include by glob patterns (e.g., GitHub Actions)
    if rules.forceIncludeGlobs.contains(where: { Glob.match(relPath: rel, pattern: $0) }) {
      return true
    }

    // Config files without extension (Dockerfile/Makefile)
    if ext.isEmpty && ["dockerfile", "makefile"].contains(name.lowercased()) {
      return true
    }

    // Standard source extension allowlist
    if rules.allowedExts.contains(ext) {
      return true
    }

    // Include README or near-code docs if small
    if ["readme", "readme.md"].contains(name.lowercased()) {
      return true
    }

    // Tests treated as code if extension is otherwise allowed
    if TestHeuristics.isTestFile(url) {
      return rules.allowedExts.contains(ext)
    }

    return false
  }
}
