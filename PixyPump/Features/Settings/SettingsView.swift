import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

/// Settings, grouped the way people look for things:
/// Profile → Training → Food → Look & Buddy → Notifications → Data & privacy → About (→ Developer).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(Prefs.autoRest) private var autoRest = true
    @AppStorage(Prefs.restSeconds) private var restSeconds = 90
    /// Some exercises have their own rest length (changed with +30 / −30 on the timer).
    @State private var hasCustomRest = RestPlan.hasCustom
    private let restFooter = "The rest timer starts when you log a set. Big lifts (squat, bench, deadlift…) rest 1 min longer and small moves (curls, raises…) 30 s shorter. Using +30 or −30 on the timer remembers the new length for that exercise."
    @AppStorage(Prefs.haptics) private var hapticsOn = true
    @AppStorage(Backup.lastBackupKey) private var lastBackupAt = 0.0
    @AppStorage("goalKcal") private var goalKcal = 2500.0
    @AppStorage("goalProtein") private var goalProtein = 160.0
    @AppStorage("goalCarbs") private var goalCarbs = 280.0
    @AppStorage("goalFat") private var goalFat = 75.0

    @State private var backupURL: URL?
    @State private var showImporter = false
    @State private var showGoals = false
    @State private var showPlan = false
    @State private var showPlanBuilder = false
    @AppStorage(Prefs.lengthUnit) private var lengthRaw = "cm"
    @State private var message: String?
    @State private var exportURLs: [URL] = []
    @State private var confirmDelete = false
    @AppStorage(DailyStreak.reminderKey) private var streakReminder = true
    @AppStorage("notif.training") private var notifTraining = true
    @AppStorage("notif.rewards") private var notifRewards = true
    @AppStorage("notif.missions") private var notifMissions = true
    @AppStorage("notif.food") private var notifFood = true
    @AppStorage("notif.comeback") private var notifComeback = true
    @AppStorage(SFX.enabledKey) private var soundsOn = true
    @AppStorage(SFX.volumeKey) private var soundVolume = 0.7
    @AppStorage(SFX.packKey) private var soundPack = "8bit"
    @State private var deleting = false
    @AppStorage(Prefs.userName) private var userName = ""
    @AppStorage(HealthSync.enabledKey) private var healthOn = false
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.kg.rawValue
    @AppStorage(DevMode.unlockAllKey) private var unlockAll = false
    // Watched so Settings itself redraws in a new look when you come back from Appearance.
    @AppStorage(AppTheme.accentKey) private var accentID = "ice"
    @AppStorage(AppTheme.surfaceKey) private var surfaceID = "midnight"
    @AppStorage(AppTheme.headingKey) private var headings = "pixel"
    @State private var alertStatus: RestAlertStatus?
    @Environment(\.scenePhase) private var scenePhase

    /// Same choices as the rest timer's own menu (1:00 to 3:00, in 30-second steps).
    private let restOptions = [60, 90, 120, 150, 180]

    private var lastBackupText: String {
        guard lastBackupAt > 0 else { return "You haven't made a backup yet." }
        let date = Date(timeIntervalSince1970: lastBackupAt)
        return "Last backup: " + date.formatted(.relative(presentation: .named))
    }

    /// Backed up in the last 7 days?
    private var backupIsRecent: Bool {
        lastBackupAt > 0 && Date.now.timeIntervalSince1970 - lastBackupAt < 7 * 24 * 3600
    }

    private func macro(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter).foregroundStyle(color)
            Text("\(Int(grams))g").foregroundStyle(Color.ppText.opacity(0.8))
        }
        .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
    }

    /// A tappable row that opens a sheet: icon, title, optional value on the right, chevron.
    private func sheetRow(_ title: String, icon: PixelGlyph, value: String? = nil,
                          action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack {
                Label { Text(title) } icon: { Image.pixel(icon) }
                Spacer()
                if let value {
                    Text(value)
                        .font(.pixel(DS.TextSize.subhead))
                        .foregroundStyle(.secondary)
                }
                Image.pixel(.chevronRight, size: 16)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        // Reading the look here makes Settings redraw with it (see the @AppStorage notes above).
        let _ = (accentID, surfaceID, headings)
        NavigationStack {
            Form {
                AccountSection()
                profileSection
                trainingSection
                foodSection
                lookSection
                notificationsSection
                dataSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .ppScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all your data?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                if HealthSync.isConfigured && (HealthSync.isEnabled || HealthSync.hasSavedWorkouts) {
                    Button("Delete everything + Apple Health workouts", role: .destructive) {
                        deleteMyData(includingHealth: true)
                    }
                }
                Button("Delete everything", role: .destructive) {
                    deleteMyData(includingHealth: false)
                }
                Button("Keep my data", role: .cancel) {}
            } message: {
                Text("Workouts, food, body weight, your plan, buddy, progress and settings will be erased from this iPhone. This can't be undone, so make a backup first if you might want it back.")
            }
            .onChange(of: unitRaw) { _, _ in exportURLs = [] }   // re-export in the new unit
            .task { alertStatus = await RestAlertStatus.current() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { alertStatus = await RestAlertStatus.current() } }
            }
            .sheet(isPresented: $showGoals) { GoalsView() }
            .sheet(isPresented: $showPlan) { RoutineEditorView() }
            .sheet(isPresented: $showPlanBuilder) { PlanBuilderSheet() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        message = try Backup.restore(from: url, context: context).text
                        RoutineStore.shared.reloadFromDisk()
                    } catch {
                        message = error.localizedDescription
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .alert("Backup", isPresented: Binding(get: { message != nil },
                                                  set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
        // A new look (Settings → Appearance) is applied to the whole app once Settings closes.
        // Not sooner on purpose: redrawing the tabs would also close this sheet mid-edit,
        // because Settings is opened from inside those tabs.
        // (On the stack itself, so opening a sub-page doesn't trigger it.)
        .onDisappear { NotificationCenter.default.post(name: .appearanceMayHaveChanged, object: nil) }
    }

    // MARK: Sections

    /// 1. Profile: who you are and the units you think in.
    private var profileSection: some View {
        Section {
            HStack {
                Text("Your name")
                TextField("Optional", text: $userName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .frame(minHeight: 44)
            Picker("Weights in", selection: $unitRaw) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .hapticOnChange(of: unitRaw)
            Picker("Body measurements in", selection: $lengthRaw) {
                Text("cm").tag("cm")
                Text("in").tag("in")
            }
        } header: {
            PPHeader("Profile")
        } footer: {
            Text("Weights are always saved precisely, so switching between kg and lb never changes your history.")
        }
        .listRowBackground(Color.ppCard)
    }

    /// 2. Training: your plan, the rest timer and what you see while lifting.
    private var trainingSection: some View {
        Section {
            sheetRow("Training plan", icon: .calendar,
                     value: Routine.dayCount == 1 ? "1 day" : "\(Routine.dayCount) days") { showPlan = true }
            sheetRow("Build a new plan for me", icon: .zap) { showPlanBuilder = true }
            Toggle("Start rest timer after each set", isOn: $autoRest)
                .hapticOnChange(of: autoRest)
            Picker("Usual rest", selection: $restSeconds) {
                ForEach(restOptions, id: \.self) { seconds in
                    Text("\(seconds / 60):" + String(format: "%02d", seconds % 60)).tag(seconds)
                }
            }
            if hasCustomRest {
                Button {
                    Haptics.tap()
                    RestPlan.resetAll()
                    hasCustomRest = false
                    UndoCenter.shared.show("Rest lengths reset")
                } label: {
                    Label { Text("Reset rest per exercise") } icon: { Image.pixel(.reload) }
                }
            }
            if let alertStatus {
                restAlertRow(alertStatus)
            }
            Toggle(isOn: Binding(
                get: { healthOn },
                set: { on in
                    healthOn = on
                    if on { Task { _ = await HealthSync.requestAccess() } }
                })) {
                Label { Text("Save workouts to Apple Health") } icon: { Image.pixel(.heart) }
            }
            .disabled(!HealthSync.isConfigured)
        } header: {
            PPHeader("Training")
        } footer: {
            Text(HealthSync.isConfigured
                 ? restFooter
                 : restFooter + " Apple Health needs a one-time setup in Xcode.")
        }
        .listRowBackground(Color.ppCard)
    }

    /// 3. Food: your daily calorie and macro goals.
    private var foodSection: some View {
        Section {
            Button { Haptics.tap(); showGoals = true } label: {
                HStack(spacing: 14) {
                    Image.pixel(.target, size: 32)
                        .foregroundStyle(Color.brand)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(goalKcal).spaced) kcal")
                            .font(.pixel(DS.TextSize.title3, relativeTo: .title2))
                            .foregroundStyle(Color.ppText)
                        HStack(spacing: 10) {
                            macro("P", goalProtein, .ppProtein)
                            macro("C", goalCarbs, .ppCarbs)
                            macro("F", goalFat, .ppFat)
                        }
                    }
                    Spacer(minLength: 0)
                    Image.pixel(.chevronRight, size: 16)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Daily calorie goals: \(Int(goalKcal)) kilocalories")
            .accessibilityHint("Change your goals or use the calculator")
        } header: {
            PPHeader("Food")
        } footer: {
            Text("Your daily calorie goals. Tap to change them or use the calculator.")
        }
        .listRowBackground(Color.ppCard)
    }

    /// 4. Look & Buddy: how PixyPump looks, sounds and feels.
    private var lookSection: some View {
        Section {
            NavigationLink {
                BuddyEditorView()
            } label: {
                HStack(spacing: 12) {
                    PixelBuddy(size: 32, animated: false)
                    Text("Customise your buddy")
                }
                .frame(minHeight: 44)
            }
            NavigationLink {
                AppearanceView()
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(Color.brand).frame(width: 22, height: 22)
                        .frame(width: 32)
                    Text("Appearance")
                }
                .frame(minHeight: 44)
            }
            Toggle("Sound effects", isOn: $soundsOn)
                .hapticOnChange(of: soundsOn)
                .onChange(of: soundsOn) { _, on in if on { SFX.play(.mission) } }
            if soundsOn {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $soundVolume, in: 0.1...1, onEditingChanged: { editing in
                        if !editing { SFX.play(.duelWon) }   // hear the new volume
                    })
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sound volume")
                // Same moments, different flavour. Plays a sample when you switch.
                Picker("Sound style", selection: $soundPack) {
                    ForEach(SFX.packs, id: \.id) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .onChange(of: soundPack) { _, _ in SFX.play(.levelUp) }
            }
            Toggle("Vibrate on taps", isOn: $hapticsOn)
                .hapticOnChange(of: hapticsOn)
        } header: {
            PPHeader("Look & Buddy")
        } footer: {
            Text("A new look applies to the whole app when you close Settings.")
        }
        .listRowBackground(Color.ppCard)
    }

    /// 5. Notifications: each kind can be switched off.
    private var notificationsSection: some View {
        Section {
            Toggle("Streak alerts (20:00, last call 22:00)", isOn: $streakReminder)
                .onChange(of: streakReminder) { _, on in
                    // Off: drop tonight's alerts now. On: they're scheduled next time the streak updates.
                    if !on { DailyStreak.cancelReminder() }
                }
            Toggle(NotificationPlanner.Kind.training.title, isOn: $notifTraining)
            Toggle(NotificationPlanner.Kind.rewards.title, isOn: $notifRewards)
            Toggle(NotificationPlanner.Kind.missions.title, isOn: $notifMissions)
            Toggle(NotificationPlanner.Kind.food.title, isOn: $notifFood)
            Toggle(NotificationPlanner.Kind.comeback.title, isOn: $notifComeback)
        } header: {
            PPHeader("Notifications")
        } footer: {
            Text("At most one nudge a day besides streak alerts, and never between 22:30 and 8:00. Training reminders come at the time you usually train.")
        }
        .listRowBackground(Color.ppCard)
        .onChange(of: [notifTraining, notifRewards, notifMissions, notifFood, notifComeback]) { _, _ in
            // Rebuilt with the new choices when you leave the app.
            NotificationPlanner.cancelAll()
        }
    }

    /// 6. Data & privacy: backup first (it protects your history), then export, legal and delete.
    private var dataSection: some View {
        Section {
            HStack(spacing: 10) {
                Image.pixel(lastBackupAt > 0 ? .check : .warning, size: 16)
                Text(lastBackupText)
            }
            .font(.subheadline)
            .foregroundStyle(backupIsRecent ? Color.ppDone : Color.ppCarbs)
            if let backupURL {
                ShareLink(item: backupURL) {
                    Label { Text("Save or send the backup") } icon: { Image.pixel(.upload) }
                }
            } else {
                Button {
                    createBackup()
                } label: {
                    Label { Text("Create backup") } icon: { Image.pixel(.save) }
                }
            }
            Button {
                showImporter = true
            } label: {
                Label { Text("Restore from backup…") } icon: { Image.pixel(.reload) }
            }
            if exportURLs.isEmpty {
                Button {
                    do {
                        exportURLs = try DataTools.exportCSV(context: context)
                        Haptics.success()
                    } catch {
                        message = "Couldn't create the export: \(error.localizedDescription)"
                    }
                } label: {
                    Label { Text("Export as spreadsheet (CSV)") } icon: { Image.pixel(.copy) }
                }
            } else {
                ShareLink(items: exportURLs) {
                    Label { Text("Save or send the \(exportURLs.count) CSV files") } icon: { Image.pixel(.upload) }
                }
            }
            NavigationLink {
                LegalView(document: .privacy)
            } label: {
                Label { Text("Privacy Policy") } icon: { Image.pixel(.eye) }
            }
            NavigationLink {
                LegalView(document: .terms)
            } label: {
                Label { Text("Terms of Use") } icon: { Image.pixel(.list) }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label { Text(deleting ? "Deleting…" : "Delete my data…") } icon: { Image.pixel(.trash) }
            }
            .disabled(deleting)
        } header: {
            PPHeader("Data & privacy")
        } footer: {
            Text("A backup is one file with everything: save it to Files (iCloud Drive) to keep it safe, or to move to a new phone. Restoring never deletes anything. The CSV export is for spreadsheets (Numbers, Excel).\n\nYour data lives on this iPhone (an account is optional). Deleting it erases everything here, and optionally the workouts \(AppInfo.name) saved to Apple Health.")
        }
        .listRowBackground(Color.ppCard)
    }

    /// 7. About.
    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label { Text("About & credits") } icon: { Image.pixel(.more) }
            }
        } header: {
            PPHeader("About")
        }
        .listRowBackground(Color.ppCard)
    }

    #if DEBUG
    /// Owner only: Debug builds from Xcode. Never in the App Store version.
    private var developerSection: some View {
        Section {
            Toggle("Unlock everything", isOn: $unlockAll)
                .tint(Color.brand)
        } header: {
            PPHeader("Developer")
        } footer: {
            Text("All buddy items, gear and colours, no levels needed. Only in builds run from Xcode.")
        }
        .listRowBackground(Color.ppCard)
    }
    #endif

    /// Erases everything (Health first, while we still know it was used), then closes Settings.
    private func deleteMyData(includingHealth: Bool) {
        Haptics.warning()
        deleting = true
        Task {
            if includingHealth { _ = await HealthSync.deleteSavedWorkouts() }
            DataTools.deleteEverything(context: context)
            deleting = false
            dismiss()
        }
    }

    /// Shows how the rest timer will alert you, with a fix if it can't.
    private func restAlertRow(_ status: RestAlertStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image.pixel(status == .off ? .warning : .bell, size: 16)
                Text(status.title)
            }
            .foregroundStyle(status == .off ? Color.ppCarbs : (status == .unknown ? Color.ppText : Color.ppDone))
            Text(status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status == .off {
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.pixel(DS.TextSize.subhead))
                .frame(minHeight: 44)
                .buttonStyle(.borderless)
            } else if status == .unknown {
                Button("Allow rest alerts") {
                    Task {
                        if #available(iOS 26.0, *), RestAlarm.isConfigured { _ = await RestAlarm.isAllowed() }
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        alertStatus = await RestAlertStatus.current()
                    }
                }
                .font(.pixel(DS.TextSize.subhead))
                .frame(minHeight: 44)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func createBackup() {
        do {
            backupURL = try Backup.export(context: context)
            hapticSuccess()
        } catch {
            message = "Couldn't create the backup: \(error.localizedDescription)"
        }
    }
}
