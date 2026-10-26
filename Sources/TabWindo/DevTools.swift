#if DEBUG
    import AppKit
    import ScreenCaptureKit

    /// Development tools, compiled into debug builds only:
    ///   --list               prints the windows the switcher would show, then quits
    ///   --snapshot <file>    shows the panel for a moment, saves a picture of it, then quits
    @MainActor
    enum DevTools {
        /// Runs `--list` (never returns) or gives the delegate for `--snapshot`; nil when neither is asked.
        static func delegate(for arguments: [String]) -> NSApplicationDelegate? {
            if arguments.contains("--list") { listWindowsAndExit() }
            guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else {
                return nil
            }
            return SnapshotDelegate(path: arguments[index + 1])
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
            print("Saved \(path)")
        }
    }
#endif
