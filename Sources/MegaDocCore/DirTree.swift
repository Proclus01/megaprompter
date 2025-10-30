import Foundation
import MegaprompterCore

public enum DirTreeBuilder {
  public static func buildTree(root: URL, maxDepth: Int, ignoreNames: Set<String>, ignoreGlobs: [String]) -> String {
    var lines: [String] = []
    let base = root.path
    func rel(_ u: URL) -> String {
      let p = u.path
      let baseWithSlash = base.hasSuffix("/") ? base : (base + "/")
      if p.hasPrefix(baseWithSlash) {
        return String(p.dropFirst(baseWithSlash.count))
      }
      return u.lastPathComponent
    }

    let rules = RulesFactory.build(for: [])
    func pruned(_ url: URL) -> Bool {
      let comps = url.pathComponents
      if comps.contains(where: { rules.pruneDirs.contains($0) || ignoreNames.contains($0) }) {
        return true
      }
      let r = rel(url)
      if ignoreGlobs.contains(where: { Glob.match(relPath: r, pattern: $0) }) {
        return true
      }
      return false
    }

    func walk(_ dir: URL, depth: Int, prefix: String) {
      guard depth <= maxDepth else { return }
      guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }

      let entries = items
        .filter { !pruned($0) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

      for (idx, e) in entries.enumerated() {
        let isDir = (try? e.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isLast = idx == entries.count - 1
        let branch = isLast ? "└── " : "├── "
        lines.append(prefix + branch + e.lastPathComponent)
        if isDir {
          let newPrefix = prefix + (isLast ? "    " : "│   ")
          walk(e, depth: depth + 1, prefix: newPrefix)
        }
      }
    }

    lines.append(root.lastPathComponent)
    walk(root, depth: 1, prefix: "")
    return lines.joined(separator: "\n")
  }
}
