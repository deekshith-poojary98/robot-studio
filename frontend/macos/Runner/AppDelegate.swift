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
  override func applicationWillTerminate(_ notification: Notification) {
    Self.terminatePackagedBackendIfNeeded()
    super.applicationWillTerminate(notification)
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Self.terminatePackagedBackendIfNeeded()
    return .terminateNow
  }

  private static func terminatePackagedBackendIfNeeded() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let pidFile = home.appendingPathComponent(".robot-studio/backend.pid")
    guard
      let raw = try? String(contentsOf: pidFile, encoding: .utf8),
      let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
      pid > 1
    else {
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
}
