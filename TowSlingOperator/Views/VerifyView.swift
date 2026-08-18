import SwiftUI

/// Confirming the email address and the phone number.
///
/// These are not paperwork. Until both are confirmed the company cannot accept
/// a job at all — the board refuses it — because a customer is handed this
/// number the moment a job is taken, and a number nobody answers is worse than
/// no truck. So the screen says that, rather than presenting two green ticks as
/// their own reward.
struct VerifyView: View {
    let channel: Channel
    let destination: String
    let onVerified: () -> Void

    /// Identifiable so `.sheet(item:)` can drive it — that presenter needs an
    /// id, and a Bool plus a separate "which one" is how the wrong sheet ends
    /// up on screen when both are tapped quickly.
    enum Channel: String, Identifiable {
        case email, phone

        var id: String { rawValue }

        var title: String { self == .email ? "Confirm your email" : "Confirm your phone" }
        var sentVia: String { self == .email ? "email" : "text message" }
        var icon: String { self == .email ? "envelope.fill" : "message.fill" }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var sending = false
    @State private var confirming = false
    @State private var sent = false
    @State private var errorMessage: String?
    @State private var note: String?
    /// Seconds until "send another" becomes tappable. The server rate-limits
    /// these and a button that just fails is worse than one that waits.
    @State private var cooldown = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        VStack(alignment: .leading, spacing: 8) {
                            Label(destination, systemImage: channel.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text("We send a six-digit code by \(channel.sentVia). "
                               + "It is good for a few minutes.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                            // Why this is worth doing, said once and plainly.
                            Text("Your company cannot accept jobs until both your email and "
                               + "your phone are confirmed — a customer is given this number "
                               + "the moment you take a job.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground()

                        if sent {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Enter the code")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(Theme.inkDim)
                                TextField("000000", text: $code)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Theme.ink)
                                    .frame(height: 58)
                                    .background(Theme.bg)
                                    .overlay(RoundedRectangle(cornerRadius: 11)
                                        .stroke(Theme.line, lineWidth: 1.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                    .onChange(of: code) { value in
                                        // Digits only, six of them. Pasting from
                                        // a text often brings spaces with it.
                                        let digits = value.filter(\.isNumber)
                                        if digits != value { code = String(digits.prefix(6)) }
                                        else if digits.count > 6 { code = String(digits.prefix(6)) }
                                    }

                                Button {
                                    confirm()
                                } label: {
                                    if confirming { ProgressView().tint(.white) }
                                    else { Text("Confirm") }
                                }
                                .buttonStyle(PrimaryButtonStyle(enabled: code.count == 6))
                                .disabled(code.count != 6 || confirming)

                                Button(cooldown > 0 ? "Send another in \(cooldown)s" : "Send another code") {
                                    send()
                                }
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(cooldown > 0 ? Theme.inkFaint : Theme.accent)
                                .disabled(cooldown > 0 || sending)
                                .frame(maxWidth: .infinity)
                            }
                            .cardBackground(padding: 18)
                        } else {
                            Button {
                                send()
                            } label: {
                                if sending { ProgressView().tint(.white) }
                                else { Text("Send me a code") }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(sending)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let note {
                            Text(note)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.green)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(channel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onReceive(timer) { _ in if cooldown > 0 { cooldown -= 1 } }
        }
    }

    private func send() {
        sending = true
        errorMessage = nil
        note = nil
        Task {
            struct SendResponse: Decodable {
                let already: Bool?
                /// Masked by the server — "j***@company.com" — so the operator
                /// can tell WHICH address it went to without this being a way
                /// to read the record back out.
                let sentTo: String?
                enum CodingKeys: String, CodingKey {
                    case already
                    case sentTo = "sent_to"
                }
            }
            do {
                let r = try await API.shared.post("/verify/send",
                                                  body: ["channel": channel.rawValue],
                                                  as: SendResponse.self)
                sending = false
                if r.already == true {
                    note = "That is already confirmed."
                    onVerified()
                    return
                }
                sent = true
                cooldown = 60
                note = r.sentTo.map { "Code sent to \($0)." } ?? "Code sent."
            } catch let e as APIError {
                sending = false
                errorMessage = e.message
                // 429 means one is already in flight — show the box so the code
                // they have just received is not stranded behind a Send button.
                if e.status == 429 { sent = true; cooldown = 60 }
            } catch {
                sending = false
                errorMessage = "Could not send the code."
            }
        }
    }

    private func confirm() {
        confirming = true
        errorMessage = nil
        note = nil
        Task {
            struct Ack: Decodable { }
            do {
                _ = try await API.shared.post("/verify/confirm",
                                              body: ["channel": channel.rawValue, "code": code],
                                              as: Ack.self)
                confirming = false
                note = "Confirmed."
                onVerified()
                dismiss()
            } catch let e as APIError {
                confirming = false
                // The server counts down the attempts left and says so. Its
                // wording is better than anything generic this screen could
                // invent, so it is passed straight through.
                errorMessage = e.message
                code = ""
            } catch {
                confirming = false
                errorMessage = "Could not confirm that code."
            }
        }
    }
}
