/// The steps that put a transcript into the target app, mirroring the CLI's
/// osascript delivery (bin/tmux-whisper process_inline_recording).
public enum DeliveryStep: Equatable, Sendable {
  case setClipboard(String)
  /// Re-activate the app that was frontmost when recording started.
  case activateOriginalApp
  case wait(milliseconds: Int)
  /// A key press with modifiers, as ANSI virtual key code + CGEventFlags-style mask.
  case key(code: UInt16, command: Bool, control: Bool)
}

public enum DeliveryPlan {
  public static let keyV: UInt16 = 9
  public static let keyReturn: UInt16 = 36
  public static let keyJ: UInt16 = 38

  public static func steps(text: String, delivery: Delivery, hasOriginalApp: Bool) -> [DeliveryStep] {
    var steps: [DeliveryStep] = [.setClipboard(text)]
    if delivery.pasteTarget == "restore" && hasOriginalApp {
      steps.append(.activateOriginalApp)
      if delivery.activateDelayMs > 0 {
        steps.append(.wait(milliseconds: delivery.activateDelayMs))
      }
    }
    steps.append(.key(code: keyV, command: true, control: false))
    guard delivery.autosend else { return steps }

    // Give the target app a moment to insert the paste before sending.
    if delivery.sendDelayMs > 0 {
      steps.append(.wait(milliseconds: delivery.sendDelayMs))
    }
    switch delivery.sendMode {
    case "ctrl_j":
      steps.append(.key(code: keyJ, command: false, control: true))
    case "cmd_enter":
      steps.append(.key(code: keyReturn, command: true, control: false))
    default:
      steps.append(.key(code: keyReturn, command: false, control: false))
    }
    return steps
  }
}
