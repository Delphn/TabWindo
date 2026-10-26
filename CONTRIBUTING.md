# Contributing

Thanks for helping. TabWindo stays small on purpose: it switches windows, fast and privately, and does nothing
else. Before starting anything big, open an issue so we can agree it fits.

## Setup

You need macOS 26 or later and Xcode 26 or later.

```sh
swift build && swift test   # build and run the tests
./build.sh                  # install your build to /Applications and launch it
```

`build.sh` signs with your Apple Development certificate, so macOS keeps TabWindo's permissions across rebuilds.
On first launch, allow Accessibility and Screen Recording in System Settings.

## Making a change

- Read [CLAUDE.md](CLAUDE.md). Its commands, map of the code and rules apply to people and AI agents alike.
- One change per pull request, small enough to review in one sitting.
- Logic that can be tested gets a test.
- Before you push, make sure `swift build`, `swift test` and
  `xcrun swift format lint --strict --recursive Sources Tests Package.swift` pass. With Claude Code, `/preflight`
  runs them all, plus a review.
- To format: `xcrun swift format --in-place --recursive Sources Tests Package.swift`.
- AI assistants are welcome. You're still the author: understand every line and try the change yourself.

Reviews follow [REVIEW.md](REVIEW.md). For security issues, see [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your work is released under the [MIT License](LICENSE).
