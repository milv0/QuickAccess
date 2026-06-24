import Foundation

public struct SettingsPayload {
    public let sites: [Site]
    public let runInBackground: Bool
    public let showGuideWindow: Bool
    public let launchAtLogin: Bool
}

public final class SettingsViewModel: ObservableObject {
    @Published public var sites: [Site]
    @Published public var runInBackground: Bool
    @Published public var showGuideWindow: Bool
    @Published public var launchAtLogin: Bool
    @Published public var originalSites: [Site]
    @Published public var originalBg: Bool
    @Published public var originalGuide: Bool
    @Published public var originalLogin: Bool
    public var onSave: ((SettingsPayload) -> Void)?
    public var onReload: (() -> Void)?

    public var hasChanges: Bool {
        sites != originalSites || runInBackground != originalBg
            || showGuideWindow != originalGuide || launchAtLogin != originalLogin
    }

    public func markSaved() {
        originalSites = sites
        originalBg = runInBackground
        originalGuide = showGuideWindow
        originalLogin = launchAtLogin
    }

    public init(
        sites: [Site], runInBackground: Bool, showGuideWindow: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.sites = sites
        self.runInBackground = runInBackground
        self.showGuideWindow = showGuideWindow
        self.launchAtLogin = launchAtLogin
        self.originalSites = sites
        self.originalBg = runInBackground
        self.originalGuide = showGuideWindow
        self.originalLogin = launchAtLogin
    }
}
