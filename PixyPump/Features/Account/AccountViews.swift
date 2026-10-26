import SwiftUI
import SwiftData

// Screens for the optional account: the sign-in buttons, the "Save your progress"
// screen, the email-code sheet, the Home reminder card and Settings → Account.

// MARK: - The three buttons

/// Apple, Google, Email — the same buttons sign up and sign in.
struct SignInButtons: View {
    /// Called once someone is signed in.
    var onSignedIn: () -> Void = {}

    @State private var busy: AuthProvider?
    @State private var error: String?
    @State private var emailSheet = false
    private let auth = AuthStore.shared

    var body: some View {
        VStack(spacing: 12) {
            // Apple's standard look: black button, Apple logo.
            Button { run(.apple) { try await auth.signInWithApple() } } label: {
                label(busy == .apple, icon: Image(systemName: "applelogo"), text: "Continue with Apple")
                    .foregroundStyle(.white)
                    .background(Color.black, in: Capsule())   // ds-allow: Apple sign-in button guideline
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
            .accessibilityLabel("Continue with Apple")

            // Google's look: white button, coloured G.
            Button { run(.google) { try await auth.signInWithGoogle() } } label: {
                label(busy == .google, icon: GoogleG().frame(width: 18, height: 18), text: "Continue with Google")
                    .foregroundStyle(Color(hex: 0x1F1F1F))   // ds-allow: Google sign-in button guideline
                    .background(Color.white, in: Capsule())   // ds-allow: Google sign-in button guideline
            }
            .accessibilityLabel("Continue with Google")

            Button {
                Haptics.tap()
                emailSheet = true
            } label: {
                label(false, icon: Image(systemName: "envelope.fill"), text: "Continue with email")
                    .foregroundStyle(Color.ppText)
                    .background(Color.ppLine.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.ppLine.opacity(0.18), lineWidth: 1))
            }
            .accessibilityLabel("Continue with email")

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.ppFlame)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .buttonStyle(.squish)
        .disabled(busy != nil)
        .sheet(isPresented: $emailSheet) {
            EmailCodeSheet { onSignedIn() }
        }
    }

    private func label<Icon: View>(_ loading: Bool, icon: Icon, text: String) -> some View {
        HStack(spacing: 10) {
            if loading {
                ProgressView().tint(.gray)
            } else {
                icon
            }
            Text(text).font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Capsule())
    }

    private func run(_ provider: AuthProvider, _ action: @escaping () async throws -> Void) {
        Haptics.tap()
        error = nil
        busy = provider
        Task {
            do {
                try await action()
                busy = nil
                onSignedIn()
            } catch AuthError.cancelled {
                busy = nil           // closed the Apple sheet: no error to show
            } catch {
                busy = nil
                withAnimation { self.error = error.localizedDescription }
            }
        }
    }
}

/// Google's four-colour "G", drawn so no image file is needed.
private struct GoogleG: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let line = r * 0.42
            func arc(_ from: Double, _ to: Double, _ hex: UInt32) {
                var p = Path()
                p.addArc(center: center, radius: r - line / 2, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                context.stroke(p, with: .color(Color(hex: hex)), lineWidth: line)
            }
            arc(-40, 45, 0x4285F4)    // blue (right)
            arc(45, 135, 0x34A853)    // green (bottom)
            arc(135, 200, 0xFBBC05)   // yellow (left-bottom)
            arc(200, 320, 0xEA4335)   // red (top)
            // The bar of the G.
            context.fill(Path(CGRect(x: center.x, y: center.y - line / 2, width: r, height: line)),
                         with: .color(Color(hex: 0x4285F4)))   // ds-allow: Google logo colour
        }
        .accessibilityHidden(true)
    }
}

// MARK: - "Save your progress"

/// The account screen: shown in onboarding, from the Home card and from Settings.
struct SaveProgressView: View {
    /// Shown in onboarding (no close button, the flow has its own buttons).
    var embedded = false
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                PixelBuddy(mood: .idle, size: 72, action: .wave, backdrop: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save your progress")
                        .font(.pixel(DS.TextSize.title, relativeTo: .title))
                        .foregroundStyle(Color.ppText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Free, and takes a few seconds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                perk("🔥", "Keep your streak, XP and buddy safe")
                perk("📱", "Pick up where you left off on a new phone")
                perk("🔒", "Your workouts stay private")
            }

            SignInButtons {
                onDone()
                if !embedded { dismiss() }
            }

            Text("By continuing you agree to our Terms of Use and Privacy Policy. Everything already on this iPhone is kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if AuthStore.shared.isMock {
                Text("Demo mode: no server yet, so sign-in is simulated on this phone.")
                    .font(.caption2)
                    .foregroundStyle(Color.ppFat)
            }
        }
    }

    private func perk(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.title3)
            Text(text).font(.callout).foregroundStyle(Color.ppText)
        }
    }
}

/// `SaveProgressView` in its own sheet, with a "Not now" close.
struct SaveProgressSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SaveProgressView()
                    .padding(24)
            }
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Email code

