import SwiftUI

// Small shared pieces for a calmer, safer app: an Undo toast after deletes and logs,
// a Settings button for every tab, and one place that keeps big pop-ups from stacking.

// MARK: - Undo toast

/// "Set deleted · Undo" at the bottom of the screen for a few seconds.
/// Call `UndoCenter.shared.show("Food deleted") { …put it back… }` right after a change.
@MainActor @Observable
final class UndoCenter {
    static let shared = UndoCenter()

    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let undo: (() -> Void)?
    }

    private(set) var item: Item?
    private var hideTask: Task<Void, Never>?

    /// Shows the toast. Pass `undo: nil` for a plain confirmation.
    func show(_ message: String, undo: (() -> Void)? = nil) {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            item = Item(message: message, undo: undo)
        }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func performUndo() {
        guard let undo = item?.undo else { return }
        Haptics.success()
        undo()
        dismiss()
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { item = nil }
    }
}

/// Attached once at the root (ContentView). Sits above the tab bar.
struct UndoToastHost: ViewModifier {
    private let center = UndoCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let item = center.item {
                HStack(spacing: 12) {
                    Text(item.message)
                        .font(.subheadline)
                        .foregroundStyle(Color.ppText)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if item.undo != nil {
                        Button("Undo") { center.performUndo() }
                            .font(.pixel(DS.TextSize.body, relativeTo: .subheadline))
                            .foregroundStyle(Color.brand)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .frame(minHeight: 52)
                .background(Color.ppCard, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.ppLine.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 96)   // clear of the tab bar and rest timer
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(item.id)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Undo") { center.performUndo() }
            }
        }
    }
}

extension View {
    func undoToasts() -> some View { modifier(UndoToastHost()) }
}

// MARK: - Settings from any tab

/// Gear button for a tab's toolbar that opens Settings.
struct SettingsToolbarButton: View {
    @State private var showing = false

    var body: some View {
        Button {
            Haptics.tap()
            showing = true
        } label: {
            Image.pixel(.gear)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showing) { SettingsView() }
    }
}

// MARK: - One big moment at a time

/// Keeps full-screen moments (workout summary, level up, gym bag) from stacking on top of each other.
/// A screen that shows one sets `isBusy` while it's up; others wait until it's false.
@MainActor @Observable
final class MomentQueue {
    static let shared = MomentQueue()
    /// True while a summary, level-up or bag reveal is on screen.
    var isBusy = false
}
