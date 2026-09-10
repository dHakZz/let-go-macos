import AppKit
import Foundation
import SwiftUI

struct SuggestionSubmission: Sendable {
    let name: String
    let email: String
    let subject: String
    let suggestion: String
}

private enum SuggestionDeliveryError: LocalizedError {
    case invalidResponse
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The suggestion service did not respond. Please check your connection and try again."
        case .rejected(let message):
            return message
        }
    }
}

private struct SuggestionService: Sendable {
    private static let endpoint = URL(string: "https://formsubmit.co/ajax/j.justinchacon@gmail.com")!
    private static let formOrigin = "https://let-go-app.invalid"
    private static let formSource = "https://let-go-app.invalid/suggestions"

    enum Result: Equatable, Sendable {
        case sent
        case activationRequired
    }

    func send(_ submission: SuggestionSubmission) async throws -> Result {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
        request.setValue("Let Go/\(version) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue(Self.formOrigin, forHTTPHeaderField: "Origin")
        request.setValue(Self.formSource, forHTTPHeaderField: "Referer")
        request.httpBody = try JSONEncoder().encode(
            Payload(
                name: submission.name,
                email: submission.email,
                subject: submission.subject,
                message: submission.suggestion,
                emailSubject: "[Let Go Suggestion] \(submission.subject)",
                template: "table",
                formSource: Self.formSource
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuggestionDeliveryError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SuggestionDeliveryError.rejected(
                Self.message(from: data) ?? "The suggestion could not be sent. Please try again in a moment."
            )
        }

        if let success = Self.success(from: data), !success {
            let serviceMessage = Self.message(from: data) ?? ""
            if serviceMessage.localizedCaseInsensitiveContains("activation") ||
                serviceMessage.localizedCaseInsensitiveContains("activate form") {
                return .activationRequired
            }
            throw SuggestionDeliveryError.rejected(
                serviceMessage.isEmpty ? "The suggestion service could not accept this message." : serviceMessage
            )
        }

        return .sent
    }

    private static func success(from data: Data) -> Bool? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawValue = object["success"]
        else { return nil }

        if let value = rawValue as? Bool { return value }
        if let value = rawValue as? String { return value.lowercased() == "true" }
        return nil
    }

    private static func message(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? String,
            !message.isEmpty
        else { return nil }
        return message
    }

    private struct Payload: Encodable {
        let name: String
        let email: String
        let subject: String
        let message: String
        let emailSubject: String
        let template: String
        let formSource: String

        enum CodingKeys: String, CodingKey {
            case name
            case email
            case subject
            case message
            case emailSubject = "_subject"
            case template = "_template"
            case formSource = "_url"
        }
    }
}

@MainActor
private final class SuggestionsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case sending
        case sent
        case activationRequired
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private let service = SuggestionService()

    func submit(_ submission: SuggestionSubmission) async {
        guard phase != .sending else { return }
        phase = .sending
        do {
            let result = try await service.send(submission)
            phase = result == .sent ? .sent : .activationRequired
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        phase = .idle
    }
}

struct SuggestionsView: View {
    private enum Field: Hashable {
        case name
        case email
        case subject
        case suggestion
    }

    let appIcon: NSImage
    let onClose: () -> Void

    @StateObject private var viewModel = SuggestionsViewModel()
    @State private var name = ""
    @State private var email = ""
    @State private var subject = ""
    @State private var suggestion = ""
    @FocusState private var focusedField: Field?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSubject: String { subject.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSuggestion: String { suggestion.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        !trimmedName.isEmpty &&
        isValidEmail &&
        !trimmedSubject.isEmpty &&
        !trimmedSuggestion.isEmpty
    }

    private var isValidEmail: Bool {
        trimmedEmail.range(
            of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#,
            options: .regularExpression
        ) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Share a Suggestion")
                        .font(.title2.bold())
                    Text("Tell us what would make Let Go more useful.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                fieldLabel("Name")
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)

                fieldLabel("Email")
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .email)
                if !trimmedEmail.isEmpty && !isValidEmail {
                    Text("Enter a complete email address, such as name@example.com.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                fieldLabel("Subject")
                TextField("What is your suggestion about?", text: $subject)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .subject)

                fieldLabel("Suggestion")
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $suggestion)
                        .font(.body)
                        .focused($focusedField, equals: .suggestion)
                        .scrollContentBackground(.hidden)
                        .padding(6)

                    if suggestion.isEmpty {
                        Text("Describe your idea, improvement, or problem…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 135)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
            }

            statusMessage

            Spacer(minLength: 0)

            HStack {
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if viewModel.phase == .sent {
                    Button("Send Another") {
                        name = ""
                        email = ""
                        subject = ""
                        suggestion = ""
                        viewModel.reset()
                        focusedField = .name
                    }
                } else {
                    Button {
                        let submission = SuggestionSubmission(
                            name: trimmedName,
                            email: trimmedEmail,
                            subject: trimmedSubject,
                            suggestion: trimmedSuggestion
                        )
                        Task {
                            await viewModel.submit(submission)
                        }
                    } label: {
                        if viewModel.phase == .sending {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Sending…")
                            }
                        } else {
                            Label("Send Suggestion", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || viewModel.phase == .sending)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            focusedField = .name
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch viewModel.phase {
        case .sent:
            Label("Suggestion sent. Thank you for helping improve Let Go.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        case .activationRequired:
            Label("One-time setup required: check j.justinchacon@gmail.com for FormSubmit’s activation email, activate the form, then try again.", systemImage: "envelope.badge")
                .font(.callout)
                .foregroundStyle(.orange)
        case .idle, .sending:
            Text("Sent securely to Justin through FormSubmit. FormSubmit may retain submissions for up to 30 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }
}
