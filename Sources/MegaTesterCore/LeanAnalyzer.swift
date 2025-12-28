import Foundation

/// Lightweight Lean 4 analyzer for MegaTest.
/// Identifies common subject types in Lean source:
/// - def / abbrev
/// - theorem / lemma
/// - structure / inductive
///
/// This is intentionally heuristic and does not attempt full parsing.
enum LeanAnalyzer {

  static func analyze(url: URL, content: String) -> [TestSubject] {
    let lang = "lean"
    var out: [TestSubject] = []

    // Lean identifiers commonly include `'` (prime).
    // Examples:
    //   def foo' := ...
    //   theorem bar : ... := by ...
    //
    // Note: we avoid matching `namespace` and `section` here; those are not "testable" units.
    let re = try! NSRegularExpression(
      pattern: #"(?m)^\s*(def|abbrev|theorem|lemma|structure|inductive|class)\s+([A-Za-z_][A-Za-z0-9_']*)\b"#
    )

    let ns = content as NSString
    let rng = NSRange(location: 0, length: ns.length)

    re.enumerateMatches(in: content, options: [], range: rng) { m, _, _ in
      guard let m, m.numberOfRanges >= 3 else { return }
      let kindTok = ns.substring(with: m.range(at: 1))
      let name = ns.substring(with: m.range(at: 2))

      let subjectKind: SubjectKind = {
        switch kindTok {
        case "structure", "inductive", "class":
          return .class
        default:
          return .function
        }
      }()

      let meta: [String: String] = [
        "lean_decl": kindTok
      ]

      // For Lean, the "test" story is proof checking / compilation checks; risk is usually low per decl.
      let sub = TestSubject(
        id: "\(url.path)#lean:\(kindTok):\(name)",
        kind: subjectKind,
        language: lang,
        name: name,
        path: url.path,
        signature: "\(kindTok) \(name)",
        exported: true,
        params: [],
        riskScore: 2,
        riskFactors: ["lean declaration: \(kindTok)"],
        io: IOCapabilities(readsFS: false, writesFS: false, network: false, db: false, env: false, concurrency: false),
        meta: meta
      )
      out.append(sub)
    }

    return out
  }
}
