import Foundation

/// File-system helpers (URL-centric, robust for symlinks and path ops).
public enum FileSystem {
  public static func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    return exists && isDir.boolValue
  }

  public static func fileSize(_ url: URL) -> UInt64? {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) }
  }

  public static func writeString(_ string: String, to url: URL) throws {
    try string.write(to: url, atomically: true, encoding: .utf8)
  }

  /// Portable `which` implementation to locate an executable in PATH.
  public static func which(_ name: String) -> String? {
    let env = ProcessInfo.processInfo.environment
    let path = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin")
    for dir in path.split(separator: ":") {
      let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }
}

public extension URL {
  /// `true` if the URL represents a directory (exists + isDir).
  var isDirectory: Bool { FileSystem.isDirectory(self) }

  /// Relative POSIX path from `base` to `self`, with a simple, robust implementation.
  func pathRelative(to base: URL) -> String {
    let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
    if self.path.hasPrefix(basePath) {
      return String(self.path.dropFirst(basePath.count))
    }
    return self.lastPathComponent
  }
}
