import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // IDE chrome (rail + sidebar + editor + bottom panel) needs a real floor.
    let minimumSize = NSSize(width: 1280, height: 720)
    self.minSize = minimumSize
    if frame.width < minimumSize.width || frame.height < minimumSize.height {
      setContentSize(minimumSize)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Prefer the human product name over the Dart package id (robot_studio).
    self.title = "Robot Studio"

    super.awakeFromNib()
  }
}
