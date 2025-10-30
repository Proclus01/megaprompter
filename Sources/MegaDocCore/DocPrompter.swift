import Foundation

public enum DocPrompter {
  public static func generate(from r: MegaDocReport) -> String {
    var lines: [String] = []
    lines.append("You are a documentation-aware agent. Use the structure and imports to understand this codebase and/or the fetched docs.")
    lines.append("")
    lines.append("Mode: \(r.mode.rawValue)")
    if !r.languages.isEmpty {
      lines.append("Languages: " + r.languages.joined(separator: ", "))
    }
    lines.append("")
    if !r.rootPath.isEmpty {
      lines.append("Directory tree:")
      lines.append(r.directoryTree)
      lines.append("")
      lines.append("Import/dependency graph:")
      lines.append(r.importGraph)
    }
    if let umlAscii = r.umlAscii, !umlAscii.isEmpty {
      lines.append("")
      lines.append("UML (ASCII):")
      lines.append(umlAscii)
    }
    if !r.externalDependencies.isEmpty {
      lines.append("")
      lines.append("External dependencies (approximate):")
      for (dep, cnt) in r.externalDependencies.sorted(by: { $0.key < $1.key }) {
        lines.append("  - \(dep): \(cnt) reference(s)")
      }
    }
    lines.append("")
    lines.append("Purpose summary:")
    lines.append(r.purposeSummary)
    if !r.fetchedDocs.isEmpty {
      lines.append("")
      lines.append("Fetched docs:")
      for d in r.fetchedDocs.prefix(12) {
        lines.append("- \(d.title) [\(d.uri)]")
      }
      if r.fetchedDocs.count > 12 { lines.append("... \(r.fetchedDocs.count - 12) more") }
    }
    lines.append("")
    lines.append("Instructions:")
    lines.append("- Extract architectural overview, key modules, and responsibilities.")
    lines.append("- Use the UML to identify entrypoints, service boundaries, and data sources.")
    lines.append("- Relate external dependencies to specific modules and features.")
    lines.append("- If fetch mode: summarize content relevance to the codebase or to the requested topic.")
    lines.append("- Return a concise outline plus follow-up questions if crucial information is missing.")
    return lines.joined(separator: "\n")
  }
}
