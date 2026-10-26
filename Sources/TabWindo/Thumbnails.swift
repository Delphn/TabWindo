import ScreenCaptureKit

/// Pictures of windows for the switcher. Taken only while the panel is on screen and kept in
/// memory only: nothing is written to disk or sent anywhere.
@MainActor
final class Thumbnails {
    var onImage: (@MainActor (CGWindowID, CGImage) -> Void)?
    private(set) var images: [CGWindowID: CGImage] = [:]

    /// Captures every listed window in parallel and hands each picture over as soon as it's ready.
    func capture(_ windows: [WindowItem], pixelSize: CGSize) {
        guard CGPreflightScreenCaptureAccess() else { return }
        let ids = Set(windows.map(\.id))
        images = images.filter { ids.contains($0.key) }  // forget windows that are gone
        Task {
            let start = CACurrentMediaTime()
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            else { return }
            var count = 0
            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for window in content.windows where ids.contains(window.windowID) {
                    group.addTask { (window.windowID, await Self.picture(of: window, fitting: pixelSize)) }
                }
                for await (id, image) in group {
                    guard let image else { continue }
                    count += 1
                    images[id] = image
                    onImage?(id, image)
                }
            }
            logger.debug(
                "Captured \(count, privacy: .public) of \(ids.count, privacy: .public) windows in \((CACurrentMediaTime() - start) * 1000, format: .fixed(precision: 1), privacy: .public) ms"
            )
        }
    }

    private nonisolated static func picture(of window: SCWindow, fitting size: CGSize) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }
        let scale = min(size.width / frame.width, size.height / frame.height)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(frame.width * scale))
        configuration.height = max(1, Int(frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
    }
}
