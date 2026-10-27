# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

PixyPump is a local-first SwiftUI + SwiftData iPhone app (iOS 27, Xcode 27): a pixel-art gym tracker and
calorie counter with a game layer (buddy, XP/levels, streaks, gym bags, missions).

**Follow `AGENTS.md`** (the binding rules for AI assistants) and `CONTRIBUTING.md`. Read the relevant doc in
`docs/` before changing an area: `DESIGN_SYSTEM.md`, `UX_FLOWS.md`, `ARCHITECTURE.md`, `COPY.md`.

## Commands

```bash
# Design-system lint — must pass before finishing (CI runs it on every PR)
python3 scripts/design_lint.py

# Build for the simulator (same as CI)
xcodebuild build -project PixyPump.xcodeproj -scheme PixyPump \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

There is no test target; verification is the lint, a clean build with no new warnings, and trying the flow on
a simulator (including large text and Reduce Motion). Debug builds have **Settings → Developer → Unlock
everything** (`dev.unlockAll`) to test cosmetics. Without `PixyPump/GoogleService-Info.plist` (untracked) accounts run
in demo mode (`MockAuthService`, email code `123456`); with it they use Firebase (`FirebaseAuthService`).

## Architecture essentials

- **Single target, synchronized folder.** Files under `PixyPump/` are picked up automatically — never edit
  `project.pbxproj` to add files.
- **Entry:** `App/GymTrackerApp.swift` opens the one `ModelContainer` (`AppData.container`, also used by
  code that saves outside a screen) and shows `DataErrorView` instead of an empty store if it fails.
  `ContentView` owns the tabs (`AppTab` in `SwipeNavigation.swift`).
- **Persistence is split:** SwiftData for logged data (`Exercise`, `WorkoutSet`, `FoodItem`, `FoodEntry`,
  `SavedMeal`, `SavedMealItem`); UserDefaults (often versioned JSON keys like `activeWorkout.v1`) for state,
  rewards and settings. A new key must go in the registry in `docs/ARCHITECTURE.md`,
  `DataTools.deleteEverything`, and optionally `Backup.settingKeys`. Never rename keys or model properties.
- **Logic lives in plain types, not views** (e.g. `Gamification`, `Rewards`, `WorkoutFlow`, `PlanGenerator`,
  `Backup`). Stores are `@MainActor @Observable` singletons with `.shared`; the target defaults to MainActor
  isolation, so pure value types must be marked `nonisolated`.
- **Design system is enforced by lint.** `DesignSystem/DesignTokens.swift` (`DS.*`, `AppInfo`) and `Theme.swift`
  (`Color.pp*`, fonts, cards, buttons) are the only places raw values belong. Art/palette files (`Mascot`,
  `MascotSprites`, `Celebration`, `Customize`, `Splash`) are partially exempt — see `SYSTEM_FILES` /
  `ART_FILES` in `scripts/design_lint.py`. One-off exceptions need `// ds-allow: reason` on the line.
- **Full-screen celebrations go through `MomentQueue`** and destructive actions through `UndoCenter`
  (both in `DesignSystem/UXKit.swift`) so only one moment shows at a time and deletes are undoable.
- **Accounts:** screens only use `AuthStore` (`Services/Auth.swift`), which picks `FirebaseAuthService` or the mock.
- `Features/Buddy/MascotSprites.swift` is generated pixel data — don't hand-edit it.

## Known doc drift

`docs/ARCHITECTURE.md` lists `LiveRest` + `RestActivity` (Live Activity) under `Services/`, but those files are
not in the repo. Check before relying on them.
