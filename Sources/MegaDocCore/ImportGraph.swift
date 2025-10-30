import Foundation
import MegaprompterCore

public enum ImportGrapher {

  public static func build(root: URL, files: [URL], maxAnalyzeBytes: Int) -> (imports: [DocImport], asciiGraph: String) {
    var all: [DocImport] = []
    var edges: [(String, String)] = []

    for f in files {
      guard let lang = language(for: f) else { continue }
      guard let data = try? Data(contentsOf: f) else { continue }
      var text = String(decoding: data, as: UTF8.self)
      if text.utf8.count > maxAnalyzeBytes {
        text = String(text.prefix(maxAnalyzeBytes))
      }
      let imps = parseImports(content: text, lang: lang)
      let resolved = imps.map { raw -> DocImport in
        let res = resolve(root: root, from: f, raw: raw, lang: lang)
        return DocImport(file: f.path, language: lang, raw: raw, isInternal: res.isInternal, resolvedPath: res.resolvedPath)
      }
      all.append(contentsOf: resolved)
      for r in resolved {
        let to = r.isInternal ? (r.resolvedPath ?? r.raw) : r.raw
        edges.append((f.path, to))
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

  private static func resolve(root: URL, from file: URL, raw: String, lang: String) -> (isInternal: Bool, resolvedPath: String?) {
    if raw.hasPrefix("./") || raw.hasPrefix("../") {
      if let rp = resolveRelative(root: root, from: file, raw: raw) {
        return (true, rp.path)
      }
      return (true, nil)
    }
    if raw.contains("://") { return (false, nil) }
    let stem = raw.split(separator: "/").last.map(String.init) ?? raw
    if let rp = searchByStem(root: root, stem: stem) {
      return (true, rp.path)
    }
    return (false, nil)
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

  private static func searchByStem(root: URL, stem: String) -> URL? {
    guard let enumr = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
    for case let f as URL in enumr {
      if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false {
        if f.deletingPathExtension().lastPathComponent == stem || f.lastPathComponent == stem {
          return f
        }
      }
    }
    return nil
  }

  private static func renderASCII(root: URL, edges: [(String,String)]) -> String {
    var bySrc: [String: [String]] = [:]
    for (from, to) in edges {
      let relFrom = relativize(from, root)
      let relTo = to.contains("/") ? relativize(to, root) : to
      bySrc[relFrom, default: []].append(relTo)
    }
    var lines: [String] = []
    for src in bySrc.keys.sorted() {
      lines.append(src)
      let tgts = Array(Set(bySrc[src]!)).sorted()
      for t in tgts {
        let tag = t.contains("/") ? "(internal)" : "(external)"
        lines.append("  └─> \(t) \(tag)")
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func relativize(_ p: String, _ root: URL) -> String {
    let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
    if p.hasPrefix(base) { return String(p.dropFirst(base.count)) }
    return p
  }

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
