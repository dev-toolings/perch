import XCTest

@testable import PerchKit

final class ToolDiffTests: XCTestCase {

    private func input(_ dict: [String: JSONValue]) -> JSONValue {
        .object(dict)
    }

    func testEditProducesNumberedAdditionsAndDeletions() {
        let diff = ToolDiff.build(
            toolName: "Edit",
            toolInput: input([
                "file_path": .string("src/auth/middleware.ts"),
                "old_string": .string("const verify = (token) =>\n  jwt.verify(token);"),
                "new_string": .string(
                    "const verify = (token) =>\n  if (!token) throw new AuthError();\n  return jwt.verify(token);"
                ),
            ]))

        guard let diff else { return XCTFail("an Edit should diff") }
        XCTAssertEqual(diff.filePath, "src/auth/middleware.ts")
        XCTAssertEqual(diff.additions, 2)
        XCTAssertEqual(diff.deletions, 1)
        XCTAssertEqual(diff.badge, "+2 -1")

        // Context line first, numbered from the fragment.
        XCTAssertEqual(diff.lines.first, .init(kind: .context, text: "const verify = (token) =>", number: 1))
        XCTAssertTrue(diff.lines.contains(.init(kind: .deleted, text: "  jwt.verify(token);", number: 2)))
        XCTAssertTrue(
            diff.lines.contains(
                .init(kind: .added, text: "  if (!token) throw new AuthError();", number: 2)))
    }

    func testWriteIsAllAdditionsAndATrailingNewlineIsNotALine() {
        let diff = ToolDiff.build(
            toolName: "Write",
            toolInput: input([
                "file_path": .string("README.md"),
                "content": .string("# Title\n\ntext\n"),
            ]))

        guard let diff else { return XCTFail("a Write should diff") }
        XCTAssertEqual(diff.additions, 3)
        XCTAssertEqual(diff.deletions, 0)
        XCTAssertEqual(diff.lines.map(\.kind), [.added, .added, .added])
        XCTAssertEqual(diff.lines.map(\.number), [1, 2, 3])
    }

    func testMultiEditConcatenatesHunksWithAnEllipsisBetweenThem() {
        let diff = ToolDiff.build(
            toolName: "MultiEdit",
            toolInput: input([
                "file_path": .string("a.swift"),
                "edits": .array([
                    input(["old_string": .string("foo"), "new_string": .string("bar")]),
                    input(["old_string": .string("baz"), "new_string": .string("qux")]),
                ]),
            ]))

        guard let diff else { return XCTFail("a MultiEdit should diff") }
        XCTAssertEqual(diff.additions, 2)
        XCTAssertEqual(diff.deletions, 2)
        XCTAssertTrue(diff.lines.contains(.init(kind: .context, text: "…", number: 0)))
    }

    func testLongContextIsTrimmedAroundTheChange() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n")
        var newLines = (1...20).map { "line \($0)" }
        newLines[10] = "changed"
        let diff = ToolDiff.build(
            toolName: "Edit",
            toolInput: input([
                "file_path": .string("f"),
                "old_string": .string(old),
                "new_string": .string(newLines.joined(separator: "\n")),
            ]))

        guard let diff else { return XCTFail() }
        // Two context lines kept on each side of the change, ellipses for the rest.
        let ellipsisCount = diff.lines.filter { $0.text == "…" }.count
        XCTAssertEqual(ellipsisCount, 2)
        XCTAssertEqual(diff.lines.count, 2 + 2 + 2 + 2) // ctx×2, del, add, ctx×2, plus…
    }

    func testNonFileToolsAndMissingFieldsReturnNil() {
        XCTAssertNil(
            ToolDiff.build(
                toolName: "Bash", toolInput: input(["command": .string("ls")])))
        XCTAssertNil(
            ToolDiff.build(
                toolName: "Edit", toolInput: input(["file_path": .string("f")])))
        XCTAssertNil(ToolDiff.build(toolName: nil, toolInput: nil))
    }
}
