import AppKit
import Combine
import Darwin
import UserNotifications
#if canImport(LetGoCore)
import LetGoCore
#endif

@MainActor
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case ready
        case scanning
        case loaded
        case failed
    }

    enum WatchPurpose: Equatable {
        case notify
        case eject
    }

    @Published private(set) var status: Status = .ready
    @Published private(set) var result: InspectionResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionMessage: String?
    @Published private(set) var isWatching = false
    @Published private(set) var watchPurpose: WatchPurpose?
    @Published private(set) var isSupporter = false
    @Published var isSupporterPanelPresented = false
    @Published var isWhatsNewPresented = false

    private let scanner = LockScanner()
    private var scanTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?

    var supportURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "LetGoSupportURL") as? String,
            !value.isEmpty,
            let url = URL(string: value),
            url.scheme == "https",
            url.host != nil
        else { return nil }
        return url
    }

    var displayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Version \(version ?? "0.1.0")"
    }

    var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    deinit {
        scanTask?.cancel()
        watchTask?.cancel()
    }

    func chooseTarget() {
        let panel = NSOpenPanel()
        panel.title = "Choose something to inspect"
        panel.message = "Select a file, folder, or external drive. Let Go will check which processes currently have it open."
        panel.prompt = "Inspect"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        inspect(url)
    }

    func inspect(_ url: URL) {
        stopWatching()
        scanTask?.cancel()
        status = .scanning
        errorMessage = nil
        actionMessage = nil

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let inspection = try await scanner.scan(url: url)
                guard !Task.isCancelled else { return }
                result = inspection
                status = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                errorMessage = error.localizedDescription
                status = .failed
            }
        }
    }

    func rescan() {
        guard let target = result?.target else { return }
        inspect(target)
    }

    func returnToStart() {
        scanTask?.cancel()
        scanTask = nil
        stopWatching()
        result = nil
        errorMessage = nil
        actionMessage = nil
        status = .ready
    }

    func presentSupporterPanel() {
        isSupporterPanelPresented = true
    }

    func startWatching(autoEject: Bool) {
        guard isSupporter else {
            presentSupporterPanel()
            return
        }

        guard let currentResult = result else { return }
        if autoEject && !canEject(currentResult) {
            actionMessage = "Automatic eject is only available for ejectable external drives."
            return
        }

        scanTask?.cancel()
        watchTask?.cancel()
        isWatching = true
        watchPurpose = autoEject ? .eject : .notify
        actionMessage = autoEject
            ? "Watching the drive. Let Go will eject it as soon as it is free."
            : "Watching for open handles. Let Go will notify you when the item is free."
        let target = currentResult.target

        watchTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                    let inspection = try await scanner.scan(url: target)
                    guard !Task.isCancelled else { return }

                    result = inspection
                    status = .loaded

                    guard inspection.processes.isEmpty else { continue }
                    isWatching = false
                    watchPurpose = nil

                    if autoEject {
                        ejectVolume()
                    } else {
                        actionMessage = "It is free now. You can safely continue."
                        notifyThatTargetIsFree(target)
                    }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    isWatching = false
                    watchPurpose = nil
                    actionMessage = "Watching stopped: \(error.localizedDescription)"
                    return
                }
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        isWatching = false
        watchPurpose = nil
    }

    func revealTarget() {
        guard let target = result?.target else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func reveal(_ handle: OpenHandle) {
        let url = URL(fileURLWithPath: handle.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func requestQuit(_ process: HoldingProcess) {
        actionMessage = nil
        let currentUserID = getuid()

        guard process.userID == currentUserID, process.userID != 0 else {
            actionMessage = "Let Go will not stop system processes. Close the related task normally or wait for it to finish."
            return
        }

        let didRequestTermination: Bool
        if let application = NSRunningApplication(processIdentifier: process.pid) {
            didRequestTermination = application.terminate()
        } else {
            didRequestTermination = Darwin.kill(process.pid, SIGTERM) == 0
        }

        if didRequestTermination {
            actionMessage = "Asked \(displayName(for: process)) to quit. Checking again…"
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.rescan()
            }
        } else {
            actionMessage = "\(displayName(for: process)) did not accept the quit request. Close it normally, then check again."
        }
    }

    func ejectVolume() {
        guard let result, canEject(result) else { return }
        let target = result.target
        actionMessage = nil

        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: target)
            actionMessage = "\(target.lastPathComponent) was safely ejected."
        } catch {
            actionMessage = "The drive is still busy: \(error.localizedDescription)"
            inspect(target)
        }
    }

    func openSupportPage() {
        if let supportURL {
            NSWorkspace.shared.open(supportURL)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Support link coming soon"
        alert.informativeText = "This is a preview. The final button will open Let Go’s support page."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showPrivacyInfo() {
        let alert = NSAlert()
        alert.messageText = "Private by design"
        alert.informativeText = "Let Go only checks the item you choose. File names and contents never leave your Mac, and system processes are never force-quit. Suggestions are sent only when you press Send, using FormSubmit for delivery."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showWhatsNew() {
        isWhatsNewPresented = true
    }

    private func notifyThatTargetIsFree(_ target: URL) {
        NSApp.requestUserAttention(.informationalRequest)

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }

            let updatedSettings = await center.notificationSettings()
            guard updatedSettings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Let Go"
            content.body = "\(target.lastPathComponent) is no longer being held open."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    func displayName(for process: HoldingProcess) -> String {
        NSRunningApplication(processIdentifier: process.pid)?.localizedName ?? process.command
    }

    func icon(for process: HoldingProcess) -> NSImage {
        if let icon = NSRunningApplication(processIdentifier: process.pid)?.icon {
            return icon
        }
        return NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil) ?? NSImage()
    }

    func icon(for target: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: target.path)
    }

    func isSafeToQuit(_ process: HoldingProcess) -> Bool {
        process.userID == getuid() && process.userID != 0
    }

    func canEject(_ result: InspectionResult) -> Bool {
        guard result.kind == .volume, result.target.path != "/" else { return false }
        let values = try? result.target.resourceValues(forKeys: [.volumeIsEjectableKey])
        return values?.volumeIsEjectable == true
    }
}
