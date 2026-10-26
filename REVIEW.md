# Review guide

How to review a change to TabWindo, for people and for Claude. `/preflight` runs Claude's code review and
security review with this guide. The rules in `CLAUDE.md` apply too.

## Must fix

Report these even when unsure, with the scenario that triggers them:

- Anything that breaks a rule in `CLAUDE.md`.
- Native ⌘Tab left off after any way out: quit, crash, signal, hang, shortcut change.
- A switch that can start, or stay open, at the lock screen.
- Screen capture outside the visible panel, or pictures written anywhere.
- Window titles, app names or pictures in logs, in files, or leaving the Mac.
- An Accessibility call that can run on the main thread.
- An event tap that can re-enable itself in a loop, or that swallows keys while the switcher is closed.
- Work while idle: a timer, poll or observer that runs while the switcher is closed.
- New permissions, entitlements, Info.plist keys or private APIs that the change doesn't explain.

## Worth flagging

- A slower path from key press to panel: anything new before the panel is shown.
- Changed logic in `GridLayout`, `PlateColors` or the window order without a test.
- Closures that keep the switcher, panel or store alive longer than they should.

## Skip

- Formatting and import order: swift-format and the lint own them.
- Naming and comment wording, unless they mislead.
- `.build/`, `dist/` and the artwork in `AppIcon.icon/`.

## How to report

- Each finding: `file:line`, what goes wrong, and the steps or state that cause it.
- Most severe first. At most three minor findings; drop the rest.
- When nothing's wrong, say "No issues found." and stop.
- On a second review, check the earlier findings are fixed. Don't raise new minor ones.
