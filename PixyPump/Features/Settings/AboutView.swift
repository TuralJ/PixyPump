import SwiftUI

/// Version, privacy and credits for the font, icons and food data.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image.pixel(.dumbbell, size: 48)
                        .foregroundStyle(Color.brand)
                    Text(AppInfo.name)
                        .font(.pixel(DS.TextSize.largeTitle, relativeTo: .largeTitle))
                        .foregroundStyle(Color.ppText)
                    Text(version)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("Everything you log stays on this iPhone. An account is optional, and there are no ads and no tracking.\n\nWhen you scan a barcode, only the barcode number is sent to Open Food Facts to look up the product.")
                    .font(.subheadline)
            } header: {
                PPHeader("Privacy")
            }
            .listRowBackground(Color.ppCard)

            Section {
                credit(title: "Food data: Open Food Facts",
                       detail: "Product data © Open Food Facts contributors, available under the Open Database License (ODbL).",
                       link: "https://world.openfoodfacts.org")
                credit(title: "Font: Geist Pixel",
                       detail: "By Vercel in collaboration with basement.studio. SIL Open Font License 1.1.",
                       link: "https://vercel.com/font")
                credit(title: "Icons: Pixelarticons",
                       detail: "By Gerrit Halfmann. MIT License. Dumbbell and fork-and-knife drawn for \(AppInfo.name).",
                       link: "https://pixelarticons.com")
            } header: {
                PPHeader("Credits")
            } footer: {
                Text("Calorie suggestions use the Mifflin–St Jeor formula and are estimates, not medical advice.")
            }
            .listRowBackground(Color.ppCard)
        }
        .ppScreen()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(title: String, detail: String, link: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            if let url = URL(string: link) {
                Link(link.replacingOccurrences(of: "https://", with: ""), destination: url)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }
}
