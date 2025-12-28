import Foundation
import MegaprompterCore

public enum ImportGrapher {

  // Internal edge model retains internal/external classification explicitly.
  private typealias Edge = (from: String, to: String, isInternal: Bool)

  public static func build(root: URL, files: [URL], maxAnalyzeBytes: Int) -> (imports: [DocImport], asciiGraph: String) {
    var all: [DocImport] = []
    var edges: [Edge] = []

    // Performance: build a one-pass index for "stem" resolution.
    // This avoids scanning the entire repo repeatedly (O(imports × repo_files)).
    let stemIndex = StemIndex.build(files: files)

    for f in files {
      guard let lang = language(for: f) else { continue }
      guard let data = try? Data(contentsOf: f) else { continue }
      var text = String(decoding: data, as: UTF8.self)
      if text.utf8.count > maxAnalyzeBytes {
        text = String(text.prefix(maxAnalyzeBytes))
      }

      let imps = parseImports(content: text, lang: lang)
      let resolvedImports: [DocImport] = imps.map { raw in
        let res = resolve(root: root, from: f, raw: raw, lang: lang, stemIndex: stemIndex)
        return DocImport(file: f.path, language: lang, raw: raw, isInternal: res.isInternal, resolvedPath: res.resolvedPath)
      }

      all.append(contentsOf: resolvedImports)

      for r in resolvedImports {
        let to = r.isInternal ? (r.resolvedPath ?? r.raw) : r.raw
        edges.append((from: f.path, to: to, isInternal: r.isInternal))
      }
    }

    let ascii = renderASCII(root: root, edges: edges)
    return (all, ascii)
  }

  public static func externalSummary(imports: [DocImport]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for i in imports where !i.isInternal {
      counts[i.raw, default: 0] += 1
    }
    return counts
  }

  private static func language(for url: URL) -> String? {
    let ext = url.pathExtension.lowercased()
    switch ext {
      case "ts","tsx": return "typescript"
      case "js","jsx","mjs","cjs": return "javascript"
      case "py": return "python"
      case "go": return "go"
      case "rs": return "rust"
      case "swift": return "swift"
      case "java": return "java"
      case "kt","kts": return "kotlin"
      default: return nil
    }
  }

