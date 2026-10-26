# TabWindo

A macOS window switcher. Hold ⌘ (or ⌥ or ⌃) and tap Tab to go through windows, not apps, most recent first,
on a Liquid Glass grid of previews. Swift in Swift 5 language mode, AppKit, SwiftPM, macOS 26+, no
dependencies.

## Commands

- Build: `swift build`
- Test: `swift test` (Swift Testing, pure logic only)
- Lint: `xcrun swift format lint --strict --recursive Sources Tests Package.swift`
- Format: `xcrun swift format --in-place --recursive Sources Tests Package.swift`. A hook already formats each
  Swift file Claude edits.
- Try it: `./build.sh` builds, signs, installs to /Applications and relaunches. `./build.sh debug` adds two tools:
  - `open -n -W --stdout "$TMPDIR/list.txt" /Applications/TabWindo.app --args --list` writes the windows the
    switcher would show.
  - `open -n -W /Applications/TabWindo.app --args --snapshot "$TMPDIR/panel.png"` saves a picture of the panel.
    It fails while the Mac is locked.
- Logs: `/usr/bin/log show --last 5m --debug --predicate 'subsystem == "dev.delphin.TabWindo"'` (in zsh, plain
  `log` is a builtin).
- Release: `./release.sh` (Developer ID, notarization, DMG). Never run it unasked: it uploads the app to Apple.

## Map of Sources/TabWindo

- `main.swift`: app delegate, menu bar menu, settings, permission prompts
- `Hotkeys.swift`: Carbon hot keys for ⌘Tab and ⌃Tab; the event tap for ⌥Tab and for keys while the switcher is open
- `WindowStore.swift`: the window list, kept current on its own thread from Accessibility notifications
- `Switcher.swift`: one switch, from key press to focus: show delay, selection, modifier release
- `SwitcherPanel.swift`, `PanelViews.swift`: the glass panel, its plates and tiles
- `GridLayout.swift`, `PlateColors.swift`: layout and color logic, covered by tests
- `Thumbnails.swift`: previews with ScreenCaptureKit
- `Private.swift`: every private macOS API, in one place
- `DevTools.swift`: `--list` and `--snapshot`, debug builds only

## Rules

- No dependencies, no network code, no analytics, no updater.
- Private APIs are declared only in `Private.swift`.
- Accessibility calls to other apps run on the store thread or the focus queue, never on the main thread, so a
  frozen app can't freeze the switcher.
- Screen capture only while the panel is on screen, never on a quick tap. Pictures stay in memory.
- Native ⌘Tab comes back on every way out: quit, shortcut change, SIGTERM, SIGINT, SIGHUP.
- The event tap re-enables itself only after `.tapDisabledByTimeout`. Reacting to other disable events loops and
  burns CPU.
- 0% CPU while idle: nothing runs while the switcher is closed. The 120 Hz modifier poll runs only while it's open.
- Logs hold counts and timings, never window titles or app names. Anything logged on every switch uses `.debug`.
- Logic that can be pure stays out of AppKit, as `nonisolated static` functions with tests (like
  `GridLayout`, `PlateColors.assign`, `WindowStore.comesBefore`).
- Small files with one job each. Comments say why, in plain words.

## Done means

`swift build`, `swift test` and the lint pass. For anything you can see or feel, also run `./build.sh` and try it,
or take a `--snapshot`. Before a merge, run `/preflight`. Reviews follow `REVIEW.md`.
