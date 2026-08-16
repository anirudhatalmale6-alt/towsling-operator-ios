import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: Session

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 56)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 13))

                    Text("TowSling")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 14)

                    Text("The tow you need, when you need it")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 14) {
                        field("Email", focused: .email) {
                            TextField("", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }

                        field("Password", focused: .password) {
                            SecureField("", text: $password)
                                .textContentType(.password)
                                .focused($focus, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { submit() }
                        }

                        if let error = session.signInError {
                            Text(error)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            submit()
                        } label: {
                            if session.isSigningIn {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign in")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                        .disabled(!canSubmit || session.isSigningIn)
                        .padding(.top, 4)
                    }
                    .cardBackground(padding: 20)
                    .padding(.top, 28)

                    Text("Use the same email and password as the website.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkFaint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 18)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit, !session.isSigningIn else { return }
        focus = nil
        Task {
            await session.signIn(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, focused: Field,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.inkDim)
            content()
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 13)
                .frame(height: 48)
                .background(Theme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(focus == focused ? Theme.accent : Theme.line, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
    }
}
