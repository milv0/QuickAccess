//
//  QuickAccess.swift
//  QuickAccess - Menubar app for quick website launching
//
//  Created by Mingyu
//  Contact: uqwe00@gmail.com
//  © 2026 Mingyu. All rights reserved.
//

import Cocoa
import ServiceManagement
import SwiftUI

enum Defaults {
    static let appVersion = "1.1.0"
    static let defaultWidth = 800
    static let defaultHeight = 600
    static let defaultX = 100
    static let defaultY = 100
    static let resizeDelay = 0.2
    static let coldStartDelay = 3.0
    static let resizeRetries = 20
    static let retryInterval = 0.2
    static let domainRegex = try? NSRegularExpression(pattern: "^[a-zA-Z0-9._-]+$")
}

// MARK: - Data Models for config persistence

struct Site: Codable {
    var name: String
    var url: String
    var width: Int
    var height: Int
    var x: Int
    var y: Int
}

struct Config: Codable {
    var runInBackground: Bool
    var sites: [Site]

    init(runInBackground: Bool = true, sites: [Site]) {
        self.runInBackground = runInBackground
        self.sites = sites
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runInBackground = try container.decodeIfPresent(Bool.self, forKey: .runInBackground) ?? true
        sites = try container.decode([Site].self, forKey: .sites)
    }
}


// MARK: - App Delegate — menu bar app lifecycle

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var config: Config = Config(sites: [])
    let configPath = NSString(string: "~/.quickaccess.json").expandingTildeInPath
    var settingsWindow: NSWindow?
    let resizeQueue = DispatchQueue(label: "com.mingyupark.QuickAccess.resize")

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        copyDefaultConfigIfNeeded()
        loadConfig()
        NSApp.setActivationPolicy(config.runInBackground ? .accessory : .regular)

        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "QuickAccess")
        }
        buildMenu()
    }

    // MARK: Config handling — writes default config on first launch
    func copyDefaultConfigIfNeeded() {
        if !FileManager.default.fileExists(atPath: configPath) {
            let defaultJSON = """
            {
              "sites": [
                {"name": "Google", "url": "https://www.google.com/", "width": 600, "height": 400, "x": 100, "y": 100},
                {"name": "GitHub", "url": "https://github.com/", "width": 800, "height": 600, "x": 100, "y": 100}
              ]
            }
            """
            do {
                try defaultJSON.write(toFile: configPath, atomically: true, encoding: .utf8)
            } catch {
                NSLog("[QuickAccess] Failed to write default config: %@", error.localizedDescription)
            }
        }
    }

    func loadConfig() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
            NSLog("[QuickAccess] Failed to read config file at %@", configPath)
            return
        }
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Cannot read config file. Using defaults."
                alert.alertStyle = .warning
                alert.runModal()
            }
            config = Config(sites: [
                Site(name: "Google", url: "https://www.google.com/", width: 600, height: 400, x: Defaults.defaultX, y: Defaults.defaultY),
                Site(name: "GitHub", url: "https://github.com/", width: Defaults.defaultWidth, height: Defaults.defaultHeight, x: Defaults.defaultX, y: Defaults.defaultY)
            ])
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        for site in config.sites {
            let item = NSMenuItem(title: site.name, action: #selector(openSite(_:)), keyEquivalent: "")
            item.representedObject = site
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About QuickAccess", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "QuickAccess"
        alert.informativeText = "Version \(Defaults.appVersion)\n\nMade by Mingyu\nuqwe00@gmail.com"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: Site opening logic — launches Chrome in app mode, then repositions via AppleScript
    @objc func openSite(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? Site else { return }

        // Fix #6: Check if Chrome is installed
        if !FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app") {
            let alert = NSAlert()
            alert.messageText = "Google Chrome is not installed."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        // Fix #1: Escape all AppleScript-special characters to prevent injection
        let rawDomain = URL(string: site.url)?.host ?? ""
        // Strict validation: only allow safe hostname characters
        guard let domainRegex = Defaults.domainRegex,
              !rawDomain.isEmpty,
              domainRegex.firstMatch(in: rawDomain, range: NSRange(rawDomain.startIndex..., in: rawDomain)) != nil else {
            NSLog("[QuickAccess] Invalid domain: %@", rawDomain)
            return
        }
        let domain = rawDomain

        // Validate bounds are numeric
        let bx = site.x
        let by = site.y
        let bw = site.width
        let bh = site.height
        let bounds = "\(bx), \(by), \(bx + bw), \(by + bh)"

        let retries = Defaults.resizeRetries
        let retryInterval = Defaults.retryInterval
        let script = """
        tell application "Google Chrome"
          repeat \(retries) times
            repeat with w in windows
              set tabUrl to URL of active tab of w
              if tabUrl contains "\(domain)" then
                set bounds of w to {\(bounds)}
                return
              end if
            end repeat
            delay \(retryInterval)
          end repeat
        end tell
        """

        // Detect if Chrome is already running for delay calculation
        let chromeRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.google.Chrome" }
        let delay = chromeRunning ? Defaults.resizeDelay : Defaults.coldStartDelay

        // Open Chrome in app mode using modern Process API
        let openTask = Process()
        openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openTask.arguments = ["-na", "Google Chrome", "--args", "--app=\(site.url)"]
        do {
            try openTask.run()
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Failed to launch Chrome."
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
            return
        }

        // Reposition the window via osascript after a short delay
        resizeQueue.asyncAfter(deadline: .now() + delay) {
            let scriptTask = Process()
            scriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            scriptTask.arguments = ["-e", script]
            do {
                try scriptTask.run()
                scriptTask.waitUntilExit()
                if scriptTask.terminationStatus != 0 {
                    NSLog("[QuickAccess] osascript exited with status %d", scriptTask.terminationStatus)
                }
            } catch {
                NSLog("[QuickAccess] Failed to launch osascript: %@", error.localizedDescription)
            }
        }
    }

    @objc func openSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        var sites = config.sites
        var runInBackground = config.runInBackground
        
        var settingsView = SettingsView(sites: .init(get: { sites }, set: { sites = $0 }),
                                         runInBackground: .init(get: { runInBackground }, set: { runInBackground = $0 }))
        settingsView.onSave = { [weak self] newSites, bg in
            guard let self = self else { return }
            self.config = Config(runInBackground: bg, sites: newSites)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(self.config) {
                try? data.write(to: URL(fileURLWithPath: self.configPath), options: .atomic)
            }
            self.buildMenu()
            NSApp.setActivationPolicy(bg ? .accessory : .regular)
        }
        settingsView.onReload = { [weak self] in
            self?.reloadConfig()
        }
        
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "QuickAccess Settings"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.styleMask = [.titled, .closable, .resizable]
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc func reloadConfig() {
        loadConfig()
        buildMenu()
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSLog("[QuickAccess] Launch at login toggle failed: %@", error.localizedDescription)
            }
        }
        buildMenu()
    }

    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}


