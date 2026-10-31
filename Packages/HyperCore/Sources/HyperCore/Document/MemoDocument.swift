import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 단일 텍스트 파일 문서. NSTextStorage 를 직접 소유해 텍스트 뷰와 공유한다(1.3MB 문자열 복사를 피하기 위해).
/// - 저장: 원자적 쓰기, 세션 첫 저장 전 스냅샷, 빈 내용 저장 차단
/// - 외부 변경: DispatchSource 로 감지 → 수정 중이 아니면 자동 재로드, 수정 중이면 외부본 스냅샷 + 경고
@MainActor
public final class MemoDocument: NSObject, ObservableObject, NSTextStorageDelegate {
    /// 현재 파일. switchTo(url:) 로 바뀐다 — 객체와 textStorage 는 그대로 유지된다.
    @Published public private(set) var url: URL
    public let textStorage = NSTextStorage()

    @Published public private(set) var isLoaded = false
    @Published public private(set) var isDirty = false
    @Published public private(set) var lastSaved: Date?
    @Published public private(set) var externalChange: Date?
    @Published public private(set) var lineIndex = LineIndex()
    @Published public private(set) var status = ""
    @Published public private(set) var errorMessage: String?
    /// 디스크에서 내용을 통째로 바꿨을 때 증가 — 뷰는 undo 스택을 비우고 속성을 다시 입힌다.
    @Published public private(set) var reloadGeneration = 0
    /// 줄바꿈 종류 (UltraEdit 상태바 표기): UNIX / DOS / MAC
    @Published public private(set) var lineEnding = "UNIX"
    @Published public private(set) var fileSize: Int = 0
    /// 파일 인코딩. UTF-8 이 아니면 EUC-KR(CP949) → CP1252 → Latin-1 순으로 손실 없이 읽히는 것을 고르고, 저장도 같은 인코딩으로 한다.
    @Published public private(set) var encoding: String.Encoding = .utf8
    @Published public private(set) var hasBOM = false
    public var encodingName: String { Self.name(of: encoding) + (hasBOM ? " BOM" : "") }

    public var autosaveDelay: TimeInterval = 2.0
    /// 한글 런에 입힐 폰트(2:1 폭 보정). 에디터가 테마/폰트 적용 시 설정.
    public var hangulFont: PlatformFont?

    private var autosaveTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    nonisolated(unsafe) private var watchSource: DispatchSourceFileSystemObject?
    private var ourLastWrite: Date?
    private var snapshotTaken = false
    private var loadedLength = 0
    /// 파일 전환 세대. 전환 전에 시작된 저장 완료 콜백이 새 파일 상태를 덮어쓰지 않도록.
    private var fileGeneration = 0
    /// load/reload 의 전체 교체 중에는 저장소 변경 알림을 '사용자 편집' 으로 치지 않는다 (0 보다 크면 교체 중)
    private var programmaticReplaceDepth = 0

    public init(url: URL) {
        self.url = url.resolvingSymlinksInPath()
        super.init()
        textStorage.delegate = self
    }

    deinit { watchSource?.cancel(); PerfProbe.log?("MemoDocument deinit") }

    /// 다른 파일로 전환. 새 MemoDocument 를 만들지 않고 같은 NSTextStorage 의 내용만 바꾼다.
    /// NSTextContentStorage.textStorage 를 갈아끼우는 방식은 반복할수록 TextKit 2 레이아웃 질의가
    /// 2KB 문서에서도 50ms 대로 퇴화하는 것이 실측됐다. 전체 범위 replaceCharacters 는 정상 편집 경로라 수 ms.
    public func switchTo(url newURL: URL) {
        let resolved = newURL.resolvingSymlinksInPath()
        // 진행 중/예약된 저장이 있으면 동기로 마무리 — 전환 뒤에 끝나는 비동기 저장이 최신 편집을 버리지 않도록
        if isLoaded && (isDirty || saveRequestedWhileSaving) { saveSynchronously() }
        fileGeneration += 1
        autosaveTask?.cancel(); autosaveTask = nil
        indexTask?.cancel(); indexTask = nil
        watchSource?.cancel(); watchSource = nil
        isSaving = false; saveRequestedWhileSaving = false
        snapshotTaken = false; ourLastWrite = nil
        externalChange = nil; lastSaved = nil
        url = resolved
        // 새 문서를 처음 올릴 때와 같이 한글 보정은 에디터의 전체 속성 적용(apply)에 맡긴다 (delegate 경로와 중복 방지)
        let keepHangul = hangulFont
        hangulFont = nil
        load()
        hangulFont = keepHangul
        if !isLoaded {
            // 읽기 실패: 이전 파일 내용이 새 경로 아래 남지 않도록 비운다 (저장은 isLoaded 가드로 차단됨)
            replaceAll(with: "")
            isDirty = false
        }
    }

