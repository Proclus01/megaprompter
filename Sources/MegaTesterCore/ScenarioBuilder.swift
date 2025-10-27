import Foundation

enum ScenarioBuilder {
  static func scenarios(for s: TestSubject, frameworks: [String], levels: LevelSet) -> [ScenarioSuggestion] {
    var out: [ScenarioSuggestion] = []

    if levels.contains(.unit) {
      out.append(unitScenario(s))
    }
    if levels.contains(.integration) && (s.io.network || s.io.db || s.io.readsFS || s.io.writesFS || s.io.env) {
      out.append(integrationScenario(s))
    }
    if levels.contains(.smoke) && isEntryPointish(s) {
      out.append(smokeScenario(s))
    }
    if levels.contains(.e2e) && s.kind == .endpoint {
      out.append(e2eScenarioForEndpoint(s))
    }
    return out
  }

  private static func unitScenario(_ s: TestSubject) -> ScenarioSuggestion {
    let fuzz = FuzzInputs.forParams(s.params)
    return ScenarioSuggestion(
      level: .unit,
      title: "Unit tests for \(s.name)",
      rationale: "Validate core logic, boundary conditions, and error paths. Risk score \(s.riskScore).",
      steps: [
        "Isolate \(s.kind == .class ? "type" : "function") \(s.name) by mocking external effects.",
        "Cover happy-path plus edge cases below."
      ],
      inputs: fuzz,
      assertions: [
        "Correct outputs for valid inputs",
        "Throws/returns errors for invalid inputs",
        "Idempotency and no state leakage",
        "Handles large input sizes within time limits"
      ]
    )
  }

  private static func integrationScenario(_ s: TestSubject) -> ScenarioSuggestion {
    var steps: [String] = []
    if s.io.db { steps.append("Use a disposable DB (e.g., testcontainers) for read/write/transaction tests") }
    if s.io.network { steps.append("Mock/stub external HTTP endpoints and cover retries/timeouts") }
    if s.io.readsFS || s.io.writesFS { steps.append("Use a temp directory for FS reads/writes; test permissions and missing paths") }
    if s.io.env { steps.append("Vary environment variables; test unset/malformed values") }
    if s.io.concurrency { steps.append("Run concurrent invocations to detect races and locking issues") }
    return ScenarioSuggestion(
      level: .integration,
      title: "Integration tests for \(s.name)",
      rationale: "Covers real I/O and cross-module boundaries indicated by IO capabilities.",
      steps: steps,
      inputs: [],
      assertions: [
        "Correct behavior under network/DB errors",
        "Resource cleanup (connections, files)",
        "Retry/backoff adherence",
        "No deadlocks or race conditions"
      ]
    )
  }

  private static func smokeScenario(_ s: TestSubject) -> ScenarioSuggestion {
    return ScenarioSuggestion(
      level: .smoke,
      title: "Smoke test for \(s.name)",
      rationale: "Ensure the primary entrypoint boots and responds.",
      steps: [
        "Build/start the service or executable",
        "Probe /health or a trivial endpoint",
        "Run CLI --help / basic command returns 0"
      ],
      inputs: [],
      assertions: [
        "Process exits 0 or keeps running",
        "Boot completes within a short timeout",
        "Basic route returns HTTP 200"
      ]
    )
  }

  private static func e2eScenarioForEndpoint(_ s: TestSubject) -> ScenarioSuggestion {
    let path = s.meta["path"] ?? "/"
    let method = s.meta["method"] ?? "GET"
    let payloads = FuzzInputs.apiPayloads(forPath: path, method: method)
    return ScenarioSuggestion(
      level: .e2e,
      title: "E2E for \(method) \(path)",
      rationale: "Validate the full request/response path and data persistence effects.",
      steps: [
        "Start the service with a disposable backing store",
        "Issue requests with the payloads below",
        "Follow-on GET/queries to verify persisted state"
      ],
      inputs: payloads,
      assertions: [
        "Status codes and response schemas",
        "Auth/permissions if applicable",
        "Idempotency and invariants across requests"
      ]
    )
  }

  private static func isEntryPointish(_ s: TestSubject) -> Bool {
    if s.kind == .entrypoint { return true }
    let n = s.name.lowercased()
    return n == "main" || n.contains("start") || n.contains("run") || n.contains("boot")
  }
}

enum FuzzInputs {
  static func forParams(_ ps: [SubjectParam]) -> [String] {
    var cases: [String] = []
    if ps.isEmpty {
      return [
        "No inputs: call with defaults; expect not to crash and return sane output"
      ]
    }
    for p in ps.prefix(8) {
      let t = (p.typeHint ?? "").lowercased()
      let n = p.name.lowercased()
      if t.contains("int") || t.contains("float") || t.contains("double") || t.contains("number") || n.contains("count") || n.contains("limit") || n.contains("size") || n.contains("retries") || n.contains("attempts") {
        cases += [
          "\(p.name)=0, 1, -1",
          "\(p.name)=very large value",
          "\(p.name)=NaN/Inf (if floating-point)"
        ]
      } else if t.contains("string") || n.contains("name") || n.contains("id") || n.contains("path") || n.contains("text") || n.contains("url") || n.contains("email") {
        cases += [
          "\(p.name)=\"\" (empty), whitespace-only",
          "\(p.name) very long (10k chars), unicode/emoji",
          "\(p.name) with injection-like content ('; DROP, ../../, <script>)"
        ]
      } else if t.contains("bool") || n.hasPrefix("is") || n.hasPrefix("has") {
        cases += ["\(p.name)=true and \(p.name)=false"]
      } else if t.contains("array") || t.contains("[") || t.contains("list") || t.contains("vec") || t.contains("[]") {
        cases += [
          "\(p.name)=[] (empty), single-element, very large array",
          "\(p.name) with duplicates, nulls"
        ]
      } else if t.contains("map") || t.contains("dict") || t.contains("object") || t.contains("struct") {
        cases += [
          "\(p.name) missing required keys",
          "\(p.name) with extra/unknown keys",
          "\(p.name) with nested empty/large collections"
        ]
      } else {
        cases += [
          "\(p.name) nominal valid value",
          "\(p.name) invalid/malformed value"
        ]
      }
      // Extra heuristics by name
      if n.contains("timeout") || n.contains("ms") || n.contains("delay") {
        cases += ["\(p.name)=0 (no wait), \(p.name)=1ms, \(p.name)=very large, \(p.name) negative"]
      }
      if n.contains("port") {
        cases += ["\(p.name)=-1, 0, 80, 443, 65535, 65536 (invalid)"]
      }
      if n.contains("url") {
        cases += ["\(p.name) invalid ('not a url'), http://example, https://example.com/path?x=1"]
      }
      if n.contains("path") {
        cases += ["\(p.name)='..', '/', '/tmp/file', very long nested path"]
      }
      if n.contains("email") {
        cases += ["\(p.name)='user@example.com', 'user+tag@example.com', 'not-an-email'"]
      }
      if p.optional { cases.append("\(p.name)=nil/undefined") }
    }
    return Array(cases.prefix(24))
  }

  static func apiPayloads(forPath: String, method: String) -> [String] {
    [
      "\(method) \(forPath) with minimal valid payload",
      "\(method) \(forPath) missing required fields",
      "\(method) \(forPath) with extra fields",
      "\(method) \(forPath) unauthorized/forbidden",
      "\(method) \(forPath) with oversized body and invalid JSON"
    ]
  }
}