import SwiftUI

// MARK: - SwiftUI Settings View

struct SettingsView: View {
    @Binding var sites: [Site]
    @Binding var runInBackground: Bool
    @State private var selectedIndex: Int? = nil
    @State private var showDeleteAlert = false
    @State private var showSavedFeedback = false
    
    var onSave: (([Site], Bool) -> Void)?
    var onReload: (() -> Void)?
    
    var body: some View {
        HSplitView {
            // Left: Site list
            VStack(spacing: 8) {
                List(selection: $selectedIndex) {
                    ForEach(sites.indices, id: \.self) { i in
                        Text(sites[i].name)
                            .tag(i)
                    }
                    .onMove { from, to in
                        sites.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.bordered)
                .frame(minWidth: 160)
                
                HStack(spacing: 4) {
                    Button("Add") { addSite() }
                    Button("Remove") { showDeleteAlert = true }
                        .disabled(selectedIndex == nil)
                }
                .padding(.bottom, 8)
            }
            .frame(width: 180)
            
            // Right: Site config
            VStack(alignment: .leading, spacing: 0) {
                if let idx = selectedIndex, idx < sites.count {
                    SiteConfigView(site: $sites[idx])
                } else {
                    Spacer()
                    Text("Select a site to configure")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
                
                Divider().padding(.vertical, 8)
                
                // Bottom bar
                HStack {
                    Toggle("Run in Background", isOn: $runInBackground)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    
                    Spacer()
                    
                    Button("Import") { importConfig() }
                    Button("Export") { exportConfig() }
                    Button("Reload") { onReload?() }
                    
                    Button(showSavedFeedback ? "Saved ✓" : "Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 234/255, green: 88/255, blue: 12/255))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("Delete site?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { removeSite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let idx = selectedIndex, idx < sites.count {
                Text("This will remove \"\(sites[idx].name)\".")
            }
        }
    }
    
    private func addSite() {
        sites.append(Site(name: "New Site", url: "https://", width: Defaults.defaultWidth, height: Defaults.defaultHeight, x: Defaults.defaultX, y: Defaults.defaultY))
        selectedIndex = sites.count - 1
    }
    
    private func removeSite() {
        guard let idx = selectedIndex, idx < sites.count else { return }
        sites.remove(at: idx)
        selectedIndex = sites.isEmpty ? nil : min(idx, sites.count - 1)
    }
    
    private func save() {
        onSave?(sites, runInBackground)
        showSavedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSavedFeedback = false }
    }
    
    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "quickaccess.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let configPath = NSString(string: "~/.quickaccess.json").expandingTildeInPath
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: configPath), to: url)
    }
    
    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(Config.self, from: data)
            let configPath = NSString(string: "~/.quickaccess.json").expandingTildeInPath
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            sites = config.sites
            runInBackground = config.runInBackground
            onReload?()
        } catch {
            // silent
        }
    }
}

// MARK: - Site Configuration Panel

struct SiteConfigView: View {
    @Binding var site: Site
    @State private var layoutSelection = 0
    @State private var sizeSelection = 0
    
