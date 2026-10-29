import Foundation

/// The built-in language catalog.
public enum Languages {
    public static let plainText = Language(id: "text", name: "Plain Text", extensions: ["txt"], strings: [], capitalizedTypes: false, highlightNumbers: false)

    private static let cKeywords = """
        auto break case char const continue default do double else enum extern float for goto if inline int long \
        register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while \
        bool true false NULL _Bool size_t
        """
    private static let jsKeywords = """
        break case catch class const continue debugger default delete do else export extends finally for function if \
        import in instanceof let new return super switch this throw try typeof var void while with yield async await \
        of static get set null undefined true false NaN Infinity
        """
    private static let preprocessor: (pattern: String, kind: TokenKind) = (#"^[ \t]*#[ \t]*\w+"#, .attribute)
    private static let atAttribute: (pattern: String, kind: TokenKind) = (#"@[A-Za-z_][\w.]*"#, .attribute)

    public static let all: [Language] = [
        Language(
            id: "swift", name: "Swift", extensions: ["swift"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"\"\"", "\""],
            keywords: """
                associatedtype class deinit enum extension fileprivate func import init inout internal let open operator \
                private precedencegroup protocol public rethrows static struct subscript typealias var break case catch \
                continue default defer do else fallthrough for guard if in repeat return throw switch where while as \
                false is nil self Self super throws true try async await actor some any convenience dynamic final lazy \
                mutating nonmutating optional override required unowned weak willSet didSet get set package consume \
                borrowing consuming nonisolated isolated macro
                """,
            patterns: [atAttribute, (#"#[A-Za-z_]\w*"#, .attribute)],
            runCommand: "swift {file}", installHint: "Install Xcode or the Swift toolchain from swift.org."
        ),
        Language(
            id: "python", name: "Python", extensions: ["py", "pyw"],
            lineComments: ["#"], strings: ["\"\"\"", "'''", "\"", "'"],
            keywords: """
                False None True and as assert async await break class continue def del elif else except finally for \
                from global if import in is lambda nonlocal not or pass raise return try while with yield match case self
                """,
            types: "int str float bool list dict set tuple bytes object type len range print open isinstance super Exception",
            patterns: [atAttribute], indentAfterColon: true,
            runCommand: "python3 -u {file}", installHint: "Install Python with `brew install python` or from python.org."
        ),
        Language(
            id: "javascript", name: "JavaScript", extensions: ["js", "mjs", "cjs", "jsx"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["`", "\"", "'"],
            keywords: jsKeywords,
            runCommand: "node {file}", installHint: "Install Node.js with `brew install node` or from nodejs.org."
        ),
        Language(
            id: "typescript", name: "TypeScript", extensions: ["ts", "tsx", "mts", "cts"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["`", "\"", "'"],
            keywords: jsKeywords + """
                 interface type enum implements namespace declare abstract readonly private protected public keyof \
                infer is as satisfies any unknown never string number boolean symbol bigint object
                """,
            patterns: [atAttribute],
            runCommand: "npx --yes tsx {file}", installHint: "Install Node.js with `brew install node` (tsx is fetched by npx)."
        ),
        Language(
            id: "c", name: "C", extensions: ["c", "h"],
            lineComments: ["//"], blockComment: ("/*", "*/"),
            keywords: cKeywords, capitalizedTypes: false, patterns: [preprocessor],
            runCommand: "clang -std=c17 -Wall {file} -o {out} && {out}", installHint: "Run `xcode-select --install`."
        ),
        Language(
            id: "cpp", name: "C++", extensions: ["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "ipp"],
            lineComments: ["//"], blockComment: ("/*", "*/"),
            keywords: cKeywords + """
                 alignas alignof and asm catch class constexpr consteval constinit co_await co_return co_yield decltype \
                delete explicit export friend mutable namespace new noexcept nullptr operator or private protected public \
                reinterpret_cast static_assert static_cast dynamic_cast const_cast template this thread_local throw try \
                typeid typename using virtual wchar_t override final concept requires
                """,
            types: "std string vector map set unordered_map array optional unique_ptr shared_ptr",
            capitalizedTypes: false, patterns: [preprocessor],
            runCommand: "clang++ -std=c++20 -Wall {file} -o {out} && {out}", installHint: "Run `xcode-select --install`."
        ),
        Language(
            id: "objc", name: "Objective-C", extensions: ["m", "mm"],
            lineComments: ["//"], blockComment: ("/*", "*/"),
            keywords: cKeywords + " self super nil Nil YES NO id instancetype nonatomic strong weak copy assign readonly readwrite",
            patterns: [preprocessor, (#"@[A-Za-z_]\w*"#, .keyword)],
            runCommand: "clang -fobjc-arc -framework Foundation {file} -o {out} && {out}", installHint: "Run `xcode-select --install`."
        ),
        Language(
            id: "java", name: "Java", extensions: ["java"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"\"\"", "\"", "'"],
            keywords: """
                abstract assert boolean break byte case catch char class const continue default do double else enum \
                extends final finally float for goto if implements import instanceof int interface long native new package \
                private protected public return short static strictfp super switch synchronized this throw throws \
                transient try void volatile while var record sealed permits yield true false null
                """,
            patterns: [atAttribute],
            runCommand: "java {file}", installHint: "Install a JDK with `brew install openjdk`."
        ),
        Language(
            id: "kotlin", name: "Kotlin", extensions: ["kt", "kts"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"\"\"", "\"", "'"],
            keywords: """
                as break class continue do else false for fun if in interface is null object package return super this \
                throw true try typealias val var when while by catch constructor finally get import init set where \
                abstract annotation companion const crossinline data enum external final infix inline inner internal \
                lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg
                """,
            patterns: [atAttribute],
            runCommand: "kotlinc {file} -include-runtime -d {out}.jar && java -jar {out}.jar", installHint: "Install Kotlin with `brew install kotlin`."
        ),
        Language(
            id: "csharp", name: "C#", extensions: ["cs"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\"\"\"", "\"", "'"],
            keywords: """
                abstract as base bool break byte case catch char checked class const continue decimal default delegate do \
                double else enum event explicit extern false finally fixed float for foreach goto if implicit in int \
                interface internal is lock long namespace new null object operator out override params private protected \
                public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw \
                true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while async await get \
                set init record yield
                """,
            patterns: [preprocessor],
            runCommand: "dotnet run {file}", installHint: "Install the .NET SDK with `brew install --cask dotnet-sdk`."
        ),
        Language(
            id: "go", name: "Go", extensions: ["go"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["`", "\"", "'"],
            keywords: """
                break case chan const continue default defer else fallthrough for func go goto if import interface map \
                package range return select struct switch type var true false nil iota
                """,
            types: "string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 bool byte rune error any",
            capitalizedTypes: false, indentWithTabs: true,
            runCommand: "go run {file}", installHint: "Install Go with `brew install go`."
        ),
        Language(
            id: "rust", name: "Rust", extensions: ["rs"],
            lineComments: ["//"], blockComment: ("/*", "*/"), strings: ["\""],
            keywords: """
                as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod \
                move mut pub ref return self Self static struct super trait true type unsafe use where while
                """,
            types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str",
            patterns: [(#"#!?\[[^\]\n]*\]"#, .attribute), (#"\b[a-z_]\w*!"#, .function)],
            runCommand: "rustc {file} -o {out} && {out}", installHint: "Install Rust with `brew install rust` or from rustup.rs."
        ),
        Language(
            id: "ruby", name: "Ruby", extensions: ["rb", "rake", "gemspec"], fileNames: ["Gemfile", "Rakefile"],
            lineComments: ["#"], blockComment: ("=begin", "=end"),
            keywords: """
                BEGIN END alias and begin break case class def defined do else elsif end ensure false for if in module \
                next nil not or redo rescue retry return self super then true undef unless until when while yield \
                require require_relative puts attr_accessor attr_reader attr_writer
                """,
            patterns: [(#"(?<![\w:]):[A-Za-z_]\w*"#, .string), (#"@{1,2}\w+"#, .attribute)],
            runCommand: "ruby {file}", installHint: "Install Ruby with `brew install ruby`."
        ),
        Language(
            id: "php", name: "PHP", extensions: ["php"],
            lineComments: ["//", "#"], blockComment: ("/*", "*/"),
            keywords: """
                abstract and array as break callable case catch class clone const continue declare default do echo else \
                elseif empty extends final finally fn for foreach function global goto if implements include include_once \
                instanceof interface isset list match namespace new or print private protected public readonly require \
                require_once return static switch throw trait try unset use var while xor yield true false null
                """,
            patterns: [(#"\$\w+"#, .attribute), (#"<\?php|\?>"#, .tag)],
            runCommand: "php {file}", installHint: "Install PHP with `brew install php`."
        ),
        Language(
            id: "shell", name: "Shell", extensions: ["sh", "bash", "zsh", "command"], fileNames: [".zshrc", ".bashrc", ".zprofile", ".bash_profile"],
            lineComments: ["#"],
            keywords: """
                if then else elif fi case esac for while until do done in function select time return exit break continue \
                local export readonly declare unset shift source alias echo printf read cd test true false set
                """,
            capitalizedTypes: false,
            patterns: [(#"\$\{[^}\n]*\}|\$[\w@#?*!$-]"#, .attribute)],
            runCommand: "/bin/zsh {file}"
        ),
        Language(
            id: "lua", name: "Lua", extensions: ["lua"],
            lineComments: ["--"], blockComment: ("--[[", "]]"),
            keywords: "and break do else elseif end false for function goto if in local nil not or repeat return then true until while",
            capitalizedTypes: false,
            runCommand: "lua {file}", installHint: "Install Lua with `brew install lua`."
        ),
        Language(
            id: "sql", name: "SQL", extensions: ["sql"],
            lineComments: ["--"], blockComment: ("/*", "*/"),
            keywords: """
                select from where insert into values update set delete create table drop alter add column index primary \
                key foreign references not null unique default and or in is like between join left right inner outer full \
                on as group by order having limit offset distinct union all exists case when then else end count sum avg \
                min max view database if begin commit rollback transaction int integer varchar text date boolean real float
                """,
            caseInsensitiveKeywords: true, capitalizedTypes: false,
            runCommand: "sqlite3 -box < {file}"
        ),
        Language(
            id: "html", name: "HTML / XML", extensions: ["html", "htm", "xhtml", "xml", "svg", "plist", "vue"],
            blockComment: ("<!--", "-->"), capitalizedTypes: false, highlightNumbers: false,
            patterns: [(#"</?[A-Za-z][\w:.-]*|/?>"#, .tag), (#"\b[\w:-]+(?==)"#, .attribute), (#"&#?\w+;"#, .number)],
            runCommand: "open {file}"
        ),
        Language(
            id: "css", name: "CSS", extensions: ["css", "scss", "less"],
            lineComments: [], blockComment: ("/*", "*/"), capitalizedTypes: false,
            patterns: [(#"#[0-9a-fA-F]{3,8}\b"#, .number), (#"@[\w-]+"#, .keyword), (#"[\w-]+(?=\s*:[^:])"#, .attribute), (#"[.#][A-Za-z_-][\w-]*"#, .type)]
        ),
        Language(
            id: "json", name: "JSON", extensions: ["json", "jsonc", "geojson"],
            lineComments: ["//"], strings: ["\""], keywords: "true false null", capitalizedTypes: false,
            patterns: [(#""(?:\\.|[^"\\\n])*"(?=\s*:)"#, .attribute)]
        ),
        Language(
            id: "yaml", name: "YAML", extensions: ["yml", "yaml"],
            lineComments: ["#"], keywords: "true false null yes no on off", capitalizedTypes: false,
            patterns: [(#"^[ \t-]*[\w.\-/]+(?=[ \t]*:)"#, .attribute), (#"^---|^\.\.\."#, .keyword)],
            indentAfterColon: true
        ),
        Language(
            id: "toml", name: "TOML", extensions: ["toml", "ini", "cfg", "conf"],
            lineComments: ["#", ";"], strings: ["\"\"\"", "\"", "'"], keywords: "true false", capitalizedTypes: false,
            patterns: [(#"^[ \t]*\[[^\]\n]*\]"#, .heading), (#"^[ \t]*[\w.-]+(?=[ \t]*=)"#, .attribute)]
        ),
        Language(
            id: "markdown", name: "Markdown", extensions: ["md", "markdown"],
            strings: [], capitalizedTypes: false, highlightNumbers: false,
            patterns: [
                ("```[\\s\\S]*?(?:```|\\z)", .string), (#"`[^`\n]+`"#, .string), (#"^#{1,6}[ \t].*"#, .heading),
                (#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, .keyword), (#"\[[^\]\n]*\]\([^)\n]*\)"#, .attribute),
                (#"^[ \t]*(?:[-*+]|\d+\.)[ \t]"#, .number), (#"^>.*"#, .comment),
            ],
            runCommand: "open {file}"
        ),
        Language(
            id: "makefile", name: "Makefile", extensions: ["mk", "make"], fileNames: ["Makefile", "makefile", "GNUmakefile"],
            lineComments: ["#"], keywords: "ifeq ifneq ifdef ifndef else endif include define endef export override", capitalizedTypes: false,
            patterns: [(#"^[\w.%/ -]+(?=:(?!=))"#, .function), (#"\$\([^)\n]*\)|\$[@<^*?]"#, .attribute)],
            indentWithTabs: true,
            runCommand: "make -f {file}"
        ),
        Language(
            id: "diff", name: "Diff", extensions: ["diff", "patch"],
            strings: [], capitalizedTypes: false, highlightNumbers: false,
            patterns: [
                (#"^(?:diff --git|index |---|\+\+\+).*"#, .comment), (#"^@@[^\n]*"#, .attribute),
                (#"^\+[^\n]*"#, .inserted), (#"^-[^\n]*"#, .deleted),
            ]
        ),
        Language(
            id: "dockerfile", name: "Dockerfile", extensions: ["dockerfile"], fileNames: ["Dockerfile", "Containerfile"],
            lineComments: ["#"],
            keywords: "from run cmd label expose env add copy entrypoint volume user workdir arg onbuild stopsignal healthcheck shell as",
            caseInsensitiveKeywords: true, capitalizedTypes: false,
            patterns: [(#"\$\{[^}\n]*\}|\$\w+"#, .attribute)]
        ),
    ]

    /// Picks the language for a file from its name, then its extension, then a `#!` line.
    public static func forFile(named fileName: String, firstLine: String? = nil) -> Language {
        if let match = all.first(where: { $0.fileNames.contains(fileName) }) { return match }
        let ext = (fileName as NSString).pathExtension.lowercased()
        if !ext.isEmpty, let match = all.first(where: { $0.extensions.contains(ext) }) { return match }
        if let line = firstLine, line.hasPrefix("#!") {
            let interpreters: [(String, String)] = [("python", "python"), ("node", "javascript"), ("ruby", "ruby"), ("php", "php"), ("sh", "shell")]
            if let (_, id) = interpreters.first(where: { line.contains($0.0) }) { return language(id: id) ?? plainText }
        }
        return plainText
    }

    public static func language(id: String) -> Language? {
        id == plainText.id ? plainText : all.first { $0.id == id }
    }
}
