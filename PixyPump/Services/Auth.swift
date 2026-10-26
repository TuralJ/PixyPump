import Foundation
import AuthenticationServices
import UIKit

// Accounts: optional, "save your progress" style. The app keeps working without one,
// and signing in never touches the workouts already on this iPhone.
//
// All screens talk to `AuthStore`, which talks to an `AuthService`.
// Today that's `MockAuthService` (works fully offline, for building and testing).
// To connect a backend later (Supabase, Firebase or your own), write a type that
// conforms to `AuthService` and set it in `AuthStore.init` — no screen changes needed.

// MARK: - Settings you flip when the backend is ready

nonisolated enum AuthConfig {
    /// Use the real "Sign in with Apple" sheet. Needs the "Sign in with Apple" capability
    /// in Xcode (target → Signing & Capabilities) and a paid developer account.
    /// While false, the Apple button signs in a pretend Apple user so you can test the flow.
    static let realAppleSignIn = false

    /// The code the pretend email sign-in accepts (shown on screen while mocking).
    static let mockEmailCode = "123456"
}

// MARK: - Model

nonisolated enum AuthProvider: String, Codable, Sendable {
    case apple, google, email

    var title: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        }
    }
}

/// The signed-in person. (Secrets like tokens belong in the Keychain once there's a real backend.)
nonisolated struct AuthUser: Codable, Equatable, Sendable {
    var id: String
    var name: String?
    var email: String?
    var provider: AuthProvider
    var createdAt: Date
}

nonisolated enum AuthError: LocalizedError, Sendable {
    case cancelled
    case invalidEmail
    case wrongCode
    case appleNotSetUp
    case network
    case other(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .invalidEmail: return "That doesn't look like an email address."
        case .wrongCode: return "That code isn't right. Check the email and try again."
        case .appleNotSetUp: return "Sign in with Apple isn't switched on for this build yet."
        case .network: return "Couldn't reach the server. Check your connection and try again."
        case .other(let message): return message
        }
    }
}

// MARK: - The plug for your backend

@MainActor
protocol AuthService {
    /// Apple has already said yes on the phone; send its token to your backend.
    func signInWithApple(userID: String, identityToken: Data?, fullName: PersonNameComponents?,
                         email: String?) async throws -> AuthUser
    /// Google sign-in (Google's SDK or your backend's OAuth).
    func signInWithGoogle() async throws -> AuthUser
    /// Emails a 6-digit code. Same call for new and returning people.
    func sendEmailCode(to email: String) async throws
    /// Checks the code; creates the account if it's new.
    func verifyEmailCode(_ code: String, email: String) async throws -> AuthUser
    func signOut() async
    /// Deletes the account on the server (App Store rule: must be possible in the app).
    func deleteAccount(_ user: AuthUser) async throws
}

/// Pretend backend: everything works, nothing leaves the phone.
@MainActor
final class MockAuthService: AuthService {
    private func pause() async { try? await Task.sleep(for: .milliseconds(700)) }

    func signInWithApple(userID: String, identityToken: Data?, fullName: PersonNameComponents?,
                         email: String?) async throws -> AuthUser {
        await pause()
        let name = fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
        return AuthUser(id: "apple-\(userID)", name: (name?.isEmpty ?? true) ? nil : name,
                        email: email ?? "you@privaterelay.appleid.com", provider: .apple, createdAt: .now)
    }

    func signInWithGoogle() async throws -> AuthUser {
        await pause()
        return AuthUser(id: "google-demo", name: nil, email: "you@gmail.com", provider: .google, createdAt: .now)
    }

    func sendEmailCode(to email: String) async throws {
        await pause()
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthUser {
        await pause()
        guard code == AuthConfig.mockEmailCode else { throw AuthError.wrongCode }
        return AuthUser(id: "email-\(email.lowercased())", name: nil, email: email, provider: .email, createdAt: .now)
    }

    func signOut() async {}

    func deleteAccount(_ user: AuthUser) async throws {
        await pause()
    }
}

// MARK: - Store used by the screens

@MainActor @Observable
final class AuthStore {
    static let shared = AuthStore()
    private static let userKey = "auth.user.v1"
    /// "Save your progress" card on Home was closed.
    nonisolated static let nudgeDismissedKey = "auth.nudgeDismissed"

    private(set) var user: AuthUser? {
        didSet { save() }
    }
    /// Swap this for your real backend.
    private let service: AuthService

    var isSignedIn: Bool { user != nil }
    var isMock: Bool { service is MockAuthService }

    private init() {
        service = MockAuthService()
        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(AuthUser.self, from: data)
        }
    }

    private func save() {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.userKey)
        }
    }

    // Sign in (sign up is the same thing: a new account is made on first sign-in).

    func signInWithApple() async throws {
        if AuthConfig.realAppleSignIn {
            let credential = try await AppleSignIn().run()
            user = try await service.signInWithApple(userID: credential.user, identityToken: credential.identityToken,
                                                     fullName: credential.fullName, email: credential.email)
        } else {
            user = try await service.signInWithApple(userID: "demo", identityToken: nil, fullName: nil, email: nil)
        }
        didSignIn()
    }

    func signInWithGoogle() async throws {
        user = try await service.signInWithGoogle()
        didSignIn()
    }

    func sendEmailCode(to email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmail(trimmed) else { throw AuthError.invalidEmail }
        try await service.sendEmailCode(to: trimmed)
    }

    func verifyEmailCode(_ code: String, email: String) async throws {
        user = try await service.verifyEmailCode(code.trimmingCharacters(in: .whitespaces),
                                                 email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        didSignIn()
    }

    func signOut() async {
        await service.signOut()
        user = nil
    }

    func deleteAccount() async throws {
        guard let user else { return }
        try await service.deleteAccount(user)
        self.user = nil
    }

    private func didSignIn() {
        UserDefaults.standard.set(true, forKey: Self.nudgeDismissedKey)
        Haptics.success()
    }

    static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty && !text.contains(" ")
    }
}

// MARK: - Real Sign in with Apple (used when AuthConfig.realAppleSignIn is on)

/// What we need from Apple's answer, copied out so it can cross actors safely.
private nonisolated struct AppleCredential: Sendable {
    var user: String
    var identityToken: Data?
    var fullName: PersonNameComponents?
    var email: String?
}

@MainActor
private final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate,
                                 ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    /// Held until Apple answers (the controller doesn't keep itself alive; `self` stays alive
    /// because the caller is awaiting `run()`).
    private var controller: ASAuthorizationController?

    func run() async throws -> AppleCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let result: Result<AppleCredential, Error>
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            result = .success(AppleCredential(user: credential.user, identityToken: credential.identityToken,
                                              fullName: credential.fullName, email: credential.email))
        } else {
            result = .failure(AuthError.other("Apple didn't return an account."))
        }
        Task { @MainActor in self.finish(result) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as? ASAuthorizationError)?.code
        let mapped: Error = code == .canceled ? AuthError.cancelled
            : (code == .unknown ? AuthError.appleNotSetUp : error)
        Task { @MainActor in self.finish(.failure(mapped)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
