// Sources/MegaDiagnose/CLI.swift
import Foundation
import ArgumentParser
import MegaprompterCore
import MegaDiagnoserCore

struct MegaDiagnoseCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "megadiagnose",
    abstract: "Diagnose multi-language projects, emit XML/JSON diagnostics and a fix prompt, and write a MEGADIAG_* artifact in the run directory."
  )

  @Argument(help: "Target directory ('.' by default). Accepts relative or absolute paths.")
  var path: String = "."

  @Flag(name: .long, help: "Force run even if the directory does not look like a code project.")
  var force: Bool = false

  @Option(name: .long, help: "Timeout in seconds per tool invocation (default: 120).")
  var timeoutSeconds: Int = 120

  @Option(name: .long, help: "Write XML output to this file (default: stdout).")
  var xmlOut: String?

  @Option(name: .long, help: "Write JSON output to this file.")
  var jsonOut: String?

  @Option(name: .long, help: "Write fix prompt text to this file.")
  var promptOut: String?

  @Flag(name: .long, help: "Print a brief summary to stderr.")
  var showSummary: Bool = true

  @Flag(name: .long, help: "Write artifact as a hidden dotfile (.MEGADIAG_*). By default, it's visible (MEGADIAG_*).")
  var artifactHidden: Bool = false

  @Option(name: .long, help: "Directory where the MEGADIAG_* artifact is written (default: the target PATH).")
  var artifactDir: String?

  @Option(
    name: [.customLong("ignore"), .customShort("I"), .short],
    parsing: .upToNextOption,
    help: ArgumentHelp("Directory names or glob paths to ignore (repeatable). Examples: --ignore data --ignore docs/generated/**")
  )
  var ignore: [String] = []

  func run() throws {
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard FileSystem.isDirectory(root) else {
      throw RuntimeError("Error: path is not a directory: \(root.path)")
    }

    // Determine artifact root
    let artifactRoot: URL = {
      if let dir = artifactDir, !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: dir).resolvingSymlinksInPath()
      }
      return root
    }()

    if !FileSystem.isDirectory(artifactRoot) {
      try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    }

    // Detect project (safety)
    let detector = ProjectDetector()
    let profile = try detector.detect(at: root)

    if !profile.isCodeProject && !force {
      let reason = profile.why.isEmpty ? "" : ("\n" + profile.why.joined(separator: "\n"))
      throw RuntimeError("""
      Safety stop: This directory does not appear to be a code project.\(reason)
      If you are certain, re-run with --force.
      """)
    }

    // Split user ignores into simple directory names vs. glob/path patterns.
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

    // Run diagnostics
    let runner = DiagnosticsRunner(root: root, timeoutSeconds: timeoutSeconds, ignoreNames: ignoreNames, ignoreGlobs: ignoreGlobs)
    let report = runner.run(profile: profile)

    if showSummary {
      Console.info("Languages analyzed: " + report.languages.map { $0.name }.joined(separator: ", "))
      let totalIssues = report.languages.reduce(0) { $0 + $1.issues.count }
      let errs = report.languages.reduce(0) { $0 + $1.issues.filter { $0.severity == .error }.count }
      let warns = report.languages.reduce(0) { $0 + $1.issues.filter { $0.severity == .warning }.count }
      Console.info("Issues: \(totalIssues) (errors: \(errs), warnings: \(warns))")
      if !ignoreNames.isEmpty || !ignoreGlobs.isEmpty {
        if !ignoreNames.isEmpty { Console.info("Ignore names: \(ignoreNames.joined(separator: ", "))") }
        if !ignoreGlobs.isEmpty { Console.info("Ignore globs: \(ignoreGlobs.joined(separator: ", "))") }
      }
      for lang in report.languages {
        Console.info(" - \(lang.name): \(lang.issues.count) issues")
      }
    }

    // Prepare outputs
    let xml = report.toXML()
    let jsonData = try JSONEncoder().encode(report)
    let jsonString = String(decoding: jsonData, as: UTF8.self)
    let prompt = FixPrompter.generateFixPrompt(from: report, root: root)

    // Persist artifact first (visible by default). This ensures we always create the MEGADIAG_* file.
    do {
      let artifactURL = try DiagnosticsIO.writeArtifact(
        root: artifactRoot,
        report: report,
        xml: xml,
        json: jsonString,
        prompt: prompt,
        visible: !artifactHidden
      )
      Console.success("Wrote diagnostics artifact: \(artifactURL.path)")

      // Best effort: create/update a 'latest' symlink for convenience.
      if let latest = try? DiagnosticsIO.updateLatestSymlink(root: artifactRoot, artifactURL: artifactURL, visible: !artifactHidden) {
        Console.info("Updated latest symlink: \(latest.path)")
      }
    } catch {
      Console.error("Failed to write diagnostics artifact: \(error)")
    }

    // Write XML output (stdout by default)
    if let p = xmlOut {
      try FileSystem.writeString(xml, to: URL(fileURLWithPath: p))
    } else {
      FileHandle.standardOutput.write(Data((xml + "\n").utf8))
    }

    // Optional JSON file
    if let p = jsonOut {
      try jsonData.write(to: URL(fileURLWithPath: p))
    }

    // Optional prompt file or preview
    if let p = promptOut {
      try FileSystem.writeString(prompt, to: URL(fileURLWithPath: p))
    } else {
      Console.success("Fix prompt (first lines):")
      Console.info(prompt.split(separator: "\n").prefix(10).joined(separator: "\n") + (prompt.contains("\n") ? "\n..." : ""))
    }
  }
}

struct RuntimeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

