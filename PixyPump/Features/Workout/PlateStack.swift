import SwiftUI
import UIKit

// Plate Stack: a little falling-blocks puzzle to play while you rest.
// Our own game (own name, board size and pixel style) — it pauses itself when your rest ends.

@MainActor @Observable
final class StackGame {
    static let cols = 9
    static let rows = 16
    private static let bestKey = "plateStackBest"

    nonisolated struct Cell: Hashable, Sendable {
        var x: Int
        var y: Int
    }

    nonisolated struct Piece: Sendable {
        var kind: Int          // 1…7 (colour too)
        var cells: [Cell]      // inside its box
        var box: Int           // 2, 3 or 4 (for rotating)
        var x: Int
        var y: Int

        var placed: [Cell] { cells.map { Cell(x: $0.x + x, y: $0.y + y) } }
    }

    /// 0 = empty, otherwise the piece kind that landed there.
    private(set) var board: [[Int]] = Array(repeating: Array(repeating: 0, count: StackGame.cols), count: StackGame.rows)
    private(set) var piece: Piece
    private(set) var nextKind: Int
    private(set) var score = 0
    private(set) var lines = 0
    private(set) var isOver = false
    /// This game beat the old best.
    private(set) var isNewBest = false
    var isPaused = false
    private(set) var best = UserDefaults.standard.integer(forKey: StackGame.bestKey)
    /// Rows that just cleared (for a quick flash).
    private(set) var flashRows: Set<Int> = []

    var level: Int { lines / 8 + 1 }
    /// Seconds per step down: speeds up every 8 lines.
    var interval: Double { max(0.12, 0.75 - Double(level - 1) * 0.06) }

    private var bag: [Int] = []
    /// Touched down: one more gravity step to slide or turn before it locks.
    private var landing = false
    /// Moves that bought more time on the ground (capped so a piece can't hover forever).
    private var lockResets = 0

    init() {
        piece = Piece(kind: 1, cells: [], box: 4, x: 0, y: 0)
        nextKind = 1
        restart()
    }

    func restart() {
        board = Array(repeating: Array(repeating: 0, count: Self.cols), count: Self.rows)
        score = 0
        lines = 0
        isOver = false
        isNewBest = false
        isPaused = false
        bag = []
        nextKind = drawKind()
        spawn()
    }

    // MARK: Shapes

    private static func shape(_ kind: Int) -> (cells: [Cell], box: Int) {
        func c(_ pairs: [(Int, Int)]) -> [Cell] { pairs.map { Cell(x: $0.0, y: $0.1) } }
        switch kind {
        case 1: return (c([(0, 1), (1, 1), (2, 1), (3, 1)]), 4)   // long bar
        case 2: return (c([(0, 0), (1, 0), (0, 1), (1, 1)]), 2)   // square
        case 3: return (c([(1, 0), (0, 1), (1, 1), (2, 1)]), 3)
        case 4: return (c([(1, 0), (2, 0), (0, 1), (1, 1)]), 3)
        case 5: return (c([(0, 0), (1, 0), (1, 1), (2, 1)]), 3)
        case 6: return (c([(0, 0), (0, 1), (1, 1), (2, 1)]), 3)
        default: return (c([(2, 0), (0, 1), (1, 1), (2, 1)]), 3)
        }
    }

    /// Shuffled bag of all seven, so no long droughts of one piece.
    private func drawKind() -> Int {
        if bag.isEmpty { bag = Array(1...7).shuffled() }
        return bag.removeLast()
    }

    private func spawn() {
        let s = Self.shape(nextKind)
        piece = Piece(kind: nextKind, cells: s.cells, box: s.box, x: (Self.cols - s.box) / 2, y: 0)
        nextKind = drawKind()
        landing = false
        lockResets = 0
        if !fits(piece.placed) { endGame() }
    }

    private func fits(_ cells: [Cell]) -> Bool {
        cells.allSatisfy { $0.x >= 0 && $0.x < Self.cols && $0.y >= 0 && $0.y < Self.rows && board[$0.y][$0.x] == 0 }
    }

