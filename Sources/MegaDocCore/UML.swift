import Foundation
import MegaprompterCore

public enum UMLGranularity: String {
  case file, module, package
}

public enum UMLNodeKind: String, Codable {
  case module, external, datasource, endpoint, main
}

public enum UMLEdgeRel: String, Codable {
  case imports, uses, serves
}

public struct UMLNode: Codable {
  public let id: String
  public let label: String
  public let kind: UMLNodeKind
  public let group: String?
  public let collapsedCount: Int?

  public init(id: String, label: String, kind: UMLNodeKind, group: String?, collapsedCount: Int? = nil) {
    self.id = id
    self.label = label
    self.kind = kind
    self.group = group
    self.collapsedCount = collapsedCount
  }
}

public struct UMLEdge: Codable, Hashable {
  public let fromId: String
  public let toId: String
  public let rel: UMLEdgeRel
  public let label: String?

  public init(fromId: String, toId: String, rel: UMLEdgeRel, label: String? = nil) {
    self.fromId = fromId
    self.toId = toId
    self.rel = rel
    self.label = label
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(fromId)
    hasher.combine(toId)
    hasher.combine(rel.rawValue)
    hasher.combine(label ?? "")
  }

  public static func == (lhs: UMLEdge, rhs: UMLEdge) -> Bool {
    return lhs.fromId == rhs.fromId && lhs.toId == rhs.toId && lhs.rel == rhs.rel && lhs.label == rhs.label
  }
}

public struct UMLDiagram: Codable {
  public let nodes: [UMLNode]
  public let edges: [UMLEdge]
  public let legend: String
}

public final class UMLBuilder {
  private let root: URL
  private let imports: [DocImport]
  private let files: [URL]
  private let maxAnalyzeBytes: Int
  private let granularity: UMLGranularity

  public init(root: URL, imports: [DocImport], files: [URL], maxAnalyzeBytes: Int, granularity: UMLGranularity) {
    self.root = root
    self.imports = imports
    self.files = files
    self.maxAnalyzeBytes = maxAnalyzeBytes
    self.granularity = granularity
  }

