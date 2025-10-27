import Foundation

// Lightweight heuristics: extract subjects, infer params, IO, risk, endpoints.

enum Heuristics {
  static let extToLang: [String: String] = [
    "ts":"typescript","tsx":"typescript","js":"javascript","jsx":"javascript","mjs":"javascript","cjs":"javascript",
    "py":"python",
    "go":"go",
    "rs":"rust",
    "swift":"swift",
    "java":"java"
  ]

  static func language(for url: URL) -> String? {
    let ext = url.pathExtension.lowercased()
    return extToLang[ext]
  }

  static func analyzeFile(url: URL, content: String, lang: String) -> [TestSubject] {
    switch lang {
    case "typescript", "javascript": return JSAnalyzer.analyze(url: url, content: content, lang: lang)
    case "python": return PyAnalyzer.analyze(url: url, content: content)
    case "go": return GoAnalyzer.analyze(url: url, content: content)
    case "rust": return RsAnalyzer.analyze(url: url, content: content)
    case "swift": return SwAnalyzer.analyze(url: url, content: content)
    case "java": return JavaAnalyzer.analyze(url: url, content: content)
    default: return []
    }
  }
}

// MARK: - Shared risk + IO detection

enum Risk {
  static func scoreAndFactors(in s: String, lang: String) -> (score: Int, factors: [String]) {
    var score = 1
    var factors: [String] = []

    let branchWords = [" if"," else"," switch"," case"," for"," while"," try"," catch"," guard"," defer"," when"," match"]
    let concurrencyWords = ["async","await","goroutine","go ","chan","thread","DispatchQueue","Task","tokio","spawn","Executor","CompletableFuture"]
    let fsWords = ["fs.","FileManager","open(","readFile","writeFile","os.Open","os.Create","pathlib","io.open","java.nio","Files."]
    let netWords = ["http.","fetch","URLSession","requests","axios","reqwest","net/http",".GET(","@GetMapping","#[get(","HttpClient"]
    let dbWords = ["database/sql","gorm","sqlalchemy","psycopg2","pg.","mongoose","MongoClient","redis","JPA","EntityManager","CoreData","ORM"]
    let envWords = ["process.env","os.environ","getenv","Environment."]

    func approximateCount(_ needles: [String]) -> Int {
      let lower = s.lowercased()
      var total = 0
      for n in needles {
        let parts = lower.components(separatedBy: n.lowercased())
        if parts.count > 1 { total += parts.count - 1 }
      }
      return total
    }

    let branches = approximateCount(branchWords)
    score += min(5, branches / 2)
    if branches > 0 { factors.append("branches ~\(branches)") }

    let conc = approximateCount(concurrencyWords)
    if conc > 0 { score += 2; factors.append("concurrency hints") }

    let fs = approximateCount(fsWords) > 0
    let net = approximateCount(netWords) > 0
    let db = approximateCount(dbWords) > 0
    let env = approximateCount(envWords) > 0

    var ioFlags: [String] = []
    if fs { score += 1; ioFlags.append("fs") }
    if net { score += 1; ioFlags.append("network") }
    if db { score += 2; ioFlags.append("db") }
    if env { score += 1; ioFlags.append("env") }
    if !ioFlags.isEmpty { factors.append("io: " + ioFlags.joined(separator: ",")) }

    let lines = s.split(separator: "\n").count
    if lines > 200 { score += 1; factors.append("long file (~\(lines) lines)") }

    return (max(1, min(10, score)), factors)
  }

  static func ioFlags(in s: String) -> IOCapabilities {
    func has(_ substrings: [String]) -> Bool {
      let lower = s.lowercased()
      for x in substrings { if lower.contains(x.lowercased()) { return true } }
      return false
    }
    let readsFS = has(["readFile","open(","os.Open","FileManager","io.open","Files.read"])
    let writesFS = has(["writeFile","fs.write","os.Create","os.Write","FileManager.default.create","Files.write"])
    let network = has(["http.","fetch","URLSession","requests","axios","reqwest","net/http","HttpClient"])
    let db = has(["database/sql","gorm","sqlalchemy","psycopg2","mongo","mongoose","redis","EntityManager","JPA"])
    let env = has(["process.env","os.environ","getenv","Environment."])
    let concurrency = has(["async","await","go ","chan","thread","DispatchQueue","Task","tokio","spawn","Executor","CompletableFuture"])
    return IOCapabilities(readsFS: readsFS, writesFS: writesFS, network: network, db: db, env: env, concurrency: concurrency)
  }
}

// MARK: - Language analyzers (regex-based)

