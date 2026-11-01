import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import HyperCore

// export: 파일 › Export as HTML… / Export as PDF…. HTML 은 HyperCore `HTMLExporter`(마크다운 → MarkdownHTML 독립 문서, 메모·코드 → 구문 색 pre),
// PDF 는 같은 HTML 을 화면 밖 WKWebView 에 올려 인쇄 작업(`printOperation` → 파일 저장)으로 쪽이 나뉘는 PDF 를 만들고, 안 되면 `createPDF`(한 장) 로 폴백.
// 메뉴·저장 패널 액세서리는 ExportUI.swift.

enum ExportFormat: String, Sendable {
    case html, pdf
    var fileExtension: String { rawValue }
    var contentType: UTType { self == .html ? .html : .pdf }
    var label: String { self == .html ? "HTML" : "PDF" }
}

/// 저장 패널 액세서리의 테마 선택
enum ExportTheme: String, CaseIterable, Sendable {
    case current, light, dark
}

struct ExportOptions: Sendable, Equatable {
    var theme: ExportTheme = .current
    /// 코드·메모용 줄 번호 열 (마크다운에는 영향 없음)
    var lineNumbers = false

    static let themeKey = "export.theme"
    static let lineNumbersKey = "export.lineNumbers"

    static func load() -> ExportOptions {
        let d = AppDefaults.store
        var o = ExportOptions()
        if let t = d.string(forKey: themeKey), let th = ExportTheme(rawValue: t) { o.theme = th }
        o.lineNumbers = d.bool(forKey: lineNumbersKey)
        return o
    }
    func save() {
        AppDefaults.store.set(theme.rawValue, forKey: Self.themeKey)
        AppDefaults.store.set(lineNumbers, forKey: Self.lineNumbersKey)
    }
}

/// `export(to:format:options:)` 의 결과 — 셀프테스트·보고용. PDF 는 어느 경로로 만들었는지(`print` 쪽 나뉨 / `createPDF` 한 장) 적는다.
struct ExportOutcome: Sendable {
    var url: URL
    var format: ExportFormat
    var error: String?
    var pdfMethod: String?
    var ms: Double = 0
    var ok: Bool { error == nil }
}

extension AppModel {
    /// 내보내기 입력 텍스트 — 한 곳에서 뽑는다. 비밀 블록 가림이 켜져 있으면 비밀 줄을 가린 텍스트(미리보기와 같은 규칙)를 내보낸다 (secrets)
    func exportSourceText() -> String {
        let text = document.textStorage.string
        return secrets.maskEnabled ? SecretScanner.redacted(text) : text
    }

    /// 액세서리의 테마 선택 → 실제 테마
    func exportTheme(_ choice: ExportTheme) -> Theme {
        switch choice {
        case .current: return themes.current
        case .light: return themes.themes.first { $0.id == ThemeStore.defaultLightID } ?? themes.current
        case .dark: return themes.themes.first { $0.id == ThemeStore.defaultDarkID } ?? themes.current
        }
    }

    /// 현재 문서의 독립 HTML (백그라운드 생성). `baseURL` 은 PDF 용 — 상대 이미지가 문서 폴더 기준으로 풀린다; HTML 파일은 nil(저장 위치 기준).
    func exportHTML(options: ExportOptions, baseURL: URL?) async -> String {
        let text = exportSourceText()
        let url = document.url
        let theme = exportTheme(options.theme)
        let opts = HTMLExporter.Options(lineNumbers: options.lineNumbers, title: url.lastPathComponent, baseURL: baseURL)
        return await Task.detached(priority: .userInitiated) { HTMLExporter.html(for: text, url: url, theme: theme, options: opts) }.value
    }