  private static func parseImports(content: String, lang: String) -> [String] {
    var out: [String] = []
    switch lang {
      case "typescript","javascript":
        let res = try? NSRegularExpression(pattern: #"(?m)^\s*import\s+(?:[^'"]*\s+from\s+)?['"]([^'"]+)['"]"#)
        let req = try? NSRegularExpression(pattern: #"(?m)require\(\s*['"]([^'"]+)['"]\s*\)"#)
        let dyn = try? NSRegularExpression(pattern: #"(?m)import\(\s*['"]([^'"]+)['"]\s*\)"#)
        out += findMatches(res, content)
        out += findMatches(req, content)
        out += findMatches(dyn, content)
      case "python":
        let imp = try? NSRegularExpression(pattern: #"(?m)^\s*import\s+([A-Za-z0-9_\.]+)"#)
        let frm = try? NSRegularExpression(pattern: #"(?m)^\s*from\s+([A-Za-z0-9_\.]+)\s+import\s+"#)
        out += findMatches(imp, content)
        out += findMatches(frm, content)
      case "go":
        let line = try? NSRegularExpression(pattern: #"(?m)^\s*import\s+["]([^"]+)["]"#)
        out += findMatches(line, content)
        if let blk = try? NSRegularExpression(pattern: #"(?s)import\s*\(\s*([^\)]+)\s*\)"#) {
          let block = findMatchesSingle(blk, content)
          if !block.isEmpty {
            let inner = block.joined(separator: "\n")
            if let q = try? NSRegularExpression(pattern: #"(?m)["]([^"]+)["]"#) {
              out += findMatches(q, inner)
            }
          }
        }
      case "rust":
        let useR = try? NSRegularExpression(pattern: #"(?m)^\s*use\s+([A-Za-z0-9_:]+)"#)
        out += findMatches(useR, content)
      case "swift":
        let imp = try? NSRegularExpression(pattern: #"(?m)^\s*import\s+([A-Za-z0-9_]+)"#)
        out += findMatches(imp, content)
      case "java","kotlin":
        let imp = try? NSRegularExpression(pattern: #"(?m)^\s*import\s+([A-Za-z0-9_\.]+)"#)
        out += findMatches(imp, content)
      default: break
    }
    return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  private static func resolve(root: URL, from file: URL, raw: String, lang: String, stemIndex: StemIndex) -> (isInternal: Bool, resolvedPath: String?) {
    // Explicit internal import patterns first.
    if raw.hasPrefix("./") || raw.hasPrefix("../") {
      if let rp = resolveRelative(root: root, from: file, raw: raw) {
        return (true, rp.path)
      }
      return (true, nil)
    }

    // URLs are external.
    if raw.contains("://") { return (false, nil) }

    // Heuristic internal-by-stem resolution:
    // Only claim "internal" if there is a unique match in the current file set.
    // This prevents many false positives for external packages like "@scope/pkg" or "react-dom/client".
    if isLikelyExternalImport(raw, lang: lang) {
      return (false, nil)
    }

    let stem = raw.split(separator: "/").last.map(String.init) ?? raw
    if let rp = stemIndex.lookupUnique(stem: stem) {
      return (true, rp.path)
    }

    return (false, nil)
  }

  private static func isLikelyExternalImport(_ raw: String, lang: String) -> Bool {
    // JS/TS: npm scopes and node: prefixes are external.
    if lang == "typescript" || lang == "javascript" {
      if raw.hasPrefix("@") { return true }
      if raw.hasPrefix("node:") { return true }
      // Most package imports do not start with '.'; however, internal aliasing is common.
      // We avoid aggressive "stem" resolution for raw containing '/' because it is often external (e.g. react-dom/client).
      if raw.contains("/") { return true }
      return false
    }

    // Go: module paths almost always include '/' when external.
    if lang == "go" {
      if raw.contains(".") && raw.contains("/") { return true }
      return false
    }

    // Rust: crates can be single token; we conservatively do not resolve by stem unless unique match exists.
    // Keep default false.
    return false
  }

  private static func resolveRelative(root: URL, from file: URL, raw: String) -> URL? {
    let baseDir = file.deletingLastPathComponent()
    let cand = baseDir.appendingPathComponent(raw)
    let fm = FileManager.default
    if fm.fileExists(atPath: cand.path) { return cand }
    let exts = ["ts","tsx","js","jsx","mjs","cjs","py","go","rs","swift","java","kt","kts"]
    for e in exts {
      let c2 = cand.appendingPathExtension(e)
      if fm.fileExists(atPath: c2.path) { return c2 }
    }
    let idx = ["index.ts","index.tsx","index.js","mod.rs","lib.rs"]
    for i in idx {
      let c3 = cand.appendingPathComponent(i)
      if fm.fileExists(atPath: c3.path) { return c3 }
    }
    return nil
  }

  private static func renderASCII(root: URL, edges: [Edge]) -> String {
    var bySrc: [String: [(to: String, isInternal: Bool)]] = [:]
    for e in edges {
      let relFrom = relativize(e.from, root)
      let relTo = e.isInternal ? relativize(e.to, root) : e.to
      bySrc[relFrom, default: []].append((to: relTo, isInternal: e.isInternal))
    }

    var lines: [String] = []
    for src in bySrc.keys.sorted() {
      lines.append(src)
      let tgts = uniqueTargets(bySrc[src] ?? [])
      for t in tgts {
        let tag = t.isInternal ? "(internal)" : "(external)"
        lines.append("  └─> \(t.to) \(tag)")
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func uniqueTargets(_ targets: [(to: String, isInternal: Bool)]) -> [(to: String, isInternal: Bool)] {
    var seen = Set<String>()
    var out: [(to: String, isInternal: Bool)] = []
    for t in targets {
      let key = "\(t.isInternal ? "i" : "e"):\(t.to)"
      if seen.contains(key) { continue }
      seen.insert(key)
      out.append(t)
    }
    return out.sorted { lhs, rhs in
      if lhs.isInternal != rhs.isInternal { return lhs.isInternal && !rhs.isInternal }
      return lhs.to < rhs.to
    }
  }

  private static func relativize(_ p: String, _ root: URL) -> String {
    let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
    if p.hasPrefix(base) { return String(p.dropFirst(base.count)) }
    return p
  }

  // MARK: - Indexed resolution

  private struct StemIndex {
    // stem -> URLs (usually 0/1; collisions possible).
    let byStem: [String: [URL]]

    static func build(files: [URL]) -> StemIndex {
      var idx: [String: [URL]] = [:]
      idx.reserveCapacity(files.count * 2)
      for f in files {
        // Match both "Foo" and "Foo.ext"
        let stem = f.deletingPathExtension().lastPathComponent
        let full = f.lastPathComponent
        idx[stem, default: []].append(f)
        idx[full, default: []].append(f)
      }
      return StemIndex(byStem: idx)
    }

    func lookupUnique(stem: String) -> URL? {
      let key = stem.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty else { return nil }
      guard let hits = byStem[key], hits.count == 1 else { return nil }
      return hits.first
    }
  }

  // MARK: - Regex helpers

  private static func findMatches(_ re: NSRegularExpression?, _ s: String) -> [String] {
    guard let re else { return [] }
    let ns = s as NSString
    let rng = NSRange(location: 0, length: ns.length)
    var out: [String] = []
    re.enumerateMatches(in: s, options: [], range: rng) { m, _, _ in
      if let m, m.numberOfRanges >= 2 {
        let r = m.range(at: 1)
        if r.location != NSNotFound { out.append(ns.substring(with: r)) }
      }
    }
    return out
  }

  private static func findMatchesSingle(_ re: NSRegularExpression?, _ s: String) -> [String] {
    guard let re else { return [] }
    let ns = s as NSString
    let rng = NSRange(location: 0, length: ns.length)
    var out: [String] = []
    re.enumerateMatches(in: s, options: [], range: rng) { m, _, _ in
      if let m, m.numberOfRanges >= 2 {
        let r = m.range(at: 1)
        if r.location != NSNotFound { out.append(ns.substring(with: r)) }
      }
    }
    return out
  }
}
