import Foundation
import MegaprompterCore

public final class DocFetcher {
  private let allowDomains: Set<String>
  private let maxDepth: Int

  public init(allowDomains: Set<String>, maxDepth: Int) {
    self.allowDomains = allowDomains
    self.maxDepth = maxDepth
  }

  public func fetch(uri: String) -> [FetchedDoc] {
    if uri.hasPrefix("file://") || uri.hasPrefix("/") || uri.hasPrefix("./") || uri.hasPrefix("../") {
      return fetchLocal(uri: uri)
    }
    if uri.lowercased().hasPrefix("http://") || uri.lowercased().hasPrefix("https://") {
      return fetchHTTP(uri: uri)
    }
    return fetchLocal(uri: uri)
  }

  public static func summarize(docs: [FetchedDoc]) -> String {
    if docs.isEmpty { return "No docs fetched." }
    var lines: [String] = []
    lines.append("Fetched \(docs.count) doc(s):")
    for d in docs.prefix(12) {
      lines.append("- \(d.title) [\(d.uri)]")
    }
    if docs.count > 12 {
      lines.append("... \(docs.count - 12) more")
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Local

  private func fetchLocal(uri: String) -> [FetchedDoc] {
    let url: URL
    if uri.hasPrefix("file://") { url = URL(string: uri) ?? URL(fileURLWithPath: uri) }
    else { url = URL(fileURLWithPath: uri) }

    var out: [FetchedDoc] = []
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
      if isDir.boolValue {
        if let enumr = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
          for case let f as URL in enumr {
            if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false {
              if isDocFile(f) {
                if let s = try? String(contentsOf: f) {
                  out.append(FetchedDoc(uri: f.path, title: f.lastPathComponent, contentPreview: preview(s)))
                }
              }
            }
          }
        }
      } else {
        if let s = try? String(contentsOf: url) {
          out.append(FetchedDoc(uri: url.path, title: url.lastPathComponent, contentPreview: preview(s)))
        }
      }
    } else {
      Console.warn("Local path not found: \(uri)")
    }
    return out
  }

  // MARK: - HTTP

  private func fetchHTTP(uri: String) -> [FetchedDoc] {
    guard let url = URL(string: uri) else { return [] }
    guard allowDomains.isEmpty || (url.host.map { allowDomains.contains($0) } ?? false) else {
      Console.warn("Domain \(url.host ?? "(nil)") not allowed; skipping \(uri)")
      return []
    }
    var visited = Set<URL>()
    var queue: [(url: URL, depth: Int)] = [(url, 1)]
    var out: [FetchedDoc] = []

    while !queue.isEmpty {
      let (u, depth) = queue.removeFirst()
      if visited.contains(u) { continue }
      visited.insert(u)
      if let (html, title) = httpGetText(u) {
        out.append(FetchedDoc(uri: u.absoluteString, title: title, contentPreview: preview(html)))
        if depth < maxDepth, let host = u.host {
          let links = extractLinks(html: html, base: u)
          for v in links {
            if v.host == host, (allowDomains.isEmpty || allowDomains.contains(host)) {
              queue.append((v, depth + 1))
            }
          }
        }
      }
    }
    return out
  }

  private func httpGetText(_ url: URL) -> (String, String)? {
    var req = URLRequest(url: url)
    req.setValue("text/html, text/plain; q=0.8", forHTTPHeaderField: "Accept")

    // Use a concurrency-safe result box to avoid mutating a captured var in a @Sendable closure.
    let sema = DispatchSemaphore(value: 0)
    let box = ConcurrentResultBox()

    let task = URLSession.shared.dataTask(with: req) { [url] data, _, _ in
      defer { sema.signal() }
      guard let data, let s = String(data: data, encoding: .utf8) else { return }
      let title = DocFetcher.extractTitleStatic(html: s) ?? url.lastPathComponent
      box.set((s, title))
    }
    task.resume()
    _ = sema.wait(timeout: .now() + 30)
    return box.get()
  }

  // Make title extraction static so the URLSession closure does not capture `self`.
  private static func extractTitleStatic(html: String) -> String? {
    if let r = try? NSRegularExpression(
      pattern: #"<title[^>]*>(.*?)</title>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators]
    ) {
      let ns = html as NSString
      let m = r.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length))
      if let m, m.numberOfRanges >= 2 {
        let s = ns.substring(with: m.range(at: 1))
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return nil
  }

  private func extractLinks(html: String, base: URL) -> [URL] {
    guard let r = try? NSRegularExpression(
      pattern: #"<a\s+[^>]*href=['"]([^'"]+)['"]"#,
      options: [.caseInsensitive]
    ) else { return [] }
    let ns = html as NSString
    let rng = NSRange(location: 0, length: ns.length)
    var out: [URL] = []
    r.enumerateMatches(in: html, options: [], range: rng) { m, _, _ in
      if let m, m.numberOfRanges >= 2 {
        let href = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        if let u = URL(string: href, relativeTo: base)?.absoluteURL {
          out.append(u)
        }
      }
    }
    return out
  }

  private func isDocFile(_ url: URL) -> Bool {
    let n = url.lastPathComponent.lowercased()
    let exts = [".md",".rst",".adoc",".txt",".html",".htm",".mdx"]
    return exts.contains(where: { n.hasSuffix($0) }) || n == "readme" || n == "readme.md"
  }

  private func preview(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }
    return trimmed.split(separator: "\n").prefix(40).joined(separator: "\n")
  }
}

// A simple, thread-safe holder for an optional (String, String) result.
// Marked @unchecked Sendable to allow capture in @Sendable closures safely under our lock discipline.
private final class ConcurrentResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: (String, String)?

  func set(_ v: (String, String)?) {
    lock.lock()
    value = v
    lock.unlock()
  }

  func get() -> (String, String)? {
    lock.lock()
    let v = value
    lock.unlock()
    return v
  }
}