  public func build(includeIO: Bool, includeEndpoints: Bool, maxNodes: Int) -> UMLDiagram {
    var nodes: [String: UMLNode] = [:]
    var edges = Set<UMLEdge>()
    var externalCounts: [String: Int] = [:]

    var fileToModule: [String: String] = [:]
    for f in files {
      let rel = relativize(f.path)
      fileToModule[f.path] = moduleName(forRelPath: rel)
    }

    for di in imports {
      let fromFile = di.file
      let fromModule = fileToModule[fromFile] ?? moduleName(forRelPath: relativize(fromFile))
      let fromId = nodeId(label: fromModule, kind: .module)
      ensureNode(nodes: &nodes, id: fromId, label: fromModule, kind: .module, group: groupFor(label: fromModule))

      if di.isInternal, let rp = di.resolvedPath {
        let toModule = fileToModule[rp] ?? moduleName(forRelPath: relativize(rp))
        let toId = nodeId(label: toModule, kind: .module)
        ensureNode(nodes: &nodes, id: toId, label: toModule, kind: .module, group: groupFor(label: toModule))
        edges.insert(UMLEdge(fromId: fromId, toId: toId, rel: .imports, label: nil))
      } else {
        let ext = di.raw
        externalCounts[ext, default: 0] += 1
      }
    }

    let topExternalCount = max(5, min(15, maxNodes / 6))
    let sortedExternals = externalCounts.sorted { $0.value > $1.value }
    let keptExternals = Set(sortedExternals.prefix(topExternalCount).map { $0.key })
    let collapsedCount = max(0, sortedExternals.count - keptExternals.count)
    if collapsedCount > 0 {
      let lbl = "external/*"
      let id = nodeId(label: lbl, kind: .external)
      ensureNode(nodes: &nodes, id: id, label: "[external/*] (\(collapsedCount) more)", kind: .external, group: "external")
      for di in imports where !di.isInternal {
        if !keptExternals.contains(di.raw) {
          let fromModule = fileToModule[di.file] ?? moduleName(forRelPath: relativize(di.file))
          let fromId = nodeId(label: fromModule, kind: .module)
          ensureNode(nodes: &nodes, id: fromId, label: fromModule, kind: .module, group: groupFor(label: fromModule))
          edges.insert(UMLEdge(fromId: fromId, toId: id, rel: .imports, label: nil))
        }
      }
    }
    for di in imports where !di.isInternal {
      if keptExternals.contains(di.raw) {
        let extLbl = "ext:\(di.raw)"
        let extId = nodeId(label: extLbl, kind: .external)
        ensureNode(nodes: &nodes, id: extId, label: extLbl, kind: .external, group: "external")
        let fromModule = fileToModule[di.file] ?? moduleName(forRelPath: relativize(di.file))
        let fromId = nodeId(label: fromModule, kind: .module)
        ensureNode(nodes: &nodes, id: fromId, label: fromModule, kind: .module, group: groupFor(label: fromModule))
        edges.insert(UMLEdge(fromId: fromId, toId: extId, rel: .imports, label: nil))
      }
    }

    var moduleToIO: [String: IOFlags] = [:]
    var mainFiles: [URL] = []
    if includeIO || includeEndpoints {
      for f in files {
        guard let data = try? Data(contentsOf: f) else { continue }
        var text = String(decoding: data, as: UTF8.self)
        if text.utf8.count > maxAnalyzeBytes { text = String(text.prefix(maxAnalyzeBytes)) }
        let lower = text.lowercased()
        let rel = relativize(f.path)
        let module = fileToModule[f.path] ?? moduleName(forRelPath: rel)
        if includeIO {
          let current = moduleToIO[module] ?? IOFlags()
          let merged = current.merged(with: detectIO(in: lower))
          moduleToIO[module] = merged
        }
        if includeEndpoints {
          let lang = language(for: f)
          for ep in detectEndpoints(in: text, lang: lang) {
            let epLabel = "(\(ep.method) \(ep.path))"
            let epId = nodeId(label: "endpoint:\(ep.method) \(ep.path)", kind: .endpoint)
            ensureNode(nodes: &nodes, id: epId, label: epLabel, kind: .endpoint, group: "endpoint")
            let modId = nodeId(label: module, kind: .module)
            ensureNode(nodes: &nodes, id: modId, label: module, kind: .module, group: groupFor(label: module))
            edges.insert(UMLEdge(fromId: epId, toId: modId, rel: .serves, label: nil))
          }
        }
        if isMainFile(url: f, contentLower: lower) {
          mainFiles.append(f)
        }
      }
    }

    if includeIO {
      for (module, flags) in moduleToIO {
        let modId = nodeId(label: module, kind: .module)
        ensureNode(nodes: &nodes, id: modId, label: module, kind: .module, group: groupFor(label: module))
        if flags.db {
          let dbName = flags.dbKind ?? "db"
          let id = nodeId(label: "db:\(dbName)", kind: .datasource)
          ensureNode(nodes: &nodes, id: id, label: "db: \(dbName)", kind: .datasource, group: "datasource")
          edges.insert(UMLEdge(fromId: modId, toId: id, rel: .uses, label: "uses"))
        }
        if flags.fsRead || flags.fsWrite {
          let id = nodeId(label: "fs", kind: .datasource)
          ensureNode(nodes: &nodes, id: id, label: "fs", kind: .datasource, group: "datasource")
          edges.insert(UMLEdge(fromId: modId, toId: id, rel: .uses, label: flags.fsWrite ? "reads/writes" : "reads"))
        }
        if flags.env {
          let id = nodeId(label: "env", kind: .datasource)
          ensureNode(nodes: &nodes, id: id, label: "env", kind: .datasource, group: "datasource")
          edges.insert(UMLEdge(fromId: modId, toId: id, rel: .uses, label: "reads"))
        }
        if flags.network {
          let id = nodeId(label: "http:external", kind: .datasource)
          ensureNode(nodes: &nodes, id: id, label: "http: external", kind: .datasource, group: "datasource")
          edges.insert(UMLEdge(fromId: modId, toId: id, rel: .uses, label: "calls"))
        }
      }
    }

    if let mf = mainFiles.first {
      let mainId = nodeId(label: "main", kind: .main)
      ensureNode(nodes: &nodes, id: mainId, label: "main", kind: .main, group: "main")
      let mainPath = mf.path
      let mainImports = imports.filter { $0.file == mainPath && $0.isInternal && $0.resolvedPath != nil }
      let mm = fileToModule[mainPath] ?? moduleName(forRelPath: relativize(mainPath))
      for mi in mainImports {
        if let rp = mi.resolvedPath {
          let target = fileToModule[rp] ?? moduleName(forRelPath: relativize(rp))
          let toId = nodeId(label: target, kind: .module)
          ensureNode(nodes: &nodes, id: toId, label: target, kind: .module, group: groupFor(label: target))
          edges.insert(UMLEdge(fromId: mainId, toId: toId, rel: .imports, label: nil))
        }
      }
      let selfId = nodeId(label: mm, kind: .module)
      ensureNode(nodes: &nodes, id: selfId, label: mm, kind: .module, group: groupFor(label: mm))
      edges.insert(UMLEdge(fromId: mainId, toId: selfId, rel: .imports, label: nil))
    }

    let legend = """
Legend:
- [module] components (grouped by \(granularity.rawValue))
- ext:* are external libraries
- db:/fs/env/http:external are data sources
- (METHOD /path) are HTTP endpoints
- main is the top-level entrypoint (if detected)
Arrows:
- imports: [a] --> [b]
- uses:    [a] ..> [ds]
- serves:  (endpoint) --> [handler module]
"""
    return UMLDiagram(nodes: Array(nodes.values), edges: Array(edges), legend: legend)
  }

