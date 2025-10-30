// Sources/MegaDoc/CLI.swift
import Foundation
import ArgumentParser
import MegaprompterCore
import MegaDocCore

struct MegaDocCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "megadoc",
    abstract: "Build a documentation artifact from code (dir tree, imports/deps, purpose) or fetch docs from URIs."
  )

  @Argument(help: "Target directory ('.' by default) for --create.")
  var path: String = "."

  @Flag(name: .long, help: "Create documentation artifact from local codebase.")
  var create: Bool = false

  @Option(name: .long, parsing: .upToNextOption,
          help: "Fetch documentation from one or more URIs (http(s)://, file://, or absolute/relative paths).")
  var get: [String] = []

  @Flag(name: .long, help: "Force run even if the directory does not look like a code project (applies to --create).")
  var force: Bool = false

  @Option(name: .long, help: "Write XML output to this file (default: stdout).")
  var xmlOut: String?

  @Option(name: .long, help: "Write JSON output to this file.")
  var jsonOut: String?

  @Option(name: .long, help: "Write prompt text to this file.")
  var promptOut: String?

  @Flag(name: .long, inversion: .prefixedNo,
        help: "Print a brief summary to stderr (use --no-show-summary to disable).")
  var showSummary: Bool = true

  @Flag(name: .long, help: "Write artifact as a hidden dotfile (.MEGADOC_*). Visible by default (MEGADOC_*).")
  var artifactHidden: Bool = false

  @Option(name: .long, help: "Directory where the MEGADOC_* artifact is written (default: the target PATH for --create).")
  var artifactDir: String?

  // Local analysis options
  @Option(
    name: [.customLong("ignore"), .customShort("I"), .short],
    parsing: .upToNextOption,
    help: ArgumentHelp("Directory names or glob paths to ignore (repeatable). Examples: --ignore data --ignore docs/generated/**")
  )
  var ignore: [String] = []

  @Option(name: .long, help: "Skip files larger than this many bytes when scanning (default: 1500000).")
  var maxFileBytes: Int = 1_500_000

  @Option(name: .long, help: "Analyze at most this many bytes of each file for heuristics (default: 200000).")
  var maxAnalyzeBytes: Int = 200_000

  @Option(name: .long, help: "Limit directory tree depth (default: 6).")
  var treeDepth: Int = 6

  // Fetch options
  @Option(name: .long, help: "Crawl depth for --get (default: 1 = fetch the URI only).")
  var crawlDepth: Int = 1

  @Option(name: .long, parsing: .upToNextOption, help: "Allow only these domains when crawling (repeatable).")
  var allowDomain: [String] = []

  func run() throws {
    // Validate mode
    let isCreate = create
    let hasGet = !get.isEmpty
    if !(isCreate || hasGet) {
      throw RuntimeError("Specify --create to analyze local code or --get <URI> to fetch docs.")
    }
    if isCreate && hasGet {
      throw RuntimeError("Use either --create or --get in a single run, not both.")
    }

    // Determine artifact root
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath()
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let artifactRoot: URL = {
      if let dir = artifactDir, !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: dir).resolvingSymlinksInPath()
      }
      return isCreate ? root : cwd
    }()
    if !FileSystem.isDirectory(artifactRoot) {
      try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
    }

    var report: MegaDocReport

    if isCreate {
      guard FileSystem.isDirectory(root) else {
        throw RuntimeError("Error: path is not a directory: \(root.path)")
      }

      let detector = ProjectDetector()
      let profile = try detector.detect(at: root)

      if !profile.isCodeProject && !force {
        let reason = profile.why.isEmpty ? "" : ("\n" + profile.why.joined(separator: "\n"))
        throw RuntimeError("""
        Safety stop: This directory does not appear to be a code project.\(reason)
        If you are certain, re-run with --force.
        """)
      }

      // Split ignores
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

      // Collect files (reuse megaprompt scanner rules)
      let scanner = ProjectScanner(
        profile: profile,
        maxFileBytes: maxFileBytes,
        extraPruneDirNames: ignoreNames,
        extraPruneGlobs: ignoreGlobs
      )
      let files = try scanner.collectFiles()

      // Build doc pieces
      let dirTree = DirTreeBuilder.buildTree(root: root, maxDepth: max(1, treeDepth), ignoreNames: Set(ignoreNames), ignoreGlobs: ignoreGlobs)
      let (imports, asciiGraph) = ImportGrapher.build(root: root, files: files, maxAnalyzeBytes: maxAnalyzeBytes)
      let purpose = PurposeGuesser.guess(root: root, files: files, languages: Array(profile.languages), maxAnalyzeBytes: maxAnalyzeBytes)
      let external = ImportGrapher.externalSummary(imports: imports)

      report = MegaDocReport(
        generatedAt: isoNow(),
        mode: .local,
        rootPath: root.path,
        languages: Array(profile.languages).sorted(),
        directoryTree: dirTree,
        importGraph: asciiGraph,
        imports: imports,
        externalDependencies: external,
        purposeSummary: purpose,
        fetchedDocs: []
      )

    } else {
      // Fetch mode
      let fetcher = DocFetcher(allowDomains: Set(allowDomain), maxDepth: max(1, crawlDepth))
      var docs: [FetchedDoc] = []
      for uri in get {
        docs.append(contentsOf: fetcher.fetch(uri: uri))
      }
      let summary = DocFetcher.summarize(docs: docs)
      report = MegaDocReport(
        generatedAt: isoNow(),
        mode: .fetch,
        rootPath: "",
        languages: [],
        directoryTree: "fetch mode: no directory tree",
        importGraph: "fetch mode: no import graph",
        imports: [],
        externalDependencies: [:],
        purposeSummary: summary,
        fetchedDocs: docs
      )
    }

    // Outputs
    let xml = report.toXML()
    let jsonData = try JSONEncoder().encode(report)
    let json = String(decoding: jsonData, as: UTF8.self)
    let prompt = DocPrompter.generate(from: report)

    // Artifact
    do {
      let artifactURL = try MegaDocIO.writeArtifact(root: artifactRoot, report: report, xml: xml, json: json, prompt: prompt, visible: !artifactHidden)
      Console.success("Wrote documentation artifact: \(artifactURL.path)")
      if let latest = try? MegaDocIO.updateLatestSymlink(root: artifactRoot, artifactURL: artifactURL, visible: !artifactHidden) {
        Console.info("Updated latest symlink: \(latest.path)")
      }
    } catch {
      Console.error("Failed to write megadoc artifact: \(error)")
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
      Console.success("Doc prompt (first lines):")
      Console.info(prompt.split(separator: "\n").prefix(12).joined(separator: "\n") + (prompt.contains("\n") ? "\n" : ""))
    }

    if showSummary {
      Console.info("Mode: \(report.mode.rawValue)")
      if !report.languages.isEmpty {
        Console.info("Languages: " + report.languages.joined(separator: ", "))
      }
      Console.info("Imports: \(report.imports.count), External deps: \(report.externalDependencies.count), Docs fetched: \(report.fetchedDocs.count)")
    }
  }
}

struct RuntimeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
