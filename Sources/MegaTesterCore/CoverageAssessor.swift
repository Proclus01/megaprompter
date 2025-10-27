import Foundation
import MegaprompterCore

public enum TestCoverageAssessor {

  public static func assess(subjects: [TestSubject], testFiles: [URL], maxAnalyzeBytes: Int) -> [String: Coverage] {
    guard !subjects.isEmpty, !testFiles.isEmpty else { return [:] }

    // Preload test file contents (trimmed) once
    var testContents: [(url: URL, text: String, lower: String)] = []
    testContents.reserveCapacity(testFiles.count)
    for tf in testFiles {
      guard let data = try? Data(contentsOf: tf) else { continue }
      var text = String(decoding: data, as: UTF8.self)
      if text.utf8.count > maxAnalyzeBytes {
        text = String(text.prefix(maxAnalyzeBytes))
      }
      testContents.append((tf, text, text.lowercased()))
    }

    var results: [String: Coverage] = [:]

    for subj in subjects {
      var totalHits = 0
      var evidence: [CoverageEvidence] = []
      var foundKeywords = Set<String>()

      // Compile a simple word-boundary regex for the subject name
      let name = subj.name
      let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
      let re = try? NSRegularExpression(pattern: pattern, options: [])

      for (url, text, lower) in testContents {
        let hits = re.map { countMatches($0, in: text) } ?? 0
        if hits > 0 {
          totalHits += hits
          evidence.append(CoverageEvidence(file: url.path, hits: hits))
          // Keyword hints found in same file
          for kw in edgeKeywords where lower.contains(kw) {
            foundKeywords.insert(kw)
          }
        }
      }

      if totalHits == 0 {
        results[subj.id] = Coverage.missing()
        continue
      }

      // Scoring
      var score = 0
      if totalHits >= 10 { score += 3 }
      else if totalHits >= 5 { score += 2 }
      else { score += 1 }

      if foundKeywords.count >= 2 { score += 1 }

      // Evidence path hints for integration/e2e
      let pathHints = evidence.map { $0.file.lowercased() }
      if pathHints.contains(where: { $0.contains("integration") || $0.contains("e2e") || $0.contains("end2end") }) {
        score += 1
      }

      let flag: CoverageFlag = (score >= 4) ? .green : ((score >= 2) ? .yellow : .red)
      let status = (flag == .green) ? "DONE" : ((flag == .yellow) ? "PARTIAL" : "MISSING")
      let notes: [String] = [
        "hits=\(totalHits)",
        "edge_keywords=\(Array(foundKeywords).sorted().joined(separator: ","))"
      ]

      // Keep top 5 evidence files by hits
      let topEv = evidence.sorted { $0.hits > $1.hits }.prefix(5)
      results[subj.id] = Coverage(flag: flag, status: status, score: score, evidence: Array(topEv), notes: notes)
    }

    return results
  }

  private static let edgeKeywords: [String] = [
    "empty","nil","null","undefined","invalid","error","throws","throw","exception",
    "large","huge","max","min","boundary","timeout","retry","concurrent","race",
    "unauthorized","forbidden","denied","overflow","underflow"
  ]

  private static func countMatches(_ re: NSRegularExpression, in text: String) -> Int {
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    return re.numberOfMatches(in: text, options: [], range: range)
  }
}
