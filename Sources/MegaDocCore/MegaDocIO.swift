import Foundation
import MegaprompterCore

public enum MegaDocIO {

  @discardableResult
  public static func writeArtifact(root: URL, report: MegaDocReport, xml: String, json: String, prompt: String, visible: Bool = true) throws -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let ts = formatter.string(from: Date())
    let prefix = visible ? "MEGADOC_" : ".MEGADOC_"
    let url = root.appendingPathComponent(prefix + ts, isDirectory: false)

    var lines: [String] = []
    lines.append("<documentation_artifact generatedAt=\"\(escapeAttr(report.generatedAt))\">")
    lines.append("  <xml><![CDATA[")
    lines.append(xml)
    lines.append("  ]]></xml>")
    lines.append("  <json><![CDATA[")
    lines.append(json)
    lines.append("  ]]></json>")
    lines.append("  <doc_prompt><![CDATA[")
    lines.append(prompt)
    lines.append("  ]]></doc_prompt>")
    if let umlAscii = report.umlAscii, !umlAscii.isEmpty {
      lines.append("  <uml_ascii><![CDATA[")
      lines.append(umlAscii)
      lines.append("  ]]></uml_ascii>")
    }
    if let umlPlant = report.umlPlantUML, !umlPlant.isEmpty {
      lines.append("  <uml_plantuml><![CDATA[")
      lines.append(umlPlant)
      lines.append("  ]]></uml_plantuml>")
    }
    lines.append("</documentation_artifact>")

    try FileSystem.writeString(lines.joined(separator: "\n"), to: url)

    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else {
      throw NSError(domain: "MegaDocIO", code: 1, userInfo: [NSLocalizedDescriptionKey: "Artifact not found: \(url.path)"])
    }
    let attrs = try fm.attributesOfItem(atPath: url.path)
    if let size = attrs[.size] as? NSNumber, size.intValue <= 0 {
      throw NSError(domain: "MegaDocIO", code: 2, userInfo: [NSLocalizedDescriptionKey: "Artifact is empty: \(url.path)"])
    }
    return url
  }

  @discardableResult
  public static func updateLatestSymlink(root: URL, artifactURL: URL, visible: Bool = true) throws -> URL {
    let name = visible ? "MEGADOC_latest" : ".MEGADOC_latest"
    let linkURL = root.appendingPathComponent(name, isDirectory: false)
    let fm = FileManager.default
    if fm.fileExists(atPath: linkURL.path) {
      try fm.removeItem(at: linkURL)
    }
    try fm.createSymbolicLink(at: linkURL, withDestinationURL: artifactURL)
    return linkURL
  }

  private static func escapeAttr(_ s: String) -> String {
    // Robust XML attribute escaping for the artifact envelope.
    return s
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