  public static func toASCII(_ d: UMLDiagram) -> String {
    var lines: [String] = []
    lines.append(d.legend)
    let edgeLines: [String] = d.edges
      .sorted(by: { (lhs, rhs) in
        if lhs.rel == rhs.rel {
          if lhs.fromId == rhs.fromId { return lhs.toId < rhs.toId }
          return lhs.fromId < rhs.fromId
        }
        return lhs.rel.rawValue < rhs.rel.rawValue
      })
      .map { e in
        let from = label(for: e.fromId, in: d)
        let to = label(for: e.toId, in: d)
        switch e.rel {
        case .imports:
          return "\(from) --> \(to)"
        case .uses:
          if let lbl = e.label, !lbl.isEmpty {
            return "\(from) ..> \(to) <<\(lbl)>>"
          } else {
            return "\(from) ..> \(to)"
          }
        case .serves:
          return "\(from) --> \(to)"
        }
      }
    lines.append(contentsOf: edgeLines)
    return lines.joined(separator: "\n")
  }

  public static func toPlantUML(_ d: UMLDiagram) -> String {
    var lines: [String] = []
    lines.append("@startuml")
    lines.append("skinparam componentStyle rectangle")
    for n in d.nodes.sorted(by: { $0.id < $1.id }) {
      let id = pumlId(n.id)
      switch n.kind {
      case .module:
        lines.append("rectangle \"\(escapeQuotes(n.label))\" as \(id)")
      case .external:
        lines.append("component \"\(escapeQuotes(n.label))\" as \(id)")
      case .datasource:
        if n.label.lowercased().hasPrefix("db:") {
          lines.append("database \"\(escapeQuotes(n.label))\" as \(id)")
        } else {
          lines.append("queue \"\(escapeQuotes(n.label))\" as \(id)")
        }
      case .endpoint:
        lines.append("usecase \"\(escapeQuotes(n.label))\" as \(id)")
      case .main:
        lines.append("rectangle \"main\" as \(id)")
      }
    }
    for e in d.edges.sorted(by: { $0.fromId + $0.toId < $1.fromId + $1.toId }) {
      let from = pumlId(e.fromId)
      let to = pumlId(e.toId)
      switch e.rel {
      case .imports:
        lines.append("\(from) --> \(to)")
      case .uses:
        if let lbl = e.label, !lbl.isEmpty {
          lines.append("\(from) ..> \(to) : \(escapeQuotes(lbl))")
        } else {
          lines.append("\(from) ..> \(to)")
        }
      case .serves:
        lines.append("\(from) --> \(to)")
      }
    }
    lines.append("@enduml")
    return lines.joined(separator: "\n")
  }

  // Helpers

  private func ensureNode(nodes: inout [String: UMLNode], id: String, label: String, kind: UMLNodeKind, group: String?) {
    if nodes[id] == nil {
      nodes[id] = UMLNode(id: id, label: label, kind: kind, group: group, collapsedCount: nil)
    }
  }

  private func nodeId(label: String, kind: UMLNodeKind) -> String {
    let raw = "\(kind.rawValue)_\(label)"
    return raw
      .replacingOccurrences(of: "[^A-Za-z0-9_:/ .-]", with: "", options: .regularExpression)
      .replacingOccurrences(of: " ", with: "_")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
  }

