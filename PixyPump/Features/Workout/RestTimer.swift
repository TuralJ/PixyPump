import SwiftUI
import UIKit
import UserNotifications
import AudioToolbox
import AlarmKit

/// One rest timer for the whole app. It keeps running while you switch
/// exercises or tabs, and survives the app being in the background.
///
/// When rest is over:
/// - iOS 26+ with alarms allowed: a real system alarm rings (lock screen,
///   silent mode, keeps going until you tap "Done").
/// - Otherwise: a notification, plus repeated vibration while the app is open.
@MainActor @Observable
final class RestTimer {
    static let shared = RestTimer()

    private(set) var endDate: Date?
    private(set) var duration: TimeInterval = 0
    private(set) var isRinging = false
    /// What's coming after the rest ("Next: Set 3 · 40 kg × 8"), shown in the timer bar.
    var nextHint: String?
    /// Exercise this rest belongs to, so +30 / −30 is remembered for it (see `RestPlan`).
    private(set) var restExercise: String?

    private var waitTask: Task<Void, Never>?
    private var alarmTask: Task<Void, Never>?
    private var systemAlarmID: UUID?
    private var usesSystemAlarm = false
    private let notificationID = "rest-timer"

    private init() {
        // Pick up a timer that was running when the app was closed.
        let defaults = UserDefaults.standard
        restExercise = defaults.string(forKey: "restExercise")
        defaults.removeObject(forKey: "lockScreenSet.v1")   // from the removed lock-screen button
        if let saved = defaults.string(forKey: "restTimerAlarmID") {
            systemAlarmID = UUID(uuidString: saved)
            usesSystemAlarm = systemAlarmID != nil
        }
        let savedEnd = defaults.double(forKey: "restTimerEnd")
        if savedEnd > 0, Date(timeIntervalSince1970: savedEnd) > .now {
            duration = defaults.double(forKey: "restTimerDuration")
            schedule(end: Date(timeIntervalSince1970: savedEnd), alert: false)
        }
    }

    var isRunning: Bool { endDate != nil }

