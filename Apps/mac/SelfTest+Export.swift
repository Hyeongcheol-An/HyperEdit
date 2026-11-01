import SwiftUI
import AppKit
import PDFKit
import HyperCore

// 셀프테스트: HTML/PDF 내보내기 — 패널 없이 `export(to:format:options:)` 로 임시 폴더에 쓴다.
// 마크다운 → HTML(제목·본문·스크립트 없음·테마 색) → PDF(%PDF 헤더, 긴 문서는 2쪽 이상, 10초 안) → 코드(.py) HTML 의 토큰 span·줄 번호
// → 2 MB 초과 문서의 PDF 거절 안내 → 파일 메뉴 항목. 끝나면 sample.md 를 다시 연다 (뒤 검사가 그 문서를 전제한다).
extension SelfTest {
    @MainActor
    static func runExport(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func read(_ u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "" }
        func lastOutput(_ en: String, _ ko: String) -> Bool { model.output.suffix(6).contains { $0.text.contains(en) || $0.text.contains(ko) } }
        func mark(_ s: String) { Perf.log("[selftest export] " + s) }

        let sampleURL = model.document.url
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-export-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { check(false, "export: cannot create temp dir \(error)"); return }
        log("export dir \(dir.path)")

        // 1. 현재 문서(sample.md, 편집된 상태) → HTML (Hyper Light 고정)
        mark("html")
        let htmlURL = dir.appendingPathComponent("sample.html")
        let r1 = await model.export(to: htmlURL, format: .html, options: ExportOptions(theme: .light, lineNumbers: true))
        // 로그·상태바는 export 직후에 본다 — 아래 check 들이 출력 패널에 PASS 줄을 더하기 때문
        let htmlLogged = lastOutput("Exported HTML", "HTML 내보내기 완료") && model.document.status.contains("sample.html")
        let htmlStatus = model.document.status
        let html = read(htmlURL)
        let light = model.exportTheme(.light)
        check(r1.ok && !html.isEmpty, "export HTML → \(htmlURL.lastPathComponent) written (\(html.utf8.count) B, \(Int(r1.ms)) ms)\(r1.error.map { " · \($0)" } ?? "")")
        check(html.hasPrefix("<!DOCTYPE html>") && html.contains("<h1") && html.contains("HyperEdit self-test sample") && html.contains("NEEDLE first"),
              "HTML has <h1>, the sample heading and body text")
        check(!html.contains("<script") && !html.contains("<link ") && !html.contains("src=\"http"), "HTML has no scripts or external resources")
        check(html.contains("background: \(light.background.hexString)") && html.contains("content=\"light\""), "HTML uses the Hyper Light palette (\(light.background.hexString))")
        check(html.contains("<title>sample.md</title>") && !html.contains("<base "), "HTML has the file name as title and no <base> (relative paths resolve next to the file)")
        check(!html.contains("class=\"line\""), "line-number option is ignored for Markdown")
        check(htmlLogged, "output log + status bar report the export · '\(htmlStatus)'")

        // 2. 긴 마크다운 → PDF: 쪽이 나뉘어야 한다 (2쪽 이상)
        mark("pdf long")
        var longMD = "# Export PDF sample\n\n"
        for i in 1...60 {
            longMD += "## Section \(i)\n\nParagraph \(i): HyperEdit exports the same HTML it previews, so headings, lists and code keep their theme colors. 한글 문단도 섞여 있다 — 줄 바꿈과 쪽 나눔을 확인한다.\n\n- item a \(i)\n- item b with `code` and **bold**\n\n"
            if i % 10 == 0 { longMD += "```swift\nlet value\(i) = \"string\" // comment\nfunc f\(i)() -> Int { return \(i) }\n```\n\n" }
        }
        let longURL = dir.appendingPathComponent("long.md")
        do { try longMD.write(to: longURL, atomically: true, encoding: .utf8) } catch { check(false, "cannot write long.md: \(error)") }
        model.open(url: longURL); await wait(600)
        let pdfURL = dir.appendingPathComponent("long.pdf")
        let r2 = await model.export(to: pdfURL, format: .pdf, options: ExportOptions(theme: .dark))
        let pdfDoc = PDFDocument(url: pdfURL)
        let pages = pdfDoc?.pageCount ?? 0
        let pdfSize = ((try? FileManager.default.attributesOfItem(atPath: pdfURL.path))?[.size] as? Int) ?? 0
        check(r2.ok && WebPDFRenderer.isPDF(pdfURL), "export PDF → \(pdfURL.lastPathComponent) has a %PDF header (\(pdfSize) B, \(Int(r2.ms)) ms, method \(r2.pdfMethod ?? "none"))\(r2.error.map { " · \($0)" } ?? "")")
        check(pages >= 2, "long Markdown PDF is paginated: \(pages) pages (method \(r2.pdfMethod ?? "none"))")
        check(r2.ms < 10_000, "PDF export finished within 10 s (\(Int(r2.ms)) ms)")
        if let p = pdfDoc?.page(at: 0) {
            let box = p.bounds(for: .mediaBox)
            let paper = WebPDFRenderer.paperSize
            check(abs(box.width - paper.width) < 2 && abs(box.height - paper.height) < 2, "PDF page size matches the paper (\(Int(box.width))×\(Int(box.height)) vs \(Int(paper.width))×\(Int(paper.height)))")
            let text = p.string ?? ""
            check(text.contains("Export PDF sample") && text.contains("Section 1"), "PDF page 1 contains the heading text (\(text.count) chars)")
        }
        log("perf export pdf \(Int(r2.ms)) ms · \(pages) pages · \(r2.pdfMethod ?? "none")")

        // 3. 코드 파일(.py) → HTML + 줄 번호: 토큰 span 과 줄 번호 열
        mark("code")
        let py = "import os\n\ndef greet(name):\n    # say hello\n    return f\"hi {name}\"\n\nclass Thing:\n    value = 42\n"
        let pyURL = dir.appendingPathComponent("sample.py")
        do { try py.write(to: pyURL, atomically: true, encoding: .utf8) } catch { check(false, "cannot write sample.py: \(error)") }
        model.open(url: pyURL); await wait(500)
        let pyHTML = dir.appendingPathComponent("sample.py.html")
        let r3 = await model.export(to: pyHTML, format: .html, options: ExportOptions(theme: .current, lineNumbers: true))
        let code = read(pyHTML)
        check(r3.ok && code.contains("<pre class=\"code with-ln\" data-language=\"Python\""), "code HTML uses <pre class=\"code\"> with the Python grammar")
        check(code.contains("<span class=\"tok-keyword\">def</span>") && code.contains("<span class=\"tok-comment\"># say hello</span>") && code.contains("<span class=\"tok-number\">42</span>"),
              "code HTML has keyword / comment / number token spans")
        let lnCount = code.components(separatedBy: "class=\"ln\"").count - 1
        check(lnCount == 8 && code.contains("<span class=\"ln\">8</span>"), "line-number column: \(lnCount) numbered lines")
        check(code.contains(".tok-keyword { color: \(model.themes.current.syntax["keyword"]!.hexString); }"), "token colors come from the current theme's syntax palette")
        check(!code.contains("<script"), "code HTML has no scripts")
        // 같은 코드 파일의 PDF (1쪽 이상)
        let pyPDF = dir.appendingPathComponent("sample.py.pdf")
        let r4 = await model.export(to: pyPDF, format: .pdf, options: ExportOptions(theme: .light, lineNumbers: true))
        let pyPages = PDFDocument(url: pyPDF)?.pageCount ?? 0
        check(r4.ok && pyPages >= 1, "code PDF written: \(pyPages) page(s), \(Int(r4.ms)) ms, method \(r4.pdfMethod ?? "none")")

        // 4. 2 MB 초과 문서: PDF 는 안내만, HTML 은 된다
        mark("big")
        let bigURL = dir.appendingPathComponent("big.txt")
        let chunk = "2026-10-30 14:05 big export line with some words and a URL https://example.com/path · 한글 메모\n"
        let big = String(repeating: chunk, count: 2_100_000 / chunk.utf8.count + 1)
        do { try big.write(to: bigURL, atomically: true, encoding: .utf8) } catch { check(false, "cannot write big.txt: \(error)") }
        model.open(url: bigURL); await wait(1200)
        let r5 = await model.export(to: dir.appendingPathComponent("big.pdf"), format: .pdf, options: ExportOptions())
        // 거절은 출력 패널의 마지막 줄(빨간색) — 출력은 500줄에서 잘리므로 줄 수가 아니라 마지막 줄을 본다
        let lastLine = model.output.last
        let refusalLogged = lastLine?.isError == true && (lastLine!.text.contains("Export failed") || lastLine!.text.contains("내보내기 실패"))
        let addedText = lastLine.map { ($0.isError ? "! " : "") + $0.text } ?? "nil"
        check(!r5.ok && (r5.error ?? "").contains("2 MB") && !FileManager.default.fileExists(atPath: dir.appendingPathComponent("big.pdf").path),
              "PDF export of a \(big.utf8.count / 1_000_000) MB document is refused with a notice · '\(r5.error ?? "")'")
        check(refusalLogged, "refusal is logged as a single error line in the Output panel · \(addedText)")
        let bigHTML = dir.appendingPathComponent("big.html")
        let r6 = await model.export(to: bigHTML, format: .html, options: ExportOptions(theme: .light, lineNumbers: true))
        let bigBytes = ((try? FileManager.default.attributesOfItem(atPath: bigHTML.path))?[.size] as? Int) ?? 0
        check(r6.ok && bigBytes > big.utf8.count, "HTML export of the same document works (\(bigBytes / 1_000_000) MB, \(Int(r6.ms)) ms)")
        log("perf export html 2 MB \(Int(r6.ms)) ms")

        // 5. 파일 메뉴에 두 항목 (영어 또는 한국어 제목)
        mark("menu")
        let titles = (NSApp.mainMenu?.items ?? []).flatMap { $0.submenu?.items ?? [] }.map(\.title)
        let hasHTML = titles.contains { $0.hasPrefix("Export as HTML") || $0.hasPrefix("HTML로 내보내기") }
        let hasPDF = titles.contains { $0.hasPrefix("Export as PDF") || $0.hasPrefix("PDF로 내보내기") }
        check(hasHTML && hasPDF, "File menu has Export as HTML… / Export as PDF… (\(titles.filter { $0.contains("Export") || $0.contains("내보내기") }))")

        // 되돌리기: 샘플 문서로
        model.open(url: sampleURL); await wait(600)
        check(model.document.url.lastPathComponent == "sample.md", "export: sample.md reopened for the remaining checks")
    }
}
