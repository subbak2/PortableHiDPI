import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var sessions: [String: HiDPISession] = [:] // by PhysicalDisplay.key
    private var displayCache: [String: PhysicalDisplay] = [:]
    private var reconfigureScheduled = false
    private var isAsleep = false
    private let defaults = UserDefaults.standard
    private let repoURL = URL(string: "https://github.com/subbak2/PortableHiDPI")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "PortableHiDPI")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
            let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { app.scheduleReconcile() }
        }, Unmanaged.passUnretained(self).toOpaque())

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        reconcile()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
    }

    // MARK: - Saved settings (per monitor)

    private func savedResolution(for key: String) -> Resolution? {
        defaults.string(forKey: "hidpi.\(key)").flatMap(Resolution.init(storageValue:))
    }

    private func saveResolution(_ res: Resolution?, for key: String) {
        if let res {
            defaults.set(res.storageValue, forKey: "hidpi.\(key)")
        } else {
            defaults.removeObject(forKey: "hidpi.\(key)")
        }
    }

    private func preferredRefresh(for display: PhysicalDisplay) -> Double {
        let rate = defaults.double(forKey: "refresh.\(display.key)")
        return display.supportedRefreshRates.contains(rate) ? rate : 60
    }

    // MARK: - Display changes

    private func scheduleReconcile() {
        guard !reconfigureScheduled else { return }
        reconfigureScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.reconfigureScheduled = false
            self?.reconcile()
        }
    }

    /// Drops sessions whose monitor went away and re-applies saved settings to monitors that came back.
    private func reconcile() {
        guard !isAsleep else { return }
        let externals = Displays.externals(cache: &displayCache)
        let present = Set(externals.map(\.key))
        for (key, session) in sessions where !present.contains(key) || CGDisplayIsOnline(session.display.id) == 0 {
            session.stop()
            sessions[key] = nil
        }
        for display in externals where sessions[display.key] == nil {
            if let res = savedResolution(for: display.key), display.candidates.contains(res) {
                enable(display, res, refresh: preferredRefresh(for: display), remember: false)
            }
        }
    }

    /// Mirroring a virtual display across sleep can freeze WindowServer or come back unmirrored,
    /// so tear everything down before sleep and rebuild from the saved settings after wake.
    @objc private func willSleep() {
        isAsleep = true
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
    }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isAsleep = false
            self?.reconcile()
        }
    }

    private func enable(_ display: PhysicalDisplay, _ res: Resolution, refresh: Double, remember: Bool) {
        sessions[display.key]?.stop()
        let session = HiDPISession(display: display, resolution: res, refresh: refresh)
        sessions[display.key] = session
        if remember { saveResolution(res, for: display.key) }
        session.start { [weak self] error in
            guard let self, let error else { return }
            if self.sessions[display.key] === session { self.sessions[display.key] = nil }
            // Don't retry a failing setting on every reconnect.
            self.saveResolution(nil, for: display.key)
            self.showError(error, display: display)
        }
    }

    private func disable(_ key: String) {
        sessions[key]?.stop()
        sessions[key] = nil
        saveResolution(nil, for: key)
    }

    private func showError(_ error: Error, display: PhysicalDisplay) {
        let alert = NSAlert()
        alert.messageText = L("HiDPI could not be enabled on \(display.name)", "\(display.name)에서 HiDPI를 켜지 못했습니다")
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let externals = Displays.externals(cache: &displayCache)
        if externals.isEmpty {
            menu.addItem(disabledItem(L("No external display", "연결된 외장 모니터 없음")))
        }
        for display in externals {
            addSection(for: display, to: menu)
            menu.addItem(.separator())
        }
        if !externals.isEmpty { menu.removeItem(at: menu.numberOfItems - 1) }

        menu.addItem(.separator())
        let login = NSMenuItem(title: L("Launch at Login", "로그인 시 실행"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let about = NSMenuItem(title: L("About PortableHiDPI…", "PortableHiDPI 정보…"), action: #selector(openRepo), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: L("Quit", "종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addSection(for display: PhysicalDisplay, to menu: NSMenu) {
        var header = "\(display.name) — \(display.native)"
        if let d = display.diagonalInches { header += String(format: " · %.1f\"", d) }
        menu.addItem(disabledItem(header))

        let active = sessions[display.key]
        let off = NSMenuItem(title: L("Off (macOS default)", "끄기 (macOS 기본)"), action: #selector(selectOff(_:)), keyEquivalent: "")
        off.target = self
        off.representedObject = display.key
        off.state = active == nil ? .on : .off
        off.indentationLevel = 1
        menu.addItem(off)

        let refresh = active?.refresh ?? preferredRefresh(for: display)
        let recommended = display.recommended
        for res in display.candidates {
            var title = L("\(res) HiDPI", "\(res) HiDPI")
            if res == recommended { title += L("  (recommended)", "  (추천)") }
            let item = NSMenuItem(title: title, action: #selector(selectResolution(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Choice(display: display, resolution: res, refresh: refresh)
            item.state = active?.resolution == res ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        let sizeTitle = display.panelInches.map { L("Monitor Size: \(Self.inchText($0))", "모니터 크기: \(Self.inchText($0))") }
            ?? L("Monitor Size: Auto", "모니터 크기: 자동")
        let sizeParent = NSMenuItem(title: sizeTitle, action: nil, keyEquivalent: "")
        sizeParent.indentationLevel = 1
        let sizeMenu = NSMenu()
        let auto = NSMenuItem(title: L("Auto (from monitor)", "자동 (모니터 정보)"), action: #selector(selectPanelSize(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = SizeChoice(key: display.key, inches: nil)
        auto.state = display.panelInches == nil ? .on : .off
        sizeMenu.addItem(auto)
        for inches in Displays.panelSizes {
            let item = NSMenuItem(title: Self.inchText(inches), action: #selector(selectPanelSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = SizeChoice(key: display.key, inches: inches)
            item.state = display.panelInches == inches ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeParent.submenu = sizeMenu
        menu.addItem(sizeParent)

        let rates = display.supportedRefreshRates
        if rates.count > 1 {
            let parent = NSMenuItem(title: L("Refresh Rate: \(Int(refresh)) Hz", "주사율: \(Int(refresh))Hz"), action: nil, keyEquivalent: "")
            parent.indentationLevel = 1
            let sub = NSMenu()
            for rate in rates {
                let item = NSMenuItem(title: "\(Int(rate)) Hz", action: #selector(selectRefresh(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = Choice(display: display, resolution: active?.resolution, refresh: rate)
                item.state = rate == refresh ? .on : .off
                sub.addItem(item)
            }
            parent.submenu = sub
            menu.addItem(parent)
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private final class Choice {
        let display: PhysicalDisplay
        let resolution: Resolution?
        let refresh: Double
        init(display: PhysicalDisplay, resolution: Resolution?, refresh: Double) {
            self.display = display
            self.resolution = resolution
            self.refresh = refresh
        }
    }

    private final class SizeChoice {
        let key: String
        let inches: Double?
        init(key: String, inches: Double?) {
            self.key = key
            self.inches = inches
        }
    }

    private static func inchText(_ inches: Double) -> String {
        inches == inches.rounded() ? "\(Int(inches))\"" : String(format: "%.1f\"", inches)
    }

    /// Only changes the "(recommended)" hint and the size reported for the virtual display;
    /// an active session keeps running until the next resolution pick.
    @objc private func selectPanelSize(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? SizeChoice else { return }
        if let inches = c.inches {
            defaults.set(inches, forKey: "inches.\(c.key)")
        } else {
            defaults.removeObject(forKey: "inches.\(c.key)")
        }
    }

    @objc private func selectOff(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        disable(key)
    }

    @objc private func selectResolution(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? Choice, let res = c.resolution else { return }
        enable(c.display, res, refresh: c.refresh, remember: true)
    }

    @objc private func selectRefresh(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? Choice else { return }
        defaults.set(c.refresh, forKey: "refresh.\(c.display.key)")
        if let res = c.resolution {
            enable(c.display, res, refresh: c.refresh, remember: true)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openRepo() {
        NSWorkspace.shared.open(repoURL)
    }
}
