import PerchKit
import SwiftUI

struct QuestionCardView: View {
    let request: AskUserQuestionRequest
    let draftID: QuestionDraftID
    let drafts: QuestionDraftStore
    var isReadOnly = false
    let submit: ([String: [String]]) -> Void
    let cancel: () -> Void

    @ViewBuilder
    var body: some View {
        if isReadOnly {
            CopilotQuestionReadOnlyView(request: request, cancel: cancel)
        } else if request.questions.count == 1 {
            SingleQuestionView(
                request: request, draftID: draftID, drafts: drafts,
                submit: submit, cancel: cancel)
        } else {
            WizardQuestionView(
                request: request, draftID: draftID, drafts: drafts,
                submit: submit, cancel: cancel)
        }
    }
}

/// Copilot can surface a question through its hook without accepting an answer payload
/// from Perch. The options remain readable, while the only action returns to the owning
/// client instead of presenting controls that cannot complete the request.
struct CopilotQuestionReadOnlyView: View {
    let request: AskUserQuestionRequest
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.info)
                Text(t("Question"))
                    .font(Theme.label(12, .semibold))
                    .foregroundStyle(Theme.primary)
                Spacer(minLength: 0)
                TagPill(text: "Copilot", brandColor: Theme.info)
            }

            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 5) {
                    Text(question.question)
                        .font(Theme.label(12, .semibold))
                        .foregroundStyle(Theme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(question.options) { option in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: question.multiSelect ? "square" : "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.tertiary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label)
                                    .font(Theme.label(11, .medium))
                                if !option.description.isEmpty {
                                    Text(option.description)
                                        .font(Theme.mono(9))
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer(minLength: 0)
                ApprovalButton(
                    label: t("Answer in terminal"),
                    axIdentifier: "question.copilot.terminal",
                    action: cancel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("question.copilot.readOnly")
    }
}

/// Vibe treats one direct question and a multi-step questionnaire as separate surfaces.
/// They deliberately share the answer engine below; the distinction controls navigation,
/// identity and future state-specific presentation without duplicating submission rules.
struct SingleQuestionView: View {
    let request: AskUserQuestionRequest
    let draftID: QuestionDraftID
    let drafts: QuestionDraftStore
    let submit: ([String: [String]]) -> Void
    let cancel: () -> Void

    var body: some View {
        QuestionSubmissionView(
            request: request, draftID: draftID, drafts: drafts,
            submit: submit, cancel: cancel)
            .accessibilityIdentifier("question.single")
    }
}

struct WizardQuestionView: View {
    let request: AskUserQuestionRequest
    let draftID: QuestionDraftID
    let drafts: QuestionDraftStore
    let submit: ([String: [String]]) -> Void
    let cancel: () -> Void

    var body: some View {
        QuestionSubmissionView(
            request: request, draftID: draftID, drafts: drafts,
            submit: submit, cancel: cancel)
            .accessibilityIdentifier("question.wizard")
    }
}

/// Answering `AskUserQuestion` from the notch.
///
/// Approving the *asking* of a question is useless — the point of the tool is the answer.
/// A session is blocked while this is up, so it shows one question at a time with its
/// options, and only submits once every question has one.
private struct QuestionSubmissionView: View {
    let request: AskUserQuestionRequest
    let draftID: QuestionDraftID
    let drafts: QuestionDraftStore
    let submit: ([String: [String]]) -> Void
    let cancel: () -> Void

    @State private var answers: [String: [String]] = [:]
    /// What was typed rather than picked, keyed by question.
    @State private var typed: [String: String] = [:]
    @State private var index = 0

    init(
        request: AskUserQuestionRequest, draftID: QuestionDraftID,
        drafts: QuestionDraftStore, submit: @escaping ([String: [String]]) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.request = request
        self.draftID = draftID
        self.drafts = drafts
        self.submit = submit
        self.cancel = cancel

        let draft = drafts.draft(for: draftID)
        _answers = State(initialValue: draft.responses.mapValues(\.picked))
        _typed = State(initialValue: draft.responses.mapValues(\.typed))
        _index = State(
            initialValue: min(max(0, draft.currentIndex), max(0, request.questions.count - 1)))
    }

    private var question: AskQuestion? {
        request.questions.indices.contains(index) ? request.questions[index] : nil
    }

    /// Picked plus typed — what actually gets submitted, and what "is this answered yet"
    /// is judged against.
    private var effective: [String: [String]] {
        request.merged(picked: answers, typed: typed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if let question {
                // The question, its options and the answer field scroll together; the
                // header and the controls do not. The panel is sized to fit this whole
                // body — see `QuestionCard` — so the scroll is the overflow case rather
                // than the normal one, and when it does happen the buttons are still
                // where they were. A card that has to be scrolled to reach its own
                // Submit is a card nobody submits.
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(question.question)
                            .font(Theme.label(12, .semibold))
                            .foregroundStyle(Theme.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        options(for: question)
                        otherField(for: question)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: QuestionCard.maxBodyHeight)
                .scrollIndicators(.automatic)
            }
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Button("") {
                guard request.isComplete(effective) else { return }
                submit(effective)
            }
            .keyboardShortcut(.return, modifiers: .control)
            .opacity(0)
        }
        .onChange(of: answers) { _, _ in saveDraft() }
        .onChange(of: typed) { _, _ in saveDraft() }
        .onChange(of: index) { _, _ in saveDraft() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.claude)

            Text(question?.header.isEmpty == false ? question!.header : t("Question"))
                .font(Theme.label(12, .semibold))
                .foregroundStyle(Theme.primary)

            Spacer(minLength: 0)

            if request.questions.count > 1 {
                Text(t("%lld of %lld", index + 1, request.questions.count))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.tertiary)
            }
            if question?.multiSelect == true {
                Chip(text: t("multi"), tint: Theme.info)
            }
        }
    }

    private func options(for question: AskQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                if question.multiSelect {
                    let row = MultiSelectOptionButton(
                        index: index,
                        option: option,
                        isSelected: selected(question).contains(option.label)
                    ) {
                        toggle(option.label, in: question)
                    }
                    if index < 9 {
                        row.keyboardShortcut(
                            KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                    } else {
                        row
                    }
                } else {
                    let row = SingleSelectOptionButton(
                        index: index,
                        option: option,
                        isSelected: selected(question).contains(option.label)
                    ) {
                        toggle(option.label, in: question)
                    }
                    if index < 9 {
                        row.keyboardShortcut(
                            KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                    } else {
                        row
                    }
                }
            }
        }
    }

    /// The free-text answer — the "none of these" every question implicitly has.
    ///
    /// Without it the only way to say something the options do not cover was to leave the
    /// notch and type in the terminal, which defeats the card.
    private func otherField(for question: AskQuestion) -> some View {
        TextField(
            question.multiSelect ? t("…and something else") : t("Other — write your answer"),
            text: Binding(
                get: { typed[question.question] ?? "" },
                set: { typed[question.question] = $0 })
        )
        .textFieldStyle(.plain)
        .font(Theme.mono(10))
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.raised.opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    hasTyped(question) ? Theme.active.opacity(0.5) : Theme.hairline,
                    lineWidth: 1)
        )
        // Enter submits, the way it does in the terminal prompt this replaces.
        .onSubmit {
            guard request.isComplete(effective) else { return }
            if index < request.questions.count - 1 { index += 1 } else { submit(effective) }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if index > 0 {
                ApprovalButton(label: t("Back"), axIdentifier: "question.back") {
                    index -= 1
                }
            }

            Spacer(minLength: 0)

            ApprovalButton(
                label: t("Answer in terminal"), axIdentifier: "question.terminal",
                action: cancel)

            if index < request.questions.count - 1 {
                ApprovalButton(
                    label: t("Next"), foreground: Theme.info,
                    axIdentifier: "question.next",
                    isEnabled: !(effective[question?.question ?? ""]?.isEmpty ?? true)
                ) { index += 1 }
            } else {
                ApprovalButton(
                    label: request.questions.count > 1 ? t("Submit all") : t("Submit"),
                    shortcut: "⌃↩",
                    foreground: Theme.active,
                    axIdentifier: "question.submit",
                    isEnabled: request.isComplete(effective)
                ) {
                    submit(effective)
                }
            }
        }
    }

    private func hasTyped(_ question: AskQuestion) -> Bool {
        !(typed[question.question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveDraft() {
        var responses: [String: QuestionResponseDraft] = [:]
        for question in request.questions {
            let response = QuestionResponseDraft(
                picked: answers[question.question] ?? [],
                typed: typed[question.question] ?? "")
            if !response.picked.isEmpty || !response.typed.isEmpty {
                responses[question.question] = response
            }
        }
        drafts.save(
            QuestionAnswerDraft(currentIndex: index, responses: responses),
            for: draftID)
    }

    /// What the option rows draw as picked.
    ///
    /// For a single-select question, typing hides the option tick: the two are alternatives
    /// and showing both selected would misrepresent what is about to be submitted.
    private func selected(_ question: AskQuestion?) -> [String] {
        guard let question else { return [] }
        if !question.multiSelect && hasTyped(question) { return [] }
        return answers[question.question] ?? []
    }

    /// Single-select replaces; multi-select accumulates and can be unpicked.
    private func toggle(_ label: String, in question: AskQuestion) {
        // Picking an option in a single-select question retracts anything typed — the
        // click is the more recent statement of intent.
        if !question.multiSelect { typed[question.question] = "" }

        var current = answers[question.question] ?? []
        if question.multiSelect {
            if let existing = current.firstIndex(of: label) {
                current.remove(at: existing)
            } else {
                current.append(label)
            }
        } else {
            current = current == [label] ? [] : [label]
        }
        answers[question.question] = current
    }
}

private struct SingleSelectOptionButton: View {
    let index: Int
    let option: AskQuestion.Option
    let isSelected: Bool
    var modSymbol = "⌃"
    var showsShortcutHint = true
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            QuestionOptionLabel(
                option: option,
                symbol: isSelected ? "largecircle.fill.circle" : "circle",
                shortcut: shortcut,
                isSelected: isSelected,
                isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("question.option.single.\(index)")
    }

    private var shortcut: String? {
        showsShortcutHint && isHovered && index < 9 ? "\(modSymbol)\(index + 1)" : nil
    }
}

private struct MultiSelectOptionButton: View {
    let index: Int
    let option: AskQuestion.Option
    let isSelected: Bool
    var modSymbol = "⌃"
    var showsShortcutHint = true
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            QuestionOptionLabel(
                option: option,
                symbol: isSelected ? "checkmark.square.fill" : "square",
                shortcut: shortcut,
                isSelected: isSelected,
                isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("question.option.multi.\(index)")
    }

    private var shortcut: String? {
        showsShortcutHint && isHovered && index < 9 ? "\(modSymbol)\(index + 1)" : nil
    }
}

private struct QuestionOptionLabel: View {
    let option: AskQuestion.Option
    let symbol: String
    let shortcut: String?
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Theme.active : Theme.tertiary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(option.label)
                    .font(Theme.label(11, .medium))
                    .foregroundStyle(Theme.primary)
                if !option.description.isEmpty {
                    Text(option.description)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if let shortcut {
                Text(shortcut)
                    .font(Theme.mono(9, .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Theme.active.opacity(0.12)
                        : Theme.raised.opacity(isHovered ? 0.75 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Theme.active.opacity(0.5) : Theme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

/// Approving a plan, or sending back what to change.
///
/// Denying with a message is not a refusal here — Claude Code reads it as feedback and
/// keeps going, which is what "tell it what to fix" means.
///
/// Approving is a choice of mode rather than a yes: that is what Claude Code's own prompt
/// asks, and one button saying "Approve" could only ever guess which one it meant.
struct PlanCardView: View {
    let request: PlanApprovalRequest
    /// What the panel is drawn at, less its padding. Code blocks are never wrapped, so the
    /// only way they can be made to fit is to be measured against this.
    var contentWidth: CGFloat = NotchState.alertWidth
    let approve: (PlanMode) -> Void
    let reject: (String) -> Void

    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.info)
                Text(t("Plan"))
                    .font(Theme.label(12, .semibold))
                    .foregroundStyle(Theme.primary)
                Spacer(minLength: 0)
            }

            ScrollView {
                // Block by block, because a plan's structure is the plan. Passing the whole
                // document through `AttributedString(markdown:)` parsed the syntax and then
                // dropped every block boundary — a heading welded to the paragraph under it
                // and an ASCII diagram double-spaced into nonsense, which is the state in
                // which nobody reads it and everybody approves it.
                MarkdownText(request.plan, density: .reading, width: contentWidth - 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
            // The card is sized for its content — see `PlanCard.extraHeight` — so this cap
            // is the overflow case rather than the normal one. Shared with the sizing so
            // the two cannot disagree about where the plan stops fitting.
            .frame(maxHeight: PlanCard.maxBodyHeight)
            .scrollIndicators(.automatic)

            TextField(t("Tell Claude what to change…"), text: $feedback)
                .textFieldStyle(.plain)
                .font(Theme.mono(10))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Theme.raised.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1)
                )

            HStack(spacing: 6) {
                ApprovalButton(
                    label: feedback.isEmpty ? t("Reject") : t("Send feedback"),
                    foreground: Theme.warning,
                    axIdentifier: "plan.reject"
                ) {
                    reject(feedback)
                }
                Spacer(minLength: 0)
                ForEach(PlanMode.allCases, id: \.self) { mode in
                    ApprovalButton(
                        label: t(mode.title),
                        // Bypass is the one that stops asking about anything at all, and
                        // it reads the same as the other two if it is not coloured.
                        foreground: mode == .bypassPermissions ? Theme.danger : Theme.active,
                        axIdentifier: "plan.\(mode.rawValue)"
                    ) {
                        approve(mode)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The decision button contract reflected by Vibe's `ApprovalButton`.
struct ApprovalButton: View {
    let label: String
    var shortcut: String?
    var foreground: Color = Theme.secondary
    var background: Color = Color.white
    var axIdentifier: String
    var axLabel: String?
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                if let shortcut {
                    Text(shortcut)
                        .font(Theme.mono(9, .medium))
                        .opacity(0.65)
                }
            }
            .font(Theme.label(11, .medium))
            .foregroundStyle(isEnabled ? foreground : Theme.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(background.opacity(isHovered && isEnabled ? 0.2 : 0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier(axIdentifier)
        .accessibilityLabel(axLabel ?? label)
    }
}

/// Shared button shape for the answer cards.
struct SmallButton: View {
    let title: String
    let tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.label(11, .medium))
                .foregroundStyle(tint ?? Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((tint ?? Color.white).opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }
}
