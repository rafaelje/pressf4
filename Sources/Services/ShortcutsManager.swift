import Foundation
import AppKit
import Carbon.HIToolbox

enum HotkeyAction: String, CaseIterable {
    case captureArea
    case showWindow
    case openLatest
}

private struct HotkeyDef {
    let action: HotkeyAction
    let keyCode: UInt32
    let modifiers: UInt32
}

@MainActor
final class ShortcutsManager {
    static let shared = ShortcutsManager()

    private var refs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextId: UInt32 = 1

    private let defaults: [HotkeyDef] = [
        // F4  → capture area
        .init(action: .captureArea,
              keyCode: UInt32(kVK_F4),
              modifiers: 0),
        // ⌃⌥⌘ H  → show main window
        .init(action: .showWindow,
              keyCode: UInt32(kVK_ANSI_H),
              modifiers: UInt32(controlKey | optionKey | cmdKey)),
        // ⌃⌥⌘ E  → open latest in editor
        .init(action: .openLatest,
              keyCode: UInt32(kVK_ANSI_E),
              modifiers: UInt32(controlKey | optionKey | cmdKey)),
    ]

    func register(_ bindings: [HotkeyAction: () -> Void]) {
        installEventHandler()
        for def in defaults {
            guard let cb = bindings[def.action] else { continue }
            register(def, callback: cb)
        }
    }

    private(set) var registrationErrors: [(HotkeyAction, OSStatus)] = []

    private func register(_ def: HotkeyDef, callback: @escaping () -> Void) {
        var hkRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x43505448), id: nextId) // 'CPTH'
        let status = RegisterEventHotKey(def.keyCode,
                                         def.modifiers,
                                         id,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hkRef)
        if status == noErr {
            refs.append(hkRef)
            handlers[nextId] = callback
            nextId += 1
            NSLog("PressF4: registered hotkey \(def.action) (keyCode=\(def.keyCode) mods=\(def.modifiers))")
        } else {
            registrationErrors.append((def.action, status))
            let reason = describe(status: status)
            NSLog("PressF4: FAILED to register \(def.action) status=\(status) (\(reason))")
        }
    }

    private func describe(status: OSStatus) -> String {
        switch status {
        case -9878: return "eventHotKeyExistsErr — the shortcut is already in use by another app"
        case -50:   return "paramErr — invalid parameters"
        default:    return "code \(status)"
        }
    }

    private var installed = false
    private func installEventHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            { (_, event, _) -> OSStatus in
                                var hkId = EventHotKeyID()
                                let err = GetEventParameter(event,
                                                            EventParamName(kEventParamDirectObject),
                                                            EventParamType(typeEventHotKeyID),
                                                            nil,
                                                            MemoryLayout<EventHotKeyID>.size,
                                                            nil,
                                                            &hkId)
                                if err == noErr {
                                    DispatchQueue.main.async {
                                        ShortcutsManager.shared.handle(id: hkId.id)
                                    }
                                }
                                return noErr
                            },
                            1,
                            &spec,
                            nil,
                            nil)
    }

    fileprivate func handle(id: UInt32) {
        handlers[id]?()
    }

    func unregisterAll() {
        for ref in refs { if let r = ref { UnregisterEventHotKey(r) } }
        refs.removeAll()
        handlers.removeAll()
    }
}
