import AVFoundation
import UserNotifications

/// Little 8-bit sounds for wins (made for PixyPump, so no licences needed).
/// They respect the silent switch and play over your music without stopping it.
@MainActor
enum SFX: String, CaseIterable {
    case setLogged = "sfx_set_logged"
    case duelWon = "sfx_set_duel_won"
    case record = "sfx_new_record"
    case mission = "sfx_mission_won"
    case streak = "sfx_streak_secured"
    case levelUp = "sfx_level_up"
    case gymBag = "sfx_gym_bag"
    case workoutComplete = "sfx_workout_complete"
    case restDone = "sfx_rest_timer_done"

    static let enabledKey = "soundsOn"
    static let volumeKey = "soundVolume"
    /// "8bit" (original), "arcade" or "soft".
    static let packKey = "soundPack"

    static let packs: [(id: String, name: String)] = [("8bit", "8-bit"), ("arcade", "Arcade"), ("soft", "Soft")]

    static var pack: String { UserDefaults.standard.string(forKey: packKey) ?? "8bit" }

    /// The sound file for the current pack ("sfx_arcade_level_up").
    var fileName: String {
        let pack = SFX.pack
        guard pack != "8bit" else { return rawValue }
        return "sfx_\(pack)_" + String(rawValue.dropFirst("sfx_".count))
    }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var volume: Float {
        let v = UserDefaults.standard.object(forKey: volumeKey) as? Double ?? 0.7
        return Float(min(max(v, 0), 1))
    }

    /// Cached players, per sound file.
    private static var players: [String: AVAudioPlayer] = [:]
    private static var sessionReady = false

    /// Plays a sound (if sounds are on).
    static func play(_ sound: SFX) {
        guard isEnabled else { return }
        if !sessionReady {
            // Ambient: silent switch mutes it, and it mixes with music instead of pausing it.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            sessionReady = true
        }
        guard let player = player(for: sound) else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// Loads every sound up front so the first one plays without a delay.
    static func preload() {
        for sound in allCases { _ = player(for: sound) }
    }

    private static func player(for sound: SFX) -> AVAudioPlayer? {
        let name = sound.fileName
        if let cached = players[name] { return cached }
        // Missing pack file: fall back to the original 8-bit sound.
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[name] = player
        return player
    }

    /// The rest-timer notification's sound: our chime when sounds are on, otherwise the iOS default.
    static var restNotificationSound: UNNotificationSound {
        let name = Bundle.main.url(forResource: SFX.restDone.fileName, withExtension: "wav") != nil
            ? SFX.restDone.fileName : SFX.restDone.rawValue
        guard isEnabled, Bundle.main.url(forResource: name, withExtension: "wav") != nil else {
            return .default
        }
        return UNNotificationSound(named: UNNotificationSoundName(name + ".wav"))
    }
}
