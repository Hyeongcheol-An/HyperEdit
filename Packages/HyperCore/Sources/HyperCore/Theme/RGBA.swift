import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// sRGB 색. palettes.json 의 #RRGGBB / #RRGGBBAA 문자열과 1:1.
public struct RGBA: Hashable, Sendable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 8 {
            r = Double((v >> 24) & 0xff) / 255; g = Double((v >> 16) & 0xff) / 255
            b = Double((v >> 8) & 0xff) / 255; a = Double(v & 0xff) / 255
        } else {
            r = Double((v >> 16) & 0xff) / 255; g = Double((v >> 8) & 0xff) / 255
            b = Double(v & 0xff) / 255; a = 1
        }
    }

    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let white = RGBA(r: 1, g: 1, b: 1)
    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    /// t=0 → self, t=1 → other. 결과는 불투명.
    public func mix(_ other: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: 1)
    }

    public func with(alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    public var hexString: String {
        let f = { (x: Double) in String(format: "%02x", Int((x * 255).rounded())) }
        return "#" + f(r) + f(g) + f(b) + (a < 0.999 ? f(a) : "")
    }

    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    #if canImport(AppKit)
    public var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    #elseif canImport(UIKit)
    public var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    #endif
}
