import Foundation

enum FrameworkDetector {
  static func detectFrameworks(root: URL) -> [String: [String]] {
    var byLang: [String: [String]] = [:]

    // JS/TS: package.json
    if let pkgData = try? Data(contentsOf: root.appendingPathComponent("package.json")),
       let pkg = String(data: pkgData, encoding: .utf8)?.lowercased() {
      var f: [String] = []
      if pkg.contains("jest") { f.append("jest") }
      if pkg.contains("vitest") { f.append("vitest") }
      if pkg.contains("mocha") { f.append("mocha") }
      if pkg.contains("playwright") { f.append("playwright") }
      if pkg.contains("cypress") { f.append("cypress") }
      byLang["javascript"] = f
      byLang["typescript"] = f
    }

    // Python: pyproject/requirements
    let candidates = ["pyproject.toml","requirements.txt","Pipfile"]
    for c in candidates {
      if let s = try? String(contentsOf: root.appendingPathComponent(c)).lowercased() {
        var f = byLang["python", default: []]
        if s.contains("pytest") { f.append("pytest") }
        if s.contains("unittest") { f.append("unittest") }
        if s.contains("behave") { f.append("behave") }
        byLang["python"] = Array(Set(f))
      }
    }

    // Go: built-in `go test`
    byLang["go"] = ["go test"]

    // Rust: cargo test
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("Cargo.toml").path) {
      byLang["rust"] = ["cargo test"]
    }

    // Swift: XCTest
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
      byLang["swift"] = ["XCTest (swift test)"]
    }

    // Java: JUnit
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("pom.xml").path) ||
       FileManager.default.fileExists(atPath: root.appendingPathComponent("build.gradle").path) ||
       FileManager.default.fileExists(atPath: root.appendingPathComponent("build.gradle.kts").path) {
      byLang["java"] = ["JUnit"]
    }

    return byLang
  }
}
