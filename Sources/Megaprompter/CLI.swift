// Sources/Megaprompter/CLI.swift
import Foundation
import ArgumentParser
import MegaprompterCore

/// `megaprompt` CLI — Generate an XML-like megaprompt from real source files in a project.
/// - Safety-first: refuses to run outside a code project (override with `--force`).
/// - Auto-detects languages and adapts include rules (e.g., prefer TS over JS).
/// - Prunes build/vendor/caches; includes tests and essential configs.
/// - Writes `.MEGAPROMPT_YYYYMMDD_HHMMSS` and copies to clipboard.
struct MegapromptCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
    commandName: "megaprompt",
    abstract: "Generate a single megaprompt from real source files in a project and copy it to the clipboard."
  )

  @Argument(help: "Target directory ('.' by default). Accepts relative or absolute paths.")
  var path: String = "."

  @Flag(name: .long, help: "Force run even if the directory does not look like a code project.")
  var force: Bool = false

  @Option(name: .long, help: "Skip files larger than this many bytes (default: 1500000).")
  var maxFileBytes: Int = 1_500_000

  @Flag(name: .long, help: "Only show what would be included; do not write or copy.")
  var dryRun: Bool = false

  @Flag(name: .long, help: "Print a summary of detected project types and included files.")
  var showSummary: Bool = false

  // Allow the user to ignore directories by name or glob/path (relative to the target root).
  // Examples:
  //   megaprompt . --ignore data
  //   megaprompt . -I docs/generated/**
  // Accepts multiple values: --ignore a --ignore b
  @Option(
    name: [.customLong("ignore"), .customShort("I"), .short],
    parsing: .upToNextOption,
    help: ArgumentHelp(
      "Directory names or glob paths to ignore (repeatable). " +
      "Examples: --ignore data --ignore docs/generated/** --ignore .cache/**"
    )
  )
  var ignore: [String] = []

  func run() throws {
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard FileSystem.isDirectory(root) else {
      throw RuntimeError("Error: path is not a directory: \(root.path)")
    }

    // 1) Detect project (safety)
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

    // 2) Scan with language-aware rules + user ignores
    let scanner = ProjectScanner(
      profile: profile,
      maxFileBytes: maxFileBytes,
      extraPruneDirNames: ignoreNames,
      extraPruneGlobs: ignoreGlobs
    )
    let files = try scanner.collectFiles()

    if showSummary || dryRun {
      Console.info("Root: \(root.path)")
      let langs = profile.languages.sorted().joined(separator: ", ")
      Console.info("Detected languages: \(langs.isEmpty ? "(none)" : langs)")
      if !profile.why.isEmpty {
        Console.info("Evidence:\n  - " + profile.why.map { "\($0)" }.joined(separator: "\n  - "))
      }
      if !ignoreNames.isEmpty || !ignoreGlobs.isEmpty {
        if !ignoreNames.isEmpty { Console.info("User ignore names: \(ignoreNames.joined(separator: ", "))") }
        if !ignoreGlobs.isEmpty { Console.info("User ignore globs: \(ignoreGlobs.joined(separator: ", "))") }
      }
      Console.info("Files to include (\(files.count)):")
      for url in files {
        Console.info("  - \(url.pathRelative(to: root))")
      }
    }

    if dryRun { return }

    // 3) Build megaprompt
    let builder = MegapromptBuilder(root: root)
    let blob = try builder.build(files: files)

    // 4) Persist + clipboard
    let outURL = try MegapromptIO.writeMegaprompt(root: root, content: blob)
    let copied = Clipboard.copyToClipboard(blob)

    Console.success("Wrote: \(outURL.path)")
    Console.success(copied ? "Megaprompt copied to clipboard."
                           : "Clipboard copy not available on this system; file is written.")
  }
}

/// Lightweight runtime error type for user-facing failures.
struct RuntimeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
