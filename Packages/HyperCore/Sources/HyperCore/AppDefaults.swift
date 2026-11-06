import Foundation

/// 앱 전체가 쓰는 UserDefaults 저장소.
/// 스크린샷·셀프테스트 같은 자동화 실행(`--snapshot`, `--selftest`)에서는 휘발성 suite 로 바꿔
/// 테마·패널 상태·마지막 파일 같은 사용자 설정을 건드리지 않는다.
public enum AppDefaults {
    nonisolated(unsafe) public static var store: UserDefaults = .standard
    /// `store` 가 쓰는 영구 도메인 이름 (앱 번들 ID, 임시 suite 로 바꾸면 그 이름) — `UserDefaults.persistentDomain(forName:)` 으로
    /// 전역 도메인 값과 구분해 읽어야 하는 키(AppleLanguages)에 쓴다
    nonisolated(unsafe) public static var domainName: String = Bundle.main.bundleIdentifier ?? "hyperedit"

    /// 스냅샷(`before-first-save` 등) 폴더 — 휘발성 실행에서는 임시 폴더. nil 이면 Application Support/HyperEdit/snapshots
    nonisolated(unsafe) public static var snapshotDirectoryOverride: URL?

    /// 자동화용 임시 suite 로 전환 (이전 실행의 잔여물은 비운다). 스냅샷도 임시 폴더로 — 셀프테스트·벤치의 1~28 MB 샘플이 실제 폴더에 쌓이지 않게 (2026-11-06)
    public static func useEphemeral(suiteName: String = "hyperedit.automation") {
        guard let d = UserDefaults(suiteName: suiteName) else { return }
        d.removePersistentDomain(forName: suiteName)
        store = d
        domainName = suiteName
        let snaps = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-\(suiteName)-snapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: snaps)
        snapshotDirectoryOverride = snaps
    }
}

/// HyperCore 리소스 번들에 대한 공개 창구 (앱 셀프테스트가 엔진 카탈로그의 언어 목록을 확인한다)
public enum HyperCoreBundle {
    public static var localizations: [String] { Bundle.module.localizations }
}
