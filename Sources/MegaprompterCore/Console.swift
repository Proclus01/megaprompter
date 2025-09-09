import Foundation

/// Minimal console utility with consistent prefixes.
public enum Console {
  public static func info(_ message: String) {
    FileHandle.standardError.write(Data(("[info] \(message)\n").utf8))
  }
  public static func warn(_ message: String) {
    FileHandle.standardError.write(Data(("[warn] \(message)\n").utf8))
  }
  public static func error(_ message: String) {
    FileHandle.standardError.write(Data(("[error] \(message)\n").utf8))
  }
  public static func success(_ message: String) {
    FileHandle.standardError.write(Data(("[ok] \(message)\n").utf8))
  }
}
