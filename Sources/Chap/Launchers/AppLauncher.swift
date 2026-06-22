import ApplicationServices
import Cocoa

/// macOS 앱을 실행하고 Accessibility API로 윈도우를 리사이즈하는 런처
enum AppLauncher {
    /// 앱을 실행하고 윈도우 크기/위치를 조정
    static func launch(_ site: Site, resizeQueue: DispatchQueue, onComplete: (() -> Void)? = nil) {
        guard let path = site.appPath, !path.isEmpty else {
            LauncherUtils.showAlert(message: "No app path configured for \"\(site.name)\".")
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            LauncherUtils.showAlert(message: "App not found at: \(path)")
            return
        }

        let bundle = Bundle(path: path)
        let bundleId = bundle?.bundleIdentifier

        let screen = targetScreen(for: site)
        let bounds = centeredBounds(for: site, on: screen)
        let bw = site.width
        let bh = site.height

        NSLog(
            "[AppLauncher] launch site=%@ path=%@ bundleId=%@",
            site.name, path, bundleId ?? "nil")
        NSLog(
            "[AppLauncher] target screen=%@ bounds={left:%d, top:%d, w:%d, h:%d}",
            screen.localizedName, bounds.left, bounds.top, bw, bh)

        let canResize = checkAccessibility()
        if !canResize {
            NSLog("[AppLauncher] Accessibility not granted — launching without resize")
        }

        let appRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleId
        }

        let appURL = URL(fileURLWithPath: path)
        let openConfig = NSWorkspace.OpenConfiguration()
        openConfig.activates = true
        let startTime = CFAbsoluteTimeGetCurrent()

        NSWorkspace.shared.openApplication(at: appURL, configuration: openConfig) { app, error in
            if let error = error {
                NSLog("[AppLauncher] openApplication failed: %@", error.localizedDescription)
                onComplete?()
                return
            }
            guard let app = app else {
                onComplete?()
                return
            }
            NSLog(
                "[AppLauncher] app opened pid=%d localizedName=%@",
                app.processIdentifier, app.localizedName ?? "?")

            guard canResize else {
                onComplete?()
                return
            }

            let position = CGPoint(x: bounds.left, y: bounds.top)
            let size = CGSize(width: bw, height: bh)

            resizeQueue.async {
                let success = axResize(
                    pid: app.processIdentifier,
                    position: position,
                    size: size,
                    isRunning: appRunning
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let result = success ? "success" : "failed"
                NSLog(
                    "[AppLauncher] AX resize %@ for %@ — total %.2fs",
                    result, site.name, elapsed)
                ResizeLogger.log(
                    site: site.name, type: "app",
                    appState: appRunning ? "running" : "cold",
                    attempt: 1, delay: 0,
                    totalTime: elapsed, result: result,
                    windowCount: 0,
                    display: screen.localizedName,
                    size: "\(site.width)x\(site.height)")
                onComplete?()
            }
        }
    }

    // MARK: - AX API Resize

    /// AX API를 사용하여 윈도우 리사이즈. 윈도우가 뜰 때까지 폴링.
    private static func axResize(
        pid: pid_t, position: CGPoint, size: CGSize, isRunning: Bool
    ) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        let maxAttempts = isRunning ? 30 : 50
        let interval: useconds_t = isRunning ? 50_000 : 100_000  // 50ms / 100ms

        // running 앱은 activate 후 포커스 전환 대기
        if isRunning {
            usleep(150_000)  // 150ms
        }

        for _ in 0..<maxAttempts {
            var windowValue: AnyObject?
            let err = AXUIElementCopyAttributeValue(
                app, kAXFocusedWindowAttribute as CFString, &windowValue)
            if err == .success, let window = windowValue {
                let win = window as! AXUIElement
                setPosition(win, position)
                setSize(win, size)
                // size 적용 확인 후 position 재설정
                usleep(50_000)
                setSize(win, size)
                setPosition(win, position)
                return true
            }
            usleep(interval)
        }
        return false
    }

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    // MARK: - Accessibility 권한

    private static var accessibilityPromptShown = false

    private static func checkAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        if trusted { return true }
        if !accessibilityPromptShown {
            accessibilityPromptShown = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        return false
    }
}
