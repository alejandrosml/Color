import Cocoa
import FlutterMacOS

/// Foundation performs the safe-save operation for a file selected by the user.
/// It does not require creating an arbitrary sibling in the selected directory.
enum EduPaintAtomicFileWriter {
  static func write(path: String, data: Data) throws {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInvalidFileNameError,
                    userInfo: [NSLocalizedDescriptionKey: "Le chemin du fichier est invalide."])
    }
    let url = URL(fileURLWithPath: path)
    try checkDestination(url)
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: .forReplacing,
                           error: &coordinationError) { coordinatedURL in
      do {
        try checkDestination(coordinatedURL)
        try data.write(to: coordinatedURL, options: .atomic)
      } catch {
        writeError = error
      }
    }
    if let error = coordinationError { throw error }
    if let error = writeError { throw error }
  }

  private static func checkDestination(_ url: URL) throws {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInvalidFileNameError,
                      userInfo: [NSLocalizedDescriptionKey:
                        "Choisissez un fichier ordinaire, pas un dossier ou un lien symbolique."])
      }
    } catch let error as NSError {
      // A new file is valid. Permission failures must still be reported.
      if error.domain == NSCocoaErrorDomain &&
          (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
        return
      }
      throw error
    }
  }
}

/// One request to print a drawing: the print panel of macOS, as a sheet on
/// Color's window. Nothing goes to a printer unless the person confirms it
/// there.
private final class EduPaintPrintJob: NSObject {
  private let result: FlutterResult
  private let finished: () -> Void

  init(result: @escaping FlutterResult, finished: @escaping () -> Void) {
    self.result = result
    self.finished = finished
    super.init()
  }

  /// One page: the image as large as the page allows, never distorted, in
  /// the middle of the paper, the page turned the way the image is.
  func run(image: NSImage, pixelsWide: Int, pixelsHigh: Int, name: String, window: NSWindow) {
    // A copy: what suits a drawing never becomes the person's default for
    // other documents.
    guard let info = NSPrintInfo.shared.copy() as? NSPrintInfo else {
      finish(FlutterError(code: "PRINT_FAILED",
                          message: "Les réglages d’impression sont indisponibles.", details: nil))
      return
    }
    info.orientation = pixelsWide > pixelsHigh ? .landscape : .portrait
    // What a printer cannot reach is rarely the same on each side: the image
    // keeps to the larger margin on both sides, and to a centimetre and a
    // half, which another printer chosen in the panel can reach as well.
    let paper = info.paperSize
    let reach = info.imageablePageBounds
    let least: CGFloat = 43
    func margin(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
      let larger = max(first, second)
      return larger.isFinite && larger >= 0 && larger < 144 ? max(least, larger) : least
    }
    let across = margin(reach.minX, paper.width - reach.maxX)
    let down = margin(reach.minY, paper.height - reach.maxY)
    info.leftMargin = across
    info.rightMargin = across
    info.topMargin = down
    info.bottomMargin = down
    // One page, whatever the paper and the direction finally chosen in the
    // panel: the view is larger than any sheet of paper, in the proportions
    // of the image, and « fit » reduces it to the page of the moment.
    info.horizontalPagination = .fit
    info.verticalPagination = .fit
    info.isHorizontallyCentered = true
    info.isVerticallyCentered = true

    let enlargement = 4000 / CGFloat(max(pixelsWide, pixelsHigh))
    let view = NSImageView(frame: NSRect(x: 0, y: 0, width: CGFloat(pixelsWide) * enlargement,
                                         height: CGFloat(pixelsHigh) * enlargement))
    view.imageScaling = .scaleProportionallyUpOrDown
    view.image = image

    let operation = NSPrintOperation(view: view, printInfo: info)
    operation.jobTitle = name
    operation.showsPrintPanel = true
    operation.showsProgressPanel = true
    operation.printPanel.options = [.showsCopies, .showsPaperSize, .showsOrientation, .showsPreview]
    operation.runModal(for: window, delegate: self,
                       didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                       contextInfo: nil)
  }

  /// AppKit calls this when the operation is over: confirmed, given up, or
  /// failed — AppKit does not tell a failure from a cancellation.
  @objc func printOperationDidRun(_ printOperation: NSPrintOperation, success: Bool,
                                  contextInfo: UnsafeMutableRawPointer?) {
    finish(success ? "printed" : "cancelled")
  }

  private func finish(_ answer: Any?) {
    let done = finished
    result(answer)
    // The window lets go of this job here: nothing after this line.
    done()
  }
}

/// The small sounds of the studio. The Rust core makes them and hands each of
/// them here once, as the bytes of a WAV file; macOS plays them. The other
/// side is lib/studio_sounds.dart. A sound is never worth an error: whatever
/// fails here is silence, and the answer `false`.
private final class EduPaintSounds {
  /// More sounds, or longer ones, than Color has are not Color's.
  private static let mostSounds = 64
  private static let mostBytes = 1 << 20
  private var sounds: [Int: NSSound] = [:]