    // MARK: - Load / Save

    public func load() {
        do {
            // `--file` 로 받은 아직 없는 경로: 빈 파일을 만들어 바로 쓸 수 있게 (폴더가 없거나 쓸 수 없으면 아래에서 열기 실패로 보고)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            let data = try Data(contentsOf: url)
            guard let decoded = Self.decode(data) else {
                // 어떤 인코딩으로도 손실 없이 읽을 수 없음 → 열지 않는다 (손실 디코딩 후 자동 저장하면 파일이 망가진다)
                isLoaded = false
                errorMessage = String(localized: "Open failed: cannot determine the text encoding (not UTF-8 / EUC-KR / Latin-1)", bundle: .module)
                return
            }
            encoding = decoded.encoding
            hasBOM = decoded.bom
            replaceAll(with: decoded.text)
            isDirty = false
            isLoaded = true
            errorMessage = nil
            status = String(localized: "Loaded", bundle: .module) + (encoding == .utf8 ? "" : " · \(encodingName)")
            startWatching()
        } catch {
            isLoaded = false
            errorMessage = String(localized: "Open failed: \(error.localizedDescription)", bundle: .module)
        }
    }

    // MARK: - 인코딩

    /// CP949(확장 EUC-KR). `CFStringEncodings.dosKorean` 은 CP949 코드 페이지에 해당한다.
    public static let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))

    /// 손실 없는 디코딩만 허용. UTF-8 BOM 은 떼어 내고 기억한다. 반환 nil 이면 어느 인코딩으로도 읽을 수 없는 데이터.
    public static func decode(_ raw: Data) -> (text: String, encoding: String.Encoding, bom: Bool)? {
        var data = raw
        var bom = false
        if data.count >= 3, data[data.startIndex] == 0xEF, data[data.startIndex + 1] == 0xBB, data[data.startIndex + 2] == 0xBF {
            data = data.dropFirst(3); bom = true
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8, bom) }
        for enc in [cp949, .windowsCP1252, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return (s, enc, false) }
        }
        return nil
    }

    public static func name(of e: String.Encoding) -> String {
        switch e {
        case .utf8: return "UTF-8"
        case cp949: return "EUC-KR"
        case .windowsCP1252: return "CP1252"
        case .isoLatin1: return "Latin-1"
        default: return String(describing: e)
        }
    }

    /// 같은 폴더의 임시 파일에 쓴 뒤 교체 — 원본의 권한·확장 속성·Finder 태그를 유지한다 (`Data.write(.atomic)` 은 새 inode 메타데이터로 바뀜).
    nonisolated static func atomicReplace(_ data: Data, at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { try data.write(to: url, options: [.atomic]); return }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).hyperedit-\(UUID().uuidString.prefix(8)).tmp")
        try data.write(to: tmp)
        do { _ = try fm.replaceItemAt(url, withItemAt: tmp) }
        catch { try? fm.removeItem(at: tmp); throw error }
    }

    private func replaceAll(with text: String) {
        lineEnding = Self.detectLineEnding(text)
        fileSize = text.utf8.count
        programmaticReplaceDepth += 1
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: text)
        textStorage.endEditing()
        programmaticReplaceDepth -= 1
        loadedLength = textStorage.length
        lineIndex = LineIndex(text: text)
        reloadGeneration += 1
    }

    /// 줄바꿈 종류 판별. String.contains 는 grapheme 단위라 1MB 에 수십 ms 가 드므로 UTF-8 바이트를 직접 스캔한다.
    static func detectLineEnding(_ text: String) -> String {
        let u = text.utf8
        guard let cr = u.firstIndex(of: 0x0D) else { return "UNIX" }   // \r 없음
        let next = u.index(after: cr)
        return (next < u.endIndex && u[next] == 0x0A) ? "DOS" : "MAC"
    }

    /// 텍스트 뷰의 사용자 편집 후 호출.
    public func textDidChange() {
        isDirty = true
        scheduleIndexRebuild()
        scheduleAutosave()
    }

    /// 불변 복사본 (백그라운드에서 안전하게 읽기 위함, 1.3MB memcpy 수준)
    private func immutableSnapshot() -> NSString { textStorage.mutableString.copy() as! NSString }

    private func scheduleIndexRebuild() {
        indexTask?.cancel()
        indexTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            let snapshot = self.immutableSnapshot()
            let idx = await Task.detached(priority: .userInitiated) { LineIndex(nsString: snapshot) }.value
            if Task.isCancelled { return }
            self.lineIndex = idx
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            self?.saveIfDirty()
        }
    }

    public func saveIfDirty() { if isDirty { save() } }

    private var isSaving = false
    private var saveRequestedWhileSaving = false

    public func save() {
        guard isLoaded else { return }
        if isSaving { saveRequestedWhileSaving = true; return }
        let copyText = immutableSnapshot()
        if copyText.length == 0 && loadedLength > 0 {
            errorMessage = String(localized: "Blocked saving empty content (original had \(loadedLength) characters). Undo (⌘Z) and save again.", bundle: .module)
            return
        }
        if !snapshotTaken {
            _ = try? snapshot(tag: "before-first-save")
            snapshotTaken = true
        }
        isSaving = true
        isDirty = false
        ourLastWrite = Date()
        let url = self.url
        let length = textStorage.length
        let gen = fileGeneration
        let enc = encoding, bom = hasBOM
        // 모든 디스크 쓰기는 하나의 직렬 큐를 지난다 → 비동기 저장과 동기 저장(종료·전환)의 순서가 보장된다
        Self.writeQueue.async {
            let built = Self.encode(copyText as String, encoding: enc, bom: bom)
            let err: Error? = { do { try Self.atomicReplace(built.data, at: url); return nil } catch { return error } }()
            let bytes = built.data.count, converted = built.convertedToUTF8
            Task { @MainActor [weak self] in self?.finishSave(generation: gen, length: length, error: err, bytes: bytes, convertedToUTF8: converted) }
        }
    }

    private func finishSave(generation gen: Int, length: Int, error: Error?, bytes: Int, convertedToUTF8: Bool) {
        guard gen == fileGeneration else { return }   // 전환 전 파일의 저장 결과 — 새 파일 상태에 반영하지 않음
        isSaving = false
        ourLastWrite = Date()
        if let e = error {
            isDirty = true
            errorMessage = String(localized: "Save failed: \(e.localizedDescription)", bundle: .module)
        } else {
            lastSaved = Date()
            loadedLength = length
            fileSize = bytes
            errorMessage = nil
            if convertedToUTF8 {
                encoding = .utf8; hasBOM = false
                status = String(localized: "Saved · \(Self.timeString(lastSaved!)) · converted to UTF-8 because the original encoding cannot represent some characters", bundle: .module)
            } else {
                status = String(localized: "Saved · \(Self.timeString(lastSaved!))", bundle: .module)
            }
            startWatching()   // 교체 쓰기로 inode 가 바뀌므로 감시 재시작
        }
        if saveRequestedWhileSaving { saveRequestedWhileSaving = false; save() }
    }

    /// 종료·파일 전환처럼 비동기 저장을 기다릴 수 없을 때 호출. 같은 가드(미로드·빈 내용)를 적용하고 직렬 큐에서 동기로 쓴다.
    @discardableResult
    public func saveSynchronously() -> Bool {
        guard isLoaded, isDirty || saveRequestedWhileSaving || isSaving else { return false }
        let s = textStorage.string
        if s.isEmpty && loadedLength > 0 { return false }
        let built = Self.encode(s, encoding: encoding, bom: hasBOM)
        let url = self.url
        var err: Error?
        Self.writeQueue.sync { do { try Self.atomicReplace(built.data, at: url) } catch { err = error } }
        if let e = err { isDirty = true; errorMessage = String(localized: "Save failed: \(e.localizedDescription)", bundle: .module); return false }
        isDirty = false; saveRequestedWhileSaving = false; isSaving = false
        fileGeneration += 1   // 큐에 남아 있던 비동기 저장의 완료 콜백은 무시된다 (내용은 이 쓰기 이전에 이미 디스크에 반영됨)
        lastSaved = Date(); ourLastWrite = lastSaved
        loadedLength = textStorage.length; fileSize = built.data.count
        if built.convertedToUTF8 { encoding = .utf8; hasBOM = false }
        errorMessage = nil
        status = String(localized: "Saved · \(Self.timeString(lastSaved!))", bundle: .module)
        startWatching()
        return true
    }

    nonisolated(unsafe) private static let writeQueue = DispatchQueue(label: "hyperedit.document.write", qos: .userInitiated)

    /// 원 인코딩으로 표현할 수 없는 문자가 있으면(예: EUC-KR 파일에 이모지) UTF-8 로 변환 — 데이터는 잃지 않는다
    nonisolated static func encode(_ s: String, encoding: String.Encoding, bom: Bool) -> (data: Data, convertedToUTF8: Bool) {
        if let d = s.data(using: encoding) { return (bom ? Data([0xEF, 0xBB, 0xBF]) + d : d, false) }
        return (s.data(using: .utf8) ?? Data(), true)
    }

    // MARK: - Snapshots

    public static var snapshotDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HyperEdit/snapshots", isDirectory: true)
    }

    /// 디스크의 현재 파일을 스냅샷 폴더로 복사한 뒤 오래된 스냅샷을 정리한다. 반환: 스냅샷 경로
    @discardableResult
    public func snapshot(tag: String) throws -> URL {
        let dir = Self.snapshotDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(url.lastPathComponent)-\(f.string(from: Date()))-\(tag).txt"
        let dest = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: dest)
        Self.pruneSnapshots(in: dir, filePrefix: url.lastPathComponent + "-")
        return dest
    }

    /// 보관 정책: 파일별 최신 `keepPerFile` 개, 그리고 `maxAgeDays` 보다 오래된 것은 삭제 (무한 증가 방지)
    public static func pruneSnapshots(in dir: URL, filePrefix: String, keepPerFile: Int = 20, maxAgeDays: Int = 90) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
        for u in items {
            if let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate), d < cutoff { try? fm.removeItem(at: u) }
        }
        let mine = items.filter { $0.lastPathComponent.hasPrefix(filePrefix) && fm.fileExists(atPath: $0.path) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // 이름에 타임스탬프가 있어 사전순 = 시간순
        for u in mine.dropFirst(keepPerFile) { try? fm.removeItem(at: u) }
    }

    // MARK: - External change watching

    private func startWatching() {
        watchSource?.cancel()
        watchSource = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        src.setEventHandler { [weak self] in
            let flags = src.data
            Task { @MainActor [weak self] in self?.handleFileEvent(flags) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchSource = src
    }

    private func handleFileEvent(_ flags: DispatchSource.FileSystemEvent) {
        let structural = flags.contains(.delete) || flags.contains(.rename)
        if let w = ourLastWrite, Date().timeIntervalSince(w) < 1.5 {
            if structural { startWatching() }
            return
        }
        if structural {
            // 다른 앱의 원자적 저장: 잠시 뒤 새 inode 를 다시 감시
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.startWatching()
                self?.applyExternalChange()
            }
        } else {
            applyExternalChange()
        }
    }

    private func applyExternalChange() {
        externalChange = Date()
        if isDirty {
            _ = try? snapshot(tag: "external")
            status = String(localized: "External change detected — saving will overwrite it (the external copy is kept as a snapshot)", bundle: .module)
        } else {
            reloadFromDisk()
        }
    }

    public func reloadFromDisk() {
        guard let data = try? Data(contentsOf: url), let decoded = Self.decode(data) else { return }
        guard decoded.text != textStorage.string else { return }
        encoding = decoded.encoding
        hasBOM = decoded.bom
        replaceAll(with: decoded.text)
        isDirty = false
        status = String(localized: "Reloaded external change · \(Self.timeString(Date()))", bundle: .module)
    }

    // MARK: - NSTextStorageDelegate (한글 폭 보정)

    public nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated {
            guard editedMask.contains(.editedCharacters) else { return }
            // 문자 변경은 모두 '편집' 이다 — 텍스트 뷰를 거치지 않는 undo/redo(macOS 27 TextKit 2 는 shouldChangeText/didChangeText 를 부르지 않는다)도
            // 여기서 잡아 dirty·자동 저장·줄 인덱스 재계산을 건다. 뷰 경로의 textDidChange() 와 겹쳐도 예약 취소·재예약뿐이라 비용은 없다.
            if programmaticReplaceDepth == 0, isLoaded { textDidChange() }
            guard let font = hangulFont else { return }
            let para = (textStorage.string as NSString).paragraphRange(for: editedRange)
            HangulFontFixer.apply(font: font, to: textStorage, in: para)
        }
    }

    // MARK: - Helpers

    nonisolated static func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}