    // MARK: Moves

    var canPlay: Bool { !isOver && !isPaused }

    @discardableResult
    func move(_ dx: Int) -> Bool {
        guard canPlay else { return false }
        var p = piece
        p.x += dx
        guard fits(p.placed) else { return false }
        piece = p
        groundedMoveMade()
        return true
    }

    /// Moving or turning on the ground gives you a little more time (like real block games).
    private func groundedMoveMade() {
        guard landing, lockResets < 15 else { return }
        lockResets += 1
        landing = false
    }

    func rotate() {
        guard canPlay, piece.kind != 2 else { return }
        var p = piece
        p.cells = piece.cells.map { Cell(x: piece.box - 1 - $0.y, y: $0.x) }
        // Nudge sideways if the turn hits a wall or a block.
        for kick in [0, -1, 1, -2, 2] {
            var tried = p
            tried.x += kick
            if fits(tried.placed) {
                piece = tried
                groundedMoveMade()
                return
            }
        }
    }

    /// One step down. On the ground it waits one step first, so you can still slide it into a gap.
    func tick() {
        guard canPlay else { return }
        var p = piece
        p.y += 1
        if fits(p.placed) {
            piece = p
            landing = false
        } else if !landing {
            landing = true
        } else {
            lock()
        }
    }

    /// One row down (never locks, so holding ▼ can't drop it somewhere by accident).
    func softDrop() {
        guard canPlay else { return }
        var p = piece
        p.y += 1
        guard fits(p.placed) else { return }
        piece = p
        landing = false   // it's falling again (e.g. slid off a ledge), so it gets its grace step back
        score += 1
    }

    func hardDrop() {
        guard canPlay else { return }
        var p = piece
        var steps = 0
        while true {
            var lower = p
            lower.y += 1
            if fits(lower.placed) { p = lower; steps += 1 } else { break }
        }
        piece = p
        score += steps * 2
        lock()
    }

    /// Where the piece would land (shown faintly).
    var ghost: [Cell] {
        var p = piece
        while true {
            var lower = p
            lower.y += 1
            if fits(lower.placed) { p = lower } else { break }
        }
        return p.placed
    }

    // MARK: Landing and clearing

    /// Called with how many rows cleared (for sounds and buzzes).
    @ObservationIgnored var onClear: (Int) -> Void = { _ in }
    @ObservationIgnored var onGameOver: () -> Void = {}

    private func lock() {
        for cell in piece.placed where cell.y >= 0 && cell.y < Self.rows {
            board[cell.y][cell.x] = piece.kind
        }
        let full = (0..<Self.rows).filter { y in board[y].allSatisfy { $0 != 0 } }
        if !full.isEmpty {
            flashRows = Set(full)
            board.removeAll { row in row.allSatisfy { $0 != 0 } }
            board.insert(contentsOf: Array(repeating: Array(repeating: 0, count: Self.cols), count: full.count), at: 0)
            let points = [0, 100, 300, 500, 800][min(full.count, 4)]
            score += points * level
            lines += full.count
            onClear(full.count)
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                flashRows = []
            }
        }
        spawn()
    }

    private func endGame() {
        isOver = true
        if score > best {
            isNewBest = true
            best = score
            UserDefaults.standard.set(best, forKey: Self.bestKey)
        }
        onGameOver()
    }
}

// MARK: - Screen

