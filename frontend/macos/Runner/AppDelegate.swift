import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Flutter's AppLifecycleState.detached is unreliable on macOS desktop quit.
  /// Kill the packaged sidecar using the PID file written by BackendHost.
  ///
  /// Do not override applicationShouldTerminate to force .terminateNow — that
  /// bypasses Dart's WidgetsBindingObserver.didRequestAppExit (unsaved prompts).
  override func applicationWillTerminate(_ notification: Notification) {
    Self.terminatePackagedBackendIfNeeded()
    super.applicationWillTerminate(notification)
  }

  private static func terminatePackagedBackendIfNeeded() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let pidFile = home.appendingPathComponent(".robot-studio/backend.pid")
    let portFile = home.appendingPathComponent(".robot-studio/backend.port")
    guard
      let raw = try? String(contentsOf: pidFile, encoding: .utf8),
      let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
      pid > 1
    else {
      return
    }

    // Never SIGKILL a recycled PID. Require the process to be listening on the
    // port recorded for this sidecar (same rule as Dart BackendHost reclaim).
    let port: Int? = {
      guard let text = try? String(contentsOf: portFile, encoding: .utf8) else {
        return nil
      }
      return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }()
    if let port, port > 0, !pidListens(on: port, pid: pid) {
      try? FileManager.default.removeItem(at: pidFile)
      return
    }

    // SIGTERM first so uvicorn can shut down cleanly, then SIGKILL.
    kill(pid, SIGTERM)
    kill(-pid, SIGTERM)
    usleep(300_000)
    kill(pid, SIGKILL)
    kill(-pid, SIGKILL)
    try? FileManager.default.removeItem(at: pidFile)
  }

  private static func pidListens(on port: Int, pid: Int32) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      // If lsof is unavailable, refuse to kill — safer than guessing.
      return false
    }
    guard process.terminationStatus == 0 else { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    return text.split { $0.isWhitespace }.contains { $0 == "\(pid)" }
  }
}
