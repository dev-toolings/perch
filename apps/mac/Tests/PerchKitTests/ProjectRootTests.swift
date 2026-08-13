import Foundation
import Testing

@testable import PerchKit

/// A session in `openbotsmile/apps/web` is the `openbotsmile` project to everyone who
/// works on it — "web" names the folder and identifies nothing.
@Test func theProjectIsTheRepositoryNotTheSubdirectory() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("perch-project-\(UUID().uuidString)")
        .appendingPathComponent("openbotsmile")
    let deep = root.appendingPathComponent("apps/web/src")
    try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        ProjectRoot.resetCache()
    }
    ProjectRoot.resetCache()

    #expect(ProjectRoot.name(for: deep.path) == "openbotsmile")
    #expect(ProjectRoot.path(for: deep.path) == root.path)
}

/// A worktree's `.git` is a file, and a worktree is a project the same way its checkout is.
@Test func aWorktreeCountsAsItsOwnProject() throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("perch-worktree-\(UUID().uuidString)")
    let tree = base.appendingPathComponent("perch-fix")
    try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    try "gitdir: /elsewhere".write(
        to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: base)
        ProjectRoot.resetCache()
    }
    ProjectRoot.resetCache()

    #expect(ProjectRoot.name(for: tree.path) == "perch-fix")
}

/// Outside a repository there is nothing better to say than the folder's own name, and
/// saying nothing at all would be worse.
@Test func aPathWithNoRepositoryKeepsItsFolderName() {
    ProjectRoot.resetCache()
    #expect(ProjectRoot.name(for: "/lab/definitely-not-here/perch") == "perch")
    #expect(ProjectRoot.path(for: "/lab/definitely-not-here/perch") == nil)
}
