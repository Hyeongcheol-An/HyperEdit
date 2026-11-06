import Foundation

/// 앱(Apps/mac)이 설치하는 성능 로그 훅. 미설치 시 비용 0.
public enum PerfProbe {
    nonisolated(unsafe) public static var log: ((String) -> Void)?

    /// `log` 가 설치돼 있을 때만 시간을 재서 `threshold` ms 이상이면 기록한다. 미설치면 클로저만 실행 (비용 0)
    @discardableResult
    public static func measure<T>(_ name: @autoclosure () -> String, threshold ms: Double = 1, _ f: () throws -> T) rethrows -> T {
        guard let log else { return try f() }
        let t = CFAbsoluteTimeGetCurrent()
        let r = try f()
        let dt = (CFAbsoluteTimeGetCurrent() - t) * 1000
        if dt >= ms { log(String(format: "%@ %.1f ms", name(), dt)) }
        return r
    }
}
