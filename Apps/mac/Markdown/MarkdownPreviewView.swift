import SwiftUI
import AppKit
import WebKit
import Combine
import HyperCore

/// 마크다운 분할 미리보기 (편집기 오른쪽). WKWebView 에 `MarkdownHTML.html` 을 올린다.
/// - 다시 렌더: 편집(`document.$lineIndex`) 300 ms 디바운스 · 테마 변경·파일 전환은 즉시. 스크롤 위치는 다시 렌더해도 유지.
/// - 스크롤 동기화(편집기 → 미리보기): `EditorCaret.firstVisibleLine` 이 바뀌면 `window.scrollToLine(n)`.
/// - 2 MB 초과 파일은 렌더하지 않고 안내 문구만 보여 준다.
/// - 링크는 기본 브라우저로 열고(WKWebView 안에서 탐색하지 않음), 최초 `loadHTMLString` 외의 탐색은 모두 취소한다.
struct MarkdownPreviewView: NSViewRepresentable {
    static let maxFileSize = 2_000_000

    let document: MemoDocument
    let caret: EditorCaret
    let theme: Theme

    func makeCoordinator() -> Coordinator { Coordinator(document: document, caret: caret) }

    func makeNSView(context: Context) -> MarkdownPreviewContainer {
        let c = context.coordinator
        let container = MarkdownPreviewContainer(webView: c.makeWebView(), placeholder: c.placeholder)
        c.container = container
        c.apply(theme: theme)
        c.render(reason: .initial)
        return container
    }

    func updateNSView(_ container: MarkdownPreviewContainer, context: Context) {
        context.coordinator.apply(theme: theme)
    }

    static func dismantleNSView(_ container: MarkdownPreviewContainer, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    enum RenderReason { case initial, edit, theme, file }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let document: MemoDocument
        let caret: EditorCaret
        weak var container: MarkdownPreviewContainer?
        private(set) var webView: WKWebView?
        let placeholder = NSTextField(labelWithString: "")

        private var theme: Theme?
        private var cancellables = Set<AnyCancellable>()
        private var renderTask: Task<Void, Never>?
        private var generation = 0
        private var loadedGeneration = -1
        private var pageReady = false
        private var pendingScrollY: Double?
        private var pendingLine: Int?
        private var renderedURL: URL?
        /// `--debug-preview-log <path>`: 렌더·탐색·로드 결과를 파일에 덧붙인다 (스크린샷 자동화 진단용, 개발 전용)
        private static let debugLogPath = LaunchOptions.value("--debug-preview-log")
        private func dlog(_ s: String) {
            guard let path = Self.debugLogPath else { return }
            let line = String(format: "[%.3f] ", Date().timeIntervalSince1970) + s + "\n"
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
            else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
        }

        init(document: MemoDocument, caret: EditorCaret) {
            self.document = document
            self.caret = caret
            super.init()
            placeholder.stringValue = String(localized: "Preview is available for files up to 2 MB")
            placeholder.alignment = .center
            placeholder.font = .systemFont(ofSize: 13)
            placeholder.lineBreakMode = .byWordWrapping
            placeholder.maximumNumberOfLines = 3
            placeholder.isHidden = true
            bind()
        }

        func makeWebView() -> WKWebView {
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .nonPersistent()
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
            cfg.userContentController.add(WeakScriptMessageHandler(self), name: "link")
            let wv = WKWebView(frame: .zero, configuration: cfg)
            wv.navigationDelegate = self
            wv.allowsBackForwardNavigationGestures = false
            wv.allowsMagnification = true
            webView = wv
            return wv
        }

        private func bind() {
            // 편집: 줄 인덱스가 바뀌면(편집 250 ms 뒤 재계산) 300 ms 디바운스로 다시 렌더
            document.$lineIndex
                .dropFirst()
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .sink { [weak self] _ in self?.render(reason: .edit) }
                .store(in: &cancellables)
            // 파일 전환·디스크 재로드: 즉시
            document.$reloadGeneration
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.render(reason: self.renderedURL == self.document.url ? .edit : .file)
                }
                .store(in: &cancellables)
            // 편집기 스크롤 → 미리보기
            caret.$firstVisibleLine
                .removeDuplicates()
                .sink { [weak self] line in self?.sync(toLine: line) }
                .store(in: &cancellables)
        }

