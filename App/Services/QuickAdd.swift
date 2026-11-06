import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a typed line like "Rohan and Anika's anniversary is June 12 2019"
/// boils down to. Names are as typed; matching them to contacts is separate.
struct QuickAddGuess: Equatable, Sendable {
    var kind: OccasionKind = .birthday
    var names: [String] = []
    var month: Int?
    var day: Int?
    var year: Int?
}

enum QuickAdd {
    /// Reads the line with Apple's on-device model when this phone has it
    /// (iOS 26 with Apple Intelligence on), and with plain rules otherwise.
    static func guess(_ text: String, now: Date = .now, calendar: Calendar = .current) async -> QuickAddGuess {
        let rules = RuleReader.read(text, calendar: calendar)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let model = await ModelReader.read(text) {
            return merge(model: model, rules: rules, text: text)
        }
        #endif
        return rules
    }

    /// The model is better with names and loose phrasing. The date detector is
    /// exact about dates, so its date wins, and a year only counts if it was typed.
    static func merge(model: QuickAddGuess, rules: QuickAddGuess, text: String) -> QuickAddGuess {
        var g = model
        if rules.month != nil {
            g.month = rules.month
            g.day = rules.day
        }
        if let y = rules.year {
            g.year = y
        } else if let y = g.year, !text.contains(String(y)) {
            g.year = nil
        }
        if g.names.isEmpty { g.names = rules.names }
        return g
    }
}

// MARK: - Rules

enum RuleReader {
    private static let anniversaryWords = ["anniversary", "anniv", "wedding", "married"]
    private static let filler: Set<String> = [
        "birthday", "bday", "b-day", "anniversary", "anniv", "wedding", "married", "marriage",
        "is", "on", "was", "the", "of", "born", "in", "add", "for", "their", "his", "her", "my",
        "at", "its", "day", "date", "turns", "turned", "years", "year", "a", "an", "it",
    ]
    private static let joiners: Set<String> = ["and", "&", "+"]

    static func read(_ text: String, calendar: Calendar = .current) -> QuickAddGuess {
        var g = QuickAddGuess()
        let lower = text.lowercased()
        g.kind = anniversaryWords.contains(where: lower.contains) ? .anniversary : .birthday

        var rest = text
        if let found = findDate(in: text, calendar: calendar) {
            g.month = found.month
            g.day = found.day
            g.year = found.year
            rest.replaceSubrange(found.range, with: " ")
        }
        if g.year == nil, let (year, range) = fourDigitYear(in: rest) {
            g.year = year
            rest.replaceSubrange(range, with: " ")
        }
        g.names = names(in: rest)
        return g
    }

    private struct FoundDate {
        let month: Int, day: Int, year: Int?
        let range: Range<String.Index>
    }

    private static func findDate(in text: String, calendar: Calendar) -> FoundDate? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: ns) {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            var cal = calendar
            if let tz = match.timeZone { cal.timeZone = tz }
            let c = cal.dateComponents([.month, .day], from: date)
            guard let m = c.month, let d = c.day else { continue }
            let piece = String(text[range])
            return FoundDate(month: m, day: d, year: typedYear(in: piece), range: range)
        }
        return nil
    }

    /// The detector fills in a year either way, so only trust one that was typed:
    /// "1990", or the "90" in "3/14/90".
    private static func typedYear(in piece: String) -> Int? {
        if let (y, _) = fourDigitYear(in: piece) { return y }
        if let r = piece.range(of: #"\d{1,2}[/.-]\d{1,2}[/.-](\d{2})\b"#, options: .regularExpression) {
            let two = Int(piece[r].suffix(2)) ?? 0
            let thisYear = Calendar.current.component(.year, from: .now) % 100
            return two > thisYear ? 1900 + two : 2000 + two
        }
        return nil
    }

    private static func fourDigitYear(in text: String) -> (Int, Range<String.Index>)? {
        guard let r = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression),
              let y = Int(text[r]) else { return nil }
        return (y, r)
    }

    /// "Rohan and Anika's anniversary is " → ["Rohan", "Anika"].
    static func names(in text: String) -> [String] {
        var cleaned = text.replacingOccurrences(of: "\u{2019}", with: "'")
        cleaned = cleaned.replacingOccurrences(of: #"'s\b"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"[,.!?:;()"]"#, with: " ", options: .regularExpression)
        var people: [[String]] = [[]]
        for raw in cleaned.split(whereSeparator: \.isWhitespace) {
            let word = String(raw)
            let lower = word.lowercased()
            if joiners.contains(lower) {
                if !(people.last ?? []).isEmpty { people.append([]) }
                continue
            }
            if filler.contains(lower) || word.allSatisfy({ $0.isNumber || $0 == "/" || $0 == "-" }) { continue }
            people[people.count - 1].append(word)
        }
        return people.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
    }
}

