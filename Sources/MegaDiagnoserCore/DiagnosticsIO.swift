import Foundation
import MegaprompterCore

/// Writes a single diagnostics artifact file in the run directory.
/// The artifact wraps XML, JSON, and the fix prompt in a pseudo-XML envelope, similar to Megaprompter behavior.
/// File is visible by default (MEGADIAG_YYYYMMDD_HHMMSS).
public enum DiagnosticsIO {

  @discardableResult
  public static func writeArtifact(root: URL, report: DiagnosticsReport, xml: String, json: String, prompt: String, visible: Bool = true) throws -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let timestamp = formatter.string(from: Date())
    let prefix = visible ? "MEGADIAG_" : ".MEGADIAG_"
    let filename = prefix + timestamp
    let url = root.appendingPathComponent(filename, isDirectory: false)

    var lines: [String] = []
    lines.append("<diagnostics_artifact generatedAt=\"\(escapeAttr(report.generatedAt))\">")
    lines.append("  <xml>")
    lines.append("    <![CDATA[")
    lines.append(xml)
    lines.append("    ]]>")
    lines.append("  </xml>")
    lines.append("  <json>")
    lines.append("    <![CDATA[")
    lines.append(json)
    lines.append("    ]]>")
    lines.append("  </json>")
    lines.append("  <fix_prompt>")
    lines.append("    <![CDATA[")
    lines.append(prompt)
    lines.append("    ]]>")
    lines.append("  </fix_prompt>")
    lines.append("</diagnostics_artifact>")

    try FileSystem.writeString(lines.joined(separator: "\n"), to: url)

    // Basic verification
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else {
      throw NSError(domain: "DiagnosticsIO", code: 1, userInfo: [NSLocalizedDescriptionKey: "Artifact file not found after write: \(url.path)"])
    }
    let attrs = try fm.attributesOfItem(atPath: url.path)
    if let size = attrs[.size] as? NSNumber, size.intValue <= 0 {
      throw NSError(domain: "DiagnosticsIO", code: 2, userInfo: [NSLocalizedDescriptionKey: "Artifact file is empty: \(url.path)"])
    }
    return url
  }

  /// Create or update a symlink named MEGADIAG_latest (or .MEGADIAG_latest) next to the artifact.
  /// Returns the symlink URL. Best-effort; callers may ignore errors.
  @discardableResult
  public static func updateLatestSymlink(root: URL, artifactURL: URL, visible: Bool = true) throws -> URL {
    let name = visible ? "MEGADIAG_latest" : ".MEGADIAG_latest"
    let linkURL = root.appendingPathComponent(name, isDirectory: false)
    let fm = FileManager.default

    // If something exists at the link path, remove it (file or symlink).
    if fm.fileExists(atPath: linkURL.path) {
      try fm.removeItem(at: linkURL)
    }

    try fm.createSymbolicLink(at: linkURL, withDestinationURL: artifactURL)
    return linkURL
  }

  private static func escapeAttr(_ s: String) -> String {
    return s.replacingOccurrences(of: "\"", with: "&quot;")
  }
}

