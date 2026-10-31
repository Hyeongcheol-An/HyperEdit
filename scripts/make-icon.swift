#!/usr/bin/env swift
// 앱 아이콘 생성기: 슬레이트 그라디언트 스쿼클 + 흐린 문서 줄 + 굵은 고정폭 "H" + 파란 블록 커서.
// 사용: swift scripts/make-icon.swift  → Apps/mac/Assets.xcassets/AppIcon.appiconset/*.png + Contents.json,
//       build/HyperEdit.iconset (iconutil 용), docs/screenshots/app-icon-1024.png
import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path } ?? ".")
let setDir = root.appendingPathComponent("Apps/mac/Assets.xcassets/AppIcon.appiconset")
let iconsetDir = root.appendingPathComponent("build/HyperEdit.iconset")
try? FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

/// size 픽셀 정사각형에 아이콘을 그린다 (모든 좌표는 1024 기준 → 스케일)
func render(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    ctx.scaleBy(x: s, y: s)
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)

    // Apple macOS 아이콘 템플릿: 1024 캔버스 안 824 스쿼클 + 그림자
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237, cornerHeight: rect.height * 0.2237, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.40))
    ctx.addPath(path); ctx.setFillColor(color(0x141A23)); ctx.fillPath()
    ctx.restoreGState()

    // 배경: 슬레이트 블루 그라디언트 (위 #3A4A66 → 아래 #0F141C)
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let grad = CGGradient(colorsSpace: srgb, colors: [color(0x3A4A66), color(0x222C3D), color(0x0F141C)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: rect.maxY), end: CGPoint(x: 512, y: rect.minY), options: [])
    // 상단 유리 하이라이트
    let hl = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0.12), color(0xFFFFFF, 0.0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 512, y: rect.maxY), end: CGPoint(x: 512, y: rect.maxY - 280), options: [])
    // 흐린 "문서 줄" 장식 (왼쪽 위 2줄 — 글자와 겹치지 않는 높이; 작은 크기에서도 보이도록 30%)
    ctx.setFillColor(color(0xFFFFFF, 0.30))
    for (i, w) in [300, 200].enumerated() {
        let y = rect.maxY - 132 - CGFloat(i) * 40
        ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + 110, y: y, width: CGFloat(w), height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.fillPath()
    }
    // 하단 상태바 선 (악센트)
    ctx.setFillColor(color(0x4C8DFF, 0.45))
    ctx.fill(CGRect(x: rect.minX + 110, y: rect.minY + 112, width: rect.width - 220, height: 8))
    ctx.restoreGState()

    // 테두리 (어두운 Dock 배경에서 윤곽이 살도록 밝은 림)
    ctx.addPath(path); ctx.setStrokeColor(color(0x8A98B4, 0.45)); ctx.setLineWidth(6); ctx.strokePath()

    // "H" (Fira Code Bold, 폴백 Menlo Bold) + 블록 커서
    let fontName = NSFontManager.shared.availableFontFamilies.contains("Fira Code") ? "FiraCode-Bold" : "Menlo-Bold"
    let font = CTFontCreateWithName(fontName as CFString, 470, nil)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(0xF3F6FA)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "H", attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    // 블록 커서: 글자 높이의 절반, 넓게 — 세로로 길면 'I', 너무 낮으면 '.' 으로 읽힌다
    let cursorW: CGFloat = 130, gap: CGFloat = 44
    let totalW = bounds.width + gap + cursorW
    let x = 512 - totalW / 2 - bounds.minX
    let y = 512 - bounds.midY - 16
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: color(0x000000, 0.45))
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0x4C8DFF, 0.65))
    ctx.setFillColor(color(0x4C8DFF, 0.98))
    ctx.fill(CGRect(x: x + bounds.maxX + gap, y: y - 4, width: cursorW, height: bounds.height * 0.50))
    ctx.restoreGState()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

// Xcode 에셋 카탈로그 (macOS 10종)
let entries: [(size: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
var rendered: [Int: Data] = [:]
for e in entries {
    let px = e.size * e.scale
    let data = rendered[px] ?? render(size: px); rendered[px] = data
    let name = "icon_\(e.size)x\(e.size)\(e.scale == 2 ? "@2x" : "").png"
    try! data.write(to: setDir.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(e.scale)x", "size": "\(e.size)x\(e.size)"])
    try! data.write(to: iconsetDir.appendingPathComponent(name))
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: setDir.appendingPathComponent("Contents.json"))
try? FileManager.default.createDirectory(at: root.appendingPathComponent("docs/screenshots"), withIntermediateDirectories: true)
try! render(size: 1024).write(to: root.appendingPathComponent("docs/screenshots/app-icon-1024.png"))
print("wrote \(images.count) icons → \(setDir.path)")