/// Opened from the rest timer bar. Pauses itself when your rest is over.
struct PlateStackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var game = StackGame()
    @State private var restOver = false
    /// Board drag: which way it's going (decided after a few points), and how far we've acted on.
    @State private var dragAxis: Axis?
    @State private var usedX: CGFloat = 0
    @State private var usedY: CGFloat = 0
    private let timer = RestTimer.shared

    var body: some View {
        VStack(spacing: 14) {
            header
            hud
            board
                .overlay { overlays }
            controls
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppBackground())
        .task {
            game.onClear = { rows in
                if rows >= 4 {
                    Haptics.success()
                    SFX.play(.record)
                } else {
                    Self.impact(.medium)
                    SFX.play(.duelWon)
                }
            }
            game.onGameOver = { Haptics.warning() }
            // Gravity.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(game.interval))
                game.tick()
            }
        }
        // Rest's over (timer ran out or was stopped): pause and send you back to your set.
        .onChange(of: timer.endDate) { old, new in
            if old != nil, new == nil, !game.isOver {
                game.isPaused = true
                restOver = true
            }
        }
        // Don't let pieces fall while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !game.isOver { game.isPaused = true }
            else if phase == .active, !restOver { game.isPaused = false }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PLATE STACK")
                    .font(.pixel(DS.TextSize.title3, relativeTo: .title3))
                    .foregroundStyle(Color.ppText)
                Text("Drag to move · Tap to turn · Flick down to drop")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            restPill
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image.pixel(.close, size: 16)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close game")
        }
    }

    @ViewBuilder
    private var restPill: some View {
        if let end = timer.endDate {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(end.timeIntervalSince(context.date).rounded(.up)))
                HStack(spacing: 6) {
                    Image.pixel(.clock, size: 14)
                    Text(RestTimerBar.format(left)).font(.pixel(DS.TextSize.subhead)).monospacedDigit()
                }
                .foregroundStyle(left <= 10 ? Color.ppFlame : Color.ppText)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(Color.ppLine.opacity(0.08), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rest left: \(RestTimerBar.format(left))")
            }
        } else if timer.isRinging {
            Text("Rest's over 💪")
                .font(.pixel(DS.TextSize.footnote, relativeTo: .footnote))
                .foregroundStyle(Color.ppDone)
        }
    }

    private var hud: some View {
        HStack(spacing: 10) {
            stat("SCORE", game.score.spaced)
            stat("LINES", "\(game.lines)")
            stat("BEST", max(game.best, game.score).spaced)
            VStack(spacing: 4) {
                Text("NEXT").font(.pixel(DS.TextSize.caption, relativeTo: .caption2)).foregroundStyle(.secondary)
                PiecePreview(kind: game.nextKind)
                    .frame(width: 44, height: 28)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .glassCard(cornerRadius: DS.Radius.m)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.pixel(DS.TextSize.caption, relativeTo: .caption2)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.pixel(DS.TextSize.callout)).foregroundStyle(Color.ppText).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var board: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(StackGame.cols), geo.size.height / CGFloat(StackGame.rows))
            let width = cell * CGFloat(StackGame.cols)
            let height = cell * CGFloat(StackGame.rows)
            // Read the game here so SwiftUI redraws when it changes.
            let grid = game.board
            let flash = game.flashRows
            let over = game.isOver
            let falling = game.piece
            let ghost = game.ghost
            Canvas { context, _ in
                // Background grid.
                context.fill(Path(CGRect(x: 0, y: 0, width: width, height: height)), with: .color(Color.ppCard))
                for x in 1..<StackGame.cols {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: 0, width: 0.5, height: height)),
                                 with: .color(Color.ppLine.opacity(0.04)))
                }
                for y in 1..<StackGame.rows {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(y) * cell, width: width, height: 0.5)),
                                 with: .color(Color.ppLine.opacity(0.04)))
                }
                // Landed blocks.
                for y in 0..<StackGame.rows {
                    for x in 0..<StackGame.cols where grid[y][x] != 0 {
                        Block.draw(&context, x: x, y: y, cell: cell, kind: grid[y][x])
                    }
                }
                // Cleared-row flash.
                for y in flash {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(y) * cell, width: width, height: cell)),
                                 with: .color(Color.ppLine.opacity(0.6)))
                }
                if !over {
                    // Where it will land.
                    for c in ghost {
                        let r = CGRect(x: CGFloat(c.x) * cell + 2, y: CGFloat(c.y) * cell + 2, width: cell - 4, height: cell - 4)
                        context.stroke(Path(r), with: .color(Block.color(falling.kind).opacity(0.45)), lineWidth: 1.5)
                    }
                    for c in falling.placed {
                        Block.draw(&context, x: c.x, y: c.y, cell: cell, kind: falling.kind)
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xs).strokeBorder(Color.ppLine.opacity(0.12), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Anywhere on the board: tap to turn, drag sideways to move (follows your finger),
            // drag down to bring it lower, flick down to drop.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in boardDragChanged(value, cell: cell) }
                    .onEnded { value in boardDragEnded(value) }
            )
        }
    }

    private func boardDragChanged(_ value: DragGesture.Value, cell: CGFloat) {
        let t = value.translation
        // Lock to one direction so a sideways slide never drops the piece by accident.
        if dragAxis == nil, hypot(t.width, t.height) > 12 {
            dragAxis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
        }
        switch dragAxis {
        case .horizontal:
            let step = max(cell * 0.8, 14)
            let steps = Int((t.width - usedX) / step)
            guard steps != 0 else { return }
            var moved = false
            for _ in 0..<abs(steps) where game.move(steps > 0 ? 1 : -1) { moved = true }
            usedX += CGFloat(steps) * step
            if moved { Haptics.select() }
        case .vertical:
            let steps = Int((t.height - usedY) / max(cell, 1))
            guard steps > 0 else { return }
            for _ in 0..<steps { game.softDrop() }
            usedY += CGFloat(steps) * cell
        case nil:
            break
        }
    }

    private func boardDragEnded(_ value: DragGesture.Value) {
        defer {
            dragAxis = nil
            usedX = 0
            usedY = 0
        }
        // A very fast flick can end before onChanged ever saw it pass 12 pt.
        let t = value.translation
        if dragAxis == nil, hypot(t.width, t.height) > 12 {
            dragAxis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
        }
        if dragAxis == nil {
            game.rotate()
            Haptics.tap()
        } else if dragAxis == .vertical, value.velocity.height > 900 {
            game.hardDrop()
            Self.impact(.rigid)
        }
    }

    /// Gamepad layout: left thumb moves, right thumb turns and drops.
    /// Arrows repeat while held, so you don't have to tap them over and over.
    private var controls: some View {
        HStack(spacing: 10) {
            HoldButton(symbol: "chevron.left", label: "Move left") {
                if game.move(-1) { Haptics.select() }
            }
            HoldButton(symbol: "chevron.down", label: "Move down") { game.softDrop() }
            HoldButton(symbol: "chevron.right", label: "Move right") {
                if game.move(1) { Haptics.select() }
            }
            Spacer(minLength: 6)
            HoldButton(symbol: "arrow.down.to.line", label: "Drop", repeats: false) {
                game.hardDrop()
                Self.impact(.rigid)
            }
            HoldButton(symbol: "arrow.clockwise", label: "Turn", size: 68, round: true, accent: true, repeats: false) {
                game.rotate()
                Haptics.tap()
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var overlays: some View {
        if restOver {
            panel {
                Text("Rest's over 💪").font(.pixel(DS.TextSize.title2, relativeTo: .title2)).foregroundStyle(Color.ppText)
                Text("Score so far: \(game.score.spaced)").font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Haptics.press()
                    timer.stopAlarm()
                    dismiss()
                } label: { Text("Back to my set") }
                    .buttonStyle(.primary)
                Button {
                    restOver = false
                    game.isPaused = false
                } label: {
                    Text("Keep playing")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.pixel(DS.TextSize.subhead, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            }
        } else if game.isOver {
            panel {
                Text("Game over").font(.pixel(DS.TextSize.title2)).foregroundStyle(Color.ppText)
                Text("Score \(game.score.spaced)" + (game.isNewBest ? " · New best! 🏆" : ""))
                    .font(.subheadline)
                    .foregroundStyle(game.isNewBest ? Color.ppFat : .secondary)
                Button {
                    Haptics.press()
                    game.restart()
                } label: { Text("Play again") }
                    .buttonStyle(.primary)
            }
        }
    }

    /// Respects the "Vibrate on taps" setting, like the Haptics helpers.
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard Haptics.enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .padding(20)
            .frame(maxWidth: 280)
            .background(Color.ppBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: DS.Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(Color.ppLine.opacity(0.15), lineWidth: 1))
    }
}

/// One pixel block with a light top-left edge and a dark bottom-right edge.
private enum Block {
    /// Uses your plate colours (Settings → Appearance → Plates).
    static func color(_ kind: Int) -> Color {
        PlateColors.current.color(max(kind, 1) - 1)
    }

    static func draw(_ context: inout GraphicsContext, x: Int, y: Int, cell: CGFloat, kind: Int) {
        let r = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell).insetBy(dx: 1, dy: 1)
        let edge = max(2, cell * 0.14)
        context.fill(Path(r), with: .color(color(kind)))
        context.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: edge)), with: .color(.white.opacity(0.35)))
        context.fill(Path(CGRect(x: r.minX, y: r.minY, width: edge, height: r.height)), with: .color(.white.opacity(0.2)))
        context.fill(Path(CGRect(x: r.minX, y: r.maxY - edge, width: r.width, height: edge)), with: .color(.black.opacity(0.3)))
        context.fill(Path(CGRect(x: r.maxX - edge, y: r.minY, width: edge, height: r.height)), with: .color(.black.opacity(0.2)))
    }
}

