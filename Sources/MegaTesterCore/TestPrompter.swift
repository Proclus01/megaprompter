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
    lines.append("High priority subjects (by risk):")
    let top = plan.languages.flatMap { $0.subjects }.map { $0.subject }.sorted { $0.riskScore > $1.riskScore }.prefix(10)
    for s in top {
      let rel = relativize(s.path, root)
      let factors = s.riskFactors.isEmpty ? "" : " — " + s.riskFactors.joined(separator: "; ")
      lines.append("  • [\(s.riskScore)] \(s.language) \(s.kind.rawValue) \(s.name) (\(rel))\(factors)")
    }
    lines.append("")
    lines.append("Instructions:")
    lines.append("- Write \(levels.include.map { $0.rawValue }.joined(separator: ", ")) tests.")
    lines.append("- Use detected frameworks when applicable; keep tests minimal but thorough.")
    lines.append("- Prefer deterministic, hermetic tests; use stubs/mocks for external I/O.")
    lines.append("- Include edge cases and negative tests for each subject; cover error handling.")
    lines.append("- Name and place tests according to language conventions (e.g., __tests__, *_test.go, tests/, src/test/java, Tests/).")
    lines.append("")
    lines.append("Plan overview:")
    for lp in plan.languages {
      lines.append("- \(lp.name) (frameworks: \(lp.frameworks.joined(separator: ", ")))")
      for sp in lp.subjects.prefix(20) {
        let s = sp.subject
        let rel = relativize(s.path, root)
        lines.append("  • \(s.kind.rawValue) \(s.name) @ \(rel) [risk \(s.riskScore)]")
        for sc in sp.scenarios {
          lines.append("     - [\(sc.level.rawValue)] \(sc.title)")
        }
      }
      if lp.subjects.count > 20 {
        lines.append("  • ... \(lp.subjects.count - 20) more")
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func relativize(_ p: String, _ root: URL?) -> String {
    guard let root else { return p }
    let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
    if p.hasPrefix(base) { return String(p.dropFirst(base.count)) }
    return p
  }
}
