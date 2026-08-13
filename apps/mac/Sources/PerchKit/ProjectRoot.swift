import Foundation

/// Which project a path belongs to — the repository's name, not the folder the agent
/// happens to sit in.
///
/// The panel used to call a session by the last component of its cwd, which in a monorepo
/// is where it stops being an answer: three cards reading `web`, `api` and `mobile` are
/// three cards that never say `openbotsmile`, and the question you open the notch with is
/// which *project* is busy. The nearest `.git` above the cwd is what a person means by
/// that, and it is the one marker every repo here has.
public enum ProjectRoot {
    /// An agent's cwd is never forty levels deep. A path that is has something wrong with
    /// it, and a bounded walk keeps that from becoming a hang on the main thread.
    private static let maxDepth = 40

    /// `nonisolated(unsafe)` behind a lock rather than an actor: this is read while the
    /// panel draws, once per card and once per recent row, and awaiting an actor to render
    /// a label would turn a redraw into a suspension.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    /// The repository's name for `path`, falling back to the directory's own when the path
    /// is not in a repository at all.
    public static func name(for path: String) -> String {
        let fallback = URL(fileURLWithPath: path).lastPathComponent
        guard let root = self.path(for: path) else { return fallback }
        let name = URL(fileURLWithPath: root).lastPathComponent
        return name.isEmpty ? fallback : name
    }

    /// The repository root containing `path`, or nil when there is none.
    ///
    /// Cached per path: it touches the disk once per level, and the panel asks for the same
    /// handful of cwds on every hook. The cost is that a directory turned into a repo after
    /// the first lookup keeps its old answer until Perch restarts — which is a rename a
    /// person does once, against a redraw that happens all day.
    public static func path(for path: String) -> String? {
        if let hit = lock.withLock({ cache[path] }) { return hit }
        let resolved = walk(from: path)
        lock.withLock { cache[path] = resolved }
        return resolved
    }

    /// Forgets everything looked up so far. Only the tests need this, and a cache that
    /// cannot be cleared is a test that leaks into the next one.
    public static func resetCache() {
        lock.withLock { cache.removeAll() }
    }

    private static func walk(from path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var url = URL(fileURLWithPath: path).standardizedFileURL
        var depth = 0
        while depth < maxDepth, url.path != "/", !url.path.isEmpty {
            // A file, not only a directory: that is what a git worktree's `.git` is, and a
            // worktree is a project the same way its main checkout is.
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent(".git").path)
            {
                return url.path
            }
            url = url.deletingLastPathComponent()
            depth += 1
        }
        return nil
    }
}
