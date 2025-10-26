import Foundation

public enum Parsers {
  // Swift: /path/file.swift:10:5: error: cannot find 'X' in scope
  public static func parseSwift(_ stdout: String, _ stderr: String) -> [Diagnostic] {
    let tool = "swift build"
    var results: [Diagnostic] = []
    let combined = stdout + "\n" + stderr
    let regex = try! NSRegularExpression(pattern: #"^(.+?):(\d+):(\d+):\s+(error|warning):\s+(.+)$"#, options: [.anchorsMatchLines])
    combined.enumerateMatches(regex: regex) { m in
      let file = m[1]
      let line = Int(m[2])
      let col = Int(m[3])
      let sev = (m[4].lowercased() == "warning") ? Severity.warning : Severity.error
      let msg = m[5]
      results.append(Diagnostic(tool: tool, language: "swift", file: file, line: line, column: col, code: nil, severity: sev, message: msg))
    }
    return results
  }

  // TypeScript tsc: path.ts:10:7 - error TS1234: message
  public static func parseTypeScript(_ stdout: String, _ stderr: String) -> [Diagnostic] {
    let tool = "tsc"
    var results: [Diagnostic] = []
    let combined = stdout + "\n" + stderr
    let regex = try! NSRegularExpression(pattern: #"^(.+?\.(?:ts|tsx)):(\d+):(\d+)\s*-\s*(error|warning)\s*TS(\d+):\s*(.+)$"#, options: [.anchorsMatchLines, .caseInsensitive])
    combined.enumerateMatches(regex: regex) { m in
      let file = m[1]
      let line = Int(m[2])
      let col = Int(m[3])
      let sev = (m[4].lowercased() == "warning") ? Severity.warning : Severity.error
      let code = "TS" + m[5]
      let msg = m[6]
      results.append(Diagnostic(tool: tool, language: "typescript", file: file, line: line, column: col, code: code, severity: sev, message: msg))
    }
    return results
  }

  // Go: path/file.go:12:5: message  OR path/file.go:12: message
  public static func parseGo(_ stdout: String, _ stderr: String) -> [Diagnostic] {
    let tool = "go build"
    var results: [Diagnostic] = []
    let combined = stdout + "\n" + stderr
    let regex = try! NSRegularExpression(pattern: #"^(.+?\.go):(\d+)(?::(\d+))?:\s+(.*)$"#, options: [.anchorsMatchLines])
    combined.enumerateMatches(regex: regex) { m in
      let file = m[1]
      let line = Int(m[2])
      let col = Int(m[3])
      let msg = m[4]
      results.append(Diagnostic(tool: tool, language: "go", file: file, line: line, column: col, code: nil, severity: .error, message: msg))
    }
    return results
  }

  // Rust (cargo check):
  // error[E0599]: method `xyz` not found ...
  //  --> src/main.rs:10:5
  public static func parseRust(_ stdout: String, _ stderr: String) -> [Diagnostic] {
    let tool = "cargo check"
    var results: [Diagnostic] = []
    let combined = stdout + "\n" + stderr
    let lines = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var pendingCode: String?
    var pendingMsg: String?
    for i in 0..<lines.count {
      let line = lines[i]
      if let m = match(line, pattern: #"^error(?:\[(E\d+)\])?:\s*(.+)$"#) {
        pendingCode = (m.count > 1 && !m[1].isEmpty) ? m[1] : nil
        pendingMsg = m.count > 2 ? m[2] : "error"
        // Look ahead for location
        var j = i + 1
        while j < lines.count {
          if let loc = match(lines[j], pattern: #"^\s*-->\s+(.+?):(\d+):(\d+)$"#) {
            let file = loc[1]
            let lineN = Int(loc[2])
            let col = Int(loc[3])
            let d = Diagnostic(tool: tool, language: "rust", file: file, line: lineN, column: col, code: pendingCode, severity: .error, message: pendingMsg ?? "error")
            results.append(d)
            break
          }
          if lines[j].hasPrefix("error") { break }
          j += 1
        }
      }
      // Warnings in cargo
      if let wm = match(line, pattern: #"^warning:\s*(.+)$"#) {
        // Location lines usually follow
        var j = i + 1
        var added = false
        while j < lines.count {
          if let loc = match(lines[j], pattern: #"^\s*-->\s+(.+?):(\d+):(\d+)$"#) {
            let file = loc[1]
            let lineN = Int(loc[2])
            let col = Int(loc[3])
            let d = Diagnostic(tool: tool, language: "rust", file: file, line: lineN, column: col, code: nil, severity: .warning, message: wm[1])
            results.append(d)
            added = true
            break
          }
          if lines[j].hasPrefix("warning") || lines[j].hasPrefix("error") { break }
          j += 1
        }
        if !added {
          results.append(Diagnostic(tool: tool, language: "rust", file: "", line: nil, column: nil, code: nil, severity: .warning, message: wm[1]))
        }
      }
    }
    return results
  }

  // Python py_compile style:
  //   File "path.py", line 12
  //     bad code
  //     ^
  // SyntaxError: msg
  public static func parsePython(_ stdout: String, _ stderr: String) -> [Diagnostic] {
    let tool = "python -m py_compile"
    var results: [Diagnostic] = []
    let combined = stdout + "\n" + stderr
    let lines = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    for i in 0..<lines.count {
      let line = lines[i]
      if let m = match(line, pattern: #"^\s*File\s+"(.+?)",\s+line\s+(\d+).*$"#) {
        let file = m[1]
        let lineN = Int(m[2])
        var msg = "SyntaxError"
        var code: String? = nil
        var j = i + 1
        while j < lines.count {
          if let sm = match(lines[j], pattern: #"^(SyntaxError|IndentationError|NameError|TypeError):\s*(.+)$"#) {
            code = sm[1]
            msg = sm[2]
            break
          }
          j += 1
        }
        results.append(Diagnostic(tool: tool, language: "python", file: file, line: lineN, column: nil, code: code, severity: .error, message: msg))
      }
    }
    return results
  }

  // Java (javac/maven):
  // path/File.java:10: error: message
  public static func parseJava(_ stdout: String, _ stderr: String) -> [Diagnostic] {
    let tool = "javac/maven"
    var results: [Diagnostic] = []
    let combined = stdout + "\n" + stderr
    let regex = try! NSRegularExpression(pattern: #"^(.+?\.java):(\d+):\s+(error|warning):\s+(.+)$"#, options: [.anchorsMatchLines])
    combined.enumerateMatches(regex: regex) { m in
      let file = m[1]
      let line = Int(m[2])
      let sev = (m[3].lowercased() == "warning") ? Severity.warning : Severity.error
      let msg = m[4]
      results.append(Diagnostic(tool: tool, language: "java", file: file, line: line, column: nil, code: nil, severity: sev, message: msg))
    }
    return results
  }

  // Unix formatter: path:line:column: message
  // Useful for eslint -f unix .
  public static func parseUnixStyle(_ stdout: String, _ stderr: String, language: String, tool: String) -> [Diagnostic] {
    var results: [Diagnostic] = []
    let combined = stdout + "\n" + stderr
    let regex = try! NSRegularExpression(pattern: #"^(.+?):(\d+):(\d+):\s*(.+)$"#, options: [.anchorsMatchLines])
    combined.enumerateMatches(regex: regex) { m in
      let file = m[1]
      let line = Int(m[2])
      let col = Int(m[3])
      let msg = m[4]
      results.append(Diagnostic(tool: tool, language: language, file: file, line: line, column: col, code: nil, severity: .warning, message: msg))
    }
    return results
  }
}

// MARK: - Helpers

private func match(_ s: String, pattern: String) -> [String]? {
  guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
  guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count)) else { return nil }
  var groups: [String] = []
  for i in 0..<m.numberOfRanges {
    let r = m.range(at: i)
    if r.location != NSNotFound, let rr = Range(r, in: s) {
      groups.append(String(s[rr]))
    } else {
      groups.append("")
    }
  }
  return groups
}

private extension String {
  func enumerateMatches(regex: NSRegularExpression, block: (_ m: [String]) -> Void) {
    let ns = self as NSString
    let all = NSRange(location: 0, length: ns.length)
    regex.enumerateMatches(in: self, options: [], range: all) { res, _, _ in
      if let res = res {
        var groups: [String] = []
        for i in 0..<res.numberOfRanges {
          let r = res.range(at: i)
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
}

private extension Int {
  init?(_ s: String) {
    if let v = Int(s, radix: 10) {
      self = v
    } else {
      return nil
    }
  }
}