// MARK: - Apple's on-device model

#if canImport(FoundationModels)
@available(iOS 26.0, *)
enum ModelReader {
    private struct Reply: Decodable {
        var kind: String?
        var people: [String]?
        var month: Int?
        var day: Int?
        var year: Int?
    }

    private static let instructions = """
    You read one short note about someone's birthday or anniversary and pull out who and when. \
    Reply with only a JSON object with these keys: "kind" ("birthday" or "anniversary"), \
    "people" (each person's name exactly as written, one entry per person; a couple is two entries), \
    "month" (1-12 or null), "day" (1-31 or null), "year" (a four-digit year only if the note states one, else null). \
    Never invent a date or a year.
    """

    static func read(_ text: String) async -> QuickAddGuess? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text)
            let raw = response.content
            guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close,
                  let data = String(raw[open...close]).data(using: .utf8) else { return nil }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            var g = QuickAddGuess()
            g.kind = reply.kind?.lowercased().hasPrefix("anniv") == true ? .anniversary : .birthday
            g.names = (reply.people ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let m = reply.month, let d = reply.day, (1...12).contains(m), (1...31).contains(d) {
                g.month = m
                g.day = d
            }
            if let y = reply.year, (1900...2100).contains(y) { g.year = y }
            return g
        } catch {
            return nil
        }
    }
}
#endif

// MARK: - Matching names to contacts

enum ContactMatcher {
    struct Match: Hashable {
        let contact: ContactSnapshot
        let score: Int
    }

    /// Contacts that fit a typed name, strongest first. A nickname ("Mom")
    /// or the full name is a strong match; a first name alone is weaker.
    static func matches(for name: String, in contacts: [ContactSnapshot], limit: Int = 4) -> [Match] {
        let q = fold(name)
        let words = q.split(separator: " ").map(String.init)
        guard let firstWord = words.first, let lastWord = words.last else { return [] }
        var found: [Match] = []
        for c in contacts {
            let given = fold(c.givenName), family = fold(c.familyName), nick = fold(c.nickname)
            let full = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            var score = 0
            if !nick.isEmpty, nick == q { score = 100 }
            else if full == q { score = 95 }
            else if words.count >= 2, given.hasPrefix(firstWord), family.hasPrefix(lastWord) { score = 80 }
            else if words.count == 1, given == q { score = 60 }
            else if words.count == 1, family == q { score = 40 }
            else if words.count == 1, q.count >= 3, given.hasPrefix(q) || nick.hasPrefix(q) { score = 30 }
            if score > 0 { found.append(Match(contact: c, score: score)) }
        }
        return Array(found.sorted {
            $0.score != $1.score ? $0.score > $1.score : sortKey($0.contact) < sortKey($1.contact)
        }.prefix(limit))
    }

    /// The one contact to pick without asking: a strong match nobody ties.
    static func sure(_ matches: [Match]) -> ContactSnapshot? {
        guard let top = matches.first, top.score >= 60 else { return nil }
        if matches.count > 1, matches[1].score == top.score { return nil }
        return top.contact
    }

    private static func sortKey(_ c: ContactSnapshot) -> String { c.givenName + " " + c.familyName }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }
}
