import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var fontsChannel: FlutterMethodChannel?
  private var filePickerChannel: FlutterMethodChannel?

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
    registerFilePickerChannel(with: flutterViewController)

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

  /// Native panels without `file_picker`'s sandbox entitlement gate.
  /// Studio runs outside App Sandbox (Terminal + Robot runs), so the plugin's
  /// User Selected File check always fails even though NSOpenPanel is fine.
  private func registerFilePickerChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "robot_studio/file_picker",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "getDirectoryPath":
        self.presentOpenPanel(
          canChooseFiles: false,
          canChooseDirectories: true,
          allowedExtensions: nil,
          dialogTitle: args["dialogTitle"] as? String,
          initialDirectory: args["initialDirectory"] as? String,
          result: result
        )
      case "pickFile":
        self.presentOpenPanel(
          canChooseFiles: true,
          canChooseDirectories: false,
          allowedExtensions: args["allowedExtensions"] as? [String],
          dialogTitle: args["dialogTitle"] as? String,
          initialDirectory: args["initialDirectory"] as? String,
          result: result
        )
      case "saveFile":
        self.presentSavePanel(
          fileName: args["fileName"] as? String,
          allowedExtensions: args["allowedExtensions"] as? [String],
          dialogTitle: args["dialogTitle"] as? String,
          initialDirectory: args["initialDirectory"] as? String,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    filePickerChannel = channel
  }

  private func presentOpenPanel(
    canChooseFiles: Bool,
    canChooseDirectories: Bool,
    allowedExtensions: [String]?,
    dialogTitle: String?,
    initialDirectory: String?,
    result: @escaping FlutterResult
  ) {
    let dialog = NSOpenPanel()
    dialog.canChooseFiles = canChooseFiles
    dialog.canChooseDirectories = canChooseDirectories
    dialog.allowsMultipleSelection = false
    dialog.canCreateDirectories = true
    if let dialogTitle, !dialogTitle.isEmpty {
      dialog.title = dialogTitle
      dialog.message = dialogTitle
    }
    if let initialDirectory, !initialDirectory.isEmpty {
      dialog.directoryURL = URL(fileURLWithPath: initialDirectory)
    }
    applyExtensions(dialog, allowedExtensions)

    dialog.beginSheetModal(for: self) { response in
      guard response == .OK, let url = dialog.url else {
        result(nil)
        return
      }
      result(url.path)
    }
  }

  private func presentSavePanel(
    fileName: String?,
    allowedExtensions: [String]?,
    dialogTitle: String?,
    initialDirectory: String?,
    result: @escaping FlutterResult
  ) {
    let dialog = NSSavePanel()
    dialog.canCreateDirectories = true
    dialog.showsTagField = false
    if let dialogTitle, !dialogTitle.isEmpty {
      dialog.title = dialogTitle
    }
    if let fileName, !fileName.isEmpty {
      dialog.nameFieldStringValue = fileName
    }
    if let initialDirectory, !initialDirectory.isEmpty {
      dialog.directoryURL = URL(fileURLWithPath: initialDirectory)
    }
    applyExtensions(dialog, allowedExtensions)

    dialog.beginSheetModal(for: self) { response in
      guard response == .OK, let url = dialog.url else {
        result(nil)
        return
      }
      result(url.path)
    }
  }

  private func applyExtensions(_ dialog: NSSavePanel, _ extensions: [String]?) {
    guard let extensions, !extensions.isEmpty else { return }
    if #available(macOS 11.0, *) {
      let types = extensions.compactMap { UTType(filenameExtension: $0) }
      if !types.isEmpty {
        dialog.allowedContentTypes = types
      }
    } else {
      dialog.allowedFileTypes = extensions
    }
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
