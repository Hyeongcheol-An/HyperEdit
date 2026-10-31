import AppKit
import Carbon.HIToolbox

/// Carbon `RegisterEventHotKey` 기반 전역 단축키 — 손쉬운 사용(접근성) 권한 없이 동작한다.
/// 같은 조합을 다른 앱이 이미 등록했으면 `eventHotKeyExistsErr`(-9878) 로 실패한다. 시스템 단축키(입력 소스 전환 등)와 겹치면
/// 오류 없이 시스템이 먼저 가로채므로 설정 화면에 안내만 둔다. 메인 스레드에서만 쓴다 (Carbon 앱 이벤트 핸들러도 메인 런루프에서 불린다).
final class GlobalHotKey {
    struct Shortcut: Equatable {
        let keyCode: UInt32
        let modifiers: NSEvent.ModifierFlags
        var carbonModifiers: UInt32 {
            var m: UInt32 = 0
            if modifiers.contains(.control) { m |= UInt32(controlKey) }
            if modifiers.contains(.option) { m |= UInt32(optionKey) }
            if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
            if modifiers.contains(.command) { m |= UInt32(cmdKey) }
            return m
        }
    }

    struct RegistrationError: Error { let status: OSStatus }

    let shortcut: Shortcut
    private let id: UInt32
    private var ref: EventHotKeyRef?

    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4845_4B59   // 'HEKY'
    /// 현재 Carbon 에 등록돼 있는 핫키 수 (셀프테스트: 설정을 바꿔도 하나를 넘지 않고, 끄면 0)
    static var registeredCount: Int { handlers.count }

    init(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {
        self.shortcut = shortcut
        id = Self.nextID
        Self.nextID += 1
        try Self.installHandlerIfNeeded()
        var hotKeyRef: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, let r = hotKeyRef else { throw RegistrationError(status: status) }
        ref = r
        Self.handlers[id] = handler
    }

    deinit { unregister() }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        Self.handlers[id] = nil
    }

    /// 앱 전체에 하나뿐인 핫키 이벤트 핸들러. 눌린 핫키의 id 로 등록된 클로저를 메인 큐에서 부른다.
    private static func installHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr, hkID.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
            let handler = GlobalHotKey.handlers[hkID.id]
            DispatchQueue.main.async { handler?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
        guard status == noErr else { throw RegistrationError(status: status) }
    }
}
