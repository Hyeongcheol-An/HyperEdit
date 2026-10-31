import Foundation
import AppKit

/// 개발용 성능 계측: `--debug-perf [--debug-perf-log <path>]`. 꺼져 있으면 비용 0에 가깝다.
enum Perf {
    static let enabled = CommandLine.arguments.contains("--debug-perf")
    static let logPath: String? = {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--debug-perf-log"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()
    private static let t0 = CFAbsoluteTimeGetCurrent()
    private static let lock = NSLock()

    static func log(_ s: String) {
        guard enabled else { return }
        let line = String(format: "[perf %8.3f] ", CFAbsoluteTimeGetCurrent() - t0) + s + "\n"
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardError.write(line.data(using: .utf8)!)
        guard let p = logPath else { return }
        if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { FileManager.default.createFile(atPath: p, contents: line.data(using: .utf8)) }
    }

    @discardableResult
    static func measure<T>(_ name: @autoclosure () -> String, threshold ms: Double = 1, _ f: () throws -> T) rethrows -> T {
        guard enabled else { return try f() }
        let t = CFAbsoluteTimeGetCurrent()
        let r = try f()
        let dt = (CFAbsoluteTimeGetCurrent() - t) * 1000
        if dt >= ms { log(String(format: "%@ %.1f ms", name(), dt)) }
        return r
    }

    /// 메인 스레드 정지 감시: 50ms 간격 핑, 120ms 넘는 지연을 기록
    static func startWatchdog() {
        guard enabled else { return }
        let q = DispatchQueue(label: "perf.watchdog")
        func tick() {
            let sent = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                let lag = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                if lag > 120 { log(String(format: "MAIN THREAD STALL %.0f ms", lag)) }
                q.asyncAfter(deadline: .now() + 0.05) { tick() }
            }
        }
        q.async { tick() }
    }
}