  private static func label(for id: String, in d: UMLDiagram) -> String {
    if let n = d.nodes.first(where: { $0.id == id }) {
      switch n.kind {
      case .endpoint:
        return n.label
      default:
        return "[\(n.label)]"
      }
    }
    return id
  }

  private static func pumlId(_ s: String) -> String {
    return s.replacingOccurrences(of: "[^A-Za-z0-9_]", with: "_", options: .regularExpression)
  }

  private static func escapeQuotes(_ s: String) -> String {
    s.replacingOccurrences(of: "\"", with: "\\\"")
  }

  private func relativize(_ p: String) -> String {
    let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
    if p.hasPrefix(base) { return String(p.dropFirst(base.count)) }
    return p
  }

  private func moduleName(forRelPath rel: String) -> String {
    switch granularity {
    case .file:
      return rel
    case .module:
      let comps = rel.split(separator: "/").map(String.init)
      if comps.isEmpty { return rel }
      let anchors = ["src","lib","pkg","app","cmd","internal"]
      if let first = comps.first, anchors.contains(first), comps.count >= 2 {
        return first + "/" + comps[1]
      }
      return comps[0]
    case .package:
      let comps = rel.split(separator: "/").map(String.init)
      if comps.isEmpty { return rel }
      return comps[0]
    }
  }

  private func groupFor(label: String) -> String {
    if label.hasPrefix("src/") { return "src" }
    if label.hasPrefix("pkg/") { return "pkg" }
    if label.hasPrefix("lib/") { return "lib" }
    if label.hasPrefix("app/") { return "app" }
    if label.hasPrefix("cmd/") { return "cmd" }
    if label.hasPrefix("internal/") { return "internal" }
    return "root"
  }