  /// Starts the sound `id`, from its beginning. `wav` comes with the first
  /// request for a sound and is kept for the next ones. True when the sound
  /// was started; false also says that its bytes are wanted again.
  func play(id: Int, wav: Data?) -> Bool {
    guard id >= 0, id < EduPaintSounds.mostSounds else { return false }
    if let wav = wav {
      guard wav.count >= 44, wav.count <= EduPaintSounds.mostBytes,
            let sound = NSSound(data: wav) else {
        sounds[id] = nil
        return false
      }
      sounds[id] = sound
    }
    guard let sound = sounds[id] else { return false }
    // The same sound asked again while it plays starts again.
    if sound.isPlaying { _ = sound.stop() }
    return sound.play()
  }
}

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var filesChannel: FlutterMethodChannel?
  private var lifecycleChannel: FlutterMethodChannel?
  private var printChannel: FlutterMethodChannel?
  private var soundChannel: FlutterMethodChannel?
  private let sounds = EduPaintSounds()
  private var printJob: EduPaintPrintJob?
  private var diagnostics: EduPaintDiagnostics?
  private var lifecycleHandlerReady = false
  private let fileWriteQueue = DispatchQueue(label: "org.edupaint.files", qos: .userInitiated)
  private var closeRequestQueued = false

  func requestExitDecision(_ completion: @escaping (Bool) -> Void) {
    guard lifecycleHandlerReady, let channel = lifecycleChannel else {
      completion(false)
      return
    }
    channel.invokeMethod("requestExit", arguments: nil) { response in
      // Missing Dart handlers, malformed replies and platform errors all cancel.
      let reply = response as? [String: Any]
      let shouldExit = reply?["response"] as? String == "exit"
      DispatchQueue.main.async { completion(shouldExit) }
    }
  }

  override func performClose(_ sender: Any?) {
    requestApplicationClose()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // The native close button also consults the delegate. Never remove the
    // Flutter view before Dart can present and complete its save confirmation.
    requestApplicationClose()
    return false
  }

  private func requestApplicationClose() {
    guard !closeRequestQueued else { return }
    closeRequestQueued = true
    // Leave AppKit's close-button action before requesting an asynchronous
    // Flutter confirmation through the application's public lifecycle channel.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.closeRequestQueued = false
      NSApplication.shared.terminate(self)
    }
  }

  /// « Imprimer » : the picture of the sheet, handed to the print panel of
  /// macOS. The other side is lib/studio_printer.dart.
  private func printImage(arguments: Any?, result: @escaping FlutterResult) {
    guard printJob == nil, attachedSheet == nil else {
      result(FlutterError(code: "PRINT_BUSY",
                          message: "Un panneau est déjà ouvert sur la fenêtre.", details: nil))
      return
    }
    guard let values = arguments as? [String: Any],
          let bytes = values["rgba"] as? FlutterStandardTypedData,
          let width = values["width"] as? Int,
          let height = values["height"] as? Int,
          let name = values["name"] as? String,
          width > 0, height > 0, width <= 8192, height <= 8192,
          bytes.data.count == width * height * 4 else {
      result(FlutterError(code: "INVALID_ARGUMENT",
                          message: "Une image, sa taille et son nom sont nécessaires.", details: nil))
      return
    }
    // The engine keeps the bytes of the message only until the answer: the
    // image gets a copy of its own, which lives as long as the image does.
    let owned = bytes.data.withUnsafeBytes { buffer in
      Data(bytes: buffer.baseAddress!, count: buffer.count)
    }
    // Opaque pixels, four bytes each, rows from the top: the fourth byte is
    // not read.
    guard let provider = CGDataProvider(data: owned as CFData),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let pixels = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else {
      result(FlutterError(code: "PRINT_FAILED",
                          message: "L’image du dessin n’a pas pu être préparée.", details: nil))
      return
    }
    let image = NSImage(cgImage: pixels, size: NSSize(width: width, height: height))
    let job = EduPaintPrintJob(result: result) { [weak self] in self?.printJob = nil }
    printJob = job
    job.run(image: image, pixelsWide: width, pixelsHigh: height, name: name, window: self)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    let visibleSize = (self.screen ?? NSScreen.main)?.visibleFrame.size
    let initialWidth = min(1280, max(680, (visibleSize?.width ?? 1360) - 80))
    let initialHeight = min(850, max(520, (visibleSize?.height ?? 930) - 80))
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y,
                        width: initialWidth, height: initialHeight), display: true)
    self.minSize = NSSize(width: 680, height: 520)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(name: "org.edupaint/files",
                                      binaryMessenger: flutterViewController.engine.binaryMessenger)
    let writeQueue = fileWriteQueue
    channel.setMethodCallHandler { call, result in
      guard call.method == "writeAtomic" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String,
            let bytes = arguments["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT",
                            message: "Un chemin et des données binaires sont nécessaires.", details: nil))
        return
      }
      let data = bytes.data
      writeQueue.async {
        do {
          try EduPaintAtomicFileWriter.write(path: path, data: data)
          DispatchQueue.main.async { result(nil) }
        } catch {
          let fileError = error as NSError
          DispatchQueue.main.async {
            result(FlutterError(code: "WRITE_FAILED", message: fileError.localizedDescription,
                                details: ["domain": fileError.domain, "code": fileError.code]))
          }
        }
      }
    }
    filesChannel = channel
    lifecycleChannel = FlutterMethodChannel(name: "org.edupaint/lifecycle",
                                           binaryMessenger: flutterViewController.engine.binaryMessenger)
    lifecycleChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setHandlerReady" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let ready = call.arguments as? Bool else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a Boolean readiness state.", details: nil))
        return
      }
      self?.lifecycleHandlerReady = ready
      result(nil)
    }
    printChannel = FlutterMethodChannel(name: "org.edupaint/print",
                                        binaryMessenger: flutterViewController.engine.binaryMessenger)
    printChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "printImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let window = self else {
        result(FlutterError(code: "PRINT_FAILED",
                            message: "La fenêtre de Color n’existe plus.", details: nil))
        return
      }
      window.printImage(arguments: call.arguments, result: result)
    }
    soundChannel = FlutterMethodChannel(name: "org.edupaint/sound",
                                        binaryMessenger: flutterViewController.engine.binaryMessenger)
    soundChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "play" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let window = self,
            let values = call.arguments as? [String: Any],
            let id = values["id"] as? Int else {
        result(false)
        return
      }
      // The engine keeps the bytes of the message only until the answer:
      // the sound gets a copy of its own.
      var wav: Data?
      if let bytes = values["wav"] as? FlutterStandardTypedData {
        wav = bytes.data.withUnsafeBytes { buffer -> Data? in
          guard let base = buffer.baseAddress, buffer.count > 0 else { return nil }
          return Data(bytes: base, count: buffer.count)
        }
      }
      result(window.sounds.play(id: id, wav: wav))
    }

    super.awakeFromNib()
    self.delegate = self
    diagnostics = EduPaintDiagnostics(window: self,
      messenger: flutterViewController.engine.binaryMessenger)
  }
}

