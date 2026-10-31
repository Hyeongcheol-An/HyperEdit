import SwiftUI
import AppKit
import HyperCore
import Darwin

/// 성능 벤치마크 하네스 (개발용): `--bench [--bench-out <path.json>] [--bench-strict] [--bench-commit <sha>] [--quit]`
///
/// 임시 폴더에 자체 말뭉치(small 2 KB · medium 200 KB · large 1.3 MB · huge 8 MB)를 만들어 그 위에서만 측정한다 — 사용자 문서·설정은
/// 건드리지 않는다 (`HyperEditApp.init` 이 `--bench` 에 휘발성 UserDefaults 를 쓴다). 실행 시 `--file <임시 .md>` 를 함께 주면 기본 문서를
/// 아예 열지 않는다 (`scripts/bench.sh` 가 그렇게 한다). 결과는 Markdown 표(stderr + `<out>.md`)와 JSON(`<out>`)으로 쓴다.
/// 항목마다 예산(budget)이 있어 PASS/FAIL 을 표시하고, `--bench-strict` 면 FAIL 이 하나라도 있을 때 종료 코드 1 로 끝난다.
///
/// 실행 시간 계측: `--bench-launch-log <path>` 는 프로세스 시작(커널 p_starttime) → didFinishLaunching → 첫 ContentView → 첫 창 표시까지의
/// ms 를 한 줄로 덧붙이고, `--quit-after-launch` 는 첫 창이 보인 0.1 초 뒤 종료한다 (`scripts/bench.sh` 가 5회 반복해 중앙값을 낸다).
enum Bench {
    static var enabled: Bool { CommandLine.arguments.contains("--bench") }
    static var strict: Bool { CommandLine.arguments.contains("--bench-strict") }
    static var outPath: String? { LaunchOptions.value("--bench-out") }
    /// `--bench-only idle,open,memory,scroll,search,outline,theme,typing,replace,save` — 프로파일링용으로 일부 단계만 실행
    static func phase(_ name: String) -> Bool {
        guard let only = LaunchOptions.value("--bench-only") else { return true }
        return only.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(name)
    }

    // MARK: - 결과 모델

    struct Metric: Codable {
        let id: String
        let name: String
        let unit: String
        let median: Double
        let p95: Double
        let min: Double
        let max: Double
        let n: Int
        let budgetMedian: Double?
        let budgetP95: Double?
        let pass: Bool
        /// 참고 정보(배경 작업 등) — 예산은 있지만 strict 실패에 넣지 않는다
        let informational: Bool

        init(id: String, name: String, unit: String = "ms", samples: [Double], budget: Double? = nil, budgetP95: Double? = nil, informational: Bool = false) {
            let s = Bench.stats(samples)
            self.id = id; self.name = name; self.unit = unit
            median = s.median; p95 = s.p95; min = s.min; max = s.max; n = samples.count
            budgetMedian = budget; self.budgetP95 = budgetP95
            var ok = true
            if let b = budget, s.median > b { ok = false }
            if let b = budgetP95, s.p95 > b { ok = false }
            pass = ok
            self.informational = informational
        }
    }

    struct Machine: Codable { let model: String; let cores: Int; let memoryGB: Int; let os: String }
    /// 측정 전후 1분 부하 평균 — 코어 수를 넘으면 표에 "measured under load" 를 표시한다 (다른 빌드가 돌 때의 수치는 기준선으로 쓰지 말 것)
    struct Load: Codable { let before: Double; let after: Double; let cores: Int; var underLoad: Bool { max(before, after) > Double(cores) } }
    struct CorpusInfo: Codable { let bytes: Int; let lines: Int }
    struct Result: Codable {
        let version: String
        let commit: String
        let date: String
        let machine: Machine
        let corpus: [String: CorpusInfo]
        let load: Load
        var metrics: [Metric]
        var allPass: Bool
    }

    // MARK: - 실행 시간 이정표 (프로세스 시작 기준 ms)

