import Foundation

/// 앱 전체가 쓰는 UserDefaults 저장소.
/// 스크린샷·셀프테스트 같은 자동화 실행(`--snapshot`, `--selftest`)에서는 휘발성 suite 로 바꿔
/// 테마·패널 상태·마지막 파일 같은 사용자 설정을 건드리지 않는다.
public enum AppDefaults {
    nonisolated(unsafe) public static var store: UserDefaults = .standard

    /// 자동화용 임시 suite 로 전환 (이전 실행의 잔여물은 비운다)
    public static func useEphemeral(suiteName: String = "hyperedit.automation") {
        guard let d = UserDefaults(suiteName: suiteName) else { return }
        d.removePersistentDomain(forName: suiteName)
        store = d
    }
}
