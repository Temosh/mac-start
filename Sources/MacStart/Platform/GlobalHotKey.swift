import Carbon.HIToolbox
import MacStartCore
import os

/// A system-wide keyboard shortcut. Uses Carbon's `RegisterEventHotKey`, which needs no Accessibility or Input
/// Monitoring permission.
@MainActor
final class GlobalHotKey {
    enum RegistrationError: Error {
        /// Carbon refused the shortcut. `eventHotKeyExistsErr` means another app already owns it.
        case rejected(status: OSStatus)
    }

    /// "MSHK", tags the hotkey events this app registers.
    private static let signature: OSType = 0x4D53_484B

    private let onPress: @MainActor () -> Void
    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let logger = LogArea.hotkey.logger

    /// Calls `onPress` on the main actor each time the registered shortcut is pressed.
    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        var pressedEvent = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated { hotKey.onPress() }
                return noErr
            },
            1,
            &pressedEvent,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            logger.error("Cannot install the hotkey handler, status \(status)")
        }
    }

    isolated deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    /// Registers `hotKey` in place of the current shortcut.
    func register(_ hotKey: HotKey) throws(RegistrationError) {
        unregister()
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.modifiers.carbonFlags,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            throw .rejected(status: status)
        }
        logger.info("Registered hotkey with key code \(hotKey.keyCode), modifiers \(hotKey.modifiers.rawValue)")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

extension HotKey.Modifiers {
    /// The Carbon modifier mask for `RegisterEventHotKey`.
    fileprivate var carbonFlags: UInt32 {
        var flags = 0
        if contains(.command) { flags |= cmdKey }
        if contains(.option) { flags |= optionKey }
        if contains(.control) { flags |= controlKey }
        if contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
