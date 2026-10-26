import SwiftUI

/// Privacy Policy and Terms of Use, readable inside the app.
/// Plain-language templates — have them checked before publishing on the App Store.
enum LegalDocument: String, Identifiable {
    case privacy, terms

    var id: String { rawValue }

    var title: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }

    /// Shown under the title.
    static let updated = "Last updated: 16 October 2026"

    /// Where people can reach you about privacy. Fill this in before publishing.
    static let contactEmail = ""

    struct Section: Identifiable {
        let heading: String
        let body: String
        var id: String { heading }
    }

    var sections: [Section] {
        switch self {
        case .privacy: return Self.privacySections
        case .terms: return Self.termsSections
        }
    }

    private static var contactLine: String {
        contactEmail.isEmpty ? "contact us through the App Store page for \(AppInfo.name)"
                             : "email us at \(contactEmail)"
    }

    private static let privacySections: [Section] = [
        Section(heading: "The short version",
                body: "An account is optional. Without one, everything you log stays on your iPhone. If you create one (with Apple, Google or email), we keep your email and name to sign you in. We don't collect, sell or share your personal data, and there are no ads or tracking."),
        Section(heading: "What the app stores on your iPhone",
                body: "Workouts and sets, your training plan, food and calories, body weight and measurements, goals, and the profile details you choose to enter (such as name, sex, birth date and height). It also stores your settings, your buddy's look and your game progress. This data is saved only in the app's private storage on your device and is protected by iOS."),
        Section(heading: "What leaves your iPhone",
                body: "Only one thing, and only when you ask for it: when you scan a barcode, the barcode number is sent to Open Food Facts (openfoodfacts.org), a free public food database, to look up the product. Like any website, they can see your device's IP address. Nothing else about you is sent. Their own privacy policy applies to that lookup.\n\nIf you open an exercise video, YouTube opens in your browser or the YouTube app, under Google's privacy policy."),
        Section(heading: "Apple Health",
                body: "If you turn it on, \(AppInfo.name) can read your body weight from Apple Health and save your workouts to it. You choose exactly what's allowed in the Health app, and you can change it at any time. Health data is never used for advertising and is never shared with anyone by \(AppInfo.name)."),
        Section(heading: "Backups and exports",
                body: "Backups and spreadsheet exports are files you create yourself. They contain your data, so keep them somewhere safe. Where they go (Files, iCloud Drive, email…) is up to you."),
        Section(heading: "Notifications, camera and alarms",
                body: "Notifications and alarms are used only for your rest timer. The camera is used only to scan barcodes; no photos or video are saved or sent anywhere."),
        Section(heading: "Deleting your data",
                body: "Settings → Privacy & data → Delete my data erases everything \(AppInfo.name) has stored on this iPhone, and can also remove the workouts \(AppInfo.name) saved to Apple Health. Deleting the app also removes all of its data from your iPhone."),
        Section(heading: "Your rights",
                body: "Because your data never reaches us, we don't hold any personal data about you. You stay in full control: you can view, export, correct or delete everything in the app at any time. If you live in the EU or UK, the GDPR gives you rights over your personal data; you can also contact your local data protection authority."),
        Section(heading: "Children",
                body: "\(AppInfo.name) is not directed at children under 16."),
        Section(heading: "Changes",
                body: "If this policy changes, the new version will appear here with a new date."),
        Section(heading: "Contact",
                body: "Questions about privacy? Please \(contactLine)."),
    ]

    private static let termsSections: [Section] = [
        Section(heading: "Welcome",
                body: "By using \(AppInfo.name) you agree to these terms. If you don't agree, please don't use the app."),
        Section(heading: "Not medical advice",
                body: "\(AppInfo.name) is a training and food log. Training plans, calorie and macro targets and all other suggestions are general estimates, not medical, nutritional or professional advice. Talk to a doctor before starting a new exercise programme or diet, especially if you have a health condition, an injury or are pregnant."),
        Section(heading: "Train safely",
                body: "Lifting weights carries a risk of injury. Use good form, warm up, use a spotter or safety equipment when needed, and stop if something hurts. You are responsible for how you train."),
        Section(heading: "Food information",
                body: "Food details found by barcode come from Open Food Facts, a community database. They may be incomplete or wrong — always check the label, especially for allergies."),
        Section(heading: "Your data",
                body: "Your data is stored on your device and belongs to you. Keeping backups is your responsibility; if you delete the app or your data without a backup, it can't be recovered. See the Privacy Policy for details."),
        Section(heading: "Using the app",
                body: "Use \(AppInfo.name) for your own personal, non-commercial use. Don't try to copy, resell, reverse engineer or misuse it. Apple's standard App Store licence (EULA) also applies."),
        Section(heading: "Game features",
                body: "XP, levels, missions, gym bags and buddy items are just for fun and motivation. They have no money value, can't be bought, sold or exchanged, and may change over time."),
        Section(heading: "No guarantees",
                body: "We work hard to make \(AppInfo.name) reliable, but it's provided \"as is\" and we can't promise it will always be error-free or available."),
        Section(heading: "Liability",
                body: "To the extent the law allows, we are not liable for injuries, health problems, lost data or other losses from using the app. Nothing in these terms limits rights you have under consumer law that can't be excluded."),
        Section(heading: "Changes",
                body: "We may update these terms. The new version will appear here with a new date; continuing to use the app means you accept it."),
        Section(heading: "Contact",
                body: "Questions? Please \(contactLine)."),
    ]
}

struct LegalView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(LegalDocument.updated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(.pixel(DS.TextSize.callout, relativeTo: .headline))
                            .foregroundStyle(Color.ppText)
                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(Color.ppText.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