    func start(seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: Prefs.restSeconds)   // remembered for auto-start
        stopAlarm()
        // A rest picked by hand isn't any exercise's rest, so +30 / −30 isn't remembered for one.
        setRestExercise(nil)
        duration = TimeInterval(seconds)
        schedule(end: .now.addingTimeInterval(duration), alert: true)
    }

    /// Rest after a set of `exercise`: its own length (big lifts longer, small moves shorter).
    /// Doesn't change your default length in Settings.
    func start(for exercise: String) {
        stopAlarm()
        setRestExercise(exercise)
        duration = TimeInterval(RestPlan.seconds(for: exercise))
        schedule(end: .now.addingTimeInterval(duration), alert: true)
    }

    /// Kept on disk too, so a rest picked up after the app was closed still remembers +30 / −30.
    private func setRestExercise(_ name: String?) {
        restExercise = name
        if let name {
            UserDefaults.standard.set(name, forKey: "restExercise")
        } else {
            UserDefaults.standard.removeObject(forKey: "restExercise")
        }
    }

    /// Starts (or restarts) the timer with the last length you used (default 1:30).
    func startPreferred() {
        let saved = UserDefaults.standard.integer(forKey: Prefs.restSeconds)
        start(seconds: saved > 0 ? saved : 90)
    }

    /// Adds (or with a negative number, takes off) rest time.
    /// Taking time off never leaves less than 5 seconds, so the alarm still has time to ring.
    func addTime(seconds: Int) {
        guard let end = endDate else { return }
        let newEnd = max(end.addingTimeInterval(TimeInterval(seconds)), Date.now.addingTimeInterval(5))
        duration = max(duration + newEnd.timeIntervalSince(end), 1)
        schedule(end: newEnd, alert: true)
        // Next time this exercise rests this long (until you change it again).
        if let restExercise { RestPlan.remember(Int(duration.rounded()), for: restExercise) }
    }

    /// Puts a stopped timer back as it was (Undo after ×).
    func resume(until end: Date, duration: TimeInterval, hint: String?, exercise: String?) {
        guard end > .now else { return }
        stopAlarm()
        self.duration = duration
        nextHint = hint
        setRestExercise(exercise)
        schedule(end: end, alert: true)
    }

    func stop() {
        nextHint = nil
        setRestExercise(nil)
        waitTask?.cancel()
        endDate = nil
        clearSaved()
        stopAlarm()
        cancelAlerts()
    }

    /// Stops the vibration / ringing (the "OK" button).
    func stopAlarm() {
        alarmTask?.cancel()
        isRinging = false
        cancelSystemAlarm()
    }

    // MARK: - Internals

    private func schedule(end: Date, alert: Bool) {
        endDate = end
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: "restTimerEnd")
        UserDefaults.standard.set(duration, forKey: "restTimerDuration")

        waitTask?.cancel()
        waitTask = Task { [weak self] in
            let delay = end.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.finish(lateBy: -end.timeIntervalSinceNow)
        }

        if alert { scheduleAlerts(at: end) }
    }

    private func finish(lateBy: TimeInterval) {
        endDate = nil
        clearSaved()
        guard lateBy < 3, UIApplication.shared.applicationState == .active else { return }
        isRinging = true
        // The system alarm does its own ringing; otherwise chime and vibrate here.
        if !usesSystemAlarm {
            SFX.play(.restDone)
            vibrateLikeAlarm()
        }
    }

    /// Vibrates every second until you tap "OK" (stops by itself after a minute).
    private func vibrateLikeAlarm() {
        alarmTask?.cancel()
        alarmTask = Task { [weak self] in
            for _ in 0..<60 {
                guard !Task.isCancelled else { return }
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .seconds(1))
            }
            self?.isRinging = false
        }
    }

    private func clearSaved() {
        UserDefaults.standard.removeObject(forKey: "restTimerEnd")
    }

    // MARK: Alerts (system alarm, falling back to a notification)

    private func scheduleAlerts(at end: Date) {
        cancelAlerts()
        Task {
            if #available(iOS 26.0, *), RestAlarm.isConfigured, await RestAlarm.isAllowed() {
                let id = UUID()
                if await RestAlarm.schedule(id: id, at: end) {
                    systemAlarmID = id
                    usesSystemAlarm = true
                    UserDefaults.standard.set(id.uuidString, forKey: "restTimerAlarmID")
                    return
                }
            }
            usesSystemAlarm = false
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            scheduleNotification(at: end)
        }
    }

    private func cancelAlerts() {
        cancelSystemAlarm()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }

    private func cancelSystemAlarm() {
        guard let id = systemAlarmID else { return }
        systemAlarmID = nil
        usesSystemAlarm = false
        UserDefaults.standard.removeObject(forKey: "restTimerAlarmID")
        if #available(iOS 26.0, *), RestAlarm.isConfigured { RestAlarm.cancel(id: id) }
    }

    private func scheduleNotification(at end: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Rest's over 💪"
        content.body = "Time for your next set."
        content.sound = SFX.restNotificationSound
        // Break through Focus modes where iOS allows it, so you don't miss the end of your rest.
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID,
                                            content: content, trigger: trigger)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}

// MARK: - System alarm (AlarmKit, iOS 26+)

@available(iOS 26.0, *)
nonisolated struct RestAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
@MainActor
enum RestAlarm {
    /// iOS kills the app if alarms are used without the NSAlarmKitUsageDescription
    /// text in the project's Info settings — so check first and fall back if missing.
    static var isConfigured: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") != nil
    }

    /// Asks once for permission to set alarms; remembers the answer.
    static func isAllowed() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        default:
            return false
        }
    }

    static func schedule(id: UUID, at date: Date) async -> Bool {
        let doneButton = AlarmButton(text: "Done",
                                     textColor: .white,
                                     systemImageName: "checkmark.circle.fill")
        let alert = AlarmPresentation.Alert(title: "Rest's over 💪", stopButton: doneButton)
        let attributes = AlarmAttributes<RestAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: RestAlarmMetadata(),
            tintColor: Color.brand)
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(date),
            attributes: attributes)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    static func cancel(id: UUID) {
        try? AlarmManager.shared.stop(id: id)
        try? AlarmManager.shared.cancel(id: id)
    }
}

