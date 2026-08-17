import SwiftUI

/// Creating a towing company account, in the app.
///
/// Apple expects an app whose content sits behind a login to let people create
/// that account without leaving it — pointing them at a website to sign up is a
/// routine rejection. It is also simply better: an operator who downloads this
/// at 11pm because a friend recommended it should be looking at jobs a minute
/// later, not hunting for a laptop.
///
/// Fields mirror api/auth.php `register` exactly. Nothing is validated here that
/// the server does not also validate — the server is the one that decides, and
/// two sets of rules would disagree within a fortnight.
struct SignupView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var company = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var companyPhone = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedTerms = false

    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        Text("Join TowSling")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.ink)

                        Text("Jobs are paid for before you ever see them. No monthly "
                           + "fee, no lead fees, no exclusivity — you keep 90%.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.inkDim)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 13) {
                            field("Company name") {
                                TextField("", text: $company)
                                    .textContentType(.organizationName)
                            }
                            HStack(spacing: 10) {
                                field("First name") {
                                    TextField("", text: $firstName)
                                        .textContentType(.givenName)
                                }
                                field("Last name") {
                                    TextField("", text: $lastName)
                                        .textContentType(.familyName)
                                }
                            }
                            field("Company phone") {
                                TextField("", text: $companyPhone)
                                    .textContentType(.telephoneNumber)
                                    .keyboardType(.phonePad)
                            }
                            // Said here rather than discovered as an error. This
                            // is the number a stranded customer is given the
                            // moment this company accepts their job.
                            Text("This is the number customers are given when you accept a job.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.inkFaint)

                            field("Email") {
                                TextField("", text: $email)
                                    .textContentType(.username)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            field("Password") {
                                SecureField("", text: $password)
                                    .textContentType(.newPassword)
                            }
                            Text("At least 8 characters.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        .cardBackground(padding: 18)

                        Toggle(isOn: $acceptedTerms) {
                            HStack(spacing: 4) {
                                Text("I accept the")
                                    .foregroundStyle(Theme.inkDim)
                                Link("terms", destination: Config.termsURL)
                                    .foregroundStyle(Theme.accent)
                            }
                            .font(.system(size: 13.5))
                        }
                        .tint(Theme.accent)

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
                            else { Text("Create my account") }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                        .disabled(!canSubmit || working)

                        // What happens next, before they wonder why no jobs are
                        // arriving. A new company lands in the review queue, and
                        // silence there reads as a broken app.
                        Text("We check every company before the first job. You can sign in "
                           + "straight away and upload your insurance and licence — jobs "
                           + "start arriving once that is approved.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Sign up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !company.trimmingCharacters(in: .whitespaces).isEmpty
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && companyPhone.filter(\.isNumber).count >= 10
            && email.contains("@")
            && password.count >= 8
            && acceptedTerms
    }

    private func submit() {
        working = true
        errorMessage = nil
        Task {
            let err = await session.signUp(
                company: company.trimmingCharacters(in: .whitespaces),
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                companyPhone: companyPhone,
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            working = false
            if let err { errorMessage = err }
            // On success the session becomes signed in and RootView swaps the
            // whole screen out, so there is nothing to dismiss.
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Theme.inkDim)
            content()
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background(Theme.bg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
