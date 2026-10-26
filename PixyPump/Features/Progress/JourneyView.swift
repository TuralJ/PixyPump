import SwiftUI
import SwiftData

/// The long road: chapters of workouts, each ending in a boss you beat by finishing
/// every set. Finishing a chapter pays XP and unlocks a backdrop for your buddy.
struct JourneyView: View {
    @Query(sort: \WorkoutSet.date) private var allSets: [WorkoutSet]

    private let rowHeight: CGFloat = 76
    /// Zig-zag offsets for the path (as a fraction of the half-width).
    private let wiggle: [CGFloat] = [0, 0.45, 0.7, 0.45, 0, -0.45, -0.7, -0.45]

    var body: some View {
        let progress = GameStats(allSets: allSets).journey
        // Show everything you've done, the current chapter, and one to look forward to.
        let chapters = Array(1...(progress.chapter + 1))
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    intro
                    ForEach(chapters, id: \.self) { number in
                        chapterView(Journey.chapter(number), progress: progress)
                            .id(number)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(progress.chapter, anchor: .top) }
        }
        .background(AppBackground())
        .navigationTitle("Journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        Text("Every workout moves your buddy one step. The last step of each chapter is a boss: beat it by finishing every set.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func chapterView(_ chapter: JourneyChapter, progress: Journey.Progress) -> some View {
        let state: ChapterState = chapter.number < progress.chapter ? .done
            : chapter.number == progress.chapter ? .current : .locked
        let doneSteps = state == .done ? chapter.nodes : state == .current ? progress.step : 0
        return VStack(spacing: 14) {
            // Banner with the reward.
            HStack(spacing: 12) {
                ZStack {
                    if let backdrop = chapter.backdrop {
                        BuddyBackdrop(id: backdrop, cornerRadius: 10)
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.xs).fill(Color.ppLine.opacity(0.08))
                        Image.pixel(.star, size: 20).foregroundStyle(Color.ppFat)
                    }
                }
                .frame(width: 52, height: 52)
                .opacity(state == .locked ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHAPTER \(chapter.number)")
                        .font(.pixel(DS.TextSize.caption, relativeTo: .caption))
                        .foregroundStyle(state == .done ? Color.ppDone : Color.brand)
                    Text(chapter.name)
                        .font(.pixel(DS.TextSize.headline, relativeTo: .headline))
                        .foregroundStyle(state == .locked ? .secondary : Color.ppText)
                    Text(rewardText(chapter, state: state))
                        .font(.caption)
                        .foregroundStyle(state == .done ? Color.ppDone : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glassCard(cornerRadius: DS.Radius.tile)

            // The path.
            GeometryReader { geo in
                let points = (0..<chapter.nodes).map { point($0, width: geo.size.width) }
                ZStack {
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for p in points.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(Color.ppLine.opacity(0.15), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 8]))

                    ForEach(0..<chapter.nodes, id: \.self) { i in
                        node(index: i, chapter: chapter, done: i < doneSteps,
                             here: state == .current && i == progress.step)
                            .position(points[i])
                    }
                }
            }
            .frame(height: CGFloat(chapter.nodes) * rowHeight)
        }
    }

    private enum ChapterState { case done, current, locked }

    private func rewardText(_ chapter: JourneyChapter, state: ChapterState) -> String {
        let item = chapter.backdrop.map { MascotOptions.find($0, in: MascotOptions.backdrops).name + " backdrop · " } ?? ""
        switch state {
        case .done: return "Complete · \(item)+\(chapter.rewardXP) XP earned"
        case .current, .locked: return "Reward: \(item)+\(chapter.rewardXP) XP"
        }
    }

    private func point(_ i: Int, width: CGFloat) -> CGPoint {
        let half = (width - 80) / 2
        return CGPoint(x: width / 2 + wiggle[i % wiggle.count] * half,
                       y: CGFloat(i) * rowHeight + rowHeight / 2)
    }

    @ViewBuilder
    private func node(index: Int, chapter: JourneyChapter, done: Bool, here: Bool) -> some View {
        let boss = index == chapter.nodes - 1
        let size: CGFloat = boss ? 56 : 42
        ZStack {
            Circle()
                .fill(done ? Color.ppDone : (here ? Color.brand : Color.ppCard))
            Circle()
                .strokeBorder(boss ? Color.ppFat : Color.ppLine.opacity(done || here ? 0 : 0.2), lineWidth: boss ? 3 : 2)
            if boss {
                Image.pixel(.trophy, size: 24)
                    .foregroundStyle(done ? Color.ppBackground : Color.ppFat)
            } else if done {
                Image.pixel(.check, size: 16).foregroundStyle(Color.ppBackground)
            } else {
                Text("\(index + 1)")
                    .font(.pixel(DS.TextSize.footnote))
                    .foregroundStyle(here ? Color.ppBackground : .secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) {
            if here {
                // Your buddy stands on the step you're on.
                PixelBuddy(mood: .idle, size: 56)
                    .offset(y: -50)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            if boss && !done {
                Text("BOSS")
                    .font(.pixel(DS.TextSize.caption, relativeTo: .caption2))
                    .foregroundStyle(Color.ppFat)
                    .fixedSize()
                    .offset(x: 44)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(boss ? "Boss step\(done ? ", beaten" : "")" : "Step \(index + 1)\(done ? ", done" : "")")
    }
}
