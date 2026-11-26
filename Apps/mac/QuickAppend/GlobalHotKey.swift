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
    nonisolated(unsafe) private static var shortcuts: [UInt32: Shortcut] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4845_4B59   // 'HEKY'
    /// 지금 등록돼 있는 핫키 수 — 이 클래스의 장부 (셀프테스트: 설정을 바꿔도 하나를 넘지 않고, 끄면 0)
    static var registeredCount: Int { handlers.count }

    /// 시스템(Carbon)에 실제로 등록하는가. 스크립트가 모는 실행(AutomationRun.isScripted — 셀프테스트·벤치·실사용 하네스·스크린샷)은 하지 않는다:
    /// 전역 단축키는 기계 전체의 것이라, 테스트 인스턴스가 등록하면 사용자가 누른 ⌃⌥N 이 그 인스턴스의 패널을 띄우고 메모가 임시 문서에 붙는다
    /// (설치된 앱이 떠 있어도 같은 조합의 등록은 성공한다 — 실측 macOS 27). 그런 실행에서도 장부는 똑같이 적는다 — 컨트롤러의 상태·설정 화면의 문구가
    /// 같고, 눌림은 `press` 로 같은 길을 태운다
    nonisolated(unsafe) static var registersWithSystem = !AutomationRun.isScripted
    /// 시스템에 등록하지 않는 실행에서 "다른 앱이 이미 쓰는 조합" — 등록이 `eventHotKeyExistsErr` 로 거절된 것처럼 한다 (셀프테스트가 실패 경로를 본다)
    nonisolated(unsafe) static var takenElsewhere: [Shortcut] = []
    /// 시스템에 실제로 걸려 있는 수 (스크립트가 모는 실행에서는 늘 0)
    nonisolated(unsafe) private(set) static var systemRegistrationCount = 0

    init(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {
        self.shortcut = shortcut
        id = Self.nextID
        Self.nextID += 1
        if Self.registersWithSystem {
            try Self.installHandlerIfNeeded()
            var hotKeyRef: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
            guard status == noErr, let r = hotKeyRef else { throw RegistrationError(status: status) }
            ref = r
            Self.systemRegistrationCount += 1
        } else if Self.takenElsewhere.contains(shortcut) {
            throw RegistrationError(status: OSStatus(eventHotKeyExistsErr))
        }
        Self.handlers[id] = handler
        Self.shortcuts[id] = shortcut
    }

    deinit { unregister() }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil; Self.systemRegistrationCount -= 1 }
        Self.handlers[id] = nil
        Self.shortcuts[id] = nil
    }

    /// 등록된 핫키가 눌렸다: 그 클로저를 메인 큐에서 부른다 (Carbon 이벤트 처리기와 `press` 가 같이 쓴다)
    private static func fire(_ id: UInt32) {
        let handler = handlers[id]
        DispatchQueue.main.async { handler?() }
    }

    /// 셀프테스트·하네스용: `shortcut` 이 눌린 것처럼 한다 (시스템에 등록하지 않는 실행에서 눌림을 태우는 길). 반환: 그 조합이 등록돼 있었는가
    @discardableResult
    static func press(_ shortcut: Shortcut) -> Bool {
        guard let id = shortcuts.first(where: { $0.value == shortcut })?.key else { return false }
        fire(id)
        return true
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
            GlobalHotKey.fire(hkID.id)
            return noErr
        }, 1, &spec, nil, &eventHandler)
        guard status == noErr else { throw RegistrationError(status: status) }
    }
}
