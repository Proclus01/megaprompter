import Foundation

public enum TestPrompter {
  public static func generateTestPrompt(from plan: TestPlanReport, root: URL?, levels: LevelSet) -> String {
    var lines: [String] = []
    lines.append("You are an expert test developer. Create tests according to this plan without rewriting architecture.")
    lines.append("")
    lines.append("Context:")
    lines.append("- Languages: " + plan.languages.map { $0.name }.joined(separator: ", "))
    let totalSubjects = plan.languages.reduce(0) { $0 + $1.subjects.count }
    let totalScenarios = plan.languages.reduce(0) { $0 + $1.subjects.reduce(0) { $0 + $1.scenarios.count } }
    lines.append("- Subjects: \(totalSubjects), Scenarios: \(totalScenarios)")
    lines.append("")
    lines.append("High priority subjects (by risk; DONE items are listed but should not be re-implemented):")
    let allSP = plan.languages.flatMap { $0.subjects }
    let top = allSP.sorted { $0.subject.riskScore > $1.subject.riskScore }.prefix(12)
    for sp in top {
      let s = sp.subject
      let rel = relativize(s.path, root)
      let cov = sp.coverage
      let tag = tagFor(cov.flag)
      let factors = s.riskFactors.isEmpty ? "" : " — " + s.riskFactors.joined(separator: "; ")
      lines.append("  • [\(tag)] [\(s.riskScore)] \(s.language) \(s.kind.rawValue) \(s.name) (\(rel))\(factors)")
    }
    lines.append("")
    lines.append("Instructions:")
    lines.append("- Write \(levels.include.map { $0.rawValue }.joined(separator: ", ")) tests.")
    lines.append("- For subjects marked [DONE], do not re-add tests; only highlight any missing corner cases if found.")
    lines.append("- For [PARTIAL], improve edge coverage and negative paths; for [MISSING], create focused tests.")
    lines.append("- Prefer deterministic, hermetic tests; use stubs/mocks for external I/O.")
    lines.append("- Name and place tests according to language conventions (e.g., __tests__, *_test.go, tests/, src/test/java, Tests/).")
    lines.append("")
    lines.append("Plan overview:")
    for lp in plan.languages {
      lines.append("- \(lp.name) (frameworks: \(lp.frameworks.joined(separator: ", ")))")
      for sp in lp.subjects.prefix(25) {
        let s = sp.subject
        let rel = relativize(s.path, root)
        let tag = tagFor(sp.coverage.flag)
        lines.append("  • [\(tag)] \(s.kind.rawValue) \(s.name) @ \(rel) [risk \(s.riskScore)]")
        if sp.coverage.flag != .green {
          for sc in sp.scenarios {
            lines.append("     - [\(sc.level.rawValue)] \(sc.title)")
          }
        } else {
          // Show DONE location hints
          for ev in sp.coverage.evidence {
            let evRel = relativize(ev.file, root)
            lines.append("     - DONE in \(evRel) (hits \(ev.hits))")
          }
        }
      }
      if lp.subjects.count > 25 {
        lines.append("  • ... \(lp.subjects.count - 25) more")
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func tagFor(_ flag: CoverageFlag) -> String {
    switch flag {
      case .green: return "DONE"
      case .yellow: return "PARTIAL"
      case .red: return "MISSING"
    }
  }

  private static func relativize(_ p: String, _ root: URL?) -> String {
    guard let root else { return p }
    let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
    if p.hasPrefix(base) { return String(p.dropFirst(base.count)) }
    return p
  }
}
