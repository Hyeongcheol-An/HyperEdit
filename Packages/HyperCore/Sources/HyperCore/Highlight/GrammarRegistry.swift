import Foundation

/// 파일 확장자 → 문법. 모르는 확장자와 확장자 없는 파일은 메모 문법(Notes).
public enum GrammarRegistry {
    public static func grammar(for url: URL) -> any LanguageGrammar {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            // 확장자 없는 잘 알려진 파일
            switch url.lastPathComponent.lowercased() {
            case "dockerfile", "makefile", "gnumakefile", ".bashrc", ".zshrc", ".bash_profile", ".zprofile", ".profile": return CodeGrammar(language: .shell)
            case ".gitconfig", ".editorconfig": return CodeGrammar(language: .ini)
            default: return PlainNotesGrammar(markdown: false)
            }
        }
        return grammar(forExtension: ext)
    }

    public static func grammar(forExtension ext: String) -> any LanguageGrammar {
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

    /// 상태바 표시용 이름 ("Notes", "Markdown", "Python" …)
    public static func languageName(for url: URL) -> String { grammar(for: url).name }
}
