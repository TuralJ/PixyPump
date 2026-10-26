#!/usr/bin/env python3
"""PixyPump design-system lint.

Keeps the app on its rules: no raw font sizes, radii, colours or app-name strings in
screens. Everything comes from DesignTokens.swift (DS.*) and Theme.swift (Color.pp*).

Run:   python3 scripts/design_lint.py            (from the repo root)
Exit:  0 = clean, 1 = rule broken (CI fails the pull request).

Need an exception (e.g. a brand colour you must match exactly)? Add `// ds-allow: reason`
at the end of that line, and explain it in the pull request.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "PixyPump"

# Files that define the system (they're allowed raw values).
SYSTEM_FILES = {"DesignTokens.swift", "Theme.swift", "PixelIcons.swift"}
# Art and palette data (pixel sprites, confetti, theme packs) may use raw colours.
ART_FILES = {"Mascot.swift", "MascotSprites.swift", "Celebration.swift", "Customize.swift", "Splash.swift"}

RULES = [
    ("raw-pixel-size", re.compile(r"\.pixel\(\s*\d"),
     "Use a type token: .pixel(DS.TextSize.body) — never a raw number.", SYSTEM_FILES),
    ("raw-radius", re.compile(r"(glassCard|RoundedRectangle)\(cornerRadius:\s*([6-9]|[1-9]\d)\b"),
     "Use a radius token: DS.Radius.card / .hero / .tile / .m / .s / .xs.", SYSTEM_FILES),
    ("system-font-size", re.compile(r"\.font\(\.system\(size:"),
     "Use Dynamic Type (.body, .callout…) or .pixel(DS.TextSize…) so text scales.", SYSTEM_FILES | ART_FILES),
    ("raw-hex-colour", re.compile(r"Color\(hex:\s*0x"),
     "Add a named colour to Theme.swift (Color.ppSomething) and use that.", SYSTEM_FILES | ART_FILES),
    ("raw-white-black", re.compile(r"\bColor\.(white|black)\b(?!\.opacity)"),
     "Use Color.ppText, Color.ppOnAccent or Color.ppLine.opacity(DS.Opacity…).", SYSTEM_FILES | ART_FILES),
    ("tiny-text", re.compile(r"\.pixel\(\s*([0-9]|1[01])\s*[,)]"),
     "Text smaller than 12pt fails accessibility. Use DS.TextSize.caption or bigger.", set()),
    ("hardcoded-app-name", re.compile(r'"[^"\n]*PixyPump[^"\n]*"'),
     "Use AppInfo.name instead of writing the app name.", {"DesignTokens.swift", "Backup.swift", "DataTools.swift"}),
]

def strip_comment(line: str) -> str:
    # Ignore anything after // that isn't inside a string (good enough for our code style).
    in_str = False
    for i, ch in enumerate(line):
        if ch == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
        if not in_str and line.startswith("//", i):
            return line[:i]
    return line

def main() -> int:
    problems = 0
    files = sorted(APP.rglob("*.swift"))
    if not files:
        print(f"No Swift files found under {APP}")
        return 1
    for path in files:
        for no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "ds-allow" in raw or raw.lstrip().startswith("//"):
                continue
            line = strip_comment(raw)
            for name, pattern, message, exempt in RULES:
                if path.name in exempt:
                    continue
                if pattern.search(line):
                    problems += 1
                    rel = path.relative_to(ROOT)
                    print(f"{rel}:{no}: [{name}] {message}\n    {raw.strip()}")
    if problems:
        print(f"\n✗ {problems} design-system problem(s). See docs/DESIGN_SYSTEM.md.")
        return 1
    print(f"✓ Design lint passed ({len(files)} Swift files).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