/// Small preview of the next piece.
private struct PiecePreview: View {
    let kind: Int

    var body: some View {
        Canvas { context, size in
            let cells = StackPreviewShapes.cells(kind)
            let maxX = (cells.map(\.x).max() ?? 0) + 1
            let maxY = (cells.map(\.y).max() ?? 0) + 1
            let cell = min(size.width / CGFloat(maxX), size.height / CGFloat(maxY))
            let ox = (size.width - cell * CGFloat(maxX)) / 2
            let oy = (size.height - cell * CGFloat(maxY)) / 2
            context.translateBy(x: ox, y: oy)
            for c in cells { Block.draw(&context, x: c.x, y: c.y, cell: cell, kind: kind) }
        }
    }
}

/// Next-piece shapes, trimmed to their own size.
private enum StackPreviewShapes {
    static func cells(_ kind: Int) -> [StackGame.Cell] {
        let pairs: [(Int, Int)]
        switch kind {
        case 1: pairs = [(0, 0), (1, 0), (2, 0), (3, 0)]
        case 2: pairs = [(0, 0), (1, 0), (0, 1), (1, 1)]
        case 3: pairs = [(1, 0), (0, 1), (1, 1), (2, 1)]
        case 4: pairs = [(1, 0), (2, 0), (0, 1), (1, 1)]
        case 5: pairs = [(0, 0), (1, 0), (1, 1), (2, 1)]
        case 6: pairs = [(0, 0), (0, 1), (1, 1), (2, 1)]
        default: pairs = [(2, 0), (0, 1), (1, 1), (2, 1)]
        }
        return pairs.map { StackGame.Cell(x: $0.0, y: $0.1) }
    }
}

/// A game button that reacts on touch-down (no waiting for release) and,
/// for arrows, keeps repeating while held.
private struct HoldButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 56
    var round = false
    var accent = false
    var repeats = true
    let action: () -> Void

    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?
    /// Resets by itself if the system cancels the touch (onEnded isn't called then).
    @GestureState private var touching = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .heavy))   // ds-allow: icon scales with button
            .foregroundStyle(accent ? Color.ppBackground : Color.ppText)
            .frame(width: size, height: size)
            .background(
                accent ? AnyShapeStyle(Color.brand.opacity(pressed ? 0.75 : 1))
                       : AnyShapeStyle(Color.ppLine.opacity(pressed ? 0.22 : 0.09)),
                in: RoundedRectangle(cornerRadius: round ? size / 2 : 18, style: .continuous)
            )
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action()
                        guard repeats else { return }
                        repeater = Task {
                            try? await Task.sleep(for: .milliseconds(170))
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(for: .milliseconds(55))
                            }
                        }
                    }
                    .onEnded { _ in release() }
            )
            .onChange(of: touching) { _, now in if !now { release() } }
            .onDisappear { release() }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func release() {
        pressed = false
        repeater?.cancel()
        repeater = nil
    }
}