  private func language(for url: URL) -> String {
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
    default: return "unknown"
    }
  }

  // IO detection

  private struct IOFlags {
    var fsRead = false
    var fsWrite = false
    var network = false
    var db = false
    var env = false
    var concurrency = false
    var dbKind: String?

    func merged(with other: IOFlags) -> IOFlags {
      var m = self
      m.fsRead = m.fsRead || other.fsRead
      m.fsWrite = m.fsWrite || other.fsWrite
      m.network = m.network || other.network
      m.db = m.db || other.db
      m.env = m.env || other.env
      m.concurrency = m.concurrency || other.concurrency
      if m.dbKind == nil { m.dbKind = other.dbKind }
      return m
    }
  }

  private func detectIO(in lower: String) -> IOFlags {
    var f = IOFlags()
    if lower.contains("fs.") || lower.contains("open(") || lower.contains("os.open") || lower.contains("filemanager") || lower.contains("files.") || lower.contains("pathlib") {
      f.fsRead = true
    }
    if lower.contains("writefile") || lower.contains("fs.write") || lower.contains("os.create") || lower.contains("os.write") || lower.contains("filemanager.default.create") {
      f.fsWrite = true
    }
    if lower.contains("http.") || lower.contains("fetch(") || lower.contains("urlsession") || lower.contains("requests.") || lower.contains("reqwest") || lower.contains("net/http") || lower.contains("httpclient") {
      f.network = true
    }
    if lower.contains("process.env") || lower.contains("os.environ") || lower.contains("getenv(") || lower.contains("environment.") {
      f.env = true
    }
    if lower.contains("async") || lower.contains("await") || lower.contains("goroutine") || lower.contains(" go ") || lower.contains("chan") || lower.contains("thread") || lower.contains("dispatchqueue") || lower.contains("tokio") || lower.contains("spawn") || lower.contains("executor") || lower.contains("completablefuture") {
      f.concurrency = true
    }
    if lower.contains("sqlalchemy") || lower.contains("psycopg2") || lower.contains("gorm") || lower.contains("database/sql") || lower.contains("entitymanager") || lower.contains("jpa") || lower.contains("mongoose") || lower.contains("redis") || lower.contains("sequel") {
      f.db = true
      if lower.contains("postgres") || lower.contains("psycopg2") || lower.contains("pq") { f.dbKind = "postgres" }
      else if lower.contains("mysql") { f.dbKind = "mysql" }
      else if lower.contains("sqlite") { f.dbKind = "sqlite" }
      else if lower.contains("mongo") { f.dbKind = "mongo" }
      else if lower.contains("redis") { f.dbKind = "redis" }
    }
    return f
  }

  private func detectEndpoints(in text: String, lang: String) -> [(method: String, path: String)] {
    var out: [(String,String)] = []
    func add(_ m: String, _ p: String) { out.append((m.uppercased(), p)) }

    switch lang {
    case "javascript","typescript":
      if let re = try? NSRegularExpression(pattern: #"(?m)\b(app|router|server|fastify)\.(get|post|put|delete|patch)\(\s*['"]([^'"]+)['"]"#) {
        find3(re, text).forEach { add($0.1, $0.2) }
      }
      if let re2 = try? NSRegularExpression(pattern: #"(?m)new\s+Router\(\)\.(get|post|put|delete|patch)\(\s*['"]([^'"]+)['"]"#) {
        find2(re2, text).forEach { add($0.0, $0.1) }
      }
    case "python":
      if let re = try? NSRegularExpression(pattern: #"(?m)^\s*@(?:app|router)\.(get|post|put|delete|patch)\(\s*['"]([^'"]+)['"]"#) {
        find2(re, text).forEach { add($0.0, $0.1) }
      }
    case "go":
      if let re = try? NSRegularExpression(pattern: #"(?m)(?:http\.HandleFunc|\.GET|\.POST|\.PUT|\.DELETE)\(\s*["']([^"']+)["']"#) {
        find1(re, text).forEach { add("GET", $0) }
      }
    case "rust":
      if let re = try? NSRegularExpression(pattern: #"(?m)^\s*#\[\s*(get|post|put|delete|patch)\s*\(\s*["']([^"']+)['"]"#) {
        find2(re, text).forEach { add($0.0, $0.1) }
      }
    case "java","kotlin":
      if let re = try? NSRegularExpression(pattern: #"(?m)^\s*@(?:GetMapping|PostMapping|PutMapping|DeleteMapping)\(\s*["']([^"']+)['"]"#) {
        let m = find1(re, text)
        for p in m {
          let method: String
          if p.lowercased().contains("post") { method = "POST" }
          else if p.lowercased().contains("put") { method = "PUT" }
          else if p.lowercased().contains("delete") { method = "DELETE" }
          else { method = "GET" }
          add(method, p.replacingOccurrences(of: "\"", with: ""))
        }
      }
    default:
      break
    }
    return out
  }

  private func isMainFile(url: URL, contentLower: String) -> Bool {
    let rel = relativize(url.path).lowercased()
    if rel == "src/main.rs" || url.lastPathComponent.lowercased() == "main.swift" { return true }
    if rel.hasSuffix("/main.ts") || rel.hasSuffix("/main.js") || rel.hasSuffix("/server.ts") || rel.hasSuffix("/server.js") || rel == "src/index.ts" || rel == "src/index.js" || rel == "index.ts" || rel == "index.js" {
      return true
    }
    if contentLower.contains("package main") && contentLower.contains("func main(") { return true }
    if contentLower.contains("@main") { return true }
    if contentLower.contains("public static void main(") { return true }
    if contentLower.contains("fun main(") { return true }
    return false
  }

  private func find1(_ re: NSRegularExpression, _ s: String) -> [String] {
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
  private func find2(_ re: NSRegularExpression, _ s: String) -> [(String,String)] {
    let ns = s as NSString
    let rng = NSRange(location: 0, length: ns.length)
    var out: [(String,String)] = []
    re.enumerateMatches(in: s, options: [], range: rng) { m, _, _ in
      if let m, m.numberOfRanges >= 3 {
        let a = ns.substring(with: m.range(at: 1))
        let b = ns.substring(with: m.range(at: 2))
        out.append((a,b))
      }
    }
    return out
  }
  private func find3(_ re: NSRegularExpression, _ s: String) -> [(String,String,String)] {
    let ns = s as NSString
    let rng = NSRange(location: 0, length: ns.length)
    var out: [(String,String,String)] = []
    re.enumerateMatches(in: s, options: [], range: rng) { m, _, _ in
      if let m, m.numberOfRanges >= 4 {
        let a = ns.substring(with: m.range(at: 1))
        let b = ns.substring(with: m.range(at: 2))
        let c = ns.substring(with: m.range(at: 3))
        out.append((a,b,c))
      }
    }
    return out
  }
}
