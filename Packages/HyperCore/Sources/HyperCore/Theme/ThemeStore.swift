import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum ThemeError: Error { case missingResource }

/// 번들된 palettes.json 을 읽어 테마 목록을 제공하고 선택을 UserDefaults 에 기억한다.
/// 기본 동작은 **시스템 외형 따르기**: 라이트 → Hyper Light, 다크 → Hyper Dark.
/// 사용자가 테마를 직접 고르면 그 테마로 고정되고(따르기 꺼짐), 설정에서 다시 켤 수 있다.
@MainActor
public final class ThemeStore: ObservableObject {
    public static let defaultLightID = "hyper-light"
    public static let defaultDarkID = "hyper-dark"
    static let idKey = "hyperedit.theme.id"
    static let followKey = "hyperedit.theme.followSystem"

    @Published public private(set) var themes: [Theme]
    @Published public private(set) var current: Theme
    /// true 면 시스템 라이트/다크 전환에 맞춰 Hyper Light / Hyper Dark 를 자동 선택
    @Published public private(set) var followsSystem: Bool

    private let defaults: UserDefaults
    private var systemIsDark: Bool

    public init(defaults: UserDefaults = AppDefaults.store, systemIsDark: Bool = ThemeStore.detectSystemDark()) {
        self.defaults = defaults
        self.systemIsDark = systemIsDark
        let loaded = (try? Self.loadBundled()) ?? [Theme(palette: .fallback)]
        themes = loaded
        let savedID = defaults.string(forKey: Self.idKey)
        let follow = defaults.object(forKey: Self.followKey) as? Bool ?? (savedID == nil)
        followsSystem = follow
        let wanted = follow ? Self.systemDefaultID(isDark: systemIsDark) : (savedID ?? Self.defaultDarkID)
        current = loaded.first { $0.id == wanted }
            ?? loaded.first { $0.id == Self.defaultDarkID }
            ?? loaded[0]
    }

    public nonisolated static func loadBundled() throws -> [Theme] {
        guard let url = Bundle.module.url(forResource: "palettes", withExtension: "json") else { throw ThemeError.missingResource }
        let file = try JSONDecoder().decode(PaletteFile.self, from: Data(contentsOf: url))
        return file.themes.map(Theme.init(palette:))
    }

    public static func systemDefaultID(isDark: Bool) -> String { isDark ? defaultDarkID : defaultLightID }

    /// 현재 시스템 외형이 다크인지 (AppKit/UIKit 없는 환경에서는 false). init 의 기본 인자로 쓰이므로 nonisolated 이지만 메인 스레드에서만 호출된다.
    public nonisolated static func detectSystemDark() -> Bool {
        #if canImport(AppKit)
        return MainActor.assumeIsolated { NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
        #elseif canImport(UIKit)
        return MainActor.assumeIsolated { UITraitCollection.current.userInterfaceStyle == .dark }
        #else
        return false
        #endif
    }

    public var darkThemes: [Theme] { themes.filter(\.isDark) }
    public var lightThemes: [Theme] { themes.filter { !$0.isDark } }

    /// 사용자가 테마를 직접 선택 → 고정 (시스템 따르기 꺼짐)
    public func select(id: String) {
        guard let t = themes.first(where: { $0.id == id }) else { return }
        current = t
        followsSystem = false
        defaults.set(id, forKey: Self.idKey)
        defaults.set(false, forKey: Self.followKey)
    }

    public func selectNext(step: Int = 1) {
        guard !themes.isEmpty, let i = themes.firstIndex(where: { $0.id == current.id }) else { return }
        select(id: themes[((i + step) % themes.count + themes.count) % themes.count].id)
    }

    public func setFollowsSystem(_ on: Bool) {
        followsSystem = on
        defaults.set(on, forKey: Self.followKey)
        if on { applySystemDefault() }
    }

    /// 앱이 시스템 외형 변화를 감지하면 호출
    public func systemAppearanceChanged(isDark: Bool) {
        guard systemIsDark != isDark else { return }
        systemIsDark = isDark
        if followsSystem { applySystemDefault() }
    }

    private func applySystemDefault() {
        let id = Self.systemDefaultID(isDark: systemIsDark)
        if let t = themes.first(where: { $0.id == id }), t.id != current.id { current = t }
    }
}