enum JSAnalyzer {
  static func analyze(url: URL, content: String, lang: String) -> [TestSubject] {
    var out: [TestSubject] = []

    // export function foo(a: number, b?: string) { ... }
    let fnRe = try! NSRegularExpression(pattern: #"(?m)^\s*(?:export\s+)?function\s+([A-Za-z_]\w*)\s*\(([^)]*)\)"#)
    content.enumerateMatches(regex: fnRe) { g in
      let name = g[1]
      let params = parseParamsTS(g[2])
      let sig = "function \(name)(\(g[2]))"
      let (score, factors) = Risk.scoreAndFactors(in: blockFor(name: name, in: content) ?? content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#fn:\(name)", kind: .function, language: lang, name: name,
        path: url.path, signature: sig, exported: content.contains("export function \(name)") || content.contains("export default function \(name)"),
        params: params, riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }

    // class Foo { bar(x) { ... } }
    let clsRe = try! NSRegularExpression(pattern: #"(?m)^\s*(?:export\s+)?class\s+([A-Za-z_]\w*)"#)
    content.enumerateMatches(regex: clsRe) { g in
      let name = g[1]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#class:\(name)", kind: .class, language: lang, name: name,
        path: url.path, signature: "class \(name)", exported: content.contains("export class \(name)") || content.contains("export default class \(name)"),
        params: [], riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }

    // Express-style endpoints: app.get('/path', ...) or router.post('/path', ...)
    let routeRe = try! NSRegularExpression(pattern: #"(?m)\b(app|router)\.(get|post|put|delete|patch)\(\s*['"]([^'"]+)['"]"#)
    content.enumerateMatches(regex: routeRe) { g in
      let method = g[2].uppercased()
      let path = g[3]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#endpoint:\(method) \(path)", kind: .endpoint, language: lang, name: "\(method) \(path)",
        path: url.path, signature: nil, exported: true, params: [],
        riskScore: score, riskFactors: ["http route"] + factors, io: io, meta: ["method": method, "path": path]
      ))
    }

    return out
  }

  private static func parseParamsTS(_ plist: String) -> [SubjectParam] {
    let raw = plist.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    return raw.compactMap { s in
      guard !s.isEmpty else { return nil }
      let parts = s.split(separator: ":", maxSplits: 1).map { String($0) }
      let namePart = parts[0].trimmingCharacters(in: .whitespaces)
      let t = parts.count > 1 ? parts[1].split(separator: "=").first.map(String.init)?.trimmingCharacters(in: .whitespaces) : nil
      let optional = namePart.hasSuffix("?")
      let baseName = optional ? String(namePart.dropLast()) : namePart
      return SubjectParam(name: baseName, typeHint: t, optional: optional)
    }
  }

  private static func blockFor(name: String, in content: String) -> String? {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    for (i, line) in lines.enumerated() where line.contains(name) {
      let start = max(0, i - 10), end = min(lines.count, i + 40)
      return lines[start..<end].joined(separator: "\n")
    }
    return nil
  }
}

enum PyAnalyzer {
  static func analyze(url: URL, content: String) -> [TestSubject] {
    var out: [TestSubject] = []
    let lang = "python"

    let fnRe = try! NSRegularExpression(pattern: #"(?m)^\s*def\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*:"#)
    content.enumerateMatches(regex: fnRe) { g in
      let name = g[1]
      let params = parseParamsPy(g[2])
      let sig = "def \(name)(\(g[2])):"
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#fn:\(name)", kind: .function, language: lang, name: name,
        path: url.path, signature: sig, exported: !name.hasPrefix("_"),
        params: params, riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }

    let clsRe = try! NSRegularExpression(pattern: #"(?m)^\s*class\s+([A-Za-z_]\w*)"#)
    content.enumerateMatches(regex: clsRe) { g in
      let name = g[1]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#class:\(name)", kind: .class, language: lang, name: name,
        path: url.path, signature: "class \(name)", exported: true, params: [], riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }

    // Flask/FastAPI-like: @app.(get|post)(...)
    let routeRe = try! NSRegularExpression(pattern: #"(?m)^\s*@(?:app|router)\.(get|post|put|delete|patch)\(\s*['"]([^'"]+)['"]"#)
    content.enumerateMatches(regex: routeRe) { g in
      let method = g[1].uppercased()
      let path = g[2]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#endpoint:\(method) \(path)", kind: .endpoint, language: lang, name: "\(method) \(path)",
        path: url.path, signature: nil, exported: true, params: [],
        riskScore: score, riskFactors: ["http route"] + factors, io: io, meta: ["method": method, "path": path]
      ))
    }

    return out
  }

  private static func parseParamsPy(_ plist: String) -> [SubjectParam] {
    let raw = plist.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    return raw.compactMap { s in
      guard !s.isEmpty else { return nil }
      let parts = s.split(separator: ":", maxSplits: 1).map { String($0) }
      let name = parts[0].split(separator: "=").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? parts[0]
      let t = parts.count > 1 ? parts[1].split(separator: "=").first.map(String.init)?.trimmingCharacters(in: .whitespaces) : nil
      let optional = s.contains("=") || (t?.contains("None") ?? false)
      return SubjectParam(name: name, typeHint: t, optional: optional)
    }
  }
}

enum GoAnalyzer {
  static func analyze(url: URL, content: String) -> [TestSubject] {
    var out: [TestSubject] = []
    let lang = "go"
    // func Name(a int, b string) OR func (r T) Name(...)
    let fnRe = try! NSRegularExpression(pattern: #"(?m)^\s*func\s*(?:\([^)]+\)\s*)?([A-Za-z_]\w*)\s*\(([^)]*)\)"#)
    content.enumerateMatches(regex: fnRe) { g in
      let name = g[1]
      let params = parseParamsGo(g[2])
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      let exported = name.first.map { String($0) == String($0).uppercased() } ?? false
      out.append(TestSubject(
        id: "\(url.path)#fn:\(name)", kind: .function, language: lang, name: name,
        path: url.path, signature: "func \(name)(\(g[2]))", exported: exported,
        params: params, riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }

    // http.HandleFunc("/path", handler) / gin: r.GET("/path", ...)
    let routeRe = try! NSRegularExpression(pattern: #"(?m)(?:http\.HandleFunc|\.GET|\.POST|\.PUT|\.DELETE)\(\s*["']([^"']+)["']"#)
    content.enumerateMatches(regex: routeRe) { g in
      let method = detectMethod(around: g[0], in: content)
      let path = g[1]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#endpoint:\(method) \(path)", kind: .endpoint, language: lang, name: "\(method) \(path)",
        path: url.path, signature: nil, exported: true, params: [], riskScore: score, riskFactors: ["http route"] + factors, io: io, meta: ["method": method, "path": path]
      ))
    }

    return out
  }

  private static func parseParamsGo(_ plist: String) -> [SubjectParam] {
    let items = plist.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    return items.compactMap { s in
      guard !s.isEmpty else { return nil }
      let toks = s.split(separator: " ").map(String.init).filter { !$0.isEmpty }
      guard !toks.isEmpty else { return nil }
      let name = toks.first!
      let typeHint = toks.dropFirst().joined(separator: " ")
      return SubjectParam(name: name, typeHint: typeHint.isEmpty ? nil : typeHint, optional: false)
    }
  }

  private static func detectMethod(around match: String, in content: String) -> String {
    if match.contains(".GET(") { return "GET" }
    if match.contains(".POST(") { return "POST" }
    if match.contains(".PUT(") { return "PUT" }
    if match.contains(".DELETE(") { return "DELETE" }
    return "GET"
  }
}

enum RsAnalyzer {
  static func analyze(url: URL, content: String) -> [TestSubject] {
    var out: [TestSubject] = []
    let lang = "rust"
    let fnRe = try! NSRegularExpression(pattern: #"(?m)^\s*pub\s+fn\s+([A-Za-z_]\w*)\s*\(([^)]*)\)"#)
    content.enumerateMatches(regex: fnRe) { g in
      let name = g[1]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#fn:\(name)", kind: .function, language: lang, name: name,
        path: url.path, signature: "pub fn \(name)(\(g[2]))", exported: true,
        params: parseParamsRust(g[2]), riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }

    // actix/rocket style macros: #[get("/path")]
    let routeRe = try! NSRegularExpression(pattern: #"(?m)^\s*#\[\s*(get|post|put|delete|patch)\s*\(\s*["']([^"']+)["']"#)
    content.enumerateMatches(regex: routeRe) { g in
      let method = g[1].uppercased()
      let path = g[2]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#endpoint:\(method) \(path)", kind: .endpoint, language: lang, name: "\(method) \(path)",
        path: url.path, signature: nil, exported: true, params: [], riskScore: score, riskFactors: ["http route"] + factors, io: io, meta: ["method": method, "path": path]
      ))
    }
    return out
  }

  private static func parseParamsRust(_ plist: String) -> [SubjectParam] {
    let items = plist.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    return items.compactMap { s in
      guard !s.isEmpty else { return nil }
      let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
      guard parts.count >= 1 else { return nil }
      let name = parts[0].trimmingCharacters(in: .whitespaces)
      let ty = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
      return SubjectParam(name: name, typeHint: ty, optional: false)
    }
  }
}

enum SwAnalyzer {
  static func analyze(url: URL, content: String) -> [TestSubject] {
    var out: [TestSubject] = []
    let lang = "swift"
    let fnRe = try! NSRegularExpression(pattern: #"(?m)^\s*(?:public|open|internal|fileprivate|private)?\s*func\s+([A-Za-z_]\w*)\s*\(([^)]*)\)"#)
    content.enumerateMatches(regex: fnRe) { g in
      let name = g[1]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#fn:\(name)", kind: .function, language: lang, name: name,
        path: url.path, signature: "func \(name)(\(g[2]))", exported: true,
        params: parseParamsSwift(g[2]), riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }
    // Classes/structs/enums
    let typeRe = try! NSRegularExpression(pattern: #"(?m)^\s*(?:public|open|internal|fileprivate|private)?\s*(class|struct|enum)\s+([A-Za-z_]\w*)"#)
    content.enumerateMatches(regex: typeRe) { g in
      let name = g[2]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#class:\(name)", kind: .class, language: lang, name: name,
        path: url.path, signature: "\(g[1]) \(name)", exported: true, params: [], riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }
    return out
  }

  private static func parseParamsSwift(_ plist: String) -> [SubjectParam] {
    let items = plist.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    return items.compactMap { s in
      let namePart = s.split(separator: ":").first.map(String.init) ?? s
      let declaredName = namePart.split(separator: " ").last.map(String.init) ?? namePart
      let ty = s.split(separator: ":").dropFirst().first.map(String.init)
      let hasDefault = s.contains("=")
      let isOptional = (ty?.contains("?") ?? false) || hasDefault
      let cleanedType = ty?.split(separator: "=").first.map { String($0) }.map { $0.trimmingCharacters(in: .whitespaces) }
      return SubjectParam(name: declaredName.trimmingCharacters(in: .whitespaces), typeHint: cleanedType, optional: isOptional)
    }
  }
}

enum JavaAnalyzer {
  static func analyze(url: URL, content: String) -> [TestSubject] {
    var out: [TestSubject] = []
    let lang = "java"
    // public class X
    let clsRe = try! NSRegularExpression(pattern: #"(?m)^\s*public\s+class\s+([A-Za-z_]\w*)"#)
    content.enumerateMatches(regex: clsRe) { g in
      let name = g[1]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#class:\(name)", kind: .class, language: lang, name: name,
        path: url.path, signature: "public class \(name)", exported: true, params: [], riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }
    // public static ... foo(...)
    let fnRe = try! NSRegularExpression(pattern: #"(?m)^\s*(?:public|protected|private)\s+(?:static\s+)?[A-Za-z0-9_<>\[\]]+\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*\{"#)
    content.enumerateMatches(regex: fnRe) { g in
      let name = g[1]
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#fn:\(name)", kind: .function, language: lang, name: name,
        path: url.path, signature: "method \(name)(\(g[2]))", exported: true,
        params: parseParamsJava(g[2]), riskScore: score, riskFactors: factors, io: io, meta: [:]
      ))
    }
    // Spring endpoints
    let routeRe = try! NSRegularExpression(pattern: #"(?m)^\s*@(?:GetMapping|PostMapping|PutMapping|DeleteMapping)\(\s*["']([^"']+)["']"#)
    content.enumerateMatches(regex: routeRe) { g in
      let raw = g[0]
      let path = g[1]
      let method = detectHttpMethod(fromAnnotation: raw)
      let (score, factors) = Risk.scoreAndFactors(in: content, lang: lang)
      let io = Risk.ioFlags(in: content)
      out.append(TestSubject(
        id: "\(url.path)#endpoint:\(method) \(path)", kind: .endpoint, language: lang, name: "\(method) \(path)",
        path: url.path, signature: nil, exported: true, params: [], riskScore: score, riskFactors: ["http route"] + factors, io: io, meta: ["method": method, "path": path]
      ))
    }
    return out
  }

  private static func parseParamsJava(_ plist: String) -> [SubjectParam] {
    let items = plist.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    return items.compactMap { s in
      let toks = s.split(separator: " ").map(String.init).filter { !$0.isEmpty }
      guard toks.count >= 2 else { return nil }
      let typeHint = toks.dropLast().joined(separator: " ")
      let name = toks.last!
      return SubjectParam(name: name, typeHint: typeHint, optional: false)
    }
  }

  private static func detectHttpMethod(fromAnnotation raw: String) -> String {
    if raw.contains("@GetMapping") { return "GET" }
    if raw.contains("@PostMapping") { return "POST" }
    if raw.contains("@PutMapping") { return "PUT" }
    if raw.contains("@DeleteMapping") { return "DELETE" }
    return "GET"
  }
}

// Small regex helper
private extension String {
  func enumerateMatches(regex: NSRegularExpression, block: (_ groups: [String]) -> Void) {
    let ns = self as NSString
    let range = NSRange(location: 0, length: ns.length)
    regex.enumerateMatches(in: self, options: [], range: range) { m, _, _ in
      guard let m else { return }
      var groups: [String] = []
      for i in 0..<m.numberOfRanges {
        let r = m.range(at: i)
        if r.location != NSNotFound {
          groups.append(ns.substring(with: r))
        } else {
          groups.append("")
        }
      }
      if !groups.isEmpty { block(groups) }
    }
  }
}
