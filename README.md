# PixyPump

A pixel-art gym tracker and calorie counter for iPhone, with a game layer: a buddy you dress up,
XP and levels, daily challenges, a 🔥 streak, gym bags and a little rest-time game.

Built with **SwiftUI + SwiftData**. Deployment target iOS 27, Xcode 27, Swift 5 language mode with Swift 6 concurrency style (default MainActor).

## Getting started

1. Open `PixyPump.xcodeproj` in Xcode 27.
2. Pick an iPhone simulator and press **⌘R**.
3. In a Debug build, **Settings → Developer → Unlock everything** unlocks all cosmetics for testing.

No API keys are needed. Accounts run in demo mode until a backend is connected (see `docs/ARCHITECTURE.md`).

## Read these before changing anything

| Doc | What it's for |
|---|---|
| [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) | Colours, type, spacing, radii, components, motion, accessibility |
| [docs/UX_FLOWS.md](docs/UX_FLOWS.md) | Every user flow, and the UX rules each screen must follow |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Folder layout, data, services, saved keys, how to add a feature |
| [docs/COPY.md](docs/COPY.md) | Voice and the exact words we use (gym bag, PR, LV 5…) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branches, pull requests, the checklist |
| [AGENTS.md](AGENTS.md) | The same rules, condensed for AI coding assistants |

## Checks

```bash
python3 scripts/design_lint.py
```

Fails if a screen uses a raw font size, radius, colour, `Color.white/.black`, a non-scaling system font size,
text under 12pt or the app name written out. GitHub runs it on every pull request.

## Project layout

```
PixyPump/            ← app source (Xcode keeps this folder in sync automatically)
  App/                       app entry, tabs, splash
  DesignSystem/              tokens, colours, fonts, icons, motion, shared components
  Models/                    SwiftData models and plain data (plan, units, today's changes)
  Services/                  backup, export, Apple Health, notifications, sounds, accounts, Live Activity
  Features/<Area>/           one folder per area: Home, Workout, Plan, Food, Progress, Rewards,
                             Buddy, Onboarding, Settings, Account
  Resources/                 sounds and fonts
  Assets.xcassets            app icons and colours
docs/                        design system, flows, architecture, copy
scripts/                     checks
```
