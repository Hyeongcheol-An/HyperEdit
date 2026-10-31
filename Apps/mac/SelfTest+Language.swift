import SwiftUI
import AppKit
import HyperCore

// 셀프테스트: 인터페이스 언어 설정 — 선언한 10개 언어가 앱·엔진 번들에 모두 들어 있는지, 선택 저장/복원, 언어 매칭 규칙, 언어별 환영문.
extension SelfTest {
    @MainActor
    static func runLanguage(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) {
        let codes = AppLanguage.supported.map(\.rawValue)
        check(codes.count == 11 && Set(codes).count == 11 && codes.first == "en", "11 interface languages declared: \(codes.joined(separator: " "))")
        // 번들에 든 언어: 소스 언어(en)는 lproj 없이 바이너리에 있으므로 제외하고 본다
        let appBundled = Set(Bundle.main.localizations)
        let appMissing = codes.filter { $0 != "en" && !appBundled.contains($0) }
        check(appMissing.isEmpty, "app bundle has every declared language (missing: \(appMissing), has: \(appBundled.sorted()))")
        let coreBundled = Set(HyperCoreBundle.localizations)
        let coreMissing = codes.filter { $0 != "en" && !coreBundled.contains($0) }
        check(coreMissing.isEmpty, "HyperCore bundle has every declared language (missing: \(coreMissing))")
        // 환영문: 언어마다 파일이 있고 비어 있지 않으며 제품명을 담는다
        let welcomeLangs = Set(WelcomeDocument.availableLanguages)
        let welcomeMissing = codes.filter { !welcomeLangs.contains($0) }
        check(welcomeMissing.isEmpty, "welcome document exists for every language (missing: \(welcomeMissing))")
        let badWelcome = codes.filter { let t = WelcomeDocument.text(for: [$0]); return t.count < 200 || !t.contains("HyperEdit") || !t.hasPrefix("# ") }
        check(badWelcome.isEmpty, "welcome documents are non-trivial Markdown mentioning HyperEdit (bad: \(badWelcome))")
        check(WelcomeDocument.text(for: ["pt-PT"]).contains("HyperEdit") && WelcomeDocument.text(for: ["xx"]) == WelcomeDocument.text(for: ["en"]),
              "welcome document falls back to English for unknown languages")
        // 매칭 규칙: 지역·문자 변형은 같은 언어로, 미지원 언어는 nil
        check(AppLanguage.resolve(preferred: ["pt-PT"]) == .pt && AppLanguage.resolve(preferred: ["pt-BR"]) == .pt, "pt-PT / pt-BR → pt")
        check(AppLanguage.resolve(preferred: ["zh-CN"]) == .zhHans && AppLanguage.resolve(preferred: ["zh-Hans-SG"]) == .zhHans, "zh-CN / zh-Hans-SG → zh-Hans")
        check(AppLanguage.resolve(preferred: ["ko-KR", "en"]) == .ko && AppLanguage.resolve(preferred: ["de-CH", "fr"]) == .de, "first matching preferred language wins")
        check(AppLanguage.resolve(preferred: ["zh-TW"]) == nil && AppLanguage.resolve(preferred: ["xx"]) == nil, "unsupported languages (zh-TW, xx) resolve to nil, not English")
        check(AppLanguage.resolve(preferred: ["ar-SA"]) == .ar && AppLanguage.resolve(preferred: ["ar-EG", "fr"]) == .ar, "ar-SA / ar-EG → ar (right-to-left language included)")
        check(AppLanguage.en.guideURL.lastPathComponent == "USER_GUIDE.md" && AppLanguage.hi.guideURL.lastPathComponent == "USER_GUIDE.hi.md",
              "user guide URLs: USER_GUIDE.md for English, USER_GUIDE.<code>.md otherwise")
        check(AppLanguage.supported.allSatisfy { !$0.nativeName.isEmpty && $0.nativeName != $0.rawValue }, "every language has a native display name")
        // 저장/복원 — 휘발성 저장소(--selftest 는 ephemeral) 의 AppleLanguages
        let before = model.language
        model.language = .ja
        check(AppLanguage.stored == .ja && (AppDefaults.store.array(forKey: AppLanguage.defaultsKey) as? [String]) == ["ja"],
              "choosing a language stores AppleLanguages=[ja] in the app domain")
        check(AppLanguage.needsRelaunch(for: .ja) == (AppLanguage.running != .ja), "relaunch needed iff the choice differs from the running language (\(AppLanguage.running.rawValue))")
        model.language = .system
        check(AppLanguage.stored == .system && UserDefaults.standard.persistentDomain(forName: AppDefaults.domainName)?[AppLanguage.defaultsKey] == nil,
              "System Default removes the AppleLanguages override")
        model.language = before
        let recent = model.output.suffix(6).map(\.text)
        check(recent.contains { $0.contains("日本語") }, "language change is logged with the native language name")
        log("running UI language: \(AppLanguage.running.rawValue) · system would use: \(AppLanguage.systemResolved.rawValue)")
    }
}
