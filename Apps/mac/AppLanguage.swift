import SwiftUI
import AppKit
import HyperCore

/// 인터페이스 언어 (설정 › Language). 선택은 앱 도메인의 `AppleLanguages` 에 저장한다 — 시스템 설정 › 일반 › 언어 및 지역 › 응용 프로그램 에서
/// 앱별 언어를 고를 때 쓰는 것과 같은 키라 두 경로가 서로를 덮어쓰지 않고 한 값을 본다. SwiftUI·AppKit 은 실행 시점의 언어로 번들을 고르므로 재실행 뒤 적용된다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en, ko
    case zhHans = "zh-Hans"
    case ja, vi, hi, de, fr, es, pt, ar

    /// 카탈로그(Localizable.xcstrings)에 번역이 있는 언어. scripts/check-l10n.py 의 LANGUAGES 와 같아야 한다 (검사함).
    static let supported: [AppLanguage] = [.en, .ko, .zhHans, .ja, .vi, .hi, .de, .fr, .es, .pt, .ar]
    var id: String { rawValue }

    /// 그 언어로 쓴 이름 — 어느 언어로 보고 있든 자기 언어를 찾을 수 있도록 번역하지 않는다
    var nativeName: String {
        switch self {
        case .system: String(localized: "System Default")
        case .en: "English"
        case .ko: "한국어"
        case .zhHans: "简体中文"
        case .ja: "日本語"
        case .vi: "Tiếng Việt"
        case .hi: "हिन्दी"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        case .pt: "Português (Brasil)"
        case .ar: "العربية"
        }
    }

    /// 사용자 가이드 (docs/guide/USER_GUIDE.<code>.md, 영어는 USER_GUIDE.md)
    var guideURL: URL {
        let name = self == .en || self == .system ? "USER_GUIDE.md" : "USER_GUIDE.\(rawValue).md"
        return URL(string: "https://github.com/Hyeongcheol-An/HyperEdit/blob/main/docs/guide/\(name)")!
    }

    static let defaultsKey = "AppleLanguages"

    /// 우선 언어 목록에서 지원 언어를 고른다 — 번들이 lproj 를 고르는 것과 같은 규칙(pt-PT → pt, zh-CN → zh-Hans, de-CH → de). 아무것도 맞지 않으면 nil.
    static func resolve(preferred: [String]) -> AppLanguage? {
        let codes = supported.map(\.rawValue)
        // Foundation 은 맞는 것이 없으면 목록의 첫 항목(en)을 돌려주므로, 언어 코드가 하나라도 겹치는지 먼저 본다
        let wanted = Set(preferred.compactMap { Locale(identifier: $0).language.languageCode?.identifier })
        guard wanted.contains(where: { w in codes.contains { Locale(identifier: $0).language.languageCode?.identifier == w } }) else { return nil }
        guard let hit = Bundle.preferredLocalizations(from: codes, forPreferences: preferred).first,
              let code = Locale(identifier: hit).language.languageCode?.identifier, wanted.contains(code) else { return nil }   // zh-TW → en 폴백은 호출자가 정한다
        return AppLanguage(rawValue: hit)
    }

    /// 설정에 저장된 선택 (앱 도메인에 AppleLanguages 가 없으면 .system)
    static var stored: AppLanguage {
        guard let langs = UserDefaults.standard.persistentDomain(forName: AppDefaults.domainName)?[defaultsKey] as? [String],
              let first = langs.first else { return .system }
        return resolve(preferred: [first]) ?? .system
    }

    static func store(_ lang: AppLanguage) {
        if lang == .system { AppDefaults.store.removeObject(forKey: defaultsKey) }
        else { AppDefaults.store.set([lang.rawValue], forKey: defaultsKey) }
    }

    /// 시스템 언어 설정으로 실행했을 때 앱이 쓰게 될 언어 (앱 도메인의 덮어쓰기를 무시하고 전역 도메인을 본다)
    static var systemResolved: AppLanguage {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[defaultsKey] as? [String]
        return resolve(preferred: global ?? Locale.preferredLanguages) ?? .en
    }

    /// 이 선택으로 실행하면 보게 될 언어
    var effective: AppLanguage { self == .system ? Self.systemResolved : self }

    /// 지금 UI 가 실제로 표시되는 언어 (실행 시점에 고정 — 번들은 실행 중에 언어를 바꾸지 않는다)
    static let running: AppLanguage = resolve(preferred: Bundle.main.preferredLocalizations) ?? .en

    /// 저장된 선택을 적용하려면 재실행이 필요한가
    static func needsRelaunch(for selection: AppLanguage) -> Bool { selection.effective != running }

    /// 문서를 저장하고 종료한 뒤 같은 앱을 다시 연다 (AppDelegate 가 종료 직전에 재실행을 예약)
    @MainActor static func relaunch() {
        AppDelegate.relaunchOnQuit = true
        NSApp.terminate(nil)
    }
}