/// How you'll hear that rest is over — shown in Settings so a muted timer never surprises you.
nonisolated enum RestAlertStatus: Sendable {
    case alarm          // real system alarm (rings even on silent)
    case notification   // notification with sound
    case off            // notifications turned off for PixyPump
    case unknown        // not asked yet (asked when the first timer starts)

    @MainActor
    static func current() async -> RestAlertStatus {
        if #available(iOS 26.0, *), RestAlarm.isConfigured,
           AlarmManager.shared.authorizationState == .authorized {
            return .alarm
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .notification
        case .denied: return .off
        default: return .unknown
        }
    }

    var title: String {
        switch self {
        case .alarm: return "Rest alert: alarm"
        case .notification: return "Rest alert: notification"
        case .off: return "Rest alerts are off"
        case .unknown: return "Rest alerts: not set up yet"
        }
    }

    var detail: String {
        switch self {
        case .alarm: return "Rings even on silent and on the lock screen."
        case .notification: return "Plays your notification sound. On silent you'll only feel a buzz."
        case .off: return "You won't hear when rest is over while the app is closed. Turn notifications on in the iPhone Settings."
        case .unknown: return "\(AppInfo.name) asks for permission the first time a rest timer starts."
        }
    }
}

/// Lets the "Rest's over" pop-up show even while the app is open.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// Slim timer bar at the bottom of the screen. It only appears while the timer
/// is running or ringing; when idle it takes up no space at all.
struct RestTimerBar: View {
    private let timer = RestTimer.shared
    /// Plate Stack, the rest-time game.
    @State private var playing = false

    var body: some View {
        VStack(spacing: 0) {
            // Always here (even with the bar hidden) so the game stays open when the rest ends.
            Color.clear
                .frame(height: 0)
                .fullScreenCover(isPresented: $playing) { PlateStackView() }
            bar
        }
    }

