import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var refreshTimer: Timer?
    private var displayTimer: Timer?
    private var snapshot: UsageResponse?
    private var updatedAt: Date?
    private var accountID: String?
    private var errorMessage: String?
    private var isRefreshing = false
    private var nextAllowedRefresh = Date.distantPast
    private var language: TimeLanguage {
        get { TimeLanguage(rawValue: UserDefaults.standard.string(forKey: "timeLanguage") ?? "") ?? .chinese }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "timeLanguage") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        guard others.count <= 1 else { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        if let image = Bundle.main.url(forResource: "MenuIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:)) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            item.button?.image = image
            item.button?.imagePosition = .imageLeading
        }
        item.button?.font = .systemFont(ofSize: 13, weight: .medium)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        render()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
    }

    @objc private func didWake() { refresh() }
    @objc private func refreshNow() { refresh() }

    private func refresh() {
        guard !isRefreshing, Date() >= nextAllowedRefresh else { return }
        isRefreshing = true
        render()
        Task {
            defer { isRefreshing = false; render() }
            do {
                let tokens = try Credentials.read()
                if tokens.accountID != accountID {
                    snapshot = nil
                    updatedAt = nil
                    accountID = tokens.accountID
                    render()
                }
                let result = try await UsageClient.fetch(tokens: tokens)
                let current = try Credentials.read()
                guard current.accountID == tokens.accountID else {
                    snapshot = nil
                    updatedAt = nil
                    errorMessage = "登录状态已更新，等待下次刷新"
                    return
                }
                snapshot = result
                updatedAt = Date()
                errorMessage = nil
                NSLog("Codex Mini: usage refresh succeeded")
                nextAllowedRefresh = Date().addingTimeInterval(10)
            } catch {
                // A removed login must not leave another account's cached quota on screen.
                if (try? Credentials.read()) == nil { snapshot = nil; updatedAt = nil }
                if let usageError = error as? UsageError {
                    errorMessage = usageError.localizedDescription
                } else if let network = error as? URLError, network.code == .secureConnectionFailed {
                    errorMessage = "TLS 安全连接失败，稍后自动重试"
                } else {
                    errorMessage = "网络连接失败，请检查网络后刷新"
                }
                nextAllowedRefresh = Date().addingTimeInterval(errorMessage?.contains("频繁") == true ? 300 : 10)
                NSLog("Codex Mini: usage refresh failed: %@", errorMessage ?? "unknown")
            }
        }
    }

    private func render() {
        let primary = snapshot?.limits?.primary ?? snapshot?.limits?.secondary
        let stale = updatedAt.map { Date().timeIntervalSince($0) > 150 } ?? false
        let warning = errorMessage != nil || stale
        let title = primary?.title(language: language) ?? (isRefreshing ? "读取中…" : "未连接")
        item.button?.title = " \(title)\(warning ? " ⚠︎" : "")"
        var tooltip = ["Codex Mini · 百分比表示剩余额度", "每分钟更新用量 · 倒计时为距离额度重置的时间"]
        if let updatedAt { tooltip.append("最近成功更新：\(updatedAt.formatted(date: .omitted, time: .standard))") }
        if let errorMessage { tooltip.append(errorMessage + "；显示值为上次成功读取") }
        if stale { tooltip.append("数据尚未更新") }
        item.button?.toolTip = tooltip.joined(separator: "\n")
        item.button?.setAccessibilityLabel("Codex Mini，\(title)，剩余额度\(warning ? "，数据待更新" : "")")
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func line(_ title: String, to menu: NSMenu) {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.isEnabled = false
        menu.addItem(row)
    }

    private func command(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self
        menu.addItem(row)
        return row
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        line("Codex Mini · 剩余额度", to: menu)
        for window in [snapshot?.limits?.primary, snapshot?.limits?.secondary].compactMap({ $0 }) {
            line(window.title(language: language), to: menu)
            if let reset = window.resetDate {
                line("重置：\(reset.formatted(date: .abbreviated, time: .shortened))", to: menu)
            }
        }
        if let updatedAt { line("更新于 \(updatedAt.formatted(date: .omitted, time: .standard))", to: menu) }
        if let errorMessage {
            line("⚠︎ \(errorMessage)", to: menu)
            if snapshot != nil { line("当前显示上次成功读取的额度", to: menu) }
        }
        menu.addItem(.separator())
        let refreshRow = command(isRefreshing ? "正在刷新…" : "立即刷新", action: #selector(refreshNow), to: menu)
        refreshRow.isEnabled = !isRefreshing && Date() >= nextAllowedRefresh
        let languageRow = NSMenuItem(title: "时间语言", action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for (value, title) in [(TimeLanguage.chinese, "中文"), (.english, "English")] {
            let row = command(title, action: #selector(changeLanguage(_:)), to: languages)
            row.representedObject = value.rawValue
            row.state = language == value ? .on : .off
        }
        languageRow.submenu = languages
        menu.addItem(languageRow)
        let startup = command("开机启动", action: #selector(toggleStartup), to: menu)
        startup.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        _ = command("退出 Codex Mini", action: #selector(quit), to: menu)
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = TimeLanguage(rawValue: raw) else { return }
        language = value
        render()
    }

    @objc private func toggleStartup() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改开机启动"
            alert.informativeText = "请将 Codex Mini 放在应用程序文件夹，再到系统设置 → 通用 → 登录项中设置。"
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
