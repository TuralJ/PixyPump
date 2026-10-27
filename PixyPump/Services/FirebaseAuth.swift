import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

// The real accounts backend: Firebase Authentication. Used by `AuthStore` when Firebase is configured
// (see `FirebaseSetup`); builds without `GoogleService-Info.plist` keep using `MockAuthService`.
//
// Done so far: Google and Apple. The email link comes next.

@MainActor
final class FirebaseAuthService: AuthService {
    /// The person Firebase remembers from last time (Firebase keeps the session itself).
    var currentUser: AuthUser? {
        Auth.auth().currentUser.map(Self.authUser)
    }

    // MARK: Google

    func signInWithGoogle() async throws -> AuthUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.other("Google sign-in isn't set up in this build.")
        }
        guard let presenter = UIApplication.topViewController else {
            throw AuthError.other("Couldn't show Google sign-in. Try again.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch {
            throw Self.mapGoogle(error)
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.other("Google didn't return an account.")
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                       accessToken: result.user.accessToken.tokenString)
        return try await signIn(with: credential)
    }

    // MARK: Apple

    func signInWithApple(userID: String, identityToken: Data?, nonce: String?, fullName: PersonNameComponents?,
                         email: String?) async throws -> AuthUser {
        guard let token = identityToken.flatMap({ String(data: $0, encoding: .utf8) }), let nonce else {
            throw AuthError.other("Apple didn't return an account.")
        }
        let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: fullName)
        var user = try await signIn(with: credential)
        // Apple only shares the name on the very first sign-in, and Firebase doesn't keep it for us.
        if user.name == nil, let fullName,
           case let name = PersonNameComponentsFormatter().string(from: fullName), !name.isEmpty,
           let request = Auth.auth().currentUser?.createProfileChangeRequest() {
            request.displayName = name
            try? await request.commitChanges()
            user.name = name
        }
        return user
    }

    // MARK: Email link (next step)

    func sendEmailCode(to email: String) async throws {
        throw AuthError.other("Email sign-in is coming soon. Use Apple or Google for now.")
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthUser {
        throw AuthError.other("Email sign-in is coming soon. Use Apple or Google for now.")
    }

    // MARK: Session

    func signOut() async {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    func deleteAccount(_ user: AuthUser) async throws {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        do {
            if user.provider == .apple {
                // App Store rule: deleting the account also revokes the Apple sign-in. That needs a fresh
                // code from Apple, so ask once more (this also counts as the recent sign-in Firebase wants).
                let apple = try await AppleSignIn().run()
                guard let token = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                      let nonce = apple.nonce else { throw AuthError.other("Apple didn't return an account.") }
                let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce,
                                                               fullName: apple.fullName)
                try await firebaseUser.reauthenticate(with: credential)
                if let code = apple.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) {
                    // Needs the Apple key in Firebase (Authentication → Apple → OAuth code flow).
                    try? await Auth.auth().revokeToken(withAuthorizationCode: code)
                }
            }
            try await firebaseUser.delete()
        } catch let error as NSError where error.domain == AuthErrorDomain
                    && error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            // Firebase only deletes after a fresh sign-in. Ask Google again, then retry.
            guard user.provider == .google else { throw Self.map(error) }
            _ = try await signInWithGoogle()
            try await Auth.auth().currentUser?.delete()
        } catch {
            throw Self.map(error)
        }
        GIDSignIn.sharedInstance.signOut()
    }

    /// Google's redirect back into the app. Returns true if it was ours.
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: Helpers

    private func signIn(with credential: AuthCredential) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().signIn(with: credential)
            return Self.authUser(result.user)
        } catch {
            throw Self.map(error)
        }
    }

    private static func authUser(_ user: User) -> AuthUser {
        let provider: AuthProvider = user.providerData.contains { $0.providerID == "apple.com" } ? .apple
            : user.providerData.contains { $0.providerID == "google.com" } ? .google
            : .email
        return AuthUser(id: user.uid, name: user.displayName, email: user.email, provider: provider,
                        createdAt: user.metadata.creationDate ?? .now)
    }

    private static func mapGoogle(_ error: Error) -> Error {
        if (error as NSError).domain == kGIDSignInErrorDomain,
           (error as NSError).code == GIDSignInError.canceled.rawValue {
            return AuthError.cancelled
        }
        return map(error)
    }

    private static func map(_ error: Error) -> Error {
        let error = error as NSError
        guard error.domain == AuthErrorDomain else { return error }
        switch AuthErrorCode(rawValue: error.code) {
        case .networkError: return AuthError.network
        case .accountExistsWithDifferentCredential:
            return AuthError.other("You already have an account with this email. Sign in the way you did before.")
        default: return AuthError.other(error.localizedDescription)
        }
    }
}

extension UIApplication {
    /// The screen currently on top, for SDKs that present their own sheets.
    static var topViewController: UIViewController? {
        var top = shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
