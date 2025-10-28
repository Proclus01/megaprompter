// Sources/MegaTest/CLI.swift
import Foundation
import ArgumentParser
import MegaprompterCore
import MegaTesterCore

struct MegaTestCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "megatest",
    abstract: "Analyze code to propose a test plan (smoke, unit, integration, e2e, regression) and write a MEGATEST_* artifact."
  )

  @Argument(help: "Target directory ('.' by default). Accepts relative or absolute paths.")
  var path: String = "."

  @Flag(name: .long, help: "Force run even if the directory does not look like a code project.")
  var force: Bool = false

  @Option(name: .long, help: "Limit number of subjects analyzed (default: 500).")
  var limitSubjects: Int = 500

  @Option(name: .long, help: "Comma-separated levels to include: smoke,unit,integration,e2e,regression (default: all).")
  var levels: String?

  @Option(name: .long, help: "Write XML output to this file (default: stdout).")
  var xmlOut: String?

  @Option(name: .long, help: "Write JSON output to this file.")
  var jsonOut: String?

  @Option(name: .long, help: "Write test prompt text to this file.")
  var promptOut: String?

  @Flag(name: .long, inversion: .prefixedNo,
        help: "Print a brief summary to stderr (use --no-show-summary to disable).")
  var showSummary: Bool = true

  @Flag(name: .long, help: "Write artifact as a hidden dotfile (.MEGATEST_*). By default, it's visible (MEGATEST_*).")
  var artifactHidden: Bool = false

  @Option(name: .long, help: "Directory where the MEGATEST_* artifact is written (default: the target PATH).")
  var artifactDir: String?

  @Option(
    name: [.customLong("ignore"), .customShort("I"), .customShort("i")],
    parsing: .upToNextOption,
    help: ArgumentHelp("Directory names or glob paths to ignore (repeatable). Examples: --ignore data --ignore docs/generated/**")
  )
  var ignore: [String] = []

  @Option(name: .long, help: "Skip files larger than this many bytes during scanning (default: 1500000).")
  var maxFileBytes: Int = 1_500_000

  @Option(name: .long, help: "Analyze at most this many bytes of each file for heuristics (default: 200000).")
  var maxAnalyzeBytes: Int = 200_000

  // New: Regression flags
  @Option(name: .long, help: "Enable regression suggestions by diffing against this git ref (e.g., origin/main, HEAD~1).")
  var regressionSince: String?

  @Option(name: .long, help: "Enable regression suggestions by diffing this git range A..B (e.g., HEAD~3..HEAD).")
  var regressionRange: String?

  @Flag(name: .long, help: "Disable regression scenarios entirely.")
  var noRegression: Bool = false

  func run() throws {
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard FileSystem.isDirectory(root) else {
      throw RuntimeError("Error: path is not a directory: \(root.path)")
    }

    // Artifact dir
    let artifactRoot: URL = {
      if let dir = artifactDir, !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: dir).resolvingSymlinksInPath()
      }
      return root
    }()
    if !FileSystem.isDirectory(artifactRoot) {
      try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    }

    // Detect project
    let detector = ProjectDetector()
    let profile = try detector.detect(at: root)

    if !profile.isCodeProject && !force {
      let reason = profile.why.isEmpty ? "" : ("\n" + profile.why.joined(separator: "\n"))
      throw RuntimeError("""
      Safety stop: This directory does not appear to be a code project.\(reason)
      If you are certain, re-run with --force.
      """)
    }

    // Split ignores into names vs globs
    let rawIgnores = ignore.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    var ignoreNames: [String] = []
    var ignoreGlobs: [String] = []
    for val in rawIgnores {
      if val.contains("/") || val.contains("*") || val.contains("?") {
        ignoreGlobs.append(val)
      } else {
        ignoreNames.append(val)
      }
    }

    let levelSet = LevelSet.parse(from: levels)

    // Collect files with same rules as megaprompt
    let scanner = ProjectScanner(
      profile: profile,
      maxFileBytes: maxFileBytes,
      extraPruneDirNames: ignoreNames,
      extraPruneGlobs: ignoreGlobs
    )
    let files = try scanner.collectFiles()

    // Build regression config
    let regression: RegressionConfig? = {
      if noRegression { return RegressionConfig(mode: .disabled) }
      if let r = regressionRange, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return RegressionConfig(mode: .range(r))
      }
      if let s = regressionSince, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return RegressionConfig(mode: .since(s))
      }
      return nil
    }()

    // Build test plan
    let planner = TestPlanner(root: root, ignoreNames: ignoreNames, ignoreGlobs: ignoreGlobs, limitSubjects: limitSubjects, maxAnalyzeBytes: maxAnalyzeBytes)
    let plan = try planner.buildPlan(profile: profile, files: files, levels: levelSet, regression: regression)

    // Outputs
    let xml = plan.toXML()
    let jsonData = try JSONEncoder().encode(plan)
    let json = String(decoding: jsonData, as: UTF8.self)
    let prompt = TestPrompter.generateTestPrompt(from: plan, root: root, levels: levelSet)

    // Artifact write
    do {
      let artifactURL = try TestPlanIO.writeArtifact(root: artifactRoot, plan: plan, xml: xml, json: json, prompt: prompt, visible: !artifactHidden)
      Console.success("Wrote test-plan artifact: \(artifactURL.path)")
      if let latest = try? TestPlanIO.updateLatestSymlink(root: artifactRoot, artifactURL: artifactURL, visible: !artifactHidden) {
        Console.info("Updated latest symlink: \(latest.path)")
      }
    } catch {
      Console.error("Failed to write megatest artifact: \(error)")
    }

    // Optional outputs
    if let p = xmlOut {
      try FileSystem.writeString(xml, to: URL(fileURLWithPath: p))
    } else {
      FileHandle.standardOutput.write(Data((xml + "\n").utf8))
    }
    if let p = jsonOut {
      try jsonData.write(to: URL(fileURLWithPath: p))
    }
    if let p = promptOut {
      try FileSystem.writeString(prompt, to: URL(fileURLWithPath: p))
    } else {
      Console.success("Test prompt (first lines):")
      Console.info(prompt.split(separator: "\n").prefix(12).joined(separator: "\n") + (prompt.contains("\n") ? "\n..." : ""))
    }

    if showSummary {
      Console.info("Languages: " + plan.languages.map { $0.name }.joined(separator: ", "))
      let totalSubjects = plan.languages.reduce(0) { $0 + $1.subjects.count }
      let totalScenarios = plan.languages.reduce(0) { $0 + $1.subjects.reduce(0) { $0 + $1.scenarios.count } }
      Console.info("Subjects: \(totalSubjects), Scenarios: \(totalScenarios)")
      if let regression {
        Console.info("Regression mode: \(regression.description)")
      } else {
        Console.info("Regression mode: off")
      }
      for lang in plan.languages {
        Console.info(" - \(lang.name): \(lang.subjects.count) subjects, frameworks: \(lang.frameworks.joined(separator: ", "))")
      }
    }
  }
}

struct RuntimeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
