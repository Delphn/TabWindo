#if DEBUG
    import AppKit
    import ScreenCaptureKit

    /// Development tools, compiled into debug builds only:
    ///   --list               prints the windows the switcher would show, then quits
    ///   --snapshot <file>    shows the panel for a moment, saves a picture of it, then quits
    ///   --palette <file>     saves every installed app's icon colors and plates, in light and dark mode
    @MainActor
    enum DevTools {
        /// Runs `--list` or `--palette` (they never return) or gives the delegate for `--snapshot`; nil when none
        /// is asked.
        static func delegate(for arguments: [String]) -> NSApplicationDelegate? {
            if arguments.contains("--list") { listWindowsAndExit() }
            if let path = value(of: "--palette", in: arguments) { savePaletteAndExit(to: path) }
            return value(of: "--snapshot", in: arguments).map(SnapshotDelegate.init(path:))
        }

        private static func value(of option: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        /// One row per app: its icon, the colors taken from it (strongest first), then its plate in light and in
        /// dark mode, with its name written the way a window title would be.
        private static func savePaletteAndExit(to path: String) -> Never {
            let folders = [
                "/Applications", "/Applications/Utilities", "/System/Applications",
                "/System/Applications/Utilities", NSHomeDirectory() + "/Applications",
            ]
            var bundles = folders.flatMap { folder in
                ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
                    .filter { $0.hasSuffix(".app") }.map { folder + "/" + $0 }
            }
            bundles += NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleURL?.path)
            let apps = Set(bundles).sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            let cell = NSSize(width: 340, height: 52)
            let perRow = 4
            let canvas = FlippedView(
                frame: NSRect(
                    x: 0, y: 0, width: cell.width * CGFloat(perRow),
                    height: cell.height * CGFloat((apps.count + perRow - 1) / perRow)))
            for (index, path) in apps.enumerated() {
                let origin = NSPoint(
                    x: CGFloat(index % perRow) * cell.width, y: CGFloat(index / perRow) * cell.height)
                let icon = NSWorkspace.shared.icon(forFile: path)
                let colors = PlateColors.colors(of: icon)
                let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                canvas.addSubview(
                    PaletteSwatch(
                        icon: icon, colors: colors,
                        frame: NSRect(origin: origin, size: NSSize(width: 104, height: cell.height))))
                let light = colors.first ?? .controlAccentColor
                let tint = PlateColors.plateColor(light: light, dark: PlateColors.darkTone(light))
                for (offset, appearance) in [(104.0, NSAppearance.Name.aqua), (222, .darkAqua)] {
                    let sample = PaletteSample(
                        name: name, tint: tint,
                        frame: NSRect(x: origin.x + offset, y: origin.y, width: 118, height: cell.height))
                    sample.appearance = NSAppearance(named: appearance)
                    canvas.addSubview(sample)
                }
            }
            guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { exit(1) }
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("Saved \(apps.count) apps to \(path)")
            exit(0)
        }

        private static func listWindowsAndExit() -> Never {
            guard AXIsProcessTrusted() else {
                print("TabWindo needs Accessibility access first.")
                exit(1)
            }
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
            let store = WindowStore()
            var latest: [WindowItem] = []
            store.onChange = { latest = $0 }
            store.onReady = {
                let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                let onScreen = Set(info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
                print("\(latest.count) windows, most recent first:")
                for (rank, window) in latest.enumerated() {
                    let place =
                        window.isMinimized ? "minimized" : onScreen.contains(window.id) ? "visible" : "other Space"
                    print("\(rank + 1). [\(place)] #\(window.id) \(window.appName): \(window.title)")
                }
                exit(0)
            }
            store.start()
            dispatchMain()
        }
    }

    /// Shows the panel, saves a picture of it as it appears on screen (with the margin around it), quits.
    @MainActor
    private final class SnapshotDelegate: NSObject, NSApplicationDelegate {
        private let path: String
        private let store = WindowStore()
        private let switcher = Switcher()

        init(path: String) {
            self.path = path
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
            store.onChange = { [switcher] windows in switcher.windows = windows }
            store.onReady = { [self] in
                let number = switcher.presentForSnapshot()
                Task {
                    try? await Task.sleep(for: .seconds(1.5))  // let the thumbnails arrive
                    await save(windowNumber: number)
                    exit(0)
                }
            }
            store.start()
        }

        private func save(windowNumber: Int) async {
            guard let panel = NSApp.window(withWindowNumber: windowNumber), let screen = panel.screen,
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID,
                let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                let display = content.displays.first(where: { $0.displayID == displayID })
            else { return print("Panel or display not found") }
            let frame = panel.frame.insetBy(dx: -40, dy: -40)
            let source = CGRect(
                x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                width: frame.width, height: frame.height)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = source
            configuration.width = Int(source.width * screen.backingScaleFactor)
            configuration.height = Int(source.height * screen.backingScaleFactor)
            configuration.showsCursor = false
            guard
                let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration
                ),
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { return print("Capture failed") }
            try? png.write(to: URL(fileURLWithPath: path))
            print(
                "Saved \(path): \(switcher.windows.count) windows, panel \(panel.isVisible ? "visible" : "hidden") at \(panel.frame) on a \(screen.frame.size) screen"
            )
        }
    }

    /// For `--palette`: an app's icon and the colors taken from it.
    private final class PaletteSwatch: NSView {
        private let icon: NSImage
        private let colors: [NSColor]

        init(icon: NSImage, colors: [NSColor], frame: NSRect) {
            (self.icon, self.colors) = (icon, colors)
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor(white: 0.5, alpha: 1).setFill()
            bounds.fill()
            icon.draw(in: NSRect(x: 4, y: 8, width: 36, height: 36))
            for (index, color) in colors.prefix(4).enumerated() {
                color.setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: 46 + CGFloat(index) * 14, y: 20, width: 12, height: 12), xRadius: 3,
                    yRadius: 3
                ).fill()
            }
        }
    }

    /// For `--palette`: a plate as the panel draws it, on a stand-in for the panel's glass.
    private final class PaletteSample: NSView {
        init(name: String, tint: NSColor, frame: NSRect) {
            super.init(frame: frame)
            let plate = PlateView()
            plate.tint = tint
            plate.frame = bounds.insetBy(dx: 6, dy: 8)
            addSubview(plate)
            addSubview(PaletteLabel(name: name, tint: tint, frame: plate.frame))
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func draw(_ dirtyRect: NSRect) {
            NSColor(white: effectiveAppearance.isDark ? 0.17 : 0.93, alpha: 1).setFill()
            bounds.fill()
        }
    }

    /// For `--palette`: an app's name in the color a window title would get on its plate.
    private final class PaletteLabel: NSView {
        private let name: String
        private let tint: NSColor

        init(name: String, tint: NSColor, frame: NSRect) {
            (self.name, self.tint) = (name, tint)
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func draw(_ dirtyRect: NSRect) {
            let tint = tint.resolved(in: effectiveAppearance)
            let light = PlateStyle(tint: tint, isDark: effectiveAppearance.isDark).wantsLightText
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: light ? NSColor.white : .black.withAlphaComponent(0.85),
            ]
            let text = NSAttributedString(string: name, attributes: attributes)
            text.draw(in: bounds.insetBy(dx: 8, dy: (bounds.height - text.size().height) / 2))
        }
    }
#endif
