# Contributing

## Workflow

1. Branch from `main`: `feature/short-name` or `fix/short-name`. Never push straight to `main`.
2. Keep pull requests small and focused (one feature or fix).
3. Before opening a PR:
   - `python3 scripts/design_lint.py` passes.
   - The app builds and runs in Xcode (⌘R) with no new warnings.
   - You tried the flow you changed on a simulator, including with a large text size and Reduce Motion.
4. Fill in the PR template checklist. Add screenshots for any UI change.
5. One review from the other partner before merging. Squash-merge.

## Rules (short version)

- **No hardcoding.** Sizes, radii, spacing, timings → `DS.*`. Colours → `Color.pp*` / `.brand`. App name → `AppInfo.name`.
  Exceptions need `// ds-allow: reason`.
- **Reuse components** from `docs/DESIGN_SYSTEM.md` before making new ones. New shared pieces go in `DesignSystem/`.
- **Follow the flows and UX rules** in `docs/UX_FLOWS.md`; update the doc when you change a flow.
- **Use the agreed words** in `docs/COPY.md`.
- **Never rename saved keys**; version them (see `docs/ARCHITECTURE.md`).
- **Accessibility:** text ≥ 12pt and scaling, tap targets ≥ 44pt, labels on icon buttons, no colour-only meaning.
- **No secrets in git** (API keys, `GoogleService-Info.plist`, `.p8`). Use an untracked `Secrets.xcconfig`.

## Commit messages

Short imperative summary: `Add weigh-in reminder card`, `Fix rest timer skip on lock screen`.
