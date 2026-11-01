import Foundation

/// 파일 확장자 → 문법. 사용자 정의 문법(`UserGrammarStore`)이 먼저이고(내장 덮어쓰기 가능) 없으면 내장. 모르는 확장자와 확장자 없는 파일은 메모 문법(Notes).
public enum GrammarRegistry {
    public static func grammar(for url: URL, userGrammars store: UserGrammarStore = .shared) -> any LanguageGrammar {
        if let g = store.grammar(for: url) { return g }
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            // 확장자 없는 잘 알려진 파일
            switch url.lastPathComponent.lowercased() {
            case "dockerfile", "makefile", "gnumakefile", ".bashrc", ".zshrc", ".bash_profile", ".zprofile", ".profile": return CodeGrammar(language: .shell)
            case ".gitconfig", ".editorconfig": return CodeGrammar(language: .ini)
            default: return PlainNotesGrammar(markdown: false)
            }
        }
        return builtinGrammar(forExtension: ext)
    }

    public static func grammar(forExtension ext: String, userGrammars store: UserGrammarStore = .shared) -> any LanguageGrammar {
        if let g = store.grammar(forExtension: ext) { return g }
        return builtinGrammar(forExtension: ext)
    }

    /// 내장 문법만 (사용자 문법 무시)
    public static func builtinGrammar(forExtension ext: String) -> any LanguageGrammar {
        switch ext.lowercased() {
        case "md", "markdown", "mdown", "mkd": return PlainNotesGrammar(markdown: true)
        case "swift": return CodeGrammar(language: .swift)
        case "py", "pyi", "pyw": return CodeGrammar(language: .python)
        case "js", "mjs", "cjs", "jsx": return CodeGrammar(language: .javascript)
        case "ts", "tsx", "mts", "cts": return CodeGrammar(language: .typescript)
        case "json", "jsonc", "json5": return CodeGrammar(language: .json)
        case "sh", "bash", "zsh", "fish", "ksh": return CodeGrammar(language: .shell)
        case "yaml", "yml": return CodeGrammar(language: .yaml)
        case "html", "htm", "xhtml", "vue", "svelte": return CodeGrammar(language: .html)
        case "xml", "svg", "plist", "xib", "storyboard", "xsl", "xsd", "rss", "atom", "xcscheme", "entitlements": return CodeGrammar(language: .xml)
        case "css", "scss", "less": return CodeGrammar(language: .css)
        case "c", "h": return CodeGrammar(language: .c)
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx", "c++", "h++": return CodeGrammar(language: .cpp)
        case "m", "mm": return CodeGrammar(language: .objc)
        case "go": return CodeGrammar(language: .go)
        case "rs": return CodeGrammar(language: .rust)
        case "sql", "psql", "mysql": return CodeGrammar(language: .sql)
        case "rb", "rake", "gemspec": return CodeGrammar(language: .ruby)
        case "java": return CodeGrammar(language: .java)
        case "kt", "kts": return CodeGrammar(language: .kotlin)
        case "toml": return CodeGrammar(language: .toml)
        case "ini", "conf", "cfg", "properties", "env", "gitconfig", "editorconfig": return CodeGrammar(language: .ini)
        default: return PlainNotesGrammar(markdown: false)
        }
    }

    /// 마크다운 펜스의 정보 문자열(```swift, ```python …) → 코드 문법. 사용자 문법은 이름·확장자로 먼저 찾고, 그다음 흔한 별칭·확장자. 모르면 nil.
    public static func grammar(forFenceLanguage language: String, userGrammars store: UserGrammarStore = .shared) -> CodeGrammar? {
        let key = language.lowercased()
        if let g = store.grammar(forFenceLanguage: key) { return g }
        let ext: String
        switch key {
        case "python", "python3", "py3": ext = "py"
        case "javascript", "node": ext = "js"
        case "typescript": ext = "ts"
        case "shell", "bash", "zsh", "sh", "console", "shellsession", "fish", "dockerfile", "makefile": ext = "sh"
        case "rust": ext = "rs"
        case "golang": ext = "go"
        case "c++", "cxx", "cc": ext = "cpp"
        case "objective-c", "objc", "objectivec": ext = "m"
        case "kotlin": ext = "kt"
        case "ruby": ext = "rb"
        case "yml": ext = "yaml"
        case "jsonc", "json5": ext = "json"
        case "scss", "less": ext = "css"
        case "objective-cpp", "objc++", "mm": ext = "mm"
        case "swift", "py", "js", "jsx", "ts", "tsx", "json", "yaml", "html", "htm", "xml", "svg", "plist", "vue", "css", "c", "h", "cpp", "hpp", "m", "go", "rs",
             "sql", "rb", "java", "kt", "toml", "ini", "conf", "properties", "env": ext = key
        default: return nil
        }
        return builtinGrammar(forExtension: ext) as? CodeGrammar
    }

    /// 상태바 표시용 이름 ("Notes", "Markdown", "Python" …)
    public static func languageName(for url: URL, userGrammars store: UserGrammarStore = .shared) -> String { grammar(for: url, userGrammars: store).name }
}
