import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var mainWindow: NSWindow?
    private var suggestionsWindow: NSWindow?
    private var serviceProvider: FinderServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMainWindow()
        configureMainMenu()
        configureFinderService()
        showMainWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        showMainWindow()
        model.inspect(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func configureMainWindow() {
        let rootView = ContentView(
            model: model,
            onShowSuggestions: { [weak self] in
                self?.showSuggestions()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Let Go"
        window.setContentSize(NSSize(width: 720, height: 620))
        window.minSize = NSSize(width: 620, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        mainWindow = window
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Let Go")
        applicationMenu.addItem(menuItem("Support Let Go", action: #selector(showSupporterPanel)))
        applicationMenu.addItem(.separator())

        let hideItem = menuItem("Hide Let Go", action: #selector(NSApplication.hide(_:)), key: "h")
        hideItem.target = NSApp
        applicationMenu.addItem(hideItem)

        let hideOthersItem = menuItem("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        applicationMenu.addItem(hideOthersItem)

        let showAllItem = menuItem("Show All", action: #selector(NSApplication.unhideAllApplications(_:)))
        showAllItem.target = NSApp
        applicationMenu.addItem(showAllItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(menuItem("Quit Let Go", action: #selector(quitFromMenu), key: "q"))
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = nil
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func configureFinderService() {
        let provider = FinderServiceProvider { [weak self] urls in
            guard let self, let first = urls.first else { return }
            showMainWindow()
            model.inspect(first)
        }
        NSApp.servicesProvider = provider
        NSApp.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
        serviceProvider = provider
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func showSupporterPanel() {
        showMainWindow()
        model.presentSupporterPanel()
    }

    @objc private func showSuggestions() {
        if let suggestionsWindow {
            suggestionsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let suggestionsView = SuggestionsView(
            appIcon: model.appIcon,
            onClose: { [weak self] in
                self?.suggestionsWindow?.orderOut(nil)
            }
        )
        let hostingController = NSHostingController(rootView: suggestionsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Suggestions"
        window.setContentSize(NSSize(width: 560, height: 610))
        window.minSize = NSSize(width: 520, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        suggestionsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
