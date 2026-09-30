import AVFoundation
import Foundation
import LowkeyCore

/// Preloaded sound effects, so the start chime plays in milliseconds instead
/// of the ~0.3-0.9 s an `afplay` process needs.
final class SoundPlayer {
  enum Event: String, CaseIterable {
    case start, stop, process, error, cancel
  }

  private var players: [Event: AVAudioPlayer] = [:]

  func load(from config: AppConfig) {
    players.removeAll()
    for event in Event.allCases {
      guard let sound = config.sounds[event.rawValue], sound.enabled, let path = sound.path else { continue }
      do {
        let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        player.prepareToPlay()
        players[event] = player
      } catch {
        Log.write("sound: cannot load \(event.rawValue) from \(path): \(error.localizedDescription)")
      }
    }
  }

  func play(_ event: Event) {
    guard let player = players[event] else { return }
    player.stop()
    player.currentTime = 0
    player.play()
  }
}
