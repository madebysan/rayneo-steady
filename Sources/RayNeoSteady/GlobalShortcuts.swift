import AppKit
import Carbon

final class GlobalShortcuts {
    var onRecenter: (() -> Void)?
    var onStop: (() -> Void)?
    var onShowControls: (() -> Void)?
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private(set) var available = true
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(data).takeUnretainedValue()
            if id.id == 1 { owner.onRecenter?() }
            if id.id == 2 { owner.onStop?() }
            if id.id == 3 { owner.onShowControls?() }
            return noErr
        }, 1, &type, pointer, &handler)
        if status != noErr { available = false; return }
        for (key, id) in [(kVK_ANSI_R, UInt32(1)), (kVK_ANSI_S, UInt32(2)), (kVK_ANSI_1, UInt32(3))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(cmdKey | controlKey), EventHotKeyID(signature: 0x53544459, id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { references.append(reference) } else { available = false }
        }
    }
    deinit {
        for reference in references { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