    /// 메뉴: 저장 패널(기본 이름 = 문서 이름 + 확장자, 기본 폴더 = 문서 폴더, 액세서리 = 테마·줄 번호) → export
    func presentExportPanel(format: ExportFormat) {
        let p = NSSavePanel()
        p.directoryURL = rootDirectory
        p.nameFieldStringValue = document.url.deletingPathExtension().lastPathComponent + "." + format.fileExtension
        p.allowedContentTypes = [format.contentType]
        p.canCreateDirectories = true
        p.isExtensionHidden = false
        p.title = format == .html ? String(localized: "Export as HTML") : String(localized: "Export as PDF")
        let settings = ExportPanelSettings(options: ExportOptions.load())
        let accessory = NSHostingView(rootView: ExportAccessoryView(settings: settings, isMarkdown: HTMLExporter.isMarkdown(document.url)))
        accessory.frame = NSRect(origin: .zero, size: accessory.fittingSize)
        p.accessoryView = accessory
        guard p.runModal() == .OK, let url = p.url else { return }
        let options = settings.options
        options.save()
        Task { @MainActor in _ = await self.export(to: url, format: format, options: options) }
    }

    /// 패널 없이 내보내기 (메뉴·셀프테스트 공용). 완료·실패를 출력 로그와 상태바에 남긴다.
    @discardableResult
    func export(to url: URL, format: ExportFormat, options: ExportOptions) async -> ExportOutcome {
        let start = CFAbsoluteTimeGetCurrent()
        var outcome = ExportOutcome(url: url, format: format)
        let shortPath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        switch format {
        case .html:
            let html = await exportHTML(options: options, baseURL: nil)
            do { try html.write(to: url, atomically: true, encoding: .utf8) }
            catch { outcome.error = error.localizedDescription }
        case .pdf:
            // 미리보기와 같은 기준: 2 MB 초과 문서는 WKWebView 에 올리지 않는다
            let bytes = max(document.fileSize, exportSourceText().utf8.count)
            if bytes > MarkdownPreviewView.maxFileSize {
                outcome.error = String(localized: "PDF export is available for files up to 2 MB")
            } else {
                let folder = document.url.deletingLastPathComponent()
                let html = await exportHTML(options: options, baseURL: folder)
                let renderer = WebPDFRenderer()
                let r = await renderer.render(html: html, baseURL: folder, to: url)
                outcome.error = r.error
                outcome.pdfMethod = r.method
            }
        }
        outcome.ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if let e = outcome.error {
            log(String(localized: "Export failed · \(e)"), isError: true)
        } else {
            // 상태바 상태 칸에 띄운다 — AppModel.bind 가 document.$status 를 출력 로그로도 흘린다
            let message = format == .html ? String(localized: "Exported HTML · \(shortPath)") : String(localized: "Exported PDF · \(shortPath)")
            document.showStatus(message)
        }
        return outcome
    }
}

// MARK: - PDF

/// 화면 밖 WKWebView 로 HTML → PDF. 1순위 인쇄 작업(쪽 나뉨, 용지 Letter/A4, 여백 36 pt, 머리글·바닥글 없음) → 파일 저장;
/// 인쇄가 실패하거나 시간 안에 끝나지 않으면 2순위 `createPDF`(한 장짜리) 로 폴백한다.
@MainActor
final class WebPDFRenderer: NSObject, WKNavigationDelegate {
    struct Result: Sendable { var error: String?; var method: String? }

    static let margin: CGFloat = 36
    /// 지역이 US/CA/MX 면 Letter, 아니면 A4
    static var paperSize: NSSize {
        let region = Locale.current.region?.identifier ?? ""
        return ["US", "CA", "MX"].contains(region) ? NSSize(width: 612, height: 792) : NSSize(width: 595, height: 842)
    }
    /// 인쇄 전체 제한 — 넘기면 createPDF 폴백 (화면 밖 웹뷰의 레이아웃·폰트 로드 포함)
    static let printTimeout: TimeInterval = 20

    private var window: NSWindow?
    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Bool, Never>?
    private var printContinuation: CheckedContinuation<Bool, Never>?
    private var printFinished = false

