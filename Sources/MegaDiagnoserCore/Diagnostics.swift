import Foundation

public enum Severity: String, Codable {
  case error
  case warning
  case info
}

public struct Diagnostic: Codable {
  public let tool: String
  public let language: String
  public let file: String
  public let line: Int?
  public let column: Int?
  public let code: String?
  public let severity: Severity
  public let message: String

  public init(tool: String, language: String, file: String, line: Int?, column: Int?, code: String?, severity: Severity, message: String) {
    self.tool = tool
    self.language = language
    self.file = file
    self.line = line
    self.column = column
    self.code = code
    self.severity = severity
    self.message = message
  }
}

public struct LanguageDiagnostics: Codable {
  public let name: String
  public let tool: String
  public var issues: [Diagnostic]
}

public struct DiagnosticsReport: Codable {
  public var languages: [LanguageDiagnostics]
  public var generatedAt: String

  public init(languages: [LanguageDiagnostics], generatedAt: String) {
    self.languages = languages
    self.generatedAt = generatedAt
  }
}

public extension DiagnosticsReport {
  func toXML() -> String {
    var parts: [String] = []
    parts.append("<diagnostics>")
    for ld in languages {
      parts.append("  <language name=\"\(escapeAttr(ld.name))\" tool=\"\(escapeAttr(ld.tool))\">")
      for d in ld.issues {
        let attrs = [
          "file": escapeAttr(d.file),
          "line": d.line.map { String($0) } ?? "",
          "column": d.column.map { String($0) } ?? "",
          "severity": d.severity.rawValue,
          "code": d.code ?? ""
        ]
        parts.append("    <issue file=\"\(attrs["file"]!)\" line=\"\(attrs["line"]!)\" column=\"\(attrs["column"]!)\" severity=\"\(attrs["severity"]!)\" code=\"\(escapeAttr(attrs["code"]!))\">")
        parts.append("      <![CDATA[\(d.message)]]>")
        parts.append("    </issue>")
      }
      let errCount = ld.issues.filter { $0.severity == .error }.count
      let warnCount = ld.issues.filter { $0.severity == .warning }.count
      parts.append("    <summary count=\"\(ld.issues.count)\" errors=\"\(errCount)\" warnings=\"\(warnCount)\" />")
      parts.append("  </language>")
    }
    let totalIssues = languages.reduce(0) { $0 + $1.issues.count }
    parts.append("  <summary total_languages=\"\(languages.count)\" total_issues=\"\(totalIssues)\" />")
    let prompt = FixPrompter.generateFixPrompt(from: self, root: nil)
    parts.append("  <fix_prompt>")
    parts.append("    <![CDATA[\(prompt)]]>")
    parts.append("  </fix_prompt>")
    parts.append("</diagnostics>")
    return parts.joined(separator: "\n")
  }
}

private func escapeAttr(_ s: String) -> String {
  s.replacingOccurrences(of: "\"", with: "&quot;")
}
