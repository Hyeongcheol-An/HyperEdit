import Foundation

/// 타임스탬프 헤딩: `## 2026-10-30 (금) 14:05`. 요일은 현재 로케일로 표기된다 (영어 환경이면 `(Fri)`).
public enum Timestamp {
    public static func heading(_ date: Date = Date(), locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd (E) HH:mm"
        return "## " + f.string(from: date)
    }

    /// 타임라인 사이드바용: 줄 전체가 타임스탬프 헤딩인지. 괄호 안 요일은 로케일별 길이가 달라 1~12자 허용.
    public static let headingRegex = try! NSRegularExpression(
        pattern: #"^## (\d{4})-(\d{2})-(\d{2}) \(([^)\n]{1,12})\) (\d{2}):(\d{2})\s*$"#, options: [.anchorsMatchLines])
}