    func render(html: String, baseURL: URL?, to url: URL) async -> Result {
        let paper = Self.paperSize
        let contentWidth = paper.width - Self.margin * 2
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false   // 내보내기 HTML 에는 스크립트가 없다
        if #available(macOS 13.0, *) { cfg.preferences.shouldPrintBackgrounds = true }   // 테마 배경색을 그대로 찍는다
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: paper.height - Self.margin * 2), configuration: cfg)
        wv.navigationDelegate = self
        // 보이지 않는 창에 붙인다 — WebKit 은 창에 없는 뷰의 레이아웃·인쇄를 미룬다. 화면 밖 위치, 키 창이 되지 않게 orderBack
        let w = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: contentWidth, height: paper.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isExcludedFromWindowsMenu = true
        w.collectionBehavior = [.transient, .ignoresCycle]
        w.contentView = wv
        w.orderBack(nil)
        window = w
        webView = wv
        defer { tearDown() }

        let loaded = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            loadContinuation = c
            wv.loadHTMLString(html, baseURL: baseURL)
        }
        guard loaded else { return Result(error: "page did not load") }
        // 폰트·이미지가 자리 잡을 시간
        try? await Task.sleep(nanoseconds: 300_000_000)

        // 1. 인쇄 작업 → 파일 (쪽 나뉨)
        try? FileManager.default.removeItem(at: url)
        let printed = await runPrint(wv, paper: paper, to: url)
        if printed, Self.isPDF(url) { return Result(method: "print") }
        Perf.log("[export] print operation failed (\(printed ? "no file" : "did not finish")) → createPDF fallback")

        // 2. 폴백: 한 장짜리 PDF
        try? FileManager.default.removeItem(at: url)
        let data: Data? = await withCheckedContinuation { c in
            wv.createPDF { r in
                switch r {
                case .success(let d): c.resume(returning: d)
                case .failure(let e): Perf.log("[export] createPDF failed: \(e)"); c.resume(returning: nil)
                }
            }
        }
        guard let data else { return Result(error: "PDF rendering failed") }
        do { try data.write(to: url, options: .atomic) } catch { return Result(error: error.localizedDescription) }
        return Result(method: "createPDF")
    }

    private func runPrint(_ wv: WKWebView, paper: NSSize, to url: URL) async -> Bool {
        guard let window else { return false }
        let info = NSPrintInfo()
        info.paperSize = paper
        info.topMargin = Self.margin; info.bottomMargin = Self.margin
        info.leftMargin = Self.margin; info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = false
        let op = wv.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = NSRect(origin: .zero, size: paper)   // WebKit: 인쇄 전에 인쇄 뷰 프레임을 잡아 줘야 한다
        printFinished = false
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor [weak self] in
                await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                    guard let self else { c.resume(returning: false); return }
                    self.printContinuation = c
                    op.runModal(for: window, delegate: self, didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
                }
            }
            group.addTask { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.printTimeout * 1_000_000_000))
                guard let self, !self.printFinished else { return false }
                self.finishPrint(false)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @objc private func printOperationDidRun(_ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finishPrint(success)
    }

    private func finishPrint(_ ok: Bool) {
        guard !printFinished else { return }
        printFinished = true
        printContinuation?.resume(returning: ok)
        printContinuation = nil
    }

    static func isPDF(_ url: URL) -> Bool {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { h.closeFile() }
        return h.readData(ofLength: 5) == Data("%PDF-".utf8)
    }

    private func tearDown() {
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // loadHTMLString 의 최초 로드만 허용 (file:// base 또는 about:blank); 나머지 탐색은 취소
        if navigationAction.navigationType == .other, let u = navigationAction.request.url, u.isFileURL || u.absoluteString == "about:blank" {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loadContinuation?.resume(returning: true); loadContinuation = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadContinuation?.resume(returning: false); loadContinuation = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadContinuation?.resume(returning: false); loadContinuation = nil }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loadContinuation?.resume(returning: false); loadContinuation = nil }
}
