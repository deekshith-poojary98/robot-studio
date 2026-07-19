import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Keep the IDE shell usable on smaller displays.
    let minimumSize = NSSize(width: 1024, height: 640)
    self.minSize = minimumSize
    if frame.width < minimumSize.width || frame.height < minimumSize.height {
      setContentSize(minimumSize)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
