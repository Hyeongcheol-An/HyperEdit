import Foundation

/// 앱(Apps/mac)이 설치하는 성능 로그 훅. 미설치 시 비용 0.
public enum PerfProbe {
    nonisolated(unsafe) public static var log: ((String) -> Void)?
}
