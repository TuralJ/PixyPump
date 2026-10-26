# Rules for AI coding assistants (Claude, Copilot, Cursor…)

Read these before changing anything. They are the same rules people follow (`CONTRIBUTING.md`).

1. **Read the docs first:** `docs/DESIGN_SYSTEM.md`, `docs/UX_FLOWS.md`, `docs/COPY.md`, `docs/ARCHITECTURE.md`.
2. **No hardcoded design values.** Use `DS.Space`, `DS.Radius`, `DS.TextSize`, `DS.Size`, `DS.Motion`, `DS.Opacity`,
   `Color.pp*` / `Color.brand`, `Font.pixel(DS.TextSize.…)`, `Image.pixel(.…)`, `AppInfo.name`.
   If a value is genuinely one-off (brand logo colours, pixel art), add `// ds-allow: reason` on that line.
3. **Reuse components** (`glassCard`, `PPHeader`, `PrimaryButtonStyle`, `UndoCenter`, `SettingsToolbarButton`, `MomentQueue`…).
   Don't make a near-copy of an existing one; extend it in `DesignSystem/`.
4. **Put files in the right folder** (`Features/<Area>/`, `Models/`, `Services/`, `DesignSystem/`). The Xcode folder is
   synchronized — never edit `project.pbxproj` to add files.
5. **Swift concurrency:** the target uses default MainActor isolation. Mark pure enums/structs `nonisolated`.
   Stores are `@MainActor @Observable` with a `static let shared`.
6. **Saved data:** never rename a UserDefaults key or SwiftData property. Add new keys to the registry in
   `docs/ARCHITECTURE.md` and to `DataTools.deleteEverything`.
7. **UX rules:** every destructive action is undoable or confirmed; one full-screen moment at a time; text ≥ 12pt,
   tap targets ≥ 44pt, VoiceOver labels on icon-only buttons, respect Reduce Motion.
8. **Words:** use the terms in `docs/COPY.md` (e.g. "gym bag", "Finish workout", "Log weight").
9. **Accounts:** screens only use `AuthStore`. Backend work goes in a new `AuthService` implementation.
10. **Before finishing:** run `python3 scripts/design_lint.py` (must pass) and update any doc your change affects.
