import AppKit
import ServiceManagement

@main
final class StatusBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let reader = TemperatureReader()
    private let fanReader = FanReader()
    private var fanInfos: [FanReader.FanInfo] = []
    private static let fanTag = 999
    private var timer: Timer?
    private var interval: TimeInterval {
        didSet { UserDefaults.standard.set(interval, forKey: "interval") }
    }
    private var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode == .gpu ? "gpu" : "cpu", forKey: "displayMode") }
    }
    private var colorMode: Bool {
        didSet { UserDefaults.standard.set(colorMode, forKey: "colorMode") }
    }
    private var iconStyle: Bool {
        didSet { UserDefaults.standard.set(iconStyle, forKey: "iconStyle") }
    }
    private var lang: String {
        didSet { UserDefaults.standard.set(lang, forKey: "lang") }
    }

    override init() {
        let ud = UserDefaults.standard
        let saved = ud.double(forKey: "interval")
        self.interval = saved > 0 ? saved : 2
        self.displayMode = ud.string(forKey: "displayMode") == "gpu" ? .gpu : .cpu
        self.colorMode = ud.bool(forKey: "colorMode")
        self.iconStyle = ud.bool(forKey: "iconStyle")
        self.lang = ud.string(forKey: "lang") ?? "en"
        super.init()
    }

    private enum L {
        static func sec(_ n: Double, _ lang: String) -> String {
            String(format: lang == "zh" ? "%.0f 秒" : "%.0f sec", n)
        }
        private static let zh: [String: String] = [
            "Activity Monitor": "活动监视器",
            "Color Mode": "彩色模式",
            "Fan": "风扇",
            "No Fan": "无风扇",
            "GitHub": "GitHub",
            "Icon Prefix": "图标前缀",
            "Interval": "刷新间隔",
            "Launch at Login": "开机自启",
            "Quit": "退出",
            "-1 sec": "-1 秒",
            "+1 sec": "+1 秒",
        ]
        static func t(_ key: String, _ lang: String) -> String {
            lang == "zh" ? (zh[key] ?? key) : key
        }
    }

    private static func colorForTemp(_ temp: Double) -> NSColor {
        switch temp {
        case ..<35.0: return NSColor(red: 0.459, green: 0.808, blue: 0.984, alpha: 1)
        case 35.0..<46.0: return NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        case 46.0..<56.0: return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        default: return NSColor(red: 1.0, green: 0.25, blue: 0.2, alpha: 1)
        }
    }

    private static func iconForTemp(_ temp: Double) -> (String, NSColor) {
        return ("●", colorForTemp(temp))
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

    private var lastTemp: Double?

    private func refresh() {
        let temp = reader.readTemperature(mode: displayMode)
        guard let t = temp else {
            if lastTemp != nil {
                statusItem.button?.title = "--°"
                lastTemp = nil
            }
            return
        }
        guard t != lastTemp else { return }
        lastTemp = t
        let text = String(format: "%.0f°", t)
        if iconStyle {
            let (icon, iconColor) = Self.iconForTemp(t)
            let attrStr = NSMutableAttributedString()
            attrStr.append(NSAttributedString(string: icon + " ", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: iconColor,
                .baselineOffset: 1.5
            ]))
            attrStr.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: colorMode ? Self.colorForTemp(t) : NSColor.controlTextColor
            ]))
            statusItem.button?.attributedTitle = attrStr
        } else if colorMode {
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
        item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.labelColor])
        return item
    }

    private func checkItem(_ title: String, on: Bool, action: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.labelColor])
        if let represented { item.representedObject = represented }
        return item
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(checkItem("CPU", on: displayMode == .cpu, action: #selector(switchMode(_:)), represented: "cpu"))
        menu.addItem(checkItem("GPU", on: displayMode == .gpu, action: #selector(switchMode(_:)), represented: "gpu"))
        menu.addItem(.separator())

        let intervalTitle = "\(L.t("Interval", lang)): \(L.sec(interval, lang))"
        let intervalItem = NSMenuItem(title: intervalTitle, action: nil, keyEquivalent: "")
        intervalItem.attributedTitle = NSAttributedString(string: intervalTitle, attributes: [.foregroundColor: NSColor.labelColor])
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for s in [1, 2, 3, 5, 10, 15, 30, 45, 60] as [TimeInterval] {
            submenu.addItem(checkItem(L.sec(s, lang), on: interval == s, action: #selector(setInterval(_:)), represented: NSNumber(value: s)))
        }
        let dec = labelItem(L.t("-1 sec", lang)); dec.target = self; dec.action = #selector(decreaseInterval)
        let inc = labelItem(L.t("+1 sec", lang)); inc.target = self; inc.action = #selector(increaseInterval)
        submenu.addItem(.separator())
        submenu.addItem(dec)
        submenu.addItem(inc)
        intervalItem.submenu = submenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        menu.addItem(checkItem(L.t("Color Mode", lang), on: colorMode, action: #selector(toggleColorMode)))
        menu.addItem(checkItem(L.t("Icon Prefix", lang), on: iconStyle, action: #selector(toggleIconStyle)))
        menu.addItem(checkItem(L.t("Launch at Login", lang), on: Self.isLoginItemEnabled, action: #selector(toggleLoginItem)))
        menu.addItem(.separator())

        menu.addItem(checkItem("English", on: lang == "en", action: #selector(switchLang(_:)), represented: "en"))
        menu.addItem(checkItem("中文", on: lang == "zh", action: #selector(switchLang(_:)), represented: "zh"))
        menu.addItem(.separator())

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let versionText = version.map { "v\($0)" } ?? "development"
        let versionItem = labelItem(versionText)
        versionItem.isEnabled = false
        versionItem.toolTip = Bundle.main.bundleIdentifier
        menu.addItem(versionItem)

        let github = labelItem(L.t("GitHub", lang))
        github.target = self
        github.action = #selector(openGitHub)
        github.toolTip = "https://github.com/WHYBBE/SwiftTempBar"
        menu.addItem(github)

        let item = labelItem(L.t("Activity Monitor", lang))
        item.target = self
        item.action = #selector(openActivityMonitor)
        menu.addItem(item)
        menu.addItem(.separator())

        let quitText = L.t("Quit", lang)
        let quit = NSMenuItem(title: quitText, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.attributedTitle = NSAttributedString(string: quitText, attributes: [.foregroundColor: NSColor.labelColor])
        menu.addItem(quit)

        statusItem.menu = menu
        menu.delegate = self
    }

    @objc private func switchLang(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String else { return }
        lang = v
        rebuildMenu()
    }

    @objc private func toggleColorMode() {
        colorMode.toggle()
        refresh()
        rebuildMenu()
    }

    @objc private func toggleIconStyle() {
        iconStyle.toggle()
        refresh()
        rebuildMenu()
    }

    @objc private func toggleLoginItem() {
        let enable = !Self.isLoginItemEnabled
        if enable {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        rebuildMenu()
    }

    private static var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/WHYBBE/SwiftTempBar") {
            NSWorkspace.shared.open(url)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        while let item = menu.item(withTag: Self.fanTag) {
            menu.removeItem(item)
        }

        fanInfos = fanReader.readFans()
        let fanLabel = L.t("Fan", lang)
        let noFanText = L.t("No Fan", lang)

        if fanInfos.isEmpty {
            let item = labelItem(noFanText)
            item.isEnabled = false
            item.tag = Self.fanTag
            menu.insertItem(item, at: 0)
            let sep = NSMenuItem.separator()
            sep.tag = Self.fanTag
            menu.insertItem(sep, at: 1)
        } else {
            for (i, fan) in fanInfos.enumerated() {
                let mainItem = NSMenuItem()
                mainItem.attributedTitle = NSAttributedString(string: "\(fanLabel) \(i + 1): \(fan.current) RPM", attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 13)
                ])
                mainItem.isEnabled = false
                mainItem.tag = Self.fanTag
                menu.insertItem(mainItem, at: i * 2)

                let rangeItem = NSMenuItem()
                let rangeText = fan.max > 0 ? "\(fan.min) - \(fan.max) RPM" : ""
                rangeItem.attributedTitle = NSAttributedString(string: rangeText, attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 11)
                ])
                rangeItem.isEnabled = false
                rangeItem.tag = Self.fanTag
                menu.insertItem(rangeItem, at: i * 2 + 1)
            }
            let sep = NSMenuItem.separator()
            sep.tag = Self.fanTag
            menu.insertItem(sep, at: fanInfos.count * 2)
        }
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
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
