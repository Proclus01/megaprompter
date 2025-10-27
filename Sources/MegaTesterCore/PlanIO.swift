import Foundation
import MegaprompterCore

public enum TestPlanIO {
  @discardableResult
  public static func writeArtifact(root: URL, plan: TestPlanReport, xml: String, json: String, prompt: String, visible: Bool = true) throws -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let timestamp = formatter.string(from: Date())
    let prefix = visible ? "MEGATEST_" : ".MEGATEST_"
    let filename = prefix + timestamp
    let url = root.appendingPathComponent(filename, isDirectory: false)

    var lines: [String] = []
    lines.append("<test_plan_artifact generatedAt=\"\(escapeAttr(plan.generatedAt))\">")
    lines.append("  <xml><![CDATA[")
    lines.append(xml)
    lines.append("  ]]></xml>")
    lines.append("  <json><![CDATA[")
    lines.append(json)
    lines.append("  ]]></json>")
    lines.append("  <test_prompt><![CDATA[")
    lines.append(prompt)
    lines.append("  ]]></test_prompt>")
    lines.append("</test_plan_artifact>")

    try FileSystem.writeString(lines.joined(separator: "\n"), to: url)

    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else {
      throw NSError(domain: "TestPlanIO", code: 1, userInfo: [NSLocalizedDescriptionKey: "Artifact not found: \(url.path)"])
    }
    let attrs = try fm.attributesOfItem(atPath: url.path)
    if let size = attrs[.size] as? NSNumber, size.intValue <= 0 {
      throw NSError(domain: "TestPlanIO", code: 2, userInfo: [NSLocalizedDescriptionKey: "Artifact is empty: \(url.path)"])
    }
    return url
  }

  @discardableResult
  public static func updateLatestSymlink(root: URL, artifactURL: URL, visible: Bool = true) throws -> URL {
    let name = visible ? "MEGATEST_latest" : ".MEGATEST_latest"
    let linkURL = root.appendingPathComponent(name, isDirectory: false)
    let fm = FileManager.default
    if fm.fileExists(atPath: linkURL.path) {
      try fm.removeItem(at: linkURL)
    }
    try fm.createSymbolicLink(at: linkURL, withDestinationURL: artifactURL)
    return linkURL
  }

  private static func escapeAttr(_ s: String) -> String {
    s.replacingOccurrences(of: "\"", with: "&quot;")
  }
}
