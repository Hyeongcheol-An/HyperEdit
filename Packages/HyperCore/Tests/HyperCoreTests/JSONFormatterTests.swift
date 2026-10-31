import XCTest
@testable import HyperCore

final class JSONFormatterTests: XCTestCase {
    func testNestedStructuresAndKeyOrder() throws {
        let src = #"{"z":1,"a":{"y":[1,{"b":null,"a":true}],"x":{}},"m":[],"k":"v"}"#
        let out = try JSONFormatter.format(src)
        let expected = """
        {
          "z": 1,
          "a": {
            "y": [
              1,
              {
                "b": null,
                "a": true
              }
            ],
            "x": {}
          },
          "m": [],
          "k": "v"
        }
        """
        XCTAssertEqual(out, expected)
        XCTAssertEqual(try JSONFormatter.minify(out), src)
        XCTAssertEqual(try JSONFormatter.format(src, indent: .tabs), expected.replacingOccurrences(of: "  ", with: "\t"))
        XCTAssertEqual(try JSONFormatter.format(src, indent: .spaces(4)), expected.replacingOccurrences(of: "  ", with: "    "))
    }

    func testNumbersPreservedAsWritten() throws {
        let src = #"[1e10, -0.5, 12345678901234567890, 1.0, 0, -0, 2.50E+3, 1E-7]"#
        XCTAssertEqual(try JSONFormatter.minify(src), "[1e10,-0.5,12345678901234567890,1.0,0,-0,2.50E+3,1E-7]")
    }

    func testUnicodeStringsKeptAsIs() throws {
        let src = #"{"한글":"안녕하세요 🙂","emoji":"👩‍💻","mixed":"a\#("\\u")00e9b"}"#
        let out = try JSONFormatter.minify(src)
        XCTAssertEqual(out, #"{"한글":"안녕하세요 🙂","emoji":"👩‍💻","mixed":"aéb"}"#, "\\u 이스케이프는 글자로, 비ASCII 는 그대로")
    }

    func testEscapesAreSemanticallyPreserved() throws {
        // `\uXXXX` 시퀀스는 조각으로 조립한다 (편집 도구가 이스케이프를 글자로 바꿔 버리는 것을 막기 위해)
        let u = "\\u"
        let src = #"["a\"b\\c\/d\n\t\r\b\f","\#(u)0001x\#(u)001f","\#(u)d83d\#(u)de00","\#(u)dc00 lone","\#(u)0022\#(u)005c"]"#
        let out = try JSONFormatter.minify(src)
        XCTAssertEqual(out, #"["a\"b\\c/d\n\t\r\b\f","\#(u)0001x\#(u)001f","😀","\#(u)dc00 lone","\"\\"]"#)
        XCTAssertEqual(try JSONFormatter.minify(out), out, "다시 돌려도 안정")
        XCTAssertEqual(JSONFormatter.quote("a\"\n\tb\\한"), #""a\"\n\tb\\한""#)
    }

    func testLenientInputTrailingCommasCommentsBOM() throws {
        let src = "\u{FEFF}// comment\n{\n  \"a\": [1, 2, /* inline */ 3,],\n  \"b\": true, // trailing\n}\n"
        XCTAssertEqual(try JSONFormatter.minify(src), "{\"a\":[1,2,3],\"b\":true}\n", "출력은 엄격한 JSON, 끝 개행은 유지")
        XCTAssertEqual(try JSONFormatter.format("{}"), "{}")
        XCTAssertEqual(try JSONFormatter.format("[]\n"), "[]\n")
        XCTAssertEqual(try JSONFormatter.format(" 42 "), "42")
    }

    func testErrorPositions() {
        func err(_ s: String) -> JSONFormatter.SyntaxError? {
            do { _ = try JSONFormatter.format(s); return nil } catch let e as JSONFormatter.SyntaxError { return e } catch { return nil }
        }
        let e1 = err("{\n  \"a\": 1\n  \"b\": 2\n}")
        XCTAssertEqual(e1?.line, 3); XCTAssertEqual(e1?.column, 3)      // 쉼표 빠진 자리: 3번째 줄 "b" 앞
        XCTAssertEqual(e1?.message, "Expected ',' or '}' in object")
        let e2 = err("{\"a\": [1, 2}")
        XCTAssertEqual(e2?.line, 1); XCTAssertEqual(e2?.column, 12)     // `}` 가 `]` 자리에
        let e3 = err("{\"한글\": tru}")
        XCTAssertEqual(e3?.line, 1); XCTAssertEqual(e3?.column, 8, "열은 UTF-16 단위 — 한글 2글자 = 2열")
        XCTAssertEqual(e3?.offset, 7)
        XCTAssertEqual(e3?.message, "Unexpected 'tru'")
        let e4 = err("")
        XCTAssertEqual(e4?.message, "Unexpected end of input")
        let e5 = err("{\"a\": \"open\n}")
        XCTAssertEqual(e5?.message, "Unterminated string"); XCTAssertEqual(e5?.column, 7)
        XCTAssertEqual(err("[1] x")?.message, "Unexpected character after JSON value")
        XCTAssertEqual(err("{'a':1}")?.message, "Single quotes are not allowed in JSON — use double quotes")
        XCTAssertEqual(err("[01]")?.message, "Leading zeros are not allowed")
    }

    func testMinifyOfFormatEqualsMinify() throws {
        let src = #"  { "a" : [ 1 , 2.0 , { "b" : "cé" } ] , "d" : null , "e" : "한글" }  "#
        XCTAssertEqual(try JSONFormatter.minify(try JSONFormatter.format(src)), try JSONFormatter.minify(src))
    }

    /// 5 MB(릴리스) / 1 MB(디버그) 문서 정리 시간. 릴리스 1초 · 디버그 2초 이내.
    func testPerformanceLargeDocument() throws {
        #if DEBUG
        let count = 8_000, limit = 2.0
        #else
        let count = 40_000, limit = 1.0
        #endif
        var s = "["
        for i in 0..<count {
            if i > 0 { s += "," }
            s += #"{"id":\#(i),"name":"item \#(i) 한글 이름","tags":["a","b","c"],"score":\#(Double(i) / 7),"nested":{"ok":true,"none":null,"note":"line\nbreak"}}"#
        }
        s += "]"
        let bytes = s.utf8.count
        let t = CFAbsoluteTimeGetCurrent()
        let out = try JSONFormatter.format(s)
        let elapsed = CFAbsoluteTimeGetCurrent() - t
        print(String(format: "JSONFormatter.format %.2f MB in %.0f ms", Double(bytes) / 1_048_576, elapsed * 1000))
        XCTAssertLessThan(elapsed, limit)
        XCTAssertEqual(try JSONFormatter.minify(out), s)
    }
}
