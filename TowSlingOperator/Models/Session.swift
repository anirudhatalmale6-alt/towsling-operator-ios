import Foundation
import Combine
import SwiftUI

struct Account: Decodable, Equatable {
    let id: Int
    let name: String
    let accountType: String
    let verificationStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case accountType = "account_type"
        case verificationStatus = "verification_status"
    }
}

struct User: Decodable, Equatable {
    let id: Int
    let email: String
    let firstName: String?
    let lastName: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

private struct LoginResponse: Decodable {
    let token: String
    let user: User
    let account: Account
}

/// Who is signed in, and the token that proves it.
///
/// The token lives in the Keychain rather than UserDefaults. UserDefaults is a
/// plist in the app container: readable from a backup, and on a jailbroken or
/// shared phone readable outright. This token can accept jobs and move money.
@MainActor
final class Session: ObservableObject {

    @Published private(set) var account: Account?
    @Published private(set) var user: User?
    @Published private(set) var isRestoring = true
    @Published var signInError: String?
    @Published var isSigningIn = false

    var isSignedIn: Bool { account != nil }

    private let keychainAccount = "towsling.operator.token"

    // MARK: - Startup

    /// Called once when the app launches. If there is a stored token, prove it
    /// still works before showing the board — a token that expired while the
    /// app was closed would otherwise land an operator on an empty board with
    /// an error, which reads like "there is no work" rather than "sign in".
    func restore() async {
        defer { isRestoring = false }

        guard let token = Keychain.read(account: keychainAccount) else { return }
        await API.shared.setToken(token)

        do {
            let me = try await API.shared.get("/auth/me", as: MeResponse.self)
            account = me.account
            user = me.user
        } catch {
            // Anything at all wrong: drop it and show sign-in. A stale token is
            // worse than none, because every screen fails separately.
            await API.shared.setToken(nil)
            Keychain.delete(account: keychainAccount)
        }
    }

    private struct MeResponse: Decodable {
        let user: User
        let account: Account
    }

    // MARK: - Sign in / out

    func signIn(email: String, password: String) async {
        signInError = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let r = try await API.shared.post(
                "/auth/login",
                body: ["email": email, "password": password],
                as: LoginResponse.self
            )

            // This app is for towing companies. A provider account signing in
            // would get a board it cannot act on and buttons that 403 — say so
            // plainly instead, and do not keep the token.
            guard r.account.accountType == "tower" else {
                signInError = "That account is not a towing company. "
                            + "Use the website to sign in as a provider."
                return
            }

            Keychain.write(r.token, account: keychainAccount)
            await API.shared.setToken(r.token)
            account = r.account
            user = r.user
        } catch let e as APIError {
            signInError = e.message
        } catch {
            signInError = "Could not sign in. Try again."
        }
    }

    func signOut() async {
        // Tell the server, but do not wait on it to decide. If the network is
        // down the person in front of us still gets signed out of this phone,
        // which is the part they can see and the part that matters.
        try? await API.shared.postIgnoringResult("/auth/logout")
        await API.shared.setToken(nil)
        Keychain.delete(account: keychainAccount)
        account = nil
        user = nil
    }

    /// Called when any request comes back 401.
    func sessionExpired() async {
        await API.shared.setToken(nil)
        Keychain.delete(account: keychainAccount)
        account = nil
        user = nil
    }
}

/// The smallest Keychain wrapper that does the job. No dependency for four
/// calls, and no generic abstraction for one secret.
enum Keychain {
    private static let service = "com.towsling.operator"

    static func write(_ value: String, account: String) {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Never leaves this device and is unreadable until the phone has
            // been unlocked once since boot. A driver's phone gets lost.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
