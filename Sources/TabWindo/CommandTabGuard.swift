import AppKit
import os

/// Keeps macOS's own ⌘Tab off only while TabWindo can serve it. It comes back on quit, on any signal or crash,
/// and whenever the main thread stops answering, so a broken TabWindo never leaves the Mac without ⌘Tab.
enum CommandTabGuard {
    private struct State {
        var wantsTakeover = false
        var lastAnswer = CACurrentMediaTime()
        var handedBack = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static var watchdog: DispatchSourceTimer?
    /// How often the main thread is asked to answer, and how long without an answer counts as a hang.
    private static let askEvery: TimeInterval = 1
    private static let hangAfter: TimeInterval = 3

    /// Turns the native ⌘Tab off (`true`, for ⌘ mode) or back on.
    static func takeOverCommandTab(_ take: Bool) {
        state.withLock {
            $0.wantsTakeover = take
            $0.handedBack = false
        }
        setNativeCommandTab(enabled: !take)
    }

    /// Installs the signal handlers and starts the watchdog. Call once, at launch.
    static func install() {
        var action = sigaction()
        sigemptyset(&action.sa_mask)
        // Asked to quit: give ⌘Tab back and go at once, even if the main thread is stuck.
        action.__sigaction_u.__sa_handler = { _ in
            setNativeCommandTab(enabled: true)
            _exit(0)
        }
        for code in [SIGTERM, SIGINT, SIGHUP] { sigaction(code, &action, nil) }
        // Crashing: give ⌘Tab back, then crash as usual, so the report is still written.
        action.__sigaction_u.__sa_handler = { code in
            setNativeCommandTab(enabled: true)
            signal(code, SIG_DFL)
            raise(code)
        }
        for code in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] { sigaction(code, &action, nil) }
        startWatchdog()
    }

    /// Once a second, asks the main thread to answer. After three seconds without one, ⌘Tab goes back to macOS;
    /// when answers resume, TabWindo takes it over again.
    private static func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + askEvery, repeating: askEvery, leeway: .milliseconds(500))
        timer.setEventHandler {
            DispatchQueue.main.async { state.withLock { $0.lastAnswer = CACurrentMediaTime() } }
            let handBack: Bool? = state.withLock { current in
                guard current.wantsTakeover else { return nil }
                let isHung = CACurrentMediaTime() - current.lastAnswer > hangAfter
                guard isHung != current.handedBack else { return nil }
                current.handedBack = isHung
                return isHung
            }
            guard let handBack else { return }
            setNativeCommandTab(enabled: handBack)
            if handBack {
                logger.notice("Main thread not answering; macOS has ⌘Tab back until it does")
            } else {
                logger.notice("Main thread answering again; ⌘Tab taken over")
            }
        }
        timer.resume()
        watchdog = timer
    }
}
