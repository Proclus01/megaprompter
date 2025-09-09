import Foundation

/// Minimal glob utilities supporting `*` and `**` for directory segments.
public enum Glob {

  /// Return URLs that match `pattern` (relative to `root`).
  public static func findMatches(root: URL, pattern: String) -> [URL] {
    if !pattern.contains("*") && !pattern.contains("?") {
      let direct = root.appendingPathComponent(pattern)
      return FileManager.default.fileExists(atPath: direct.path) ? [direct] : []
    }
    var matches: [URL] = []
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
      options: [.skipsHiddenFiles],
      errorHandler: nil
    ) as? FileManager.DirectoryEnumerator else {
      return matches
    }
    while let item = enumerator.nextObject() as? URL {
      let rel = item.pathRelative(to: root)
      if Glob.match(relPath: rel, pattern: pattern) {
        matches.append(item)
      }
    }
    return matches
  }

  /// Check if `relPath` (POSIX) matches the provided glob `pattern`.
  public static func match(relPath: String, pattern: String) -> Bool {
    let regex = globToRegex(pattern)
    return relPath.range(of: regex, options: [.regularExpression]) != nil
  }

  /// Crude glob → regex converter supporting `*`, `**`, `?`.
  private static func globToRegex(_ glob: String) -> String {
    var out = "^"
    let scalars = Array(glob.unicodeScalars)
    var i = 0
    while i < scalars.count {
      let ch = scalars[i]
      if ch == "*" {
        let nextIsStar = (i + 1 < scalars.count && scalars[i + 1] == "*")
        if nextIsStar {
          out += ".*"    // ** → match across directories
          i += 2
        } else {
          out += "[^/]*" // * → within a segment
          i += 1
        }
        continue
      } else if ch == "?" {
        out += "."
      } else {
        let escaped = NSRegularExpression.escapedPattern(for: String(ch))
        out += escaped
      }
      i += 1
    }
    out += "$"
    return out
  }
}
