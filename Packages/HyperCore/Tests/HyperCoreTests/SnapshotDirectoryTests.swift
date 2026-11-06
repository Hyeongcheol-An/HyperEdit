import XCTest
@testable import HyperCore

// 휘발성 실행(--ephemeral · 셀프테스트 · 벤치)의 스냅샷 폴더가 실제 Application Support 를 벗어나는지
final class SnapshotDirectoryTests: XCTestCase {
    @MainActor
    func testEphemeralOverrideRedirectsSnapshots() {
        let saved = AppDefaults.snapshotDirectoryOverride
        defer { AppDefaults.snapshotDirectoryOverride = saved }
        AppDefaults.snapshotDirectoryOverride = nil
        XCTAssertTrue(MemoDocument.snapshotDirectory.path.hasSuffix("HyperEdit/snapshots"))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-test-snapshots", isDirectory: true)
        AppDefaults.snapshotDirectoryOverride = tmp
        XCTAssertEqual(MemoDocument.snapshotDirectory, tmp)
        XCTAssertFalse(MemoDocument.snapshotDirectory.path.contains("Application Support"))
    }
}
