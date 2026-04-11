import AppKit

@main
final class StatusBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let reader = TemperatureReader()
    private var timer: Timer?
    private var interval: TimeInterval = 2
    private var displayMode: DisplayMode = .cpu
    private var colorMode = false

    private static func colorForTemp(_ temp: Double) -> NSColor {
        switch temp {
        case ..<35: return NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1)
        case 35...45: return NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        case 46...55: return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        default: return NSColor(red: 1.0, green: 0.25, blue: 0.2, alpha: 1)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "--°"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        refresh()
        rebuildMenu()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func refresh() {
        let temp = reader.readTemperature(mode: displayMode)
        guard let t = temp else {
            statusItem.button?.title = "--°"
            return
        }
        let text = String(format: "%.0f°", t)
        if colorMode {
            statusItem.button?.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: Self.colorForTemp(t)
                ]
            )
        } else {
            statusItem.button?.title = text
        }
    }

    private func labelItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.black])
        return item
    }

    private func checkItem(_ title: String, on: Bool, action: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.black])
        if let represented { item.representedObject = represented }
        return item
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(checkItem("CPU", on: displayMode == .cpu, action: #selector(switchMode(_:)), represented: "cpu"))
        menu.addItem(checkItem("GPU", on: displayMode == .gpu, action: #selector(switchMode(_:)), represented: "gpu"))
        menu.addItem(.separator())

        for s in [1, 2, 3, 5, 10, 30] as [TimeInterval] {
            menu.addItem(checkItem(String(format: "%.0f 秒", s), on: interval == s, action: #selector(setInterval(_:)), represented: NSNumber(value: s)))
        }

        let dec = labelItem("-1 秒"); dec.target = self; dec.action = #selector(decreaseInterval); menu.addItem(dec)
        let inc = labelItem("+1 秒"); inc.target = self; inc.action = #selector(increaseInterval); menu.addItem(inc)
        menu.addItem(checkItem("彩色模式", on: colorMode, action: #selector(toggleColorMode)))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.attributedTitle = NSAttributedString(string: "退出", attributes: [.foregroundColor: NSColor.black])
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleColorMode() {
        colorMode.toggle()
        refresh()
        rebuildMenu()
    }

    @objc private func switchMode(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String else { return }
        if v == "cpu" { displayMode = .cpu } else { displayMode = .gpu }
        refresh()
        rebuildMenu()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? NSNumber else { return }
        interval = v.doubleValue
        scheduleTimer()
        rebuildMenu()
    }

    @objc private func decreaseInterval() {
        interval = max(1, interval - 1)
        scheduleTimer()
        rebuildMenu()
    }

    @objc private func increaseInterval() {
        interval += 1
        scheduleTimer()
        rebuildMenu()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = StatusBarController()
        app.delegate = delegate
        app.run()
    }
}
