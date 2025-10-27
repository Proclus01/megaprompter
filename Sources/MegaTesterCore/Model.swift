import Foundation

public enum TestLevel: String, Codable, CaseIterable {
  case smoke, unit, integration, e2e
}

public struct LevelSet: Codable {
  public let include: Set<TestLevel>
  public static func parse(from csv: String?) -> LevelSet {
    guard let csv, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return LevelSet(include: Set(TestLevel.allCases))
    }
    let items = csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    let mapped = items.compactMap { TestLevel(rawValue: $0) }
    return LevelSet(include: Set(mapped))
  }
  public func contains(_ l: TestLevel) -> Bool { include.contains(l) }
}

public enum SubjectKind: String, Codable {
  case function, method, `class`, endpoint, entrypoint, module
}

public struct SubjectParam: Codable {
  public let name: String
  public let typeHint: String?
  public let optional: Bool

  public init(name: String, typeHint: String?, optional: Bool) {
    self.name = name
    self.typeHint = typeHint
    self.optional = optional
  }
}

public struct IOCapabilities: Codable {
  public let readsFS: Bool
  public let writesFS: Bool
  public let network: Bool
  public let db: Bool
  public let env: Bool
  public let concurrency: Bool

  public init(readsFS: Bool, writesFS: Bool, network: Bool, db: Bool, env: Bool, concurrency: Bool) {
    self.readsFS = readsFS
    self.writesFS = writesFS
    self.network = network
    self.db = db
    self.env = env
    self.concurrency = concurrency
  }
}

public struct TestSubject: Codable {
  public let id: String
  public let kind: SubjectKind
  public let language: String
  public let name: String
  public let path: String
  public let signature: String?
  public let exported: Bool
  public let params: [SubjectParam]
  public let riskScore: Int
  public let riskFactors: [String]
  public let io: IOCapabilities
  public let meta: [String: String]

  public init(id: String, kind: SubjectKind, language: String, name: String, path: String, signature: String?, exported: Bool, params: [SubjectParam], riskScore: Int, riskFactors: [String], io: IOCapabilities, meta: [String: String]) {
    self.id = id
    self.kind = kind
    self.language = language
    self.name = name
    self.path = path
    self.signature = signature
    self.exported = exported
    self.params = params
    self.riskScore = riskScore
    self.riskFactors = riskFactors
    self.io = io
    self.meta = meta
  }
}

public struct ScenarioSuggestion: Codable {
  public let level: TestLevel
  public let title: String
  public let rationale: String
  public let steps: [String]
  public let inputs: [String]
  public let assertions: [String]

  public init(level: TestLevel, title: String, rationale: String, steps: [String], inputs: [String], assertions: [String]) {
    self.level = level
    self.title = title
    self.rationale = rationale
    self.steps = steps
    self.inputs = inputs
    self.assertions = assertions
  }
}

public struct SubjectPlan: Codable {
  public let subject: TestSubject
  public let scenarios: [ScenarioSuggestion]

  public init(subject: TestSubject, scenarios: [ScenarioSuggestion]) {
    self.subject = subject
    self.scenarios = scenarios
  }
}

public struct LanguagePlan: Codable {
  public let name: String
  public let frameworks: [String]
  public let subjects: [SubjectPlan]
  public let testFilesFound: Int

  public init(name: String, frameworks: [String], subjects: [SubjectPlan], testFilesFound: Int) {
    self.name = name
    self.frameworks = frameworks
    self.subjects = subjects
    self.testFilesFound = testFilesFound
  }
}

public struct TestPlanReport: Codable {
  public let languages: [LanguagePlan]
  public let generatedAt: String
  public let summary: PlanSummary

  public init(languages: [LanguagePlan], generatedAt: String, summary: PlanSummary) {
    self.languages = languages
    self.generatedAt = generatedAt
    self.summary = summary
  }
}

public struct PlanSummary: Codable {
  public let totalLanguages: Int
  public let totalSubjects: Int
  public let totalScenarios: Int

  public init(totalLanguages: Int, totalSubjects: Int, totalScenarios: Int) {
    self.totalLanguages = totalLanguages
    self.totalSubjects = totalSubjects
    self.totalScenarios = totalScenarios
  }
}

public extension TestPlanReport {
  func toXML() -> String {
    var parts: [String] = []
    parts.append("<test_plan generatedAt=\"\(escapeAttr(generatedAt))\">")
    for lp in languages {
      let frameworksJoined = lp.frameworks.joined(separator: ", ")
      parts.append("  <language name=\"\(escapeAttr(lp.name))\" frameworks=\"\(escapeAttr(frameworksJoined))\" testFilesFound=\"\(lp.testFilesFound)\">")
      for sp in lp.subjects {
        let s = sp.subject
        parts.append("    <subject id=\"\(escapeAttr(s.id))\" kind=\"\(s.kind.rawValue)\" language=\"\(escapeAttr(s.language))\" name=\"\(escapeAttr(s.name))\" path=\"\(escapeAttr(s.path))\" exported=\"\(s.exported)\">")
        if let sig = s.signature, !sig.isEmpty {
          parts.append("      <signature><![CDATA[\(sig)]]></signature>")
        }
        if !s.params.isEmpty {
          parts.append("      <params>")
          for p in s.params {
            parts.append("        <param name=\"\(escapeAttr(p.name))\" optional=\"\(p.optional)\" typeHint=\"\(escapeAttr(p.typeHint ?? ""))\"/>")
          }
          parts.append("      </params>")
        }
        if !s.riskFactors.isEmpty {
          parts.append("      <risk score=\"\(s.riskScore)\">")
          for rf in s.riskFactors {
            parts.append("        <factor><![CDATA[\(rf)]]></factor>")
          }
          parts.append("      </risk>")
        } else {
          parts.append("      <risk score=\"\(s.riskScore)\"/>")
        }
        if !s.meta.isEmpty {
          parts.append("      <meta>")
          for (k, v) in s.meta {
            parts.append("        <item key=\"\(escapeAttr(k))\" value=\"\(escapeAttr(v))\"/>")
          }
          parts.append("      </meta>")
        }
        for sc in sp.scenarios {
          parts.append("      <scenario level=\"\(sc.level.rawValue)\">")
          parts.append("        <title><![CDATA[\(sc.title)]]></title>")
          parts.append("        <rationale><![CDATA[\(sc.rationale)]]></rationale>")
          if !sc.inputs.isEmpty {
            parts.append("        <inputs>")
            for i in sc.inputs { parts.append("          <case><![CDATA[\(i)]]></case>") }
            parts.append("        </inputs>")
          }
          if !sc.steps.isEmpty {
            parts.append("        <steps>")
            for st in sc.steps { parts.append("          <step><![CDATA[\(st)]]></step>") }
            parts.append("        </steps>")
          }
          if !sc.assertions.isEmpty {
            parts.append("        <assertions>")
            for a in sc.assertions { parts.append("          <assert><![CDATA[\(a)]]></assert>") }
            parts.append("        </assertions>")
          }
          parts.append("      </scenario>")
        }
        parts.append("    </subject>")
      }
      parts.append("  </language>")
    }
    parts.append("  <summary languages=\"\(summary.totalLanguages)\" subjects=\"\(summary.totalSubjects)\" scenarios=\"\(summary.totalScenarios)\"/>")
    parts.append("</test_plan>")
    return parts.joined(separator: "\n")
  }
}

private func escapeAttr(_ s: String) -> String {
  return s
    .replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "\"", with: "&quot;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
}