/// Opt-in observations only: never activates a window or requests a Flutter frame.
private final class EduPaintDiagnostics {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private let enabled = ProcessInfo.processInfo.arguments.contains("--edupaint-diagnostics") ||
    Bundle.main.url(forResource: "edupaint-diagnostics", withExtension: "enabled") != nil
  private let queue = DispatchQueue(label: "org.edupaint.diagnostics", qos: .utility)
  private var observers: [NSObjectProtocol] = []
  private var logURL: URL?

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "org.edupaint/diagnostics", binaryMessenger: messenger)
    if enabled {
      do {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
          in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("EduPaintStudy/diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("session-\(ProcessInfo.processInfo.processIdentifier).jsonl")
        try Data().write(to: url, options: .atomic)
        logURL = url
      } catch {
        NSLog("EduPaint diagnostics unavailable: %@", String(describing: error))
      }
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "configure":
        result(["enabled": self.enabled && self.logURL != nil,
                "path": self.logURL?.path ?? ""])
      case "record":
        if self.enabled, let payload = call.arguments as? [String: Any] {
          self.record(event: payload["event"] as? String ?? "dart", dart: payload)
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    guard enabled, logURL != nil else { return }
    let notifications: [Notification.Name] = [
      NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
      NSApplication.didChangeOcclusionStateNotification,
      NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification, NSWindow.didResizeNotification,
      NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
      NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
    ]
    for name in notifications {
      observers.append(NotificationCenter.default.addObserver(forName: name,
        object: nil, queue: .main) { [weak self] notification in
          guard let self = self else { return }
          if let changedWindow = notification.object as? NSWindow,
             changedWindow !== self.window { return }
          let event = notification.name.rawValue
          self.record(event: event)
          self.channel.invokeMethod("snapshot", arguments: event)
        })
    }
    record(event: "native-installed")
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    channel.setMethodCallHandler(nil)
  }

  private func record(event: String, dart: [String: Any]? = nil) {
    guard let url = logURL, let window = window else { return }
    var record: [String: Any] = [
      "timestamp": Date().timeIntervalSince1970,
      "event": event,
      "native": [
        "appActive": NSApp.isActive,
        "appVisible": NSApp.occlusionState.contains(.visible),
        "windowVisible": window.isVisible,
        "windowOcclusionVisible": window.occlusionState.contains(.visible),
        "windowKey": window.isKeyWindow,
        "windowMain": window.isMainWindow,
        "windowMiniaturized": window.isMiniaturized,
        "attachedSheet": window.attachedSheet != nil,
      ],
    ]
    if let dart = dart { record["dart"] = dart }
    guard var bytes = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
    bytes.append(0x0A)
    let output = bytes
    queue.async {
      // Bound an accidental long diagnostic session without touching documents.
      guard let handle = try? FileHandle(forWritingTo: url) else { return }
      defer { try? handle.close() }
      do {
        if try handle.seekToEnd() < 2 * 1024 * 1024 { try handle.write(contentsOf: output) }
      } catch { /* A diagnostic failure must not affect the drawing session. */ }
    }
  }
}
