# PixyPump design system

Dark, pixel-art, friendly. Rounded "glass" cards on a near-black background, a pixel font for headings
and numbers, and one accent colour the player can change.

**The golden rule:** screens never decide sizes, colours or timings themselves. They use the names below.
If something you need doesn't exist, add it to the system first (one place), then use it.
`scripts/design_lint.py` enforces this.

| What | Where it lives |
|---|---|
| Spacing, radii, type sizes, tap size, timings, opacities | `DesignSystem/DesignTokens.swift` (`DS.*`) |
| Colours, pixel font, card style, buttons, haptics | `DesignSystem/Theme.swift` |
| Animations and micro-interactions | `DesignSystem/Motion.swift` |
| Pixel icons | `DesignSystem/PixelIcons.swift` (`Image.pixel(.glyph)`) |
| Undo toast, Settings gear, one-moment-at-a-time | `DesignSystem/UXKit.swift` |
| Confetti and celebration header | `DesignSystem/Celebration.swift` |
| App name | `AppInfo.name` in `DesignTokens.swift` |

---

## Colour

Always use these names. The accent and the background are chosen by the player (Settings → Appearance),
so they're read at runtime — never copy their hex values.

| Name | Use for |
|---|---|
| `Color.brand` | The accent: links, toggles, rings, selected states, primary chips |
| `Color.ppBackground` | Page background (via `AppBackground()`) |
| `Color.ppCard` | Cards and list rows |
| `Color.ppText` | Main text, big numbers, primary button fill |
| `Color.ppOnAccent` | Text/icons sitting on `brand`, `ppDone`, `ppFat` or `ppText` fills |
| `Color.ppLine` | Hairlines, tracks, soft fills — **always with an opacity token** |
| `.secondary` | Supporting text |
| `Color.ppDone` | Success, completed, "won" |
| `Color.ppFat` | XP, levels, rewards, locked-item hints |
| `Color.ppFlame` | Streak, warnings, time running out |
| `Color.ppFlameLight` / `ppFlameDeep` | Flame gradient ends |
| `Color.ppHeart` | Heart XP bar |
| `Color.ppMint` | Small "kcal left" style labels |
| `Color.ppProtein` / `ppCarbs` | Macro colours |
| `Color.ppGreen` | "NEXT" tag text |
| `Color.ppMuted` | Inactive tiles |

Opacity with `ppLine`: `DS.Opacity.fill` (0.08) for chip/field backgrounds, `.border` (0.15) for outlines,
`.track` (0.25) for empty progress tracks, `.disabled` (0.35).

Raw `Color(hex:)` is only allowed in the system files and in art/palette data
(sprites, confetti, theme packs). Brand assets you must match exactly (Apple/Google buttons) are marked `// ds-allow`.

## Type

- **Pixel font** (`Font.pixel(size)`) for headings, numbers, labels and buttons. Sizes come from `DS.TextSize`:

| Token | pt | Typical use |
|---|---|---|
| `caption` | 12 | Badges, tags, tiny labels — **the minimum** |
| `footnote` | 13 | Section headers (`PPHeader`), chip text |
| `subhead` | 14 | Secondary labels |
| `body` | 15 | Card titles, buttons |
| `callout` | 16 | Emphasised values |
| `headline` | 18 | Primary button, big list values |
| `title3` | 20 | Card headings |
| `title2` | 24 | Screen headings, big stats |
| `title` | 28 | Hero numbers |
| `largeTitle` | 34 | Splash title, big moments |
| `display` | 44 | LEVEL UP, celebrations |
| `hero` / `jumbo` | 56 / 64 | Giant words ("Rest") |

- Pass `relativeTo:` (e.g. `.pixel(DS.TextSize.body, relativeTo: .subheadline)`) so it grows with the iPhone's text size.
- **System font** for sentences and long text, always a Dynamic Type style (`.body`, `.callout`, `.subheadline`, `.caption`).
  Never `.system(size:)` for text (emoji/icon sizing is the only exception, marked `// ds-allow`).
- Headings can switch to a clean rounded font in Appearance; `Font.pixel` handles that automatically.

## Spacing and layout

`DS.Space`: `xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32`. Screen side margin: `DS.Space.screen` (16).
Use the scale for padding and stack spacing; avoid in-between values.

## Shape

| Token | pt | Use |
|---|---|---|
| `DS.Radius.xs` | 8 | Tiny chips, badges, sprite tiles |
| `DS.Radius.s` | 12 | Inputs, small buttons, thumbnails |
| `DS.Radius.m` | 16 | Small cards, tiles |
| `DS.Radius.tile` | 20 | Compact cards, banners |
| `DS.Radius.card` | 24 | **Standard card** |
| `DS.Radius.hero` | 32 | Hero cards (today's workout, calories) — also `glassCard()`'s default |

Pills use `Capsule()`. Radii of 1–5pt inside pixel art are fine.

## Components (reuse these, don't rebuild them)

| Component | File | Notes |
|---|---|---|
| `.glassCard(cornerRadius:)` | Theme | Every card |
| `AppBackground()` | Theme | Every screen background |
| `PPHeader("Title")` | Theme | Section headers (uppercased pixel) |
| `.buttonStyle(.primary)` | Theme | The one main action on a screen |
| `.buttonStyle(.squish)` | Motion | Tappable cards and chips |
| `EmptyStateCard` | Features/Workout/WorkoutView | Empty screens: icon, title, message, one action |
| `StatTile`, `SetBars`, `ExerciseStatusLine` | Progress / Workout | Stats and set progress |
| `TodayTile` | Home | Small tappable daily glance: icon, number, label, optional progress line |
| `XPBar` | Rewards/GameViews | Follows the player's XP bar style |
| `MissionRow` | Rewards/MissionViews | Any checklist line (challenges, missions) |
| `PixelBuddy` | Buddy/Mascot | The buddy anywhere, with mood/action |
| `UndoCenter.shared.show(...)` | UXKit | After every delete or log |
| `SettingsToolbarButton()` | UXKit | Gear on every tab |
| `MomentQueue.shared.isBusy` | UXKit | Full-screen moments never stack |
| `RollingNumber`, `CountUpText` | Motion | Numbers that change or count up |
| `PixelConfetti`, `CelebrationHeader` | Celebration | Big wins only |

## Motion

From `Motion.swift`: `.staggeredAppear(i)`, `.stamp(isOn)`, `.popOnChange(of:)`, `.xpPop(trigger:text:)`,
`.breathe(_:)`, `.wobble(_:)`, `.shimmer(_:)`, `.drawIn()`, `.growIn(i)`. Timings: `DS.Motion.quick / standard / slow`,
springs `DS.Motion.spring` and `.bouncy`.

Rules:
- Motion rewards an action or guides the eye. No motion that just loops for decoration on core screens.
- Everything must respect **Reduce Motion** (the helpers already do — use them).
- Celebrations respect **Settings → Celebrations** (Full / Subtle / Minimal).

## Feedback

- Haptics through `Haptics.tap / press / select / success / warning` (they respect the user's setting).
- Sounds through `SFX.play(.event)` (respect the setting and the sound pack).
- Every destructive action: confirm if it's big, and show an Undo toast.

## Accessibility (non-negotiable)

- Text ≥ 12pt (`DS.TextSize.caption`), scales with Dynamic Type.
- Tap targets ≥ 44pt (`DS.Size.minTap`).
- Meaning never by colour alone: add a ✓, a word or an `accessibilityLabel`.
- Every icon-only button has an `accessibilityLabel`.
