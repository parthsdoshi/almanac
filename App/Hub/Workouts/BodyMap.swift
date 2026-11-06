import SwiftUI

/// Front and back figures with the muscles a workout or exercise works filled in.
/// Same shapes as the web tracker's MuscleMap, drawn in the paper look.
struct BodyMap: View {
    let muscles: [String]
    var width: CGFloat = 48
    var lit: Color = Theme.Colors.birthday
    var off: Color = Theme.Colors.sunk
    var edge: Color = Theme.Colors.rule
    var labels = true

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            figure(BodyMapShapes.front, "Front")
            figure(BodyMapShapes.back, "Back")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muscles worked: " + muscles.joined(separator: ", "))
    }

    private func figure(_ parts: [BodyMapShapes.Part], _ label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                BodyPolygon(points: BodyMapShapes.headPoints, round: true).fill(off)
                BodyPolygon(points: BodyMapShapes.headPoints, round: true).stroke(edge, lineWidth: 1)
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    let on = BodyMapShapes.isLit(part.group, muscles)
                    BodyPolygon(points: part.points).fill(on ? lit : off)
                    BodyPolygon(points: part.points).stroke(edge, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                }
            }
            .frame(width: width, height: width * 148 / 84)
            if labels {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.Colors.inkSoft)
            }
        }
    }
}

/// A polygon in the web map's 84 × 148 box, scaled to whatever frame it's given.
struct BodyPolygon: Shape {
    let points: [CGPoint]
    var round = false

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 84, sy = rect.height / 148
        var p = Path()
        if round, let c = points.first, points.count == 2 {
            let r = points[1].x
            p.addEllipse(in: CGRect(x: (c.x - r) * sx, y: (c.y - r) * sy, width: 2 * r * sx, height: 2 * r * sy))
            return p
        }
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x * sx, y: first.y * sy))
        for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.x * sx, y: pt.y * sy)) }
        p.closeSubpath()
        return p
    }
}

enum BodyMapShapes {
    struct Part {
        let points: [CGPoint]
        let group: String?
    }

    /// Which plan muscle names light up each region.
    static let groups: [String: [String]] = [
        "front-delts": ["Front delts", "Side delts"], "chest": ["Chest"], "biceps": ["Biceps"], "core": ["Core"],
        "quads": ["Quads"], "upper-back": ["Upper back"], "rear-delts": ["Rear delts"], "lats": ["Lats"],
        "lower-back": ["Lower back"], "triceps": ["Triceps"], "glutes": ["Glutes"], "hamstrings": ["Hamstrings"],
        "forearms": ["Forearms", "Grip"],
    ]

    static func isLit(_ group: String?, _ muscles: [String]) -> Bool {
        guard let group else { return false }
        return (groups[group] ?? []).contains { muscles.contains($0) }
    }

    /// Centre and radius of the head, drawn as a circle.
    static let headPoints = [CGPoint(x: 42, y: 11), CGPoint(x: 8, y: 0)]

    private static func p(_ s: String, _ group: String? = nil) -> Part {
        let pts = s.split(separator: " ").compactMap { pair -> CGPoint? in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
        }
        return Part(points: pts, group: group)
    }

    static let front: [Part] = [
        p("34,20 50,20 46,26 38,26"),
        p("16,28 30,24 32,36 20,40", "front-delts"), p("68,28 54,24 52,36 64,40", "front-delts"),
        p("31,27 42,29 42,46 29,42", "chest"), p("53,27 42,29 42,46 55,42", "chest"),
        p("12,42 22,40 20,58 10,56", "biceps"), p("72,42 62,40 64,58 74,56", "biceps"),
        p("9,58 19,60 16,76 7,72", "forearms"), p("75,58 65,60 68,76 77,72", "forearms"),
        p("31,48 53,48 51,78 33,78", "core"), p("32,80 52,80 54,88 30,88"),
        p("30,90 41,90 40,118 28,114", "quads"), p("54,90 43,90 44,118 56,114", "quads"),
        p("29,120 39,122 37,146 30,144"), p("55,120 45,122 47,146 54,144"),
    ]

    static let back: [Part] = [
        p("32,20 52,20 48,38 36,38", "upper-back"),
        p("16,28 30,24 32,36 20,40", "rear-delts"), p("68,28 54,24 52,36 64,40", "rear-delts"),
        p("30,40 41,42 41,56 28,52", "lats"), p("54,40 43,42 43,56 56,52", "lats"),
        p("34,56 50,56 48,72 36,72", "lower-back"),
        p("12,42 22,40 20,58 10,56", "triceps"), p("72,42 62,40 64,58 74,56", "triceps"),
        p("9,58 19,60 16,76 7,72", "forearms"), p("75,58 65,60 68,76 77,72", "forearms"),
        p("31,76 42,76 41,90 29,88", "glutes"), p("53,76 42,76 43,90 55,88", "glutes"),
        p("29,92 40,92 39,118 28,114", "hamstrings"), p("55,92 44,92 45,118 56,114", "hamstrings"),
        p("29,120 39,122 37,146 30,144"), p("55,120 45,122 47,146 54,144"),
    ]
}

/// Body map beside the muscle tags, the way the web tracker lays them out.
struct MusclesWorked: View {
    let muscles: [String]
    var mapWidth: CGFloat = 46
    var title: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BodyMap(muscles: muscles, width: mapWidth)
            VStack(alignment: .leading, spacing: 6) {
                if let title { Eyebrow(text: title) }
                FlowTags(tags: muscles)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
