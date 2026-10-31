import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 한글(자모·호환자모·음절) 런에 지정 폰트를 입혀 영문:한글 폭을 1:2로 맞춘다.
/// AppKit 은 캐스케이드 폴백의 크기 지정을 무시하므로(실측) 속성 런으로 직접 지정한다.
public enum HangulFontFixer {
    public static let hangulRegex = try! NSRegularExpression(pattern: "[\\u1100-\\u11FF\\u3130-\\u318F\\uA960-\\uA97F\\uAC00-\\uD7FF]+", options: [])

    /// range 안의 한글 런에 font 적용. 넓은 범위면 호출 측에서 beginEditing/endEditing 으로 감쌀 것.
    /// NSRegularExpression 은 MB 단위에서 느리므로 unichar 를 직접 청크 스캔해 한글 런마다 addAttribute 한다.
    public static func apply(font: PlatformFont, to storage: NSTextStorage, in range: NSRange) {
        let ns = storage.string as NSString
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        guard safe.length > 0 else { return }
        let chunk = 65_536
        var buf = [unichar](repeating: 0, count: min(chunk, safe.length))
        var pos = safe.location
        let end = NSMaxRange(safe)
        var runStart = -1   // 진행 중인 한글 런의 시작(문서 오프셋), 없으면 -1
        while pos < end {
            let len = min(chunk, end - pos)
            buf.withUnsafeMutableBufferPointer { ns.getCharacters($0.baseAddress!, range: NSRange(location: pos, length: len)) }
            buf.withUnsafeBufferPointer { p in
                var i = 0
                while i < len {
                    if isHangul(p[i]) {
                        if runStart < 0 { runStart = pos + i }
                    } else if runStart >= 0 {
                        storage.addAttribute(.font, value: font, range: NSRange(location: runStart, length: pos + i - runStart))
                        runStart = -1
                    }
                    i += 1
                }
            }
            pos += len
        }
        if runStart >= 0 { storage.addAttribute(.font, value: font, range: NSRange(location: runStart, length: end - runStart)) }
    }

    @inline(__always) static func isHangul(_ c: unichar) -> Bool {
        (c >= 0xAC00 && c <= 0xD7A3) ||   // 음절 (가장 흔함, 먼저)
        (c >= 0x1100 && c <= 0x11FF) ||   // 자모
        (c >= 0x3130 && c <= 0x318F) ||   // 호환 자모
        (c >= 0xA960 && c <= 0xA97F) ||   // 확장-A
        (c >= 0xD7B0 && c <= 0xD7FF)      // 확장-B
    }

    public static func containsHangul(_ s: String) -> Bool {
        hangulRegex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
}
