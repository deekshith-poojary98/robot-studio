import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var fontsChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // IDE chrome (rail + sidebar + editor + bottom panel) needs a real floor.
    let minimumSize = NSSize(width: 1360, height: 800)
    self.minSize = minimumSize
    if frame.width < minimumSize.width || frame.height < minimumSize.height {
      setContentSize(minimumSize)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerFontCatalogChannel(with: flutterViewController)

    // Prefer the human product name over the Dart package id (robot_studio).
    self.title = "Robot Studio"
    // Document proxy icons can briefly paint the app mark in the title bar
    // during launch; this is not a document window.
    self.representedURL = nil
    self.standardWindowButton(.documentIconButton)?.isHidden = true

    super.awakeFromNib()
  }

  private func registerFontCatalogChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "robot_studio/fonts",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "listMonospaceFamilies" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self.listMonospaceFontFamilies())
    }
    fontsChannel = channel
  }

  /// Family names the OS reports as monospaced. Hidden / system faces (".SF …")
  /// are skipped so Settings does not list internal catalogs.
  private func listMonospaceFontFamilies() -> [String] {
    let manager = NSFontManager.shared
    var families: [String] = []
    for family in manager.availableFontFamilies {
      if family.hasPrefix(".") {
        continue
      }
      guard
        let members = manager.availableMembers(ofFontFamily: family),
        let first = members.first,
        let postScript = first.first as? String,
        let font = NSFont(name: postScript, size: 12),
        font.fontDescriptor.symbolicTraits.contains(.monoSpace)
      else {
        continue
      }
      families.append(family)
    }
    return families.sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }
}