/// Enter email → get a 6-digit code → done. No passwords to remember or reset.
struct EmailCodeSheet: View {
    var onSignedIn: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool
    private let auth = AuthStore.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(codeSent ? "Check your email" : "What's your email?")
                    .font(.pixel(DS.TextSize.title2, relativeTo: .title2))
                    .foregroundStyle(Color.ppText)
                Text(codeSent
                     ? "We sent a 6-digit code to \(email). Enter it below."
                     : "We'll send you a code. New here? This creates your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if codeSent {
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.pixel(DS.TextSize.title, relativeTo: .title))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .background(Color.ppLine.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.m))
                        .focused($focused)
                        .onChange(of: code) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(6))
                            if digits != new { code = digits; return }   // runs again with the cleaned value
                            if digits.count == 6 { verify() }
                        }
                    if auth.isMock {
                        Text("Demo code: \(AuthConfig.mockEmailCode)")
                            .font(.caption)
                            .foregroundStyle(Color.ppFat)
                    }
                } else {
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.ppLine.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.m))
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Color.ppFlame)
                }

                Button(action: codeSent ? verify : send) {
                    if busy { ProgressView() } else { Text(codeSent ? "Continue" : "Send code") }
                }
                .buttonStyle(.primary)
                .disabled(busy || (codeSent ? code.count < 6 : email.isEmpty))

                if codeSent {
                    HStack {
                        Button("Change email") {
                            codeSent = false
                            code = ""
                            error = nil
                        }
                        Spacer()
                        Button("Send again", action: send)
                    }
                    .font(.footnote)
                    .frame(minHeight: 44)
                }
                Spacer()
            }
            .padding(24)
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func send() {
        error = nil
        busy = true
        Task {
            do {
                try await auth.sendEmailCode(to: email)
                withAnimation { codeSent = true }
                focused = true
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func verify() {
        guard !busy else { return }
        error = nil
        busy = true
        Task {
            do {
                try await auth.verifyEmailCode(code, email: email)
                busy = false
                onSignedIn()
                dismiss()
            } catch {
                busy = false
                code = ""
                self.error = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

// MARK: - Home reminder

/// "Don't lose your progress" — once you've trained or built a streak, until you sign in or close it.
struct SaveProgressCard: View {
    let streak: Int
    @AppStorage(AuthStore.nudgeDismissedKey) private var dismissed = false
    @State private var showing = false

    var body: some View {
        HStack(spacing: 14) {
            Text("💾").font(.system(size: 30))   // ds-allow: emoji size
            VStack(alignment: .leading, spacing: 4) {
                Text(streak >= 3 ? "Don't lose your \(streak)-day 🔥 streak" : "Don't lose your progress")
                    .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                    .foregroundStyle(Color.ppText)
                Text("Create a free account to keep your workouts, XP and buddy safe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    showing = true
                } label: {
                    Text("Save my progress")
                        .font(.pixel(DS.TextSize.footnote))
                        .foregroundStyle(Color.ppOnAccent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.squish)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: DS.Radius.card)
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                withAnimation { dismissed = true }
            } label: {
                Image.pixel(.close, size: 14)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .sheet(isPresented: $showing) { SaveProgressSheet() }
    }
}

// MARK: - Settings → Account

struct AccountSection: View {
    @Environment(\.modelContext) private var context
    @State private var showingSignIn = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var message: String?
    private let auth = AuthStore.shared

    var body: some View {
        Section {
            if let user = auth.user {
                HStack(spacing: 12) {
                    PixelBuddy(size: 36, animated: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name ?? user.email ?? "Signed in")
                            .foregroundStyle(Color.ppText)
                        Text("Signed in with \(user.provider.title)" + (user.name != nil ? " · \(user.email ?? "")" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 44)
                Button("Sign out") { confirmSignOut = true }
                Button("Delete account", role: .destructive) { confirmDelete = true }
                    .disabled(busy)
            } else {
                Button {
                    Haptics.tap()
                    showingSignIn = true
                } label: {
                    HStack(spacing: 12) {
                        Text("💾").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create account or sign in").foregroundStyle(Color.ppText)
                            Text("Apple, Google or email. Free.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            PPHeader("Account")
        } footer: {
            Text(auth.isSignedIn
                 ? "Signing out keeps everything on this iPhone."
                 : "Optional. \(AppInfo.name) works fully without an account.")
        }
        .listRowBackground(Color.ppCard)
        .sheet(isPresented: $showingSignIn) { SaveProgressSheet() }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out") {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your workouts stay on this iPhone.")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { delete(alsoPhoneData: false) }
            Button("Delete account and data on this iPhone", role: .destructive) { delete(alsoPhoneData: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and anything saved with it are removed. This can't be undone.")
        }
        .alert("Account", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func delete(alsoPhoneData: Bool) {
        busy = true
        Task {
            do {
                try await auth.deleteAccount()
                if alsoPhoneData { DataTools.deleteEverything(context: context) }
                Haptics.warning()
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}
