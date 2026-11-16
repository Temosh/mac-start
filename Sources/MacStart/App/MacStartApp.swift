import AppKit

/// The entry point. MacStart runs a plain `NSApplication` without a storyboard, so the
/// menu bar and every window are built in code.
@main
enum MacStartApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // `NSApplication.delegate` is a weak reference, so keep the delegate alive while the app runs.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