    /// 커널이 기록한 프로세스 시작 시각 — `main` 이전(dyld·정적 초기화)까지 포함한 진짜 콜드 스타트 기준점
    static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }()
    nonisolated(unsafe) private static var milestones: [(String, Double)] = []
    private static var launchLogPath: String? { LaunchOptions.value("--bench-launch-log") }
    private static var launchTracking: Bool { launchLogPath != nil || LaunchOptions.has("--quit-after-launch") || enabled }

    static func msSinceProcessStart() -> Double {
        guard let s = processStart else { return -1 }
        return Date().timeIntervalSince(s) * 1000
    }

    /// AppDelegate.applicationDidFinishLaunching / ContentView.onAppear 에서 한 줄로 호출. 계측이 꺼져 있으면 비용 0.
    @MainActor
    static func launchMilestone(_ tag: String) {
        guard launchTracking else { return }
        milestones.append((tag, msSinceProcessStart()))
        if tag == "didFinishLaunching", LaunchOptions.has("--quit-after-launch") || launchLogPath != nil {
            // 실행 시간 계측은 셸에서 직접 exec 하므로 LaunchServices 의 'oapp' 이벤트가 오지 않아 AppDelegate 의 0.4 s 폴백('rapp')까지 창이 안 뜬다.
            // Dock/Finder 실행과 같은 조건이 되도록 50 ms 뒤 창이 없으면 바로 '다시 열기' 이벤트를 보낸다 (계측 모드에서만).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard NSApp.windows.isEmpty else { return }
                let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                                   targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                _ = try? event.sendEvent(options: [.noReply], timeout: 1)
                milestones.append(("reopenSent", msSinceProcessStart()))
            }
        }
        guard tag == "contentViewAppeared" else { return }
        // 첫 창이 실제로 화면에 올라온 시점을 5 ms 간격으로 확인 (최대 3 초)
        func poll(_ n: Int) {
            if NSApp.windows.contains(where: { $0.isVisible && $0.contentView != nil }) || n > 600 {
                milestones.append(("windowVisible", msSinceProcessStart()))
                writeLaunchLog()
                if LaunchOptions.has("--quit-after-launch") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { poll(n + 1) }
        }
        poll(0)
    }

    private static func writeLaunchLog() {
        let line = "pid=\(getpid()) " + milestones.map { String(format: "%@=%.1f", $0.0, $0.1) }.joined(separator: " ") + " exe=\(Bundle.main.bundlePath)\n"
        FileHandle.standardError.write(("[bench-launch] " + line).data(using: .utf8)!)
        guard let p = launchLogPath else { return }
        if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { FileManager.default.createFile(atPath: p, contents: line.data(using: .utf8)) }
    }

    // MARK: - 유틸

    static func stats(_ xs: [Double]) -> (median: Double, p95: Double, min: Double, max: Double) {
        let s = xs.sorted()
        guard !s.isEmpty else { return (0, 0, 0, 0) }
        let med = s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        let p95 = s[Swift.min(s.count - 1, Int((Double(s.count - 1) * 0.95).rounded()))]
        return (med, p95, s[0], s[s.count - 1])
    }

    static func now() -> Double { CFAbsoluteTimeGetCurrent() * 1000 }
    static func wait(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
    /// 다음 런루프 턴 — 그 사이에 CA 커밋(레이아웃·그리기)이 한 번 지나간다
    @MainActor static func nextTurn() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }
    @MainActor static func afterFrame() async { await withCheckedContinuation { c in DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { c.resume() } } }

    /// 상주 메모리(MB): resident_size 와 phys_footprint(활성 상태 보기의 "메모리")
    static func memoryMB() -> (resident: Double, footprint: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        return (Double(info.resident_size) / 1_048_576, Double(info.phys_footprint) / 1_048_576)
    }

    /// 프로세스 누적 CPU 시간(초, user+sys)
    static func cpuSeconds() -> Double {
        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        return Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6 + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6
    }

    /// 누적 깨어남 횟수(인터럽트 + 타이머)
    static func wakeups() -> Double {
        var info = task_power_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.task_interrupt_wakeups + info.task_timer_wakeups_bin_1 + info.task_timer_wakeups_bin_2)
    }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buf)
    }

    static func loadAverage() -> Double {
        var l = [Double](repeating: 0, count: 3)
        return getloadavg(&l, 3) > 0 ? l[0] : 0
    }

    static func machine() -> Machine {
        let info = ProcessInfo.processInfo
        return Machine(model: sysctlString("hw.model"), cores: info.activeProcessorCount,
                       memoryGB: Int((Double(info.physicalMemory) / 1_073_741_824).rounded()), os: info.operatingSystemVersionString)
    }

    // MARK: - 말뭉치 (결정적 PRNG — 실행마다 같은 내용)

    struct Rng {
        var s: UInt64
        mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    }

    static let smallText = """
    # Bench small sample

    ## 2026-10-30 (금) 09:30
    오늘 할 일을 정리한다. The quick brown fox jumps over the lazy dog.
    - [ ] 벤치 하네스 작성 #perf
    - [x] 셀프테스트 통과 확인
    - error budget 검토 후 배포 → 금요일

    [Title] bracket heading
    2022-01-06 01:21:02 INFO request id=4821 took 35ms
    key: value · https://example.com/docs/api/v2/items?id=1234

    ```swift
    let x = LineIndex(text: "a\\nb")   // comment
    ```

    가. 한글 항목
    1) numbered item
    name\tqty\tnote
    홍길동\t3\tok
    tail line that ends the small corpus and is long enough to wrap when the window is narrow enough for a test
    """

    /// `targetBytes` 에 이를 때까지 줄을 만든다. 평균 ~44 B/줄 → 1.3 MB ≈ 3만 줄, 8 MB ≈ 18만 줄.
    static func makeCorpus(targetBytes: Int, seed: UInt64) -> (text: String, lines: Int) {
        var rng = Rng(s: seed | 1)
        var out = ""
        out.reserveCapacity(targetBytes + 4096)
        let ko = ["오늘 회의에서 논의한 내용을 정리한다.", "다음 주까지 결과를 공유할 것.", "서버 배포는 금요일 오후로 미룬다.", "테스트 커버리지를 80% 이상으로 올린다.",
                  "한글 입력 폭 보정은 D2Coding 으로 처리한다.", "검색 결과가 비어 있으면 안내 문구를 보여 준다.", "메모는 한 파일에 계속 덧붙인다."]
        let en = ["The quick brown fox jumps over the lazy dog near the river bank.", "We should review the error budget before the next release.",
                  "Keep the main thread free: index on a snapshot, publish on the main actor.", "Autosave runs two seconds after the last edit, then the watcher restarts.",
                  "The outline shows headings, bracket titles and numbered items.", "Typing latency must stay under one frame on a 1 MB file."]
        let code = ["    for i in range(10): print(i)  # comment", "    let idx = LineIndex(text: text)  // rebuild", "    if err != nil { return err }",
                    "    def handle(error): raise RuntimeError(error)", "    const url = `https://api.example.com/v1/${id}`;", "    SELECT id, name FROM users WHERE active = 1;"]
        let hosts = ["https://example.com/docs/api/v2/items?id=", "http://localhost:8080/health?probe=", "https://github.com/Hyeongcheol-An/HyperEdit/issues/"]
        let keys = ["owner", "status", "priority", "due", "tags", "branch"]
        let vals = ["open", "done", "high", "2026-11-07", "perf, editor", "main"]
        let names = ["홍길동", "김영희", "Alice", "Bob", "이철수"]
        let days = ["월", "화", "수", "목", "금", "토", "일"]
        var bytes = 0, lines = 0, heading = 0
        while bytes < targetBytes {
            lines += 1
            let s: String
            switch rng.int(100) {
            case 0..<3:
                s = String(format: "## %04d-%02d-%02d (%@) %02d:%02d", 2020 + rng.int(7), 1 + rng.int(12), 1 + rng.int(28), rng.pick(days), rng.int(24), rng.int(60))
            case 3..<6:
                heading += 1
                s = (rng.int(3) == 0 ? "# " : "## ") + (rng.int(2) == 0 ? "Section \(heading): \(rng.pick(en).prefix(28))" : "\(heading)장 \(rng.pick(ko).prefix(14))")
            case 6..<22:
                s = rng.int(3) == 0 ? rng.pick(ko) + " " + rng.pick(ko) : rng.pick(ko)
            case 22..<38:
                s = rng.pick(en)
            case 38..<48:
                s = "서버 error 로그 확인 — retry \(1 + rng.int(5))회 후 fail, see \(rng.pick(hosts))\(1000 + rng.int(9000))"
            case 48..<58:
                s = rng.pick(code)
            case 58..<66:
                s = rng.int(2) == 0 ? "- [\(rng.int(3) == 0 ? "x" : " ")] \(rng.pick(ko).prefix(16)) #tag\(rng.int(9))" : "- \(rng.pick(en).prefix(40))"
            case 66..<72:
                s = rng.int(4) == 0 ? "name\tqty\tnote" : "\(rng.pick(names))\t\(rng.int(100))\t\(rng.int(2) == 0 ? "ok" : "error")"
            case 72..<84:
                s = String(format: "%04d-%02d-%02d %02d:%02d:%02d %@ request id=%d took %dms", 2020 + rng.int(7), 1 + rng.int(12), 1 + rng.int(28),
                           rng.int(24), rng.int(60), rng.int(60), rng.int(4) == 0 ? "ERROR" : "INFO", rng.int(10000), rng.int(900))
            case 84..<90:
                let k = rng.int(keys.count)
                s = "\(keys[k]): \(vals[k])"
            default:
                s = ""
            }
            out += s
            out += "\n"
            bytes += s.utf8.count + 1
        }
        return (out, lines + 1)   // 마지막 개행 뒤 빈 줄(에디터 관례)
    }

    // MARK: - 실행

    @MainActor
    static func run(model: AppModel) async {
        var metrics: [Metric] = []
        var corpus: [String: CorpusInfo] = [:]
        func log(_ s: String) {
            FileHandle.standardError.write(("[bench] " + s + "\n").data(using: .utf8)!)
            model.log("[bench] " + s)
        }
        func add(_ m: Metric) {
            metrics.append(m)
            log(String(format: "%@ %@ · median %.2f · p95 %.2f %@ (n=%d)", m.pass ? "PASS" : "FAIL", m.id, m.median, m.p95, m.unit, m.n))
        }
        await wait(1200)
        let loadBefore = loadAverage()

        // 0. 말뭉치
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-bench-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let urls = ["small", "medium", "large", "huge"].reduce(into: [String: URL]()) { $0[$1] = dir.appendingPathComponent("\($1).md") }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let t0 = now()
            try smallText.write(to: urls["small"]!, atomically: true, encoding: .utf8)
            corpus["small"] = CorpusInfo(bytes: smallText.utf8.count, lines: smallText.components(separatedBy: "\n").count)
            for (name, bytes, seed) in [("medium", 200_000, UInt64(11)), ("large", 1_300_000, UInt64(22)), ("huge", 8_000_000, UInt64(33))] {
                let c = makeCorpus(targetBytes: bytes, seed: seed)
                try c.text.write(to: urls[name]!, atomically: true, encoding: .utf8)
                corpus[name] = CorpusInfo(bytes: c.text.utf8.count, lines: c.lines)
            }
            log(String(format: "corpus at %@ · generated in %.0f ms · %@", dir.path, now() - t0,
                       corpus.sorted { $0.value.bytes < $1.value.bytes }.map { "\($0.key)=\($0.value.bytes)B/\($0.value.lines)L" }.joined(separator: " ")))
        } catch { log("FAIL cannot create corpus: \(error)"); return }

        let memLaunch = memoryMB()
        model.open(url: urls["small"]!)
        await wait(600)
        // 텍스트 뷰 참조 (한 번만 — `.perform` 은 문서를 dirty 로 표시하므로 이후에는 직접 호출한다)
        var tvRef: HyperTextView?
        model.send(.perform { tvRef = $0 })
        guard let tv = tvRef else { log("FAIL no text view"); return }
        model.saveNow(); await wait(500)
        model.document.autosaveDelay = 3600   // 측정 중 자동 저장이 끼어들지 않게; 저장 비용은 따로 잰다

        // 1. 시작 직후 유휴 CPU (small 문서, 구조 스캔 디바운스가 지나간 뒤)
        if phase("idle") {
            await wait(2000)
            let c0 = cpuSeconds(), w0 = wakeups(), t0 = now()
            await wait(3000)
            let dt = (now() - t0) / 1000
            let pct = (cpuSeconds() - c0) / dt * 100
            add(Metric(id: "idle.cpu.small", name: "Idle CPU, small doc, 3 s", unit: "%", samples: [pct], budget: 1))
            add(Metric(id: "idle.wakeups.small", name: "Idle wakeups/s, small doc", unit: "/s", samples: [(wakeups() - w0) / dt], budget: 30, informational: true))
        }
        add(Metric(id: "memory.rss.launch", name: "RSS after launch (small doc)", unit: "MB", samples: [memLaunch.resident], budget: 200, informational: true))
        add(Metric(id: "memory.footprint.launch", name: "Footprint after launch", unit: "MB", samples: [memLaunch.footprint], informational: true))
        if let m = milestones.first(where: { $0.0 == "windowVisible" }) {
            add(Metric(id: "launch.windowVisible", name: "Launch → first window (this run, in-process)", samples: [m.1], budget: 600, informational: true))
        }

        // 2. 파일 열기 (small → target), 5회: sync / next turn / after frame
        for (name, budget) in [("medium", 50.0), ("large", 150.0), ("huge", 800.0)] where phase("open") {
            var sync: [Double] = [], turn: [Double] = [], settled: [Double] = []
            for _ in 0..<5 {
                model.open(url: urls["small"]!); await wait(500)
                let t = now()
                model.open(url: urls[name]!)
                sync.append(now() - t)
                await nextTurn(); turn.append(now() - t)
                await afterFrame(); settled.append(now() - t)
                await wait(name == "huge" ? 1500 : 800)
            }
            add(Metric(id: "open.\(name).sync", name: "Open \(name): synchronous part", samples: sync, informational: true))
            add(Metric(id: "open.\(name).nextTurn", name: "Open \(name): + next run-loop turn", samples: turn, informational: true))
            add(Metric(id: "open.\(name).settled", name: "Open \(name): + first frame", samples: settled, budget: budget))
        }
        // 3. 메모리: huge 로드 뒤, small↔huge 5회 전환 뒤 (누수면 계속 오른다)
        if phase("memory") {
            if model.document.url != urls["huge"]! { model.open(url: urls["huge"]!); await wait(1500) }
            let memHuge = memoryMB()
            add(Metric(id: "memory.rss.huge", name: "RSS after loading huge (8 MB)", unit: "MB", samples: [memHuge.resident], budget: 400))
            add(Metric(id: "memory.footprint.huge", name: "Footprint after loading huge", unit: "MB", samples: [memHuge.footprint], informational: true))
            for _ in 0..<5 {
                model.open(url: urls["small"]!); await wait(400)
                model.open(url: urls["huge"]!); await wait(1200)
            }
            let memSwitch = memoryMB()
            add(Metric(id: "memory.rss.after5switches", name: "RSS after 5 small↔huge switches", unit: "MB", samples: [memSwitch.resident], budget: 450))
            add(Metric(id: "memory.growth.pct", name: "RSS growth over 5 switches vs first huge load", unit: "%", samples: [(memSwitch.resident - memHuge.resident) / Swift.max(1, memHuge.resident) * 100], budget: 20))
        }

        // 4. 스크롤 (large): 40 단계로 문서 끝까지, 끝으로 / 1줄로 점프
        if phase("scroll") {
            model.open(url: urls["large"]!); await wait(1500)
            let len = model.document.textStorage.length
            var steps: [Double] = []
            for i in 1...40 {
                let off = len * i / 40
                let t = now()
                tv.scrollRangeToVisible(NSRange(location: Swift.min(off, len), length: 0))
                await nextTurn()
                steps.append(now() - t)
            }
            add(Metric(id: "scroll.step.large", name: "Scroll step (1/40 of doc), large", samples: steps, budget: 16, budgetP95: 33))
            var toEnd: [Double] = [], toTop: [Double] = []
            for _ in 0..<5 {
                model.jump(toLine: 1); await nextTurn(); await afterFrame(); await wait(100)
                var t = now()
                model.goToEnd(); await nextTurn(); await afterFrame()
                toEnd.append(now() - t)
                await wait(100)
                t = now()
                model.jump(toLine: 1); await nextTurn(); await afterFrame()
                toTop.append(now() - t)
                await wait(100)
            }
            add(Metric(id: "jump.end.large", name: "Go to end (⌃⌘E), large", samples: toEnd, budget: 50))
            add(Metric(id: "jump.line1.large", name: "Go to line 1, large", samples: toTop, budget: 50))
        }

        // 5. 검색 엔진 (스냅샷 위, 동기) — large / huge
        for (name, budget) in [("large", 60.0), ("huge", 400.0)] where phase("search") {
            model.open(url: urls[name]!); await wait(name == "huge" ? 1500 : 800)
            let text = model.document.textStorage.string
            var idxT: [Double] = []
            var idx = LineIndex()
            for _ in 0..<5 { let t = now(); idx = LineIndex(text: text); idxT.append(now() - t) }
            add(Metric(id: "lineIndex.build.\(name)", name: "LineIndex full build, \(name) (background)", samples: idxT, budget: name == "large" ? 20 : 120, informational: true))
            var lit = SearchOptions(); lit.caseSensitive = true
            let ci = SearchOptions()
            var re = SearchOptions(); re.regex = true
            var ww = SearchOptions(); ww.wholeWord = true
            for (kind, q, o) in [("literal", "error", lit), ("caseInsensitive", "Error", ci), ("regex", #"\d{4}-\d{2}-\d{2}"#, re), ("wholeWord", "the", ww)] {
                var ts: [Double] = []
                var hits = 0
                for _ in 0..<5 {
                    let t = now()
                    hits = (try? SearchEngine.search(q, in: text, index: idx, options: o))?.count ?? -1
                    ts.append(now() - t)
                }
                add(Metric(id: "search.\(kind).\(name)", name: "Search \(kind) '\(q)', \(name) (\(hits) hits)", samples: ts, budget: budget))
            }
        }

        // 6. 아웃라인/타임라인 스캔 · 마크다운 HTML 렌더 (large, 배경 작업이라 참고용 예산)
        if phase("outline") {
            model.open(url: urls["large"]!); await wait(1500)
            let text = model.document.textStorage.string
            let idx = LineIndex(text: text)
            var scan: [Double] = [], md: [Double] = []
            for _ in 0..<5 {
                let t = now()
                _ = OutlineScanner.outline(text, index: idx, isMarkdown: true)
                _ = OutlineScanner.timeline(text, index: idx)
                scan.append(now() - t)
            }
            add(Metric(id: "outline.rescan.large", name: "Outline + timeline rescan, large (background)", samples: scan, budget: 300, informational: true))
            for _ in 0..<3 {
                let t = now()
                _ = MarkdownHTML.html(for: text, theme: model.themes.current, baseURL: dir)
                md.append(now() - t)
            }
            add(Metric(id: "markdown.render.large", name: "Markdown → HTML, large (background)", samples: md, budget: 1500, informational: true))
        }

        // 7. 테마 전환 · 글자 크기 (large, huge): 전체 스토리지 속성 재적용 포함, 텍스트 뷰 배경색이 바뀔 때까지
        func waitFor(_ cond: @MainActor () -> Bool, maxMs: Double) async -> Double {
            let t = now()
            while !cond() && now() - t < maxMs { await nextTurn() }
            await afterFrame()
            return now() - t
        }
        for (name, budget) in [("large", 300.0), ("huge", 1500.0)] where phase("theme") {
            model.open(url: urls[name]!); await wait(name == "huge" ? 1500 : 800)
            let original = model.themes.current
            let other = model.themes.themes.first { $0.id == (original.isDark ? ThemeStore.defaultLightID : ThemeStore.defaultDarkID) } ?? model.themes.themes.first { $0.id != original.id }!
            var ts: [Double] = []
            for _ in 0..<5 {
                for target in [other, original] {
                    var t = 0.0
                    model.themes.select(id: target.id)
                    t = await waitFor({ tv.backgroundColor.isEqual(target.background.nsColor) }, maxMs: 5000)
                    ts.append(t)
                    await wait(150)
                }
            }
            add(Metric(id: "theme.switch.\(name)", name: "Theme switch, \(name)", samples: ts, budget: budget, informational: name == "huge"))
            var fs: [Double] = []
            let size0 = model.font.size
            for _ in 0..<5 {
                for delta in [1.0, -1.0] {
                    let want = model.font.size + delta
                    model.adjustFontSize(delta)
                    fs.append(await waitFor({ ((tv.typingAttributes[.font] as? NSFont)?.pointSize ?? 0) == CGFloat(want) }, maxMs: 5000))
                    await wait(150)
                }
            }
            model.font.size = size0
            add(Metric(id: "fontSize.change.\(name)", name: "Font size change (⌘=/⌘-), \(name)", samples: fs, budget: budget, informational: name == "huge"))
        }

        // 8. 타이핑: 80타, 끝/중간, 구문 색 켬/끔 — large, huge
        let typingText = Array("the quick brown fox jumps over the lazy dog 그리고 한글 입력 ".utf16).map { String(utf16CodeUnits: [$0], count: 1) }
        @MainActor func typeRun(at offset: Int, count: Int, text: [String]) async -> [Double] {
            tv.setSelectedRange(NSRange(location: offset, length: 0))
            tv.scrollRangeToVisible(tv.selectedRange())
            await nextTurn(); await afterFrame(); await wait(150)
            tv.breakUndoCoalescing()
            tv.insertText("x", replacementRange: tv.selectedRange()); await nextTurn()   // 워밍업(레이아웃·캐시)
            var samples: [Double] = []
            for i in 0..<count {
                let t = now()
                tv.insertText(text[i % text.count], replacementRange: tv.selectedRange())
                await nextTurn()
                samples.append(now() - t)
            }
            let caret = tv.selectedRange().location
            tv.insertText("", replacementRange: NSRange(location: caret - count - 1, length: count + 1))
            await nextTurn()
            return samples
        }
        for name in ["large", "huge"] where phase("typing") {
            model.open(url: urls[name]!); await wait(name == "huge" ? 1500 : 800)
            let len = model.document.textStorage.length
            let ns = model.document.textStorage.string as NSString
            let middle = ns.lineRange(for: NSRange(location: len / 2, length: 0)).location
            for hl in [true, false] {
                if model.syntaxHighlighting != hl {
                    let t = now()
                    model.syntaxHighlighting = hl
                    await nextTurn(); await afterFrame()
                    add(Metric(id: "highlight.toggle.\(hl ? "on" : "off").\(name)", name: "Syntax colors \(hl ? "on" : "off") (⌃⌘H), \(name)", samples: [now() - t], budget: 300, informational: true))
                    await wait(300)
                }
                let tag = hl ? "hl" : "plain"
                add(Metric(id: "typing.end.\(tag).\(name)", name: "Typing at end, \(hl ? "colors on" : "colors off"), \(name)", samples: await typeRun(at: len, count: 80, text: typingText), budget: 8, budgetP95: 16))
                await wait(300)
                add(Metric(id: "typing.middle.\(tag).\(name)", name: "Typing in middle, \(hl ? "colors on" : "colors off"), \(name)", samples: await typeRun(at: middle, count: 80, text: typingText), budget: 8, budgetP95: 16))
                await wait(300)
            }
            model.syntaxHighlighting = true; await wait(300)
            // Enter 키: 중간에 개행 20회 — 북마크 없음(인덱스 경로만) / 북마크 있음(줄 추적 훅: 캐럿까지 개행 세기)
            add(Metric(id: "enter.middle.\(name)", name: "Enter in middle (no bookmarks), \(name)", samples: await typeRun(at: middle, count: 20, text: ["\n"]), budget: 8, budgetP95: 16))
            model.jump(toLine: 3); await wait(200); model.toggleBookmarkAtCaret()
            add(Metric(id: "enter.middle.bookmarked.\(name)", name: "Enter in middle (bookmark tracking on), \(name)", samples: await typeRun(at: middle, count: 20, text: ["\n"]), budget: 8, budgetP95: 16))
            model.jump(toLine: 3); await wait(200); model.toggleBookmarkAtCaret()
            await wait(300)
        }

        // 9. 모두 바꾸기 5,000건 + ⌘Z 한 번 (large)
        if phase("replace") {
            model.open(url: urls["large"]!); await wait(1200)
            var rep: [Double] = [], undo: [Double] = []
            var count = 0
            var restored = true
            for _ in 0..<5 {
                let text = model.document.textStorage.string
                let len = (text as NSString).length
                var o = SearchOptions(); o.caseSensitive = true
                let hits = (try? SearchEngine.search("error", in: text, index: LineIndex(text: text), options: o, limit: 5000)) ?? []
                count = hits.count
                let reps = hits.map { Replacement(range: $0.range, string: "warning") }
                tv.breakUndoCoalescing()
                var t = now()
                model.send(.replaceRanges(reps))
                await nextTurn()
                rep.append(now() - t)
                await wait(300)
                t = now()
                tv.undoManager?.undo()
                await nextTurn()
                undo.append(now() - t)
                restored = restored && model.document.textStorage.length == len
                await wait(500)
            }
            add(Metric(id: "replaceAll.5000.large", name: "Replace all (\(count) matches), large\(restored ? "" : " [undo did not restore length]")", samples: rep, budget: 500))
            add(Metric(id: "undo.replaceAll.large", name: "Single undo of replace-all, large", samples: undo, budget: 500))
        }

        // 10. 저장 비용 (huge): save() 의 메인 스레드 동기 부분(스냅샷 복사 포함) · 스냅샷 복사 단독
        if phase("save") {
            model.open(url: urls["huge"]!); await wait(1500)
            var saveT: [Double] = [], copyT: [Double] = []
            for _ in 0..<5 {
                tv.setSelectedRange(NSRange(location: model.document.textStorage.length, length: 0))
                tv.insertText("z", replacementRange: tv.selectedRange()); await nextTurn()
                tv.insertText("", replacementRange: NSRange(location: model.document.textStorage.length - 1, length: 1)); await nextTurn()
                let t = now()
                model.saveNow()
                saveT.append(now() - t)
                await wait(400)
            }
            for _ in 0..<5 { let t = now(); _ = model.document.textStorage.mutableString.copy(); copyT.append(now() - t) }
            add(Metric(id: "save.sync.huge", name: "save(): main-thread part, huge", samples: saveT, budget: 30))
            add(Metric(id: "snapshot.copy.huge", name: "Text snapshot copy (per index rebuild / save), huge", samples: copyT, budget: 15, informational: true))
        }

        // 11. 유휴 CPU (huge 문서, 저장·스캔이 끝난 뒤)
        if phase("idle") {
            if model.document.url != urls["huge"]! { model.open(url: urls["huge"]!) }
            await wait(2500)
            let c0 = cpuSeconds(), w0 = wakeups(), t0 = now()
            await wait(3000)
            let dt = (now() - t0) / 1000
            add(Metric(id: "idle.cpu.huge", name: "Idle CPU, huge doc, 3 s", unit: "%", samples: [(cpuSeconds() - c0) / dt * 100], budget: 1))
            add(Metric(id: "idle.wakeups.huge", name: "Idle wakeups/s, huge doc", unit: "/s", samples: [(wakeups() - w0) / dt], budget: 30, informational: true))
        }
        let memEnd = memoryMB()
        add(Metric(id: "memory.rss.end", name: "RSS at end of bench (huge open)", unit: "MB", samples: [memEnd.resident], budget: 450, informational: true))

        // 결과
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        let f = ISO8601DateFormatter()
        let strictFail = metrics.contains { !$0.pass && !$0.informational }
        let result = Result(version: version, commit: LaunchOptions.value("--bench-commit") ?? "unknown", date: f.string(from: Date()),
                            machine: machine(), corpus: corpus, load: Load(before: loadBefore, after: loadAverage(), cores: ProcessInfo.processInfo.activeProcessorCount),
                            metrics: metrics, allPass: !strictFail)
        let table = markdownTable(result)
        FileHandle.standardError.write((table + "\n").data(using: .utf8)!)
        if let p = outPath {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(result) { try? data.write(to: URL(fileURLWithPath: p)) }
            let mdPath = (p as NSString).deletingPathExtension + ".md"
            try? table.write(toFile: mdPath, atomically: true, encoding: .utf8)
        }
        log(strictFail ? "BUDGET FAILURES: \(metrics.filter { !$0.pass && !$0.informational }.map(\.id).joined(separator: ", "))" : "ALL BUDGETS PASS")
        try? FileManager.default.removeItem(at: dir)
        if strict && strictFail { exit(1) }
        if CommandLine.arguments.contains("--quit") { await wait(200); NSApp.terminate(nil) }
    }

    static func markdownTable(_ r: Result) -> String {
        func fmt(_ v: Double, _ unit: String) -> String {
            unit == "ms" ? (v >= 100 ? String(format: "%.0f", v) : String(format: "%.2f", v)) : String(format: "%.1f", v)
        }
        var out = "## HyperEdit bench · v\(r.version) · \(r.commit) · \(r.date)\n\n"
        out += "Machine: \(r.machine.model) · \(r.machine.cores) cores · \(r.machine.memoryGB) GB · \(r.machine.os)  \n"
        out += String(format: "Load average (1 min) before/after: %.1f / %.1f%@  \n", r.load.before, r.load.after, r.load.underLoad ? " — **measured under load, not a baseline**" : "")
        out += "Corpus: " + r.corpus.sorted { $0.value.bytes < $1.value.bytes }.map { "\($0.key) \($0.value.bytes / 1024) KB / \($0.value.lines) lines" }.joined(separator: " · ") + "\n\n"
        out += "| Metric | median | p95 | n | budget | result |\n|---|---:|---:|---:|---|---|\n"
        for m in r.metrics {
            var budget = m.budgetMedian.map { fmt($0, m.unit) + " " + m.unit } ?? "—"
            if let p = m.budgetP95 { budget += " / p95 " + fmt(p, m.unit) }
            let res = m.pass ? "PASS" : (m.informational ? "over (info)" : "FAIL")
            out += "| \(m.name) `\(m.id)` | \(fmt(m.median, m.unit)) \(m.unit) | \(fmt(m.p95, m.unit)) | \(m.n) | \(budget) | \(res) |\n"
        }
        out += "\n" + (r.allPass ? "All budgets PASS." : "Budget failures: " + r.metrics.filter { !$0.pass && !$0.informational }.map(\.id).joined(separator: ", ")) + "\n"
        return out
    }
}
