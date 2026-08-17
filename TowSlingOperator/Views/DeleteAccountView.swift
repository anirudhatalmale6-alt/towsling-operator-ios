import SwiftUI

/// Closing the company account for good.
///
/// Apple requires this to exist inside any app that can create an account, and
/// to be genuinely reachable rather than a link out to a website.
///
/// It shows what will happen BEFORE asking for the password, because the
/// consequences are not obvious: finished jobs are kept as financial records
/// even after the account is anonymised, and the server refuses outright while
/// money is owed or a job is still live. Somebody discovering either of those
/// after typing DELETE would rightly feel misled.
struct DeleteAccountView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var impact: Impact?
    @State private var loading = true
    @State private var password = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var errorMessage: String?

    struct Impact: Decodable {
        let canClose: Bool?
        let blockers: [String]?
        let keepsJobRecords: Bool?

        enum CodingKeys: String, CodingKey {
            case canClose        = "can_close"
            case blockers
            case keepsJobRecords = "keeps_job_records"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        if loading {
                            ProgressView().tint(Theme.inkFaint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else {
                            warning

                            if let blockers = impact?.blockers, !blockers.isEmpty {
                                blocked(blockers)
                            } else {
                                form
                            }
                        }
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.red)

            Text("Your company, your team logins, your documents and your rates are "
               + "removed. You will be signed out on every device.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            if impact?.keepsJobRecords == true {
                // Said plainly rather than discovered later. Completed jobs are
                // financial records that both sides may need for a dispute or a
                // tax return, so they survive with the personal details stripped.
                Text("Jobs you have already completed are kept as financial records, "
                   + "with your personal details removed from them. We cannot delete "
                   + "those — they are the record of money that changed hands.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func blocked(_ blockers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.amber)
            ForEach(blockers, id: \.self) { b in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Theme.amber)
                        .padding(.top, 6)
                    Text(b)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Sort these out first and this screen will let you continue.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your password")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.inkDim)
                SecureField("", text: $password)
                    .textContentType(.password)
                    .modifier(BoxedField())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Type DELETE to confirm")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.inkDim)
                TextField("", text: $confirm)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .modifier(BoxedField())
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                submit()
            } label: {
                if working { ProgressView().tint(.white) }
                else { Text("Delete my account for good") }
            }
            .buttonStyle(DestructiveButtonStyle(enabled: canSubmit))
            .disabled(!canSubmit || working)
        }
        .cardBackground(padding: 18)
    }

    private var canSubmit: Bool {
        !password.isEmpty && confirm.uppercased() == "DELETE"
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            impact = try await API.shared.get("/account/close-check", as: Impact.self)
        } catch let e as APIError {
            errorMessage = e.message
        } catch {
            errorMessage = "Could not check the account."
        }
    }

    private func submit() {
        working = true
        errorMessage = nil
        Task {
            let err = await session.deleteAccount(password: password,
                                                  confirm: confirm.uppercased())
            working = false
            if let err { errorMessage = err }
            // On success the session clears and RootView swaps back to sign-in,
            // taking this sheet with it.
        }
    }
}

/// The bordered text box used on this screen. Small enough not to earn a shared
/// component, repeated twice rather than four times.
private struct BoxedField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Red, and only red. A destructive action must not look like the accent-orange
/// primary button an operator taps forty times a day.
struct DestructiveButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(enabled ? Theme.red : Theme.red.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
