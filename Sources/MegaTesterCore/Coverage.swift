import Foundation

public enum CoverageFlag: String, Codable {
  case green, yellow, red
}

public struct CoverageEvidence: Codable {
  public let file: String
  public let hits: Int

  public init(file: String, hits: Int) {
    self.file = file
    self.hits = hits
  }
}

public struct Coverage: Codable {
  public let flag: CoverageFlag
  public let status: String
  public let score: Int
  public let evidence: [CoverageEvidence]
  public let notes: [String]

  public init(flag: CoverageFlag, status: String, score: Int, evidence: [CoverageEvidence], notes: [String]) {
    self.flag = flag
    self.status = status
    self.score = score
    self.evidence = evidence
    self.notes = notes
  }

  public static func missing() -> Coverage {
    return Coverage(flag: .red, status: "MISSING", score: 0, evidence: [], notes: ["no tests found"])
  }
}
