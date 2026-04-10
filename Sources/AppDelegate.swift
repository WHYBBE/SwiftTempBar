import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusBarController()
        statusController?.start()
    }
}
