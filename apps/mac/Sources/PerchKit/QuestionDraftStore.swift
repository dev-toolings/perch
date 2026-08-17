import Foundation

/// Identity recovered from Vibe Island 1.0.44's `QuestionDraftID` metadata.
/// A session can ask the same wording twice, so the question text is not sufficient.
public struct QuestionDraftID: Hashable, Sendable {
    public var sessionId: String
    public var runtimeInstanceId: String
    public var requestId: String

    public init(sessionId: String, runtimeInstanceId: String, requestId: String) {
        self.sessionId = sessionId
        self.runtimeInstanceId = runtimeInstanceId
        self.requestId = requestId
    }
}

public struct QuestionResponseDraft: Equatable, Sendable {
    public var picked: [String]
    public var typed: String

    public init(picked: [String] = [], typed: String = "") {
        self.picked = picked
        self.typed = typed
    }
}

/// Vibe's reflected `QuestionAnswerDraft` owns the current page and the responses.
public struct QuestionAnswerDraft: Equatable, Sendable {
    public var currentIndex: Int
    public var responses: [String: QuestionResponseDraft]

    public init(
        currentIndex: Int = 0,
        responses: [String: QuestionResponseDraft] = [:]
    ) {
        self.currentIndex = currentIndex
        self.responses = responses
    }
}

/// Process-local by design. Drafts survive SwiftUI view reconstruction and a panel
/// collapse, but never outlive the request or get written to disk as conversation data.
@MainActor
public final class QuestionDraftStore {
    private var drafts: [QuestionDraftID: QuestionAnswerDraft] = [:]

    public init() {}

    public func draft(for id: QuestionDraftID) -> QuestionAnswerDraft {
        drafts[id] ?? QuestionAnswerDraft()
    }

    public func save(_ draft: QuestionAnswerDraft, for id: QuestionDraftID) {
        drafts[id] = draft
    }

    public func remove(_ id: QuestionDraftID) {
        drafts.removeValue(forKey: id)
    }

    public var count: Int { drafts.count }
}