    @ViewBuilder
    private var bar: some View {
        if timer.isRinging {
            HStack(spacing: 10) {
                Image.pixel(.bell, size: 16)
                Text("Rest's over 💪")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                Spacer()
                Button { Haptics.tap(); withAnimation { timer.stopAlarm() } } label: {
                    Text("OK")
                        .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                        .foregroundStyle(Color.ppOnAccent)
                        .padding(.horizontal, 18)
                        .frame(minWidth: 64, minHeight: 44)
                        .background(Color.ppDone, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("OK, stop the rest alarm")
            }
            .foregroundStyle(Color.ppDone)
            .modifier(SlimBarStyle(progress: nil))
            .breathe(true, amount: 0.02)
            .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.8)).combined(with: .opacity))
        } else if let end = timer.endDate {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, end.timeIntervalSince(context.date))
                let secondsLeft = Int(remaining.rounded(.up))
                let finalCountdown = secondsLeft <= 5 && secondsLeft > 0
                HStack(spacing: 10) {
                    RestSkinIcon(skin: RestSkin.current,
                                 left: remaining / max(timer.duration, 1),
                                 warn: finalCountdown)
                    Text(RestTimerBar.format(secondsLeft))
                        .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                        .foregroundStyle(finalCountdown ? Color.ppFlame : Color.ppText)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.3), value: secondsLeft)
                        // Last 5 seconds: each tick gives a small bounce (and a tap, below).
                        .popOnChange(of: finalCountdown ? secondsLeft : 0, scale: 1.25)
                        .onChange(of: secondsLeft) { _, left in
                            if left <= 5 && left > 0 { Haptics.tap() }
                        }
                    Text(timer.nextHint ?? "rest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(-1)   // the buttons keep their size; the hint shortens
                    Spacer(minLength: DS.Space.xs)
                    // The two everyday actions, always visible…
                    Button { Haptics.tap(); timer.addTime(seconds: 30) } label: {
                        Text("+30")
                            .font(.pixel(DS.TextSize.subhead, relativeTo: .subheadline))
                            .modifier(BarButtonLook())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("Add 30 seconds")
                    Button { stopWithUndo() } label: {
                        Image.pixel(.close, size: 16)
                            .modifier(BarButtonLook())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("Stop rest timer")
                    // …and the extras in "···".
                    Menu {
                        Button { Haptics.tap(); playing = true } label: {
                            Label("Play Plate Stack", systemImage: "gamecontroller.fill")
                        }
                        Button { Haptics.tap(); timer.addTime(seconds: -30) } label: {
                            Label("−30 s", systemImage: "minus")
                        }
                    } label: {
                        Image.pixel(.more, size: 16)
                            .modifier(BarButtonLook())
                    }
                    .fixedSize()
                    .accessibilityLabel("More rest timer options")
                }
                .tint(Color.ppText)
                .modifier(SlimBarStyle(progress: remaining / max(timer.duration, 1)))
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// × stops the rest straight away; a mis-tap can be undone from the toast.
    private func stopWithUndo() {
        guard let end = timer.endDate else { return }
        let duration = timer.duration
        let hint = timer.nextHint
        let exercise = timer.restExercise
        Haptics.tap()
        withAnimation { timer.stop() }
        UndoCenter.shared.show("Rest timer stopped") {
            withAnimation { RestTimer.shared.resume(until: end, duration: duration, hint: hint, exercise: exercise) }
        }
    }

    static func format(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// Round 44 pt button look for the timer bar (big enough to hit mid-workout).
private struct BarButtonLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.ppText)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.ppLine.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Capsule look for the slim bar, with an optional thin progress line along the bottom.
private struct SlimBarStyle: ViewModifier {
    let progress: Double?

    func body(content: Content) -> some View {
        content
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 54)
            .glassCapsule()
            .overlay(alignment: .bottom) {
                if let progress {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.brand)
                            .frame(width: geo.size.width * min(max(progress, 0), 1), height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.horizontal, 18)
                    .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }
}

private extension View {
    /// Liquid glass capsule (frosted material on older iOS).
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }
}

/// Small ⏱ button for the top bar: start a rest timer by hand.
struct RestTimerMenu: View {
    private let timer = RestTimer.shared
    /// Same choices everywhere: 1:00, 1:30, 2:00, 2:30, 3:00.
    static let presets = [60, 90, 120, 150, 180]

    var body: some View {
        Menu {
            Section("Start rest timer") {
                ForEach(Self.presets, id: \.self) { seconds in
                    Button(RestTimerBar.format(seconds)) {
                        Haptics.press()
                        timer.nextHint = nil
                        withAnimation { timer.start(seconds: seconds) }
                    }
                }
            }
        } label: {
            Image.pixel(.clock)
        }
        .accessibilityLabel("Rest timer")
    }
}

/// The little picture at the start of the rest timer bar (Settings → Appearance → Rest timer).
struct RestSkinIcon: View {
    let skin: RestSkin
    /// 1 = rest just started, 0 = done.
    let left: Double
    var warn = false

    var body: some View {
        switch skin {
        case .bar:
            Image.pixel(.clock, size: 16)
                .foregroundStyle(warn ? Color.ppFlame : .secondary)
        case .hourglass:
            Canvas { context, size in
                let px = size.width / 9
                func cell(_ x: Int, _ y: Int, _ c: Color) {
                    context.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(c))
                }
                let frame: Color = warn ? .ppFlame : .secondary
                let sand = Color.ppFat
                // Caps
                for x in 0..<9 { cell(x, 0, frame); cell(x, 12, frame) }
                // Glass sides narrowing to the middle (rows 1…11).
                let widths = [7, 7, 5, 3, 1, 1, 1, 3, 5, 7, 7]
                let fillTop = Int((Double(5) * min(max(left, 0), 1)).rounded())
                let fillBottom = 5 - fillTop
                for (i, w) in widths.enumerated() {
                    let y = i + 1
                    let start = (9 - w) / 2
                    cell(start - 1, y, frame)
                    cell(start + w, y, frame)
                    // Sand: top half drains, bottom half fills.
                    let topRow = y >= 1 && y <= 5 && (6 - y) <= fillTop
                    let bottomRow = y >= 7 && y <= 11 && (y - 6) > 5 - fillBottom
                    if topRow || bottomRow {
                        for x in start..<(start + w) { cell(x, y, sand) }
                    }
                }
                if left > 0.02 { cell(4, 6, sand) }   // the falling grain
            }
            .frame(width: 13, height: 19)
        case .barbell:
            // Plates load onto the bar as the rest runs out.
            let loaded = Int(((1 - min(max(left, 0), 1)) * 4).rounded(.down))
            let colors = PlateColors.current
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { i in
                    plate(on: 3 - i < loaded, color: colors.color(3 - i), height: 8 + CGFloat(3 - i) * 3)
                }
                Rectangle().fill(Color.secondary).frame(width: 10, height: 3)
                ForEach(0..<4, id: \.self) { i in
                    plate(on: i < loaded, color: colors.color(i), height: 8 + CGFloat(i) * 3)
                }
            }
            .frame(height: 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: loaded)
        }
    }

    private func plate(on: Bool, color: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(on ? color : Color.secondary.opacity(0.2))
            .frame(width: 3, height: height)
    }
}
