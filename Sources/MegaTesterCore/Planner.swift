import Foundation
import MegaprompterCore

public final class TestPlanner {
  private let root: URL
  private let ignoreNames: Set<String>
  private let ignoreGlobs: [String]
  private let limitSubjects: Int

  public init(root: URL, ignoreNames: [String], ignoreGlobs: [String], limitSubjects: Int) {
    self.root = root
    self.ignoreNames = Set(ignoreNames)
    self.ignoreGlobs = ignoreGlobs
    self.limitSubjects = max(50, limitSubjects)
  }

  public func buildPlan(profile: ProjectProfile, files: [URL], levels: LevelSet) throws -> TestPlanReport {
    let frameworks = FrameworkDetector.detectFrameworks(root: root)

    // Pre-compute test files discovered
    let testFiles = files.filter { TestHeuristics.isTestFile($0) }
    var perLangTestFiles: [String: Int] = [:]

    // Analyze files → subjects
    var perLangSubjects: [String: [TestSubject]] = [:]
    var totalSubjects = 0

    for f in files {
      if totalSubjects >= limitSubjects { break }
      guard let lang = Heuristics.language(for: f) else { continue }
      if perLangSubjects[lang]?.count ?? 0 >= limitSubjects { continue }

      guard let data = try? Data(contentsOf: f), let content = String(data: data, encoding: .utf8) else { continue }
      let subjects = Heuristics.analyzeFile(url: f, content: content, lang: lang)
      if !subjects.isEmpty {
        let slice = subjects.prefix(max(0, limitSubjects - totalSubjects))
        perLangSubjects[lang, default: []].append(contentsOf: slice)
        totalSubjects += slice.count
      }
    }

    // Count test files per language (crude: match by extension → language)
    for (lang, _) in perLangSubjects {
      let count = testFiles.filter { tf in
        if let l = Heuristics.language(for: tf), l == lang { return true }
        return false
      }.count
      perLangTestFiles[lang] = count
    }

    // Build subject plans with scenarios
    var langPlans: [LanguagePlan] = []
    var totalScenarios = 0

    for lang in perLangSubjects.keys.sorted() {
      let subs = perLangSubjects[lang] ?? []
      let fw = frameworks[lang] ?? []
      let subjectPlans: [SubjectPlan] = subs.map { subj in
        let scenarios = ScenarioBuilder.scenarios(for: subj, frameworks: fw, levels: levels)
        totalScenarios += scenarios.count
        return SubjectPlan(subject: subj, scenarios: scenarios)
      }
      langPlans.append(LanguagePlan(name: lang, frameworks: fw, subjects: subjectPlans, testFilesFound: perLangTestFiles[lang] ?? 0))
    }

    let report = TestPlanReport(
      languages: langPlans,
      generatedAt: isoNow(),
      summary: PlanSummary(totalLanguages: langPlans.count, totalSubjects: totalSubjects, totalScenarios: totalScenarios)
    )
    return report
  }
}

private func isoNow() -> String {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f.string(from: Date())
}
