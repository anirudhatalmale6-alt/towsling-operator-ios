import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: Session

    @State private var email = ""
    @State private var password = ""
    @State private var signingUp = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    // No white tile any more. It existed because the previous
                    // mark's lower half was a near-black navy that disappeared
                    // into this background; the orange artwork carries its own
                    // contrast and has a transparent background, so a white
                    // card around it now reads as a sticker rather than a logo.
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 68)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)

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

                    // Apple expects an app whose content sits behind a login to
                    // offer a way to create the account without leaving it —
                    // sending someone to a website to sign up is a common
                    // rejection under guideline 4.0.
                    HStack(spacing: 5) {
                        Text("New here?")
                            .foregroundStyle(Theme.inkFaint)
                        Button("Sign up your tow company") { signingUp = true }
                            .foregroundStyle(Theme.accent)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 13.5))
                    .padding(.top, 16)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $signingUp) {
            SignupView()
                .environmentObject(session)
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
