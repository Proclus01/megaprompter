import Foundation
import MegaprompterCore

public enum PurposeGuesser {
  public static func guess(root: URL, files: [URL], languages: [String], maxAnalyzeBytes: Int) -> String {
    var lines: [String] = []
    if let readme = findREADME(root: root) {
      if let s = try? String(contentsOf: readme) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          lines.append("README summary (first lines):")
          let head = trimmed.split(separator: "\n").prefix(8).joined(separator: "\n")
          lines.append(head)
        }
      }
    }
    if !languages.isEmpty {
      lines.append("")
      lines.append("Detected languages: " + languages.joined(separator: ", "))
    }

    let sample = files.prefix(40)
    var keywords: [String: Int] = [:]
    let hints = [
      "web":"express|fastapi|flask|spring|ktor|actix|router\\.|http\\.|net/http|urlsession|axios|fetch|GetMapping",
      "db":"sqlalchemy|psycopg2|gorm|database/sql|entitymanager|jpa|mongoose|redis",
      "cli":"argparse|click|cobra|commander|swift-argument-parser",
      "ml":"torch|tensorflow|keras|sklearn",
      "queue":"kafka|rabbitmq|pubsub|sqs",
      "cloud":"aws|gcp|azure|s3|bigquery|pubsub|blob|cosmos",
      "test":"pytest|jest|vitest|xctest|go test|cargo test"
    ]
    for f in sample {
      if let data = try? Data(contentsOf: f), var s = String(data: data, encoding: .utf8) {
        if s.utf8.count > maxAnalyzeBytes { s = String(s.prefix(maxAnalyzeBytes)) }
        let lower = s.lowercased()
        for (k, pat) in hints {
          if lower.range(of: pat, options: .regularExpression) != nil {
            keywords[k, default: 0] += 1
          }
        }
      }
    }
    if !keywords.isEmpty {
      lines.append("")
      lines.append("Capability hints: " + keywords.sorted(by: { $0.value > $1.value }).map { "\($0.key)" }.joined(separator: ", "))
    }

    if lines.isEmpty {
      return "No README and limited hints; likely a library or service in " + (languages.first ?? "unknown language")
    }
    return lines.joined(separator: "\n")
  }

  private static func findREADME(root: URL) -> URL? {
    let names = ["README.md","Readme.md","readme.md","README","Readme","readme"]
    for n in names {
      let u = root.appendingPathComponent(n)
      if FileManager.default.fileExists(atPath: u.path) { return u }
    }
    return nil
  }
}
