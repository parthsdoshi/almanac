import SwiftUI

// Almanac pieces used by both the app and the Live Activity.

/// A tear-off calendar page: a colored band with the month, the day underneath.
struct DateChip: View {
    let date: Date
    let kind: OccasionKind
    var scale: CGFloat = 1
    /// Border color; the hero card uses a light ring on its red background.
    var ring: Color = Theme.Colors.rule

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 9 * scale, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Theme.Colors.onTint(for: kind))
                .frame(maxWidth: .infinity)
                .frame(height: 15 * scale)
                .background(Theme.Colors.tint(for: kind))
            Text(date.formatted(.dateTime.day()))
                .font(Theme.Typography.display(22 * scale, .black))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 44 * scale, height: 50 * scale)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip * scale))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip * scale).strokeBorder(ring, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.label), \(date.formatted(.dateTime.month(.wide).day()))")
    }
}

/// One scrap of confetti, positioned in unit coordinates (0...1).
struct ConfettiPiece: Identifiable {
    enum Shape { case strip, dot, squiggle }

    let id: Int
    let x: CGFloat
    let y: CGFloat
    let angle: Double
    let spin: Double
    let shape: Shape
    let colorIndex: Int
    let size: CGFloat

    /// Same seed, same confetti: static confetti doesn't jump around between renders.
    static func scatter(seed: UInt64, count: Int) -> [ConfettiPiece] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { i in
            let roll = rng.unit()
            return ConfettiPiece(
                id: i,
                x: rng.unit(),
                y: rng.unit(),
                angle: Double(rng.unit()) * 120 - 60,
                spin: Double(rng.unit()) * 720 - 360,
                shape: roll < 0.45 ? .strip : (roll < 0.75 ? .dot : .squiggle),
                colorIndex: Int(rng.next() % 1000),
                size: 0.8 + rng.unit() * 0.5)
        }
    }
}

struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    let colors: [Color]

    var body: some View {
        let color = colors.isEmpty ? Theme.Colors.gold : colors[piece.colorIndex % colors.count]
        switch piece.shape {
        case .strip:
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 7 * piece.size, height: 3 * piece.size)
        case .dot:
            Circle()
                .fill(color)
                .frame(width: 5 * piece.size, height: 5 * piece.size)
        case .squiggle:
            Squiggle()
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 12 * piece.size, height: 5 * piece.size)
        }
    }
}

struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.midY), control: CGPoint(x: rect.width * 0.25, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.width * 0.75, y: rect.maxY))
        return p
    }
}

/// Still confetti scattered over an area. Built from plain shapes so it also
/// renders in the Live Activity.
struct ConfettiField: View {
    var seed: UInt64 = 1
    var count: Int = 30
    var colors: [Color] = Theme.Colors.confetti

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(ConfettiPiece.scatter(seed: seed, count: count)) { piece in
                    ConfettiPieceView(piece: piece, colors: colors)
                        .rotationEffect(.degrees(piece.angle))
                        .position(x: piece.x * geo.size.width, y: piece.y * geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small deterministic RNG (SplitMix64).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
}
