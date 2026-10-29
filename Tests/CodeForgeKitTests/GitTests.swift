import XCTest
@testable import CodeForgeKit

final class GitTests: XCTestCase {
    func testStatus() {
        let output = """
            ## main...origin/main [ahead 2, behind 1]
            M  Sources/a.swift
             M README.md
            ?? "new file.txt"
            R  old.c -> new.c
            UU conflict.c
            """
        let status = GitStatus.parse(output)
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.upstream, "origin/main")
        XCTAssertEqual(status.ahead, 2)
        XCTAssertEqual(status.behind, 1)
        XCTAssertEqual(status.changes.map(\.path), ["Sources/a.swift", "README.md", "new file.txt", "new.c", "conflict.c"])
        XCTAssertEqual(status.changes.map(\.letter), ["M", "M", "U", "R", "!"])
        XCTAssertEqual(status.changes.map(\.isStaged), [true, false, false, true, true])
        XCTAssertEqual(status.changes[3].originalPath, "old.c")
        XCTAssertEqual(GitStatus.parse("## No commits yet on main\n").branch, "main")
    }

    func testBlame() {
        let output = """
            1111111111111111111111111111111111111111 1 1 2
            author Ahmed
            author-time 1700000000
            summary First commit
            filename main.c
            \tint main(void) {
            1111111111111111111111111111111111111111 2 2
            author Ahmed
            author-time 1700000000
            summary First commit
            filename main.c
            \t    return 0;
            0000000000000000000000000000000000000000 3 3 1
            author Not Committed Yet
            author-time 1800000000
            summary Version of main.c from main.c
            filename main.c
            \t}
            """
        let blame = GitBlame.parse(output)
        XCTAssertEqual(blame.count, 3)
        XCTAssertEqual(blame[1]?.author, "Ahmed")
        XCTAssertTrue(blame[3]!.isUncommitted)
        XCTAssertEqual(GitBlame.latest(in: blame, lines: 1...2)?.summary, "First commit")
        XCTAssertEqual(GitBlame.latest(in: blame, lines: 1...3)?.author, "Not Committed Yet")
    }

    func testRelativeTimeAndDiff() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-7200), now: now), "2 hours ago")
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-100_000), now: now), "yesterday")
        XCTAssertEqual(RelativeTime.describe(now.addingTimeInterval(-86_400 * 30), now: now), "1 month ago")
        let diff = Tokenizer(language: Languages.forFile(named: "x.diff")).tokens(in: "@@ -1 +1 @@\n-old\n+new\n")
        XCTAssertEqual(diff.map(\.kind), [.attribute, .deleted, .inserted])
    }
}
