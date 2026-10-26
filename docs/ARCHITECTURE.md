# Architecture

## Principles

- **Local-first.** Everything is stored on the iPhone (SwiftData + UserDefaults). Accounts are optional and
  never required to use the app.
- **Feature folders.** Each area owns its screens. Shared look-and-feel lives only in `DesignSystem/`.
- **Logic out of views.** Rules (XP, streaks, missions, plan generation, backup) live in plain types/enums
  that views call. Views stay about layout.
- **Main actor by default.** Stores are `@MainActor @Observable` singletons (`.shared`). Pure value types
  and constants are `nonisolated`.

## Folders (`PixyPump/`)

Xcode uses a synchronized folder, so new files and folders are picked up automatically — no project-file edits.

| Folder | Contains |
|---|---|
| `App/` | `GymTrackerApp` (entry, splash, colour scheme), `ContentView` (tabs, tab requests), `SwipeNavigation` (`AppTab`), `Splash`, `DevMode` |
| `DesignSystem/` | `DesignTokens` (`DS.*`, `AppInfo`), `Theme` (colours, fonts, cards, buttons, haptics, appearance themes), `Motion`, `PixelIcons`, `UXKit` (Undo, Settings button, MomentQueue), `Celebration` |
| `Models/` | SwiftData models (`Models`, `FoodModels`), `Routine` (the plan), `TodayChanges` (today's skips/swaps/order/early finish), `ActiveWorkout`, `TrainingLog`, `Units` |
| `Services/` | `Backup`, `DataTools` (export, delete everything), `HealthSync`, `NotificationPlanner`, `SoundEffects` (`SFX`), `Auth` (account plug), `LiveRest` + `RestActivity` (Live Activity) |
| `Features/Home` | Home tab: workout card, today tiles (`TodayTile`), one reminder, challenges sheet |
| `Features/Workout` | Workout tab (list), workout mode (`WorkoutSession`: strip, paging, `WorkoutFlow` rules), exercise screen, summary, rest timer, plate calculator, Plate Stack game |
| `Features/Plan` | Plan editor, plan generator, plan quiz |
| `Features/Food` | Calories tab, add food, barcode scanner, presets, goals |
| `Features/Progress` | Progress tab, history, PRs, body weight, journey |
| `Features/Rewards` | XP/levels (`Gamification`), bags & missions (`Rewards`), duels, daily streak, reward views, guide |
| `Features/Buddy` | The pixel buddy (`Mascot`, generated `MascotSprites`) and its editor |
| `Features/Onboarding` | First-launch flow |
| `Features/Settings` | Settings, Appearance, customisation types (`Customize`), About, Legal |
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
| Debug | `dev.unlockAll` |

## Accounts (backend plug)

`Services/Auth.swift`: screens only talk to `AuthStore`, which talks to an `AuthService`.
Today it's `MockAuthService` (demo mode, email code `123456`). To connect a backend:

1. Write a type conforming to `AuthService` (Apple token, Google, email code send/verify, sign out, delete account).
2. Use it in `AuthStore.init`.
3. For real Sign in with Apple: enable the capability and set `AuthConfig.realAppleSignIn = true`.
4. Store tokens in the Keychain, not UserDefaults.

## Adding a feature (checklist)

1. New folder or file under `Features/<Area>/`.
2. Build the UI only from `DS.*` tokens, `Color.pp*`/`brand`, `Font.pixel` / Dynamic Type and existing components.
3. Put rules/logic in a plain type, not in the view.
4. New saved key? Add it to the table above, `DataTools.deleteEverything` and (if wanted) `Backup.settingKeys`.
5. New wording? Check `docs/COPY.md`.
6. New or changed flow? Update `docs/UX_FLOWS.md`.
7. Run `python3 scripts/design_lint.py` and build in Xcode.
