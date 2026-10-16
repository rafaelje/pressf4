import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        addMenuItem(menu, title: "Capture Area   F4",
                    action: #selector(AppController.menuCapture))
        addMenuItem(menu, title: "Capture Screen", action: #selector(AppController.menuCaptureScreen))
        addMenuItem(menu, title: "Capture Window…", action: #selector(AppController.menuCaptureWindow))
        addMenuItem(menu, title: "Repeat Last Area", action: #selector(AppController.menuRepeatCapture))
        addMenuItem(menu, title: "Capture Area after 5 seconds", action: #selector(AppController.menuDelayedCapture))
        addMenuItem(menu, title: "Record GIF…", action: #selector(AppController.menuRecordGIF))
        addMenuItem(menu, title: "Scrolling Capture…", action: #selector(AppController.menuScrollingCapture))
        addMenuItem(menu, title: "Import Image…", action: #selector(AppController.menuImportImage))
        addMenuItem(menu, title: "Capture Options…", action: #selector(AppController.menuCaptureOptions))
        menu.addItem(.separator())
        addMenuItem(menu, title: "Show Window   ⌃⌥⌘H",
                    action: #selector(AppController.menuShowWindow))
        addMenuItem(menu, title: "Open Latest Capture   ⌃⌥⌘E",
                    action: #selector(AppController.menuOpenLatest))
        menu.addItem(.separator())
        addMenuItem(menu, title: "Quit",
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
    private var captureBusy = false
    private var optionsWindow: NSWindow?
    private var lastRect: CGRect? {
        get { UserDefaults.standard.string(forKey: "pressf4.lastRect").map(NSRectFromString) }
        set { UserDefaults.standard.set(newValue.map(NSStringFromRect), forKey: "pressf4.lastRect") }
    }

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

        if LibraryStore.shared.captures.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showMainWindow()
            }
        }
    }

    func beginCapture() {
        guard !captureBusy else { return }
        SelectionOverlayController.shared.begin(
            onComplete: { [weak self] rect in
                Task { @MainActor in await self?.handleSelection(rect) }
            },
            onCancel: { /* no-op */ }
        )
    }

    @MainActor
    private func handleSelection(_ rect: CGRect) async {
        guard !captureBusy else { return }
        captureBusy = true
        defer { captureBusy = false }
        do {
            let cg = try await CaptureService.shared.capture(rectGlobal: rect)
            lastRect = rect
            try acceptCapture(cg)
        } catch {
            presentError(error, title: "Could not take the capture")
        }
    }

    func acceptCapture(_ image: CGImage) throws {
        let capture = try LibraryStore.shared.add(image: image)
        ThumbnailHUDController.copyToPasteboard(capture: capture)
        ThumbnailHUDController.shared.present(capture: capture) { [weak self] in
            LibraryStore.shared.selectedID = capture.id
            self?.showMainWindow()
        }
    }

    func captureScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
              let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else { return }
        let rect = CaptureGeometry.toGlobalTopLeft(screen.frame, primaryHeight: primary.frame.height)
        Task { await handleSelection(rect) }
    }

    func repeatCapture() {
        guard let rect = lastRect else { beginCapture(); return }
        Task { await handleSelection(rect) }
    }

    func captureAfterDelay() {
        guard !captureBusy else { return }
        SelectionOverlayController.shared.begin(onComplete: { rect in
            self.captureBusy = true
            Task {
                try? await Task.sleep(for: .seconds(5))
                self.captureBusy = false
                await self.handleSelection(rect)
            }
        }, onCancel: {})
    }

    func captureWindow() {
        guard !captureBusy else { return }
        captureBusy = true
        Task {
            defer { captureBusy = false }
            do {
                let windows = try await CaptureService.shared.availableWindows()
                guard !windows.isEmpty else { throw CaptureError.captureFailed("No capturable windows are open.") }
                let alert = NSAlert()
                alert.messageText = "Capture Window"
                alert.informativeText = "Choose a window. Other windows will not appear in the capture."
                let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
                for window in windows {
                    picker.addItem(withTitle: "\(window.owningApplication?.applicationName ?? "App") — \(window.title ?? "Untitled")")
                }
                alert.accessoryView = picker
                alert.addButton(withTitle: "Capture")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let image = try await CaptureService.shared.capture(window: windows[picker.indexOfSelectedItem])
                try acceptCapture(image)
            } catch { presentError(error, title: "Could not capture the window") }
        }
    }

    func showCaptureOptions() {
        if optionsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 448, height: 420),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Capture Options"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CaptureOptionsView())
            window.center()
            optionsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        optionsWindow?.makeKeyAndOrderFront(nil)
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Open an editable PressF4 project (.pressf4.json)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try JSONDecoder().decode(EditableCaptureDocument.self, from: Data(contentsOf: url))
            guard document.version == 1,
                  let image = NSImage(data: document.imagePNG),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  cg.width <= 32768, cg.height <= 32768,
                  Double(cg.width) * Double(cg.height) <= 100_000_000 else {
                throw CaptureError.captureFailed("This project version or image size is not supported.")
            }
            let capture = try LibraryStore.shared.add(image: cg)
            do {
                try LibraryStore.shared.saveAnnotations(document.layer, for: capture)
            } catch {
                try? LibraryStore.shared.delete(capture)
                throw error
            }
            showMainWindow()
        } catch { presentError(error, title: "Could not open project") }
    }

    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let image = NSImage(contentsOf: url),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CaptureError.captureFailed("The selected image could not be opened.")
            }
            try acceptCapture(cg)
            showMainWindow()
        } catch { presentError(error, title: "Could not import image") }
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

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
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
            alert.messageText = "Some shortcuts could not be registered"
            let lines = errors.map { "• \($0.0.rawValue) (status \($0.1))" }.joined(separator: "\n")
            alert.informativeText = """
            \(lines)

            Likely cause: another app (CleanShot, Raycast, Loom, etc.) or the system is already using the shortcut. Use the menu bar icon in the meantime, or change the shortcuts in Sources/Services/ShortcutsManager.swift.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Menu selectors
    @objc func menuRecordGIF() { GIFRecordingController.shared.begin() }
    @objc func menuCaptureOptions() { showCaptureOptions() }
    @objc func menuCaptureScreen() { captureScreen() }
    @objc func menuCaptureWindow() { captureWindow() }
    @objc func menuRepeatCapture() { repeatCapture() }
    @objc func menuDelayedCapture() { captureAfterDelay() }
    @objc func menuScrollingCapture() { ScrollingCaptureController.shared.begin() }
    @objc func menuImportImage() { importImage() }
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
