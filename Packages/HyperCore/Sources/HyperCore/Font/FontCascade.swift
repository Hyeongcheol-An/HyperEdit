import Foundation
import CoreText
#if canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformFontDescriptor = NSFontDescriptor
#elseif canImport(UIKit)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformFontDescriptor = UIFontDescriptor
#endif

/// 에디터 폰트 설정. 영문은 family(Fira Code), 한글은 hangulFamily(D2Coding)를 hangulScale 배로 그려 2:1 폭을 맞춘다.
public struct FontSettings: Codable, Equatable, Sendable {
    public var family: String = "Fira Code"
    public var size: Double = 14
    public var hangulFamily: String = "D2Coding"
    /// Fira Code 반각 폭 0.6em × 2 = 1.2em → D2Coding(한글 1.0em)을 1.2배로.
    public var hangulScale: Double = 1.2
    /// 한글 런에 폴백 폰트를 명시 적용(2:1 정렬). 끄면 시스템 폴백(폭 1:1.67).
    public var hangulFix: Bool = true
    public var ligatures: Bool = true
    public var lineHeightMultiple: Double = 1.35

    public init() {}

    public static let storageKey = "hyperedit.font.settings"

    public static func load(from defaults: UserDefaults = AppDefaults.store) -> FontSettings {
        guard let data = defaults.data(forKey: storageKey),
              let s = try? JSONDecoder().decode(FontSettings.self, from: data) else { return FontSettings() }
        return s
    }

    public func save(to defaults: UserDefaults = AppDefaults.store) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

public enum FontCascade {
    public static func isInstalled(family: String) -> Bool {
        #if canImport(AppKit)
        return NSFontManager.shared.availableFontFamilies.contains(family)
        #else
        return UIFont.familyNames.contains(family)
        #endif
    }

    /// 본문 폰트: family + 시스템 폴백 앞에 hangulFamily 캐스케이드. (크기는 동일 — 2:1 보정은 HangulFontFixer 담당)
    public static func baseFont(_ s: FontSettings) -> PlatformFont {
        let size = CGFloat(s.size)
        guard isInstalled(family: s.family) else {
            #if canImport(AppKit)
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            #else
            return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            #endif
        }
        var attrs: [PlatformFontDescriptor.AttributeName: Any] = [.family: s.family]
        if !s.hangulFamily.isEmpty, isInstalled(family: s.hangulFamily) {
            attrs[.cascadeList] = [PlatformFontDescriptor(fontAttributes: [.family: s.hangulFamily])]
        }
        if !s.ligatures {
            attrs[.featureSettings] = [
                [PlatformFontDescriptor.FeatureKey.typeIdentifier: kContextualAlternatesType, PlatformFontDescriptor.FeatureKey.selectorIdentifier: kContextualAlternatesOffSelector],
                [PlatformFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType, PlatformFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector],
            ]
        }
        let desc = PlatformFontDescriptor(fontAttributes: attrs)
        #if canImport(AppKit)
        return NSFont(descriptor: desc, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        return UIFont(descriptor: desc, size: size)
        #endif
    }

    /// 한글 런 전용 폰트(hangulFamily × hangulScale). 설치 안 됐거나 보정 꺼짐이면 nil.
    public static func hangulFont(_ s: FontSettings) -> PlatformFont? {
        guard s.hangulFix, !s.hangulFamily.isEmpty, isInstalled(family: s.hangulFamily) else { return nil }
        let size = CGFloat(s.size * s.hangulScale)
        let desc = PlatformFontDescriptor(fontAttributes: [.family: s.hangulFamily])
        #if canImport(AppKit)
        return NSFont(descriptor: desc, size: size)
        #else
        return UIFont(descriptor: desc, size: size)
        #endif
    }

    /// 고정 줄 높이: 한글 폰트가 더 커도 줄 간격이 들쭉날쭉하지 않도록 본문 폰트 기준으로 고정.
    public static func lineHeight(for font: PlatformFont, multiple: Double) -> CGFloat {
        #if canImport(AppKit)
        let natural = font.ascender - font.descender + font.leading
        #else
        let natural = font.lineHeight
        #endif
        return (natural * CGFloat(multiple)).rounded(.up)
    }

    /// 반각 문자 폭 (탭 간격 계산용)
    public static func advance(of font: PlatformFont) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: font]).width
    }
}
