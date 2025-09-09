import Foundation

/// Cross-platform clipboard copy without external dependencies at runtime.
/// Tries (in order): pbcopy (macOS), wl-copy (Wayland), xclip, xsel (X11), clip (Windows).
public enum Clipboard {

  @discardableResult
  public static func copyToClipboard(_ text: String) -> Bool {
    // macOS
    if let cmd = FileSystem.which("pbcopy") {
      return runPipe([cmd], input: text)
    }
    // Wayland (Linux)
    if let cmd = FileSystem.which("wl-copy") {
      return runPipe([cmd], input: text)
    }
    // X11 (Linux)
    if let cmd = FileSystem.which("xclip") {
      return runPipe([cmd, "-selection", "clipboard"], input: text)
    }
    if let cmd = FileSystem.which("xsel") {
      return runPipe([cmd, "--clipboard", "--input"], input: text)
    }
    // Windows
    #if os(Windows)
    if let cmd = FileSystem.which("clip") {
      return runPipe([cmd], input: text)
    }
    #endif
    return false
  }

  private static func runPipe(_ command: [String], input: String) -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: command[0])
    proc.arguments = Array(command.dropFirst())

    let stdinPipe = Pipe()
    proc.standardInput = stdinPipe
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()

    do {
      try proc.run()
    } catch {
      return false
    }

    if let data = input.data(using: .utf8) {
      stdinPipe.fileHandleForWriting.write(data)
    }
    stdinPipe.fileHandleForWriting.closeFile()

    proc.waitUntilExit()
    return proc.terminationStatus == 0
  }
}