    private let layoutOptions = ["Custom", "Center", "Left Half", "Right Half", "Top Half", "Bottom Half", "Top-Left", "Top-Right", "Bottom-Left", "Bottom-Right"]
    private let sizeOptions = ["Custom", "Tiny (400×200)", "Mini (600×300)", "Medium (800×500)", "Large (1000×700)", "XL (1200×800)", "Wide (1000×400)", "Tall (500×800)", "Full (1400×900)"]
    private let sizes: [(Int, Int)] = [(400,200), (600,300), (800,500), (1000,700), (1200,800), (1000,400), (500,800), (1400,900)]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name & URL
                Group {
                    LabeledField("Name") {
                        TextField("Site name", text: $site.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("URL") {
                        TextField("https://", text: $site.url)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Divider()
                
                // Layout & Size
                Group {
                    LabeledField("Layout") {
                        Picker("", selection: $layoutSelection) {
                            ForEach(0..<layoutOptions.count, id: \.self) { i in
                                Text(layoutOptions[i]).tag(i)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: layoutSelection) { applyLayout() }
                    }
                    
                    LabeledField("Size") {
                        Picker("", selection: $sizeSelection) {
                            ForEach(0..<sizeOptions.count, id: \.self) { i in
                                Text(sizeOptions[i]).tag(i)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: sizeSelection) { applySize() }
                    }
                }
                
                Divider()
                
                // Dimensions
                HStack(spacing: 12) {
                    LabeledField("Width") {
                        TextField("", value: $site.width, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    LabeledField("Height") {
                        TextField("", value: $site.height, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                
                HStack(spacing: 12) {
                    LabeledField("X") {
                        TextField("", value: $site.x, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    LabeledField("Y") {
                        TextField("", value: $site.y, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    Button("⊹ Center") { centerXY() }
                        .buttonStyle(.bordered)
                }
                
                // Minimap
                MinimapSwiftUI(site: site)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                
                Spacer()
                
                // Uninstall
                HStack {
                    Spacer()
                    Button("Uninstall App") { uninstall() }
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                }
            }
            .padding(16)
        }
    }
    
    private func centerXY() {
        guard let screen = NSScreen.main else { return }
        let screenW = Int(screen.frame.width)
        let screenH = Int(screen.frame.height)
        site.x = (screenW - site.width) / 2
        site.y = (screenH - site.height) / 2
    }
    
    private func applyLayout() {
        guard let screen = NSScreen.main else { return }
        let screenW = Int(screen.frame.width)
        let screenH = Int(screen.frame.height)
        switch layoutSelection {
        case 1: centerXY()
        case 2: site.width = screenW/2; site.height = screenH; site.x = 0; site.y = 0
        case 3: site.width = screenW/2; site.height = screenH; site.x = screenW/2; site.y = 0
        case 4: site.width = screenW; site.height = screenH/2; site.x = 0; site.y = 0
        case 5: site.width = screenW; site.height = screenH/2; site.x = 0; site.y = screenH/2
        case 6: site.width = screenW/2; site.height = screenH/2; site.x = 0; site.y = 0
        case 7: site.width = screenW/2; site.height = screenH/2; site.x = screenW/2; site.y = 0
        case 8: site.width = screenW/2; site.height = screenH/2; site.x = 0; site.y = screenH/2
        case 9: site.width = screenW/2; site.height = screenH/2; site.x = screenW/2; site.y = screenH/2
        default: break
        }
    }
    
    private func applySize() {
        guard sizeSelection > 0 else { return }
        let (w, h) = sizes[sizeSelection - 1]
        site.width = w
        site.height = h
        if layoutSelection == 1 { centerXY() }
    }
    
    private func uninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall QuickAccess?"
        alert.informativeText = "This will remove the app, settings, and login item."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if #available(macOS 13.0, *) { try? SMAppService.mainApp.unregister() }
        let configPath = NSString(string: "~/.quickaccess.json").expandingTildeInPath
        try? FileManager.default.removeItem(atPath: configPath)
        NSWorkspace.shared.recycle([URL(fileURLWithPath: Bundle.main.bundlePath)]) { _, _ in
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Helper Views

struct LabeledField<Content: View>: View {
    let label: String
    let content: Content
    
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 50, alignment: .trailing)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            content
        }
    }
}

struct MinimapSwiftUI: View {
    let site: Site
    
    var body: some View {
        GeometryReader { geo in
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let screenW = screen.frame.width
            let screenH = screen.frame.height
            let scale = min(geo.size.width / screenW, geo.size.height / screenH)
            let mapW = screenW * scale
            let mapH = screenH * scale
            let offsetX = (geo.size.width - mapW) / 2
            
            ZStack(alignment: .topLeading) {
                // Screen
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.windowBackgroundColor))
                    .frame(width: mapW, height: mapH)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                    .offset(x: offsetX)
                
                // Site window
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.3))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.orange))
                    .frame(width: CGFloat(site.width) * scale, height: CGFloat(site.height) * scale)
                    .offset(x: offsetX + CGFloat(site.x) * scale, y: CGFloat(site.y) * scale)
            }
        }
    }
}

// MARK: - App entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Enable standard Edit menu for copy/paste/cut in text fields
let mainMenu = NSMenu()
let editMenuItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)
app.mainMenu = mainMenu

app.run()
