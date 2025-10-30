import Foundation

public struct DocImport: Codable {
  public let file: String
  public let language: String
  public let raw: String
  public let isInternal: Bool
  public let resolvedPath: String?

  public init(file: String, language: String, raw: String, isInternal: Bool, resolvedPath: String?) {
    self.file = file
    self.language = language
    self.raw = raw
    self.isInternal = isInternal
    self.resolvedPath = resolvedPath
  }
}

public struct FetchedDoc: Codable {
  public let uri: String
  public let title: String
  public let contentPreview: String

  public init(uri: String, title: String, contentPreview: String) {
    self.uri = uri
    self.title = title
    self.contentPreview = contentPreview
  }
}

public enum MegaDocMode: String, Codable { case local, fetch }

public struct MegaDocReport: Codable {
  public let generatedAt: String
  public let mode: MegaDocMode
  public let rootPath: String
  public let languages: [String]
  public let directoryTree: String
  public let importGraph: String
  public let imports: [DocImport]
  public let externalDependencies: [String: Int]
  public let purposeSummary: String
  public let fetchedDocs: [FetchedDoc]

  public init(
    generatedAt: String,
    mode: MegaDocMode,
    rootPath: String,
    languages: [String],
    directoryTree: String,
    importGraph: String,
    imports: [DocImport],
    externalDependencies: [String: Int],
    purposeSummary: String,
    fetchedDocs: [FetchedDoc]
  ) {
    self.generatedAt = generatedAt
    self.mode = mode
    self.rootPath = rootPath
    self.languages = languages
    self.directoryTree = directoryTree
    self.importGraph = importGraph
    self.imports = imports
    self.externalDependencies = externalDependencies
    self.purposeSummary = purposeSummary
    self.fetchedDocs = fetchedDocs
  }
}

public extension MegaDocReport {
  func toXML() -> String {
    var parts: [String] = []
    parts.append("<documentation generatedAt=\"\(escapeAttr(generatedAt))\" mode=\"\(mode.rawValue)\">")
    if !rootPath.isEmpty {
      parts.append("  <root><![CDATA[\(rootPath)]]></root>")
    }
    if !languages.isEmpty {
      parts.append("  <languages>")
      for l in languages { parts.append("    <language name=\"\(escapeAttr(l))\"/>") }
      parts.append("  </languages>")
    }
    parts.append("  <directory_tree><![CDATA[\n\(directoryTree)\n]]></directory_tree>")
    parts.append("  <import_graph><![CDATA[\n\(importGraph)\n]]></import_graph>")
    if !imports.isEmpty {
      parts.append("  <imports>")
      for i in imports {
        parts.append("    <import file=\"\(escapeAttr(i.file))\" language=\"\(escapeAttr(i.language))\" internal=\"\(i.isInternal)\">")
        parts.append("      <raw><![CDATA[\(i.raw)]]></raw>")
        if let rp = i.resolvedPath { parts.append("      <resolved_path><![CDATA[\(rp)]]></resolved_path>") }
        parts.append("    </import>")
      }
      parts.append("  </imports>")
    }
    if !externalDependencies.isEmpty {
      parts.append("  <external_dependencies>")
      for (dep, count) in externalDependencies.sorted(by: { $0.key < $1.key }) {
        parts.append("    <dep name=\"\(escapeAttr(dep))\" count=\"\(count)\"/>")
      }
      parts.append("  </external_dependencies>")
    }
    parts.append("  <purpose><![CDATA[\(purposeSummary)]]></purpose>")
    if !fetchedDocs.isEmpty {
      parts.append("  <fetched_docs>")
      for d in fetchedDocs {
        parts.append("    <doc uri=\"\(escapeAttr(d.uri))\" title=\"\(escapeAttr(d.title))\">")
        parts.append("      <preview><![CDATA[\(d.contentPreview)]]></preview>")
        parts.append("    </doc>")
      }
      parts.append("  </fetched_docs>")
    }
    parts.append("</documentation>")
    return parts.joined(separator: "\n")
  }
}

private func escapeAttr(_ s: String) -> String {
  s.replacingOccurrences(of: "&", with: "&amp;")
   .replacingOccurrences(of: "\"", with: "&quot;")
   .replacingOccurrences(of: "<", with: "&lt;")
   .replacingOccurrences(of: ">", with: "&gt;")
}
