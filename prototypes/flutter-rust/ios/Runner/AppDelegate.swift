// SPDX-License-Identifier: MIT
import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var native: ColorNative?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ColorNative") {
      native = ColorNative(registrar: registrar)
    }
  }
}

/// The window of Color. The gestures of the system that start at an edge of
/// the screen — going home, the control centre — wait for a second swipe, so
/// that a trait drawn near an edge stays a trait.
class ColorViewController: FlutterViewController {
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}

/// What only iOS does for Color: play its small sounds, print the sheet, and
/// put a copy of a file where the person chooses. The other side is in lib/:
/// studio_sounds.dart, studio_printer.dart and studio_files.dart. A sound is
/// never worth an error: whatever fails there is silence.
final class ColorNative: NSObject, UIDocumentPickerDelegate {
  private let registrar: FlutterPluginRegistrar
  private var channels: [FlutterMethodChannel] = []
  private var players: [Int: AVAudioPlayer] = [:]
  private var sessionReady = false
  private var pendingCopy: FlutterResult?
  private var printing = false

  /// More sounds, or longer ones, than Color has are not Color's.
  private static let mostSounds = 64
  private static let mostBytes = 1 << 20

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    let messenger = registrar.messenger()
    let sound = FlutterMethodChannel(name: "org.edupaint/sound", binaryMessenger: messenger)
    sound.setMethodCallHandler { [weak self] call, result in
      guard call.method == "play" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.play(call.arguments) ?? false)
    }
    let printer = FlutterMethodChannel(name: "org.edupaint/print", binaryMessenger: messenger)
    printer.setMethodCallHandler { [weak self] call, result in
      guard call.method == "printImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self else {
        result(FlutterError(code: "PRINT_FAILED", message: "Color n’est plus là.", details: nil))
        return
      }
      self.printImage(call.arguments, result: result)
    }
    let files = FlutterMethodChannel(name: "org.edupaint/files", binaryMessenger: messenger)
    files.setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveAs" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self else {
        result(nil)
        return
      }
      self.saveAs(call.arguments, result: result)
    }
    channels = [sound, printer, files]
  }

  /// The controller above which a panel of the system opens.
  private func presenter() -> UIViewController? {
    var top = registrar.viewController
    if top == nil {
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
      top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    }
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  // MARK: Sounds

  /// Starts the sound `id` from its beginning. `wav` comes with the first
  /// request for a sound and is kept for the next ones. True when the sound
  /// started; false also says that its bytes are wanted again.
  private func play(_ arguments: Any?) -> Bool {
    guard let values = arguments as? [String: Any],
          let id = values["id"] as? Int,
          id >= 0, id < ColorNative.mostSounds else { return false }
    if !sessionReady {
      // Ambient: the sounds of Color mix with whatever plays, and the
      // silent switch of the device silences them.
      try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
      sessionReady = true
    }
    if let bytes = values["wav"] as? FlutterStandardTypedData {
      // The engine keeps the bytes of the message only until the answer: the
      // sound gets a copy of its own.
      let owned = bytes.data.withUnsafeBytes { Data($0) }
      guard owned.count >= 44, owned.count <= ColorNative.mostBytes,
            let player = try? AVAudioPlayer(data: owned) else {
        players[id] = nil
        return false
      }
      player.prepareToPlay()
      players[id] = player
    }
    guard let player = players[id] else { return false }
    // The same sound asked again while it plays starts again.
    if player.isPlaying { player.stop() }
    player.currentTime = 0
    return player.play()
  }

  // MARK: Printing

  /// « Imprimer » : the print panel of iOS, one page, the picture as large as
  /// the paper allows. Nothing goes to a printer unless the person confirms.
  private func printImage(_ arguments: Any?, result: @escaping FlutterResult) {
    guard !printing else {
      result(FlutterError(code: "PRINT_BUSY", message: "Une impression est déjà ouverte.", details: nil))
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
    guard UIPrintInteractionController.isPrintingAvailable else {
      result(FlutterError(code: "NO_PRINTER",
                          message: "Cet appareil ne sait pas imprimer.", details: nil))
      return
    }
    // Opaque pixels, four bytes each, rows from the top: the fourth byte is
    // not read.
    let owned = bytes.data.withUnsafeBytes { Data($0) }
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
    let controller = UIPrintInteractionController.shared
    let info = UIPrintInfo(dictionary: nil)
    info.outputType = .photo
    info.orientation = width > height ? .landscape : .portrait
    info.jobName = name
    controller.printInfo = info
    controller.printingItem = UIImage(cgImage: pixels)
    printing = true
    let finished: UIPrintInteractionController.CompletionHandler = { [weak self] _, completed, error in
      self?.printing = false
      if let error = error {
        result(FlutterError(code: "PRINT_FAILED", message: error.localizedDescription, details: nil))
        return
      }
      result(completed ? "printed" : "cancelled")
    }
    if UIDevice.current.userInterfaceIdiom == .pad, let view = presenter()?.view {
      // On an iPad the panel points at the middle of the window.
      let middle = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
      _ = controller.present(from: middle, in: view, animated: true, completionHandler: finished)
    } else {
      _ = controller.present(animated: true, completionHandler: finished)
    }
  }

  // MARK: A copy where the person chooses

  /// « Exporter » : the panel of iOS where the person chooses a place — Files,
  /// iCloud Drive, another application — for a copy of the file at `path`,
  /// which waits in Color's temporary folder. The answer is the name of the
  /// copy, or nothing when the panel was closed.
  private func saveAs(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pendingCopy == nil else {
      result(FlutterError(code: "SAVE_BUSY", message: "Un panneau est déjà ouvert.", details: nil))
      return
    }
    guard let values = arguments as? [String: Any],
          let path = values["path"] as? String,
          FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "INVALID_ARGUMENT",
                          message: "Un fichier et son nom sont nécessaires.", details: nil))
      return
    }
    guard let presenter = presenter() else {
      result(FlutterError(code: "SAVE_FAILED",
                          message: "La fenêtre de Color est introuvable.", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: path)], asCopy: true)
    picker.delegate = self
    picker.shouldShowFileExtensions = true
    pendingCopy = result
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pendingCopy
    pendingCopy = nil
    result?(urls.first?.lastPathComponent ?? "")
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pendingCopy
    pendingCopy = nil
    result?(nil)
  }
}
