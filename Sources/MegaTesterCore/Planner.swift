import Foundation
import MegaprompterCore

public final class TestPlanner {
  private let root: URL
  private let ignoreNames: Set<String>
  private let ignoreGlobs: [String]
  private let limitSubjects: Int
  private let maxAnalyzeBytes: Int

  public init(root: URL, ignoreNames: [String], ignoreGlobs: [String], limitSubjects: Int, maxAnalyzeBytes: Int = 200_000) {
    self.root = root
    self.ignoreNames = Set(ignoreNames)
    self.ignoreGlobs = ignoreGlobs
    self.limitSubjects = max(50, limitSubjects)
    self.maxAnalyzeBytes = max(20_000, maxAnalyzeBytes)
  }

  public func buildPlan(profile: ProjectProfile, files: [URL], levels: LevelSet) throws -> TestPlanReport {
    let frameworks = FrameworkDetector.detectFrameworks(root: root)

    // Separate test files for metrics but exclude them from subject analysis
    let testFiles = files.filter { TestHeuristics.isTestFile($0) }
    let filesForSubjects = files.filter { !TestHeuristics.isTestFile($0) }

    // Group files by detected language for fair-share iteration
    var queues: [String: [URL]] = [:]
    for f in filesForSubjects {
      guard let lang = Heuristics.language(for: f) else { continue }
      queues[lang, default: []].append(f)
    }

    // Analyze files → subjects (round-robin across languages)
    var perLangSubjects: [String: [TestSubject]] = [:]
    var totalSubjects = 0
    let langKeys = queues.keys.sorted()
    var progressed = true
    while totalSubjects < limitSubjects && progressed {
      progressed = false
      for lang in langKeys {
        guard var q = queues[lang], !q.isEmpty else { continue }
        let f = q.removeFirst()
        queues[lang] = q
        progressed = true

        if perLangSubjects[lang]?.count ?? 0 >= limitSubjects { continue }

        guard let data = try? Data(contentsOf: f), var content = String(data: data, encoding: .utf8) else { continue }
        if content.utf8.count > maxAnalyzeBytes {
          content = String(content.prefix(maxAnalyzeBytes))
        }

        let subjects = Heuristics.analyzeFile(url: f, content: content, lang: lang)
        if !subjects.isEmpty {
          let remaining = max(0, limitSubjects - totalSubjects)
          let slice = subjects.prefix(remaining)
          perLangSubjects[lang, default: []].append(contentsOf: slice)
          totalSubjects += slice.count
          if totalSubjects >= limitSubjects { break }
        }
      }
    }

    // Count test files per language (crude: match by extension → language)
    var perLangTestFiles: [String: Int] = [:]
    for lang in perLangSubjects.keys {
      let count = testFiles.filter { tf in
        if let l = Heuristics.language(for: tf), l == lang { return true }
        return false
      }.count
      perLangTestFiles[lang] = count
    }

    // Compute coverage for all subjects vs. test files
    let allSubjects = perLangSubjects.flatMap { $0.value }
    let coverageMap = TestCoverageAssessor.assess(subjects: allSubjects, testFiles: testFiles, maxAnalyzeBytes: maxAnalyzeBytes)

    // Build subject plans with scenarios (suppress for green coverage)
    var langPlans: [LanguagePlan] = []
    var totalScenarios = 0

    for lang in perLangSubjects.keys.sorted() {
      let subs = perLangSubjects[lang] ?? []
      let fw = frameworks[lang] ?? []
      var subjectPlans: [SubjectPlan] = []
      subjectPlans.reserveCapacity(subs.count)

      for subj in subs {
        let cov = coverageMap[subj.id] ?? Coverage.missing()
        let scenariosRaw = ScenarioBuilder.scenarios(for: subj, frameworks: fw, levels: levels)
        let scenarios = (cov.flag == .green) ? [] : scenariosRaw
        totalScenarios += scenarios.count
        subjectPlans.append(SubjectPlan(subject: subj, scenarios: scenarios, coverage: cov))
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
