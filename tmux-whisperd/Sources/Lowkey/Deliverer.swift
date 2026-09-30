import AppKit
import ApplicationServices
import Foundation
import LowkeyCore

/// Executes a DeliveryPlan: clipboard, optional re-activation, and synthetic
/// key presses via CGEvent (needs the Accessibility permission).
enum Deliverer {
  static func isTrusted(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Runs on a background queue; waits are real sleeps between steps.
  static func perform(_ steps: [DeliveryStep], originalApp: NSRunningApplication?) throws {
    guard isTrusted(prompt: false) else {
      throw NSError(domain: "Lowkey", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Accessibility permission missing: text is on the clipboard (System Settings → Privacy & Security → Accessibility → Lowkey)",
      ])
    }
    for step in steps {
      switch step {
      case .setClipboard(let text):
        DispatchQueue.main.sync {
          let board = NSPasteboard.general
          board.clearContents()
          board.setString(text, forType: .string)
        }
      case .activateOriginalApp:
        DispatchQueue.main.sync {
          _ = originalApp?.activate()
        }
      case .wait(let milliseconds):
        usleep(useconds_t(milliseconds * 1000))
      case .key(let code, let command, let control):
        postKey(code: code, command: command, control: control)
      }
    }
  }

  private static func postKey(code: UInt16, command: Bool, control: Bool) {
    let source = CGEventSource(stateID: .combinedSessionState)
    var flags: CGEventFlags = []
    if command { flags.insert(.maskCommand) }
    if control { flags.insert(.maskControl) }
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }
}
