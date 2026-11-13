# Architecture

## Principles

- **Local-first.** Everything is stored on the iPhone (SwiftData + UserDefaults). Accounts are optional and
  never required to use the app.
- **Feature folders.** Each area owns its screens. Shared look-and-feel lives only in `DesignSystem/`.
- **Logic out of views.** Rules (XP, streaks, missions, plan generation, backup) live in plain types/enums
  that views call. Views stay about layout.
- **Main actor by default.** Stores are `@MainActor @Observable` singletons (`.shared`). Pure value types
  and constants are `nonisolated`.
- **Runs on iOS 17+.** That's the floor (SwiftData and `@Observable` need it). Anything newer — e.g. AlarmKit,
  Liquid Glass (`glassEffect`) — must sit behind `if #available(iOS 26, *)` with a fallback that still works.
  Test big changes on an iOS 17 or 18 simulator too.

## Folders (`PixyPump/`)

Xcode uses a synchronized folder, so new files and folders are picked up automatically — no project-file edits.

| Folder | Contains |
|---|---|
| `App/` | `GymTrackerApp` (entry, splash, colour scheme), `ContentView` (tabs, tab requests), `SwipeNavigation` (`AppTab`), `Splash`, `DevMode` |
| `DesignSystem/` | `DesignTokens` (`DS.*`, `AppInfo`), `Theme` (colours, fonts, cards, buttons, haptics, appearance themes), `Motion`, `PixelIcons`, `UXKit` (Undo, Settings button, MomentQueue), `Celebration` |
| `Models/` | SwiftData models (`Models`, `FoodModels`), `Routine` (the plan), `TodayChanges` (today's skips/swaps/order/early finish), `ActiveWorkout`, `TrainingLog`, `Units` |
| `Services/` | `Backup`, `DataTools` (export, delete everything), `HealthSync`, `NotificationPlanner`, `SoundEffects` (`SFX`), `Auth` (account plug), `FirebaseSetup` + `FirebaseAuth` (Firebase accounts), `LiveRest` + `RestActivity` (Live Activity) |
| `Features/Home` | Home tab: workout card, today tiles (`TodayTile`), one reminder, challenges sheet |
| `Features/Workout` | Workout tab (list), workout mode (`WorkoutSession`: strip, paging, `WorkoutFlow` rules), exercise screen, summary, rest timer, plate calculator, Plate Stack game |
| `Features/Plan` | Plan editor, plan generator, plan quiz |
| `Features/Food` | Calories tab, add food, barcode scanner, presets, goals |
| `Features/Progress` | Progress tab, history, PRs, body weight, journey |
| `Features/Rewards` | XP/levels (`Gamification`), bags & missions (`Rewards`), duels, daily streak, reward views, guide |
| `Features/Buddy` | The pixel buddy (`Mascot`, generated `MascotSprites`) and its editor |
| `Features/Onboarding` | First-launch flow |
| `Features/Settings` | Settings, Appearance, customisation types (`Customize`), About, Legal |
| `Features/Pro` | Paywall and the Settings Pro row (`ProStore` lives in `Services/`) |
| `Features/Account` | Sign-in screens and Settings → Account |
| `Resources/` | Sounds (`sfx_*.wav`, 3 packs) and the pixel font |

`MascotSprites.swift` is generated pixel data — edit the sprite generator, not the file by hand.

## Data

**SwiftData models:** `Exercise`, `WorkoutSet`, `FoodItem`, `FoodEntry`, `SavedMeal`, `SavedMealItem`.

**UserDefaults keys** (JSON strings for bigger values). Keys are part of saved data: **never rename one** — add a
new versioned key (`…v2`) and migrate instead. Every new key must also be added to
`DataTools.deleteEverything` (and to `Backup.settingKeys` if it should be backed up).

| Area | Keys |
|---|---|
| Workout state | `activeWorkout.v1`, `todayChanges.v1`, `routineDays.v1`, `trainedDays.v1`, `lastTrainedDay`, `lastTrainedAt`, `workoutOpenNext`, `requestedTab` |
| Rest timer | `restTimerEnd`, `restTimerDuration`, `restTimerAlarmID`, `restExercise`, `restByExercise.v1` |
| Rewards | `xpLedger.v1`, `bonusXP.v1`, `inventory.v1`, `rewardsStart`, `rewardsVersion`, `questsDone`, `seenBadges`, `seenLevel`, `starterClaimed`, `starterBagOpened`, `starterBuddyCustomised`, `plateStackBest` |
| Body & food | `bodyWeight.v1`, `goalKcal`, `goalProtein`, `goalCarbs`, `goalFat`, `goalsSetUp`, `foodPresetVersion`, `profile*`, `plan*` |
| Look | `mascotLook.v1`, `appAccent`, `appSurface`, `appHeadings`, `appConfetti`, `celebrationLevel`, `restSkin`, `xpBarStyle`, `plateColors`, `profileBanner` |
| Sound & alerts | `soundsOn`, `soundVolume`, `soundPack`, `streakReminderOn`, `notif.*` |
| Health & backup | `healthSyncOn`, `healthSavedDays`, `lastBackupAt` |
| Account | `auth.user.v1`, `auth.nudgeDismissed` |
| Tips | `tips.workoutMode` |
| Clean-up | `homeOrder`, `homeHidden` (old Home layout, only cleared), `exercisePhotosRemoved.v1` (one-time removal of old exercise photos) |
| Pro | `pro.active.v1` (cache of the App Store entitlement; refreshed every launch), `pro.since.v1` (first day of Pro), `pro.shieldDays.v1` (days the weekly shield saved; kept if Pro ends) |
| Debug | `dev.unlockAll` |

## Pro (in-app purchase)

`Services/ProStore.swift` (StoreKit 2) + `Features/Pro/PaywallView.swift` (design: Figma gym-app → 02 Paywall).

- **Products** (create them in App Store Connect with these exact IDs):
  - `com.magsudturalgymapp.pixypump.pro.monthly`: auto-renewable, 1 month, group "PixyPump Pro"
  - `com.magsudturalgymapp.pixypump.pro.yearly`: auto-renewable, 1 year, same group, intro offer: 1-week free trial
  - `com.magsudturalgymapp.pixypump.pro.lifetime`: non-consumable
- **What Pro does:** `Unlocks.everything` is true (every theme pack, app icon, buddy item, skin), and the daily
  streak gets one free freeze per week from the day Pro started (`DailyStreak.compute`). Days it saved are stored, so
  a streak never shrinks if Pro ends. Tracking, plans and calories never need Pro.
- **Rules:** prices and trial length always come from StoreKit (never hardcoded); the paywall always shows the
  price after the trial, how to cancel, Terms (Apple EULA), Privacy and Restore purchases.
- **Testing:** `PixyPump/Resources/StoreKit/PixyPump.storekit` — Product → Scheme → Edit Scheme → Run → Options →
  StoreKit Configuration. TestFlight uses the real sandbox instead.
- **Entry points:** Settings → first row, and the banner on Appearance. Don't add pop-up paywalls elsewhere.

## Accounts (backend plug)

`Services/Auth.swift`: screens only talk to `AuthStore`, which talks to an `AuthService`.

- **`FirebaseAuthService`** (`Services/FirebaseAuth.swift`) is used when `PixyPump/GoogleService-Info.plist` is in
  the build. Firebase project `pixypump`, bundle ID `com.magsudturalgymapp.pixypump`. Firebase keeps the session
  (in the Keychain); `auth.user.v1` is only a cache of it.
- **`MockAuthService`** (demo mode, email code `123456`) is used when the plist is missing, so a fresh clone or CI
  still builds and runs.

| Sign-in | Status |
|---|---|
| Google | Done. Google SDK → Firebase credential. URL scheme (`REVERSED_CLIENT_ID`) in `PixyPump-Project-Info.plist`. |
| Apple | Done, not yet tested on a device. Native sheet with a SHA-256 nonce → Firebase. Deleting an account re-asks Apple and revokes the token (needs the Apple key in Firebase → Authentication → Apple → OAuth code flow). |
| Email | Planned: Firebase email link (no 6-digit code). Until then the Firebase build shows "coming soon". |

**`GoogleService-Info.plist` is not in git.** Download it from Firebase → Project settings → Your apps → iOS and put
it in `PixyPump/`. Real secrets (the Apple `.p8` key) go in the Firebase console only, never in the app.

## Adding a feature (checklist)

1. New folder or file under `Features/<Area>/`.
2. Build the UI only from `DS.*` tokens, `Color.pp*`/`brand`, `Font.pixel` / Dynamic Type and existing components.
3. Put rules/logic in a plain type, not in the view.
4. New saved key? Add it to the table above, `DataTools.deleteEverything` and (if wanted) `Backup.settingKeys`.
5. New wording? Check `docs/COPY.md`.
6. New or changed flow? Update `docs/UX_FLOWS.md`.
7. Run `python3 scripts/design_lint.py` and build in Xcode.
