import Carbon
import AppKit

@MainActor
final class HotKeyManager: ObservableObject {
    @Published private(set) var regionStatus = "Not registered"
    @Published private(set) var displayStatus = "Not registered"
    @Published private(set) var precisionStatus = "Not registered"
    var isReady: Bool { regionRef != nil && displayRef != nil && precisionRef != nil }
    var onPrecisionCapture: (() -> Void)?
    var onRegionCapture: (() -> Void)?
    var onDisplayCapture: (() -> Void)?

    private var regionRef: EventHotKeyRef?
    private var displayRef: EventHotKeyRef?
    private var precisionRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }
                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr, hotKeyID.signature == HotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in manager.handle(id: hotKeyID.id) }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            regionStatus = "Could not listen for shortcuts (\(handlerStatus))"
            displayStatus = regionStatus
            precisionStatus = regionStatus
            return
        }

        var systemKeys: Unmanaged<CFArray>?
        let systemStatus = CopySymbolicHotKeys(&systemKeys)
        guard systemStatus == noErr, let keys = systemKeys?.takeRetainedValue() as? [[String: Any]] else {
            regionStatus = "Could not check system shortcuts. Try again."
            displayStatus = regionStatus
            precisionStatus = regionStatus
            return
        }

        let modifiers = UInt32(cmdKey | shiftKey)
        if Self.isSystemReserved(code: UInt32(kVK_ANSI_2), modifiers: modifiers, keys: keys) {
            precisionStatus = "Used by macOS — disable it in Keyboard Shortcuts"
        } else {
            let status = RegisterEventHotKey(UInt32(kVK_ANSI_2), modifiers,
                EventHotKeyID(signature: Self.signature, id: 2), GetEventDispatcherTarget(), 0, &precisionRef)
            precisionStatus = Self.registrationMessage(status)
        }
        if Self.isSystemReserved(code: UInt32(kVK_ANSI_4), modifiers: modifiers, keys: keys) {
            regionStatus = "Used by macOS — disable it in Keyboard Shortcuts"
        } else {
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_4), modifiers,
            EventHotKeyID(signature: Self.signature, id: 4),
            GetEventDispatcherTarget(), 0, &regionRef
        )
        regionStatus = Self.registrationMessage(status)
        }
        if Self.isSystemReserved(code: UInt32(kVK_ANSI_3), modifiers: modifiers, keys: keys) {
            displayStatus = "Used by macOS — disable it in Keyboard Shortcuts"
        } else {
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_3), modifiers,
            EventHotKeyID(signature: Self.signature, id: 3),
            GetEventDispatcherTarget(), 0, &displayRef
        )
        displayStatus = Self.registrationMessage(status)
        }
    }

    static func isSystemReserved(code: UInt32, modifiers: UInt32, keys: [[String: Any]]) -> Bool {
        keys.contains {
            ($0[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
            ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == code &&
            ($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == modifiers
        }
    }

    static func registrationMessage(_ status: OSStatus) -> String {
        if status == noErr { return "Ready" }
        if status == eventHotKeyExistsErr { return "Used by another app. Quit it, then try again." }
        return "Could not register shortcut (\(status)). Try again."
    }

    func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!)
    }

    func unregister() {
        if let regionRef { UnregisterEventHotKey(regionRef) }
        if let displayRef { UnregisterEventHotKey(displayRef) }
        if let precisionRef { UnregisterEventHotKey(precisionRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        regionRef = nil
        displayRef = nil
        precisionRef = nil
        eventHandler = nil
    }

    private func handle(id: UInt32) {
        switch id {
        case 2: onPrecisionCapture?()
        case 4: onRegionCapture?()
        case 3: onDisplayCapture?()
        default: break
        }
    }

    private static let signature: OSType = 0x53534854 // "SSHT"
}
