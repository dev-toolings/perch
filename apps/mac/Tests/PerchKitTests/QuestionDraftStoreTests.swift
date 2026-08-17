import Testing

@testable import PerchKit

@MainActor
@Suite("Question drafts")
struct QuestionDraftStoreTests {
    @Test func aDraftSurvivesAViewReconstructionUntilTheRequestResolves() {
        let store = QuestionDraftStore()
        let id = QuestionDraftID(
            sessionId: "session-1", runtimeInstanceId: "runtime-1", requestId: "request-1")
        let draft = QuestionAnswerDraft(
            currentIndex: 1,
            responses: [
                "Framework?": QuestionResponseDraft(picked: ["SwiftUI"], typed: "")
            ])

        store.save(draft, for: id)
        #expect(store.draft(for: id) == draft)
        #expect(store.count == 1)

        store.remove(id)
        #expect(store.draft(for: id) == QuestionAnswerDraft())
        #expect(store.count == 0)
    }

    @Test func identicalQuestionsFromDifferentRequestsNeverShareAnswers() {
        let store = QuestionDraftStore()
        let first = QuestionDraftID(
            sessionId: "session-1", runtimeInstanceId: "runtime-1", requestId: "request-1")
        let second = QuestionDraftID(
            sessionId: "session-1", runtimeInstanceId: "runtime-1", requestId: "request-2")

        store.save(
            QuestionAnswerDraft(
                responses: ["Deploy?": QuestionResponseDraft(picked: ["Yes"])]),
            for: first)

        #expect(store.draft(for: second) == QuestionAnswerDraft())
    }
}
