import Foundation

public enum FixPrompter {
  public static func generateFixPrompt(from report: DiagnosticsReport, root: URL?) -> String {
    var lines: [String] = []
    lines.append("You are an expert software engineer. Apply fixes across the project to resolve the following diagnostics.")
    lines.append("")
    lines.append("Context:")
    lines.append("- Languages analyzed: \(report.languages.map { $0.name }.joined(separator: ", "))")
    let totalIssues = report.languages.reduce(0) { $0 + $1.issues.count }
    let errs = report.languages.reduce(0) { $0 + $1.issues.filter { $0.severity == .error }.count }
    let warns = report.languages.reduce(0) { $0 + $1.issues.filter { $0.severity == .warning }.count }
    lines.append("- Total issues: \(totalIssues) (\(errs) errors, \(warns) warnings)")
    lines.append("")
    lines.append("Top issues by language:")
    for lang in report.languages {
      let e = lang.issues.filter { $0.severity == .error }.count
      let w = lang.issues.filter { $0.severity == .warning }.count
      lines.append("- \(lang.name): \(e) errors, \(w) warnings")
      for d in lang.issues.prefix(5) {
        let loc = locationString(for: d, root: root)
        let code = d.code.map { " \($0)" } ?? ""
        lines.append("  • \(loc)\(code): \(d.message)")
      }
      if lang.issues.count > 5 {
        lines.append("  • ... \(lang.issues.count - 5) more")
      }
    }
    lines.append("")
    lines.append("Instructions:")
    lines.append("- Produce minimal, correct fixes for each issue.")
    lines.append("- Maintain existing architecture and conventions.")
    lines.append("- Include tests or adjustments to tests as needed.")
    lines.append("- If a tool was unavailable, suggest installation steps.")
    lines.append("")
    lines.append("Return patches as a set of unified diffs or a patch.sh script that overwrites the relevant files using heredocs with single-quoted EOF delimiters.")
    return lines.joined(separator: "\n")
  }

  private static func locationString(for d: Diagnostic, root: URL?) -> String {
    let path: String
    if let rt = root {
      let base = rt.path.hasSuffix("/") ? rt.path : rt.path + "/"
      if d.file.hasPrefix(base) {
        path = String(d.file.dropFirst(base.count))
      } else {
        path = d.file
      }
    } else {
      path = d.file
    }
    var comps: [String] = [path]
    if let l = d.line { comps.append(String(l)) }
    if let c = d.column { comps.append(String(c)) }
    return comps.joined(separator: ":")
  }
}
