import Foundation

/// File I/O for megaprompt persistence.
public enum MegapromptIO {
  public static func writeMegaprompt(root: URL, content: String) throws -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let filename = ".MEGAPROMPT_\(formatter.string(from: Date()))"
    let outURL = root.appendingPathComponent(filename, isDirectory: false)
    try FileSystem.writeString(content, to: outURL)
    return outURL
  }
}
