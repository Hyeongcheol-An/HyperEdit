import XCTest
@testable import HyperCore

// 매크로: 단계 Codable · 연속 입력 합치기 · 저장소 저장/읽기/이름 바꾸기/삭제

final class MacroStepTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ v: T) throws -> T {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(T.self, from: enc.encode(v))
    }

    func testStepCodableRoundTripAndFlatJSON() throws {
        let steps: [MacroStep] = [.insert("- "), .command("moveToEndOfLine:"), .tool("upper"), .find("NEEDLE"), .insert("")]
        XCTAssertEqual(try roundTrip(steps), steps)
        let json = String(decoding: try JSONEncoder().encode(MacroStep.command("moveRight:")), as: UTF8.self)
        XCTAssertTrue(json.contains("\"type\":\"command\"") && json.contains("\"value\":\"moveRight:\""), json)
    }

    func testStepDecodeRejectsUnknownType() {
        let data = Data("{\"type\":\"dance\",\"value\":\"x\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MacroStep.self, from: data))
        // value 가 빠진 손으로 쓴 JSON 은 빈 문자열로 읽는다
        let noValue = Data("{\"type\":\"insert\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(MacroStep.self, from: noValue), .insert(""))
    }

    func testMacroCodableRoundTrip() throws {
        let m = Macro(name: "Checklist", steps: [.insert("- "), .command("moveDown:")], created: Date(timeIntervalSince1970: 1_700_000_000))
        let back = try roundTrip(m)
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.id, m.id)
    }

    func testRecordingCoalescesConsecutiveInsertsOnly() {
        var r = MacroRecording()
        XCTAssertTrue(r.isEmpty)
        r.append(.insert("a")); r.append(.insert("b")); r.append(.insert(""))
        r.append(.command("moveRight:"))
        r.append(.insert("c")); r.append(.insert("d"))
        r.append(.command("moveRight:")); r.append(.command("moveRight:"))   // 명령은 합치지 않는다 (→ 두 칸 이동)
        r.append(.tool("upper")); r.append(.find("x"))
        XCTAssertEqual(r.steps, [.insert("ab"), .command("moveRight:"), .insert("cd"), .command("moveRight:"), .command("moveRight:"), .tool("upper"), .find("x")])
        XCTAssertFalse(r.isEmpty)
    }
}

@MainActor
final class MacroStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("he-macro-\(UUID().uuidString)", isDirectory: true)
    }

    func testEmptyStoreHasNoFileUntilEnsured() {
        let dir = tempDir()
        let s = MacroStore(directory: dir)
        XCTAssertTrue(s.macros.isEmpty); XCTAssertNil(s.lastRecorded); XCTAssertNil(s.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.fileURL.path))
        s.ensureFileExists()
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.fileURL.path))
        XCTAssertEqual(s.fileURL.lastPathComponent, "macros.json")
        XCTAssertEqual(s.fileURL.deletingLastPathComponent().path, dir.path)
    }

    func testSaveLoadLastRecordedAndNamedMacros() {
        let dir = tempDir()
        let s = MacroStore(directory: dir)
        let recorded = Macro(name: "", steps: [.insert("- "), .command("moveToEndOfLine:"), .insert(" ✓")])
        s.setLastRecorded(recorded)
        let named = s.save(recorded, name: "  Checklist  ")
        XCTAssertEqual(named.name, "Checklist")
        XCTAssertNotEqual(named.id, recorded.id, "저장된 매크로는 새 id 를 받는다")
        XCTAssertEqual(named.steps, recorded.steps)
        let fallback = s.save(recorded, name: "   ")
        XCTAssertEqual(fallback.name, "Macro 2")

        let again = MacroStore(directory: dir)
        XCTAssertEqual(again.lastRecorded, recorded)
        XCTAssertEqual(again.macros, [named, fallback])
        XCTAssertNil(again.loadError)
        let json = (try? String(contentsOf: again.fileURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(json.contains("\"lastRecorded\"") && json.contains("\"macros\"") && json.contains("\"type\" : \"insert\""), json)
    }

    func testRenameAndDeletePersist() {
        let dir = tempDir()
        let s = MacroStore(directory: dir)
        let a = s.save(Macro(name: "", steps: [.insert("a")]), name: "A")
        let b = s.save(Macro(name: "", steps: [.insert("b")]), name: "B")
        s.rename(id: a.id, name: "Alpha")
        s.rename(id: a.id, name: "   ")                // 빈 이름은 무시
        s.rename(id: UUID(), name: "ghost")            // 없는 id 는 무시
        XCTAssertEqual(s.macros.map(\.name), ["Alpha", "B"])
        XCTAssertEqual(s.macro(id: b.id)?.steps, [.insert("b")])
        s.delete(id: b.id)
        s.delete(id: UUID())
        XCTAssertEqual(s.macros.map(\.name), ["Alpha"])
        let again = MacroStore(directory: dir)
        XCTAssertEqual(again.macros.map(\.name), ["Alpha"])
        XCTAssertEqual(again.macros.first?.id, a.id)
    }

    func testCorruptFileIsReportedNotWiped() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("macros.json"))
        let s = MacroStore(directory: dir)
        XCTAssertNotNil(s.loadError)
        XCTAssertTrue(s.macros.isEmpty)
        // 고친 뒤 reload 하면 오류가 사라지고 내용이 들어온다
        let good = MacroStore(directory: tempDir())
        good.save(Macro(name: "", steps: [.find("x")]), name: "Finder")
        try FileManager.default.removeItem(at: s.fileURL)
        try FileManager.default.copyItem(at: good.fileURL, to: s.fileURL)
        s.reload()
        XCTAssertNil(s.loadError)
        XCTAssertEqual(s.macros.map(\.name), ["Finder"])
    }
}