        func tearDown() {
            cancellables.removeAll()
            renderTask?.cancel()
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "link")
            webView?.navigationDelegate = nil
        }

        // MARK: 테마

        func apply(theme newTheme: Theme) {
            guard theme?.id != newTheme.id else { return }
            let first = theme == nil
            theme = newTheme
            container?.apply(theme: newTheme)
            placeholder.textColor = newTheme.foregroundMuted.nsColor
            if !first { render(reason: .theme) }
        }

        // MARK: 렌더

        func render(reason: RenderReason) {
            dlog("render \(reason) size=\(document.fileSize) loaded=\(document.isLoaded) frame=\(webView?.frame ?? .zero) window=\(webView?.window != nil)")
            guard let theme, let wv = webView else { return }
            if document.fileSize > MarkdownPreviewView.maxFileSize || !document.isLoaded {
                renderTask?.cancel()
                container?.showPlaceholder(true)
                return
            }
            container?.showPlaceholder(false)
            let text = document.textStorage.string
            let folder = document.url.deletingLastPathComponent()
            let fileChanged = renderedURL != document.url
            renderedURL = document.url
            generation += 1
            let gen = generation
            renderTask?.cancel()
            renderTask = Task { [weak self] in
                // 파싱·HTML 생성은 백그라운드 (2 MB 문서도 메인 스레드를 막지 않도록)
                let html = await Task.detached(priority: .userInitiated) { MarkdownHTML.html(for: text, theme: theme, baseURL: folder) }.value
                guard let self, !Task.isCancelled, gen == self.generation else { return }
                if fileChanged || reason == .file || reason == .initial {
                    // 다른 파일: 이전 스크롤 위치는 의미가 없다 → 로드 뒤 편집기의 첫 줄로 맞춘다
                    self.pendingScrollY = nil
                    self.pendingLine = self.caret.firstVisibleLine
                    self.load(html, in: wv, baseURL: folder, generation: gen)
                } else {
                    // 같은 문서 다시 렌더: 스크롤 위치 보존
                    wv.evaluateJavaScript("window.scrollY") { [weak self] y, _ in
                        guard let self, gen == self.generation else { return }
                        self.pendingScrollY = (y as? NSNumber)?.doubleValue ?? 0
                        self.pendingLine = nil
                        self.load(html, in: wv, baseURL: folder, generation: gen)
                    }
                }
            }
        }

        private func load(_ html: String, in wv: WKWebView, baseURL: URL, generation gen: Int) {
            pageReady = false
            loadedGeneration = gen
            dlog("load gen=\(gen) html=\(html.utf8.count)B base=\(baseURL.absoluteString)")
            wv.loadHTMLString(html, baseURL: baseURL)
        }

        // MARK: 스크롤 동기화

        private func sync(toLine line: Int) {
            guard pageReady, let wv = webView else { pendingLine = line; return }
            wv.evaluateJavaScript("window.scrollToLine(\(line))", completionHandler: nil)
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 허용: loadHTMLString 의 최초 로드 (요청 URL = baseURL, 사용자 동작 아님). 그 외 모든 탐색은 취소하고 외부 링크면 기본 브라우저로.
            let url = navigationAction.request.url
            if navigationAction.navigationType == .other, let u = url, u.isFileURL || u.absoluteString == "about:blank" {
                dlog("navigation allow \(u.absoluteString)")
                decisionHandler(.allow)
                return
            }
            dlog("navigation cancel type=\(navigationAction.navigationType.rawValue) \(url?.absoluteString ?? "nil")")
            if let u = url { Self.openExternally(u) }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            if Self.debugLogPath != nil {
                dlog("didFinish frame=\(webView.frame) hidden=\(webView.isHidden) window=\(webView.window != nil) container=\(container?.frame ?? .zero)")
                webView.evaluateJavaScript("JSON.stringify([document.body.innerText.length, document.documentElement.scrollHeight, window.innerWidth, window.innerHeight, getComputedStyle(document.body).backgroundColor])") { [weak self] r, e in
                    self?.dlog("page \(r.map { "\($0)" } ?? "nil") err=\(e.map { "\($0)" } ?? "none")")
                }
            }
            if let y = pendingScrollY {
                pendingScrollY = nil
                webView.evaluateJavaScript("window.scrollTo(0, \(y))", completionHandler: nil)
            } else if let line = pendingLine {
                pendingLine = nil
                webView.evaluateJavaScript("window.scrollToLine(\(line))", completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { pageReady = true; dlog("didFail \(error)") }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { pageReady = true; dlog("didFailProvisional \(error)") }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { dlog("web content process terminated"); render(reason: .file) }

        // MARK: WKScriptMessageHandler — 링크 클릭

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "link", let s = message.body as? String, let u = URL(string: s) else { return }
            Self.openExternally(u)
        }

        /// http / https / mailto 만 기본 앱으로 연다
        static func openExternally(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

/// WKUserContentController 는 핸들러를 강하게 잡는다 → 약한 대리자로 순환 참조를 끊는다
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// [웹뷰 | 안내 문구] 를 담는 컨테이너. 왼쪽 경계선과 테마 배경을 그린다.
final class MarkdownPreviewContainer: NSView {
    let webView: WKWebView
    let placeholder: NSTextField
    private var borderColor = NSColor.separatorColor

    init(webView: WKWebView, placeholder: NSTextField) {
        self.webView = webView
        self.placeholder = placeholder
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(webView)
        addSubview(placeholder)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func apply(theme: Theme) {
        layer?.backgroundColor = theme.background.nsColor.cgColor
        webView.underPageBackgroundColor = theme.background.nsColor
        borderColor = theme.border.nsColor
        needsDisplay = true
    }

    func showPlaceholder(_ on: Bool) {
        placeholder.isHidden = !on
        webView.isHidden = on
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        webView.frame = NSRect(x: 1, y: 0, width: max(0, bounds.width - 1), height: bounds.height)
        let w = min(320, max(0, bounds.width - 40))
        let size = placeholder.sizeThatFits(NSSize(width: w, height: 200))
        placeholder.frame = NSRect(x: (bounds.width - w) / 2, y: (bounds.height - size.height) / 2, width: w, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        borderColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }
}
