# TabWindo

The way of the Tab: a fast, private window switcher for macOS.

Hold ⌘ and tap Tab to flick through your open **windows**, not apps, in most-recently-used order, with live
previews. Each window sits on a plate in its app's own icon color, so you spot them at a glance. It's
built natively in Swift and AppKit with Liquid Glass, so it feels like part of macOS.

## Features

- **Windows, not apps.** Every window, most recent first: all displays, other Spaces, full-screen apps, and
  minimized windows (shown last). Windows of hidden apps stay out.
- **Instant.** The window list is kept ready in the background, and the panel appears in a few milliseconds. A
  quick tap jumps straight back to your previous window without showing anything.
- **Live previews** in a grid you size from the menu: 2 to 7 windows per row.
- **Easy on the eyes in dark mode.** Plates take a deeper, calmer shade of each app's color, and the switcher
  follows your Mac between light and dark, even when it switches on a schedule.
- **Your shortcut:** ⌘Tab (it takes over the built-in app switcher while TabWindo runs), ⌥Tab or ⌃Tab.
- **Keys while it's open:** Tab moves forward; ⇧Tab, or ⇧ on its own, moves back; the arrow keys move around the
  grid; releasing the modifier or pressing Return switches; Esc cancels. The mouse works too.
- Menu bar icon, no Dock icon, optional launch at login.

## Privacy

TabWindo needs two permissions:

- **Accessibility**, to see your windows and bring the one you pick to the front.
- **Screen Recording**, only for the previews. Pictures are taken only while the switcher is on screen (never on
  a quick tap), kept in memory, and never saved or sent anywhere. Without this permission TabWindo still works
  and shows app icons instead of previews.

There's no network code, no analytics and no updater. The whole app is a few files of Swift: read it.

## Install

Download the latest DMG from Releases, drag TabWindo to Applications, open it, and grant the two permissions
when macOS asks. Requires macOS 26 or later.

## Why not the Mac App Store?

App Store apps must run in the sandbox, and the sandbox blocks the Accessibility access needed to bring a
specific window forward. TabWindo also uses a few private macOS functions, like AltTab and yabai do, to take over
⌘Tab, focus the exact window you pick and find windows on other Spaces. So it's distributed directly, signed with a
Developer ID and notarized by Apple.

## Build from source

Requires Xcode 26 or later.

```sh
./build.sh          # build, sign with your Apple Development certificate, install to /Applications, launch
./build.sh debug    # the same, with developer tools: --list and --snapshot <file.png>
./release.sh        # universal build, Developer ID signature, notarization and DMG (setup notes inside)
```

## Contributing

Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately,
as [SECURITY.md](SECURITY.md) explains.

## License

[MIT](LICENSE)
