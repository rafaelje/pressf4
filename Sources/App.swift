import SwiftUI
import AppKit
import UserNotifications

@main
struct PressF4App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // We own all windows from AppKit (NSHostingController inside an NSWindow)
        // so this scene exists only to satisfy the App protocol.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
        installStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppController.shared.showMainWindow()
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            let img = NSImage(systemSymbolName: "camera.viewfinder",
                              accessibilityDescription: "PressF4")
            img?.isTemplate = true
            btn.image = img
        }

        let menu = NSMenu()
        addMenuItem(menu, title: "Capturar área   F4",
                    action: #selector(AppController.menuCapture))
        addMenuItem(menu, title: "Mostrar ventana   ⌃⌥⌘H",
                    action: #selector(AppController.menuShowWindow))
        addMenuItem(menu, title: "Abrir última captura   ⌃⌥⌘E",
                    action: #selector(AppController.menuOpenLatest))
        menu.addItem(.separator())
        addMenuItem(menu, title: "Salir",
                    action: #selector(AppController.menuQuit),
                    keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func addMenuItem(_ menu: NSMenu, title: String,
                             action: Selector, keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = AppController.shared
        menu.addItem(item)
    }
}

@MainActor
final class AppController: NSObject {
    static let shared = AppController()

    private var didStart = false
    private var mainWindow: NSWindow?

    func start() {
        guard !didStart else { return }
        didStart = true

        // Ensure menu bar / window can become active.
        NSApp.setActivationPolicy(.accessory)

        ShortcutsManager.shared.register([
            .captureArea: { [weak self] in self?.beginCapture() },
            .showWindow:  { [weak self] in self?.showMainWindow() },
            .openLatest:  { [weak self] in self?.openLatest() }
        ])

        warnIfHotkeyErrors()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        if LibraryStore.shared.captures.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showMainWindow()
            }
        }
    }

    func beginCapture() {
        SelectionOverlayController.shared.begin(
            onComplete: { [weak self] rect in
                Task { @MainActor in await self?.handleSelection(rect) }
            },
            onCancel: { /* no-op */ }
        )
    }

    @MainActor
    private func handleSelection(_ rect: CGRect) async {
        do {
            let cg = try await CaptureService.shared.capture(rectGlobal: rect)
            guard let capture = LibraryStore.shared.add(image: cg) else { return }

            if let nsImage = LibraryStore.shared.loadImage(for: capture) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([nsImage])
            }

            ThumbnailHUDController.shared.present(capture: capture) { [weak self] in
                self?.showMainWindow()
            }
        } catch {
            presentError(error)
        }
    }

    func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeMainWindow()
        }
        guard let window = mainWindow else { return }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeMainWindow() -> NSWindow {
        let content = MainWindowView(store: LibraryStore.shared)
        let hosting = NSHostingController(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "PressF4"
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 880, height: 540)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CapturaMainWindow")
        window.delegate = self
        return window
    }

    func openLatest() {
        guard let latest = LibraryStore.shared.latest else {
            beginCapture()
            return
        }
        LibraryStore.shared.selectedID = latest.id
        showMainWindow()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "No se pudo tomar la captura"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func warnIfHotkeyErrors() {
        let errors = ShortcutsManager.shared.registrationErrors
        guard !errors.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let alert = NSAlert()
            alert.messageText = "Algunos atajos no se pudieron registrar"
            let lines = errors.map { "• \($0.0.rawValue) (status \($0.1))" }.joined(separator: "\n")
            alert.informativeText = """
            \(lines)

            Probable causa: otra app (CleanShot, Raycast, Loom, etc.) o el sistema ya está usando el atajo. Usa el ícono de la barra de menú mientras tanto, o cambia los atajos en Sources/Services/ShortcutsManager.swift.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Menu selectors
    @objc func menuCapture()    { beginCapture() }
    @objc func menuShowWindow() { showMainWindow() }
    @objc func menuOpenLatest() { openLatest() }
    @objc func menuQuit()       { NSApp.terminate(nil) }
}

extension AppController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            // Return to menu-bar-only mode when window closes.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
