import Foundation

/// Builds the megaprompt text blob.
/// Output is intentionally *pseudo-XML*: element names are relative POSIX paths
/// (e.g., `<src/index.ts> ... </src/index.ts>`), which is not valid XML but is
/// convenient for LLMs. Contents are wrapped in `<![CDATA[ ... ]]>` to preserve code verbatim.
public final class MegapromptBuilder {
  private let root: URL

  public init(root: URL) {
    self.root = root
  }

  public func build(files: [URL]) throws -> String {
    var parts: [String] = []
    parts.append("<context>")

    for file in files {
      let rel = file.pathRelative(to: root)
      parts.append("<\(rel)>")
      parts.append("<![CDATA[")
      let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
      parts.append(content)
      parts.append("]]>")
      parts.append("</\(rel)>")
    }

    parts.append("</context>")
    return parts.joined(separator: "\n")
  }
}
