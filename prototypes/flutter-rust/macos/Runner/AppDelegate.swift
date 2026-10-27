import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var terminationRequestPending = false
  private var terminationApproved = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationApproved { return .terminateNow }
    if terminationRequestPending { return .terminateCancel }
    guard let window = mainFlutterWindow as? MainFlutterWindow else {
      return .terminateCancel
    }
    terminationRequestPending = true
    window.requestExitDecision { [weak self] shouldExit in
      guard let self = self else { return }
      self.terminationRequestPending = false
      guard shouldExit else { return }
      self.terminationApproved = true
      DispatchQueue.main.async { NSApplication.shared.terminate(sender) }
    }
    // Keep the window available while Dart confirms and finishes file writes.
    // Repeated native requests cannot bypass this outstanding decision.
    return .terminateCancel
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
