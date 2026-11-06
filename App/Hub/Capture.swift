import Foundation

/// What a jotted line is, and the pieces the app needs to file it.
struct CaptureGuess: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case reminder, note, person, occasion
        var id: String { rawValue }
        var label: String {
            switch self {
            case .reminder: "Reminder"
            case .note: "Note"
            case .person: "About a person"
            case .occasion: "Birthday"
            }
        }
    }

    var kind: Kind
    /// The to-do, the note, or the fact about the person.
    var text: String
    /// A day or time the line actually says, found by the date detector. Never a guess.
    var due: Date?
    var dueHasTime = false
    /// When a to-do with no stated date probably needs doing by.
    var horizon: Horizon = .thisWeek
    /// Name as typed, for a person note.
    var person: String?
}

/// A rough "by when" for a to-do that names no date.
enum Horizon: String, CaseIterable, Identifiable, Sendable {
    case today, tomorrow, thisWeek = "this_week", nextWeek = "next_week", thisMonth = "this_month", someday
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "This week"
        case .nextWeek: "Next week"
        case .thisMonth: "This month"
        case .someday: "No date"
        }
    }

    /// The all-day due date this stands for: Friday for a week, the last day for a month.
    func date(from now: Date = .now, calendar cal: Calendar = .current) -> Date? {
        let today = cal.startOfDay(for: now)
        func plus(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: today) ?? today }
        let wd = cal.component(.weekday, from: today) // Sun 1 ... Sat 7
        let toFriday: Int = switch wd { case 1: 0; case 7: 1; default: 6 - wd } // Sunday and Saturday: the weekend is the deadline
        switch self {
        case .today: return today
        case .tomorrow: return plus(1)
        case .thisWeek: return plus(toFriday)
        case .nextWeek: return plus(wd == 1 ? 5 : wd == 7 ? 6 : toFriday + 7)
        case .thisMonth:
            let start = cal.dateInterval(of: .month, for: today)?.start ?? today
            let last = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? today
            return max(last, plus(toFriday))
        case .someday: return nil
        }
    }

    /// Words in the line that settle it without the model.
    static func stated(in lower: String) -> Horizon? {
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !words.isDisjoint(with: ["asap", "urgent", "urgently", "tonight", "today", "now"]) || lower.contains("right away") { return .today }
        if lower.contains("tomorrow") { return .tomorrow }
        if lower.contains("next week") { return .nextWeek }
        if lower.contains("this week") || lower.contains("weekend") { return .thisWeek }
        if lower.contains("this month") || lower.contains("next month") { return .thisMonth }
        if ["someday", "eventually", "at some point", "one day"].contains(where: { lower.contains($0) }) { return .someday }
        return nil
    }
}

enum CaptureReader {
    static func read(_ text: String, now: Date = .now) async -> CaptureGuess {
        let rules = RuleCapture.read(text)
        guard let model = await ModelCapture.read(text, now: now) else { return rules }
        var g = model
        // Dates only ever come from the detector, which reads what was typed. The model only guesses a rough "by when".
        g.due = rules.due
        g.dueHasTime = rules.dueHasTime
        if let stated = Horizon.stated(in: text.lowercased()) { g.horizon = stated }
        if g.text.isEmpty { g.text = rules.text }
        return g
    }
}

enum RuleCapture {
    private static let reminderStarts = [
        "remind me to ", "remind me ", "reminder to ", "reminder: ", "todo ", "todo: ", "to do: ", "to-do: ",
        "don't forget to ", "dont forget to ", "remember to ",
    ]
    static let verbs: Set<String> = [
        "call", "text", "email", "buy", "book", "pay", "pick", "send", "schedule", "cancel", "renew", "order",
        "return", "check", "confirm", "ask", "follow", "submit", "file", "sign", "reply", "fix", "clean", "get",
        "do", "finish", "write", "wash", "water", "feed", "make", "prep", "plan", "update", "read", "move", "mail",
        "drop", "grab", "print", "install", "research", "look", "find", "talk", "meet", "sell", "register", "apply",
        "pack", "start", "set", "take", "bring", "ship", "change", "vacuum", "review", "draft", "post", "upload",
    ]
    private static let leadIns = [
        "i need to ", "i have to ", "i've got to ", "ive got to ", "i gotta ", "gotta ", "need to ", "have to ",
        "i should ", "i must ", "i want to ", "remind me to ", "don't forget to ", "dont forget to ", "remember to ",
        "todo: ", "todos: ", "to do: ", "to-do: ", "to-dos: ", "things to do: ", "tasks: ",
    ]
    private static let personVerbs = [
        " is ", " has ", " likes ", " loves ", " hates ", " started ", " moved ", " got ", " just ", " wants ",
        " prefers ", " works ", " lives ", " said ", " had ", " was ", "'s ", "’s ",
    ]

    static func read(_ raw: String) -> CaptureGuess {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        if lower.contains("birthday") || lower.contains("bday") || lower.contains("anniversary") {
            return CaptureGuess(kind: .occasion, text: text)
        }

        var body = text
        var isReminder = false
        for start in reminderStarts where lower.hasPrefix(start) {
            body = String(text.dropFirst(start.count))
            isReminder = true
            break
        }
        let firstWord = lower.split(separator: " ").first.map(String.init) ?? ""
        if verbs.contains(firstWord) { isReminder = true }

        let found = DateFinder.find(in: body)
        if isReminder || found != nil && verbs.contains(firstWord) {
            var title = body
            if let f = found {
                title.replaceSubrange(f.range, with: "")
                title = title.replacingOccurrences(of: #"\s+(on|at|by|for|before|until)\s*$"#, with: "", options: .regularExpression)
                title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            }
            return CaptureGuess(kind: .reminder, text: capitalized(title.trimmingCharacters(in: .whitespaces)),
                                due: found?.date, dueHasTime: found?.hasTime ?? false,
                                horizon: Horizon.stated(in: lower) ?? .thisWeek)
        }

        // "Priya started at Stripe" -> about Priya.
        if let first = text.first, first.isUppercase {
            for v in personVerbs {
                if let r = text.range(of: v), text.distance(from: text.startIndex, to: r.lowerBound) <= 30 {
                    let name = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if name.split(separator: " ").count <= 3, name.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" }) {
                        return CaptureGuess(kind: .person, text: text, person: name)
                    }
                }
            }
        }
        return CaptureGuess(kind: .note, text: text)
    }

    /// Several to-dos typed one per line, bullets and checkboxes stripped.
    static func lines(_ raw: String) -> [String] {
        raw.split(whereSeparator: \.isNewline).map { line in
            var t = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "[ ] ", "- ", "• ", "* "] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
            if let r = t.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) { t.removeSubrange(r) }
            return t.trimmingCharacters(in: .whitespaces)
        }
        .filter { !$0.isEmpty }
    }

    /// "I need to call mom, buy milk and renew my passport" -> three to-dos.
    /// Splits lines, then commas and semicolons; "and" only ends a comma list, or joins two verb phrases.
    static func split(_ raw: String) -> [String] {
        var out: [String] = []
        for line in lines(raw) {
            var l = line
            for lead in leadIns where l.lowercased().hasPrefix(lead) { l = String(l.dropFirst(lead.count)); break }
            var parts = l.components(separatedBy: CharacterSet(charactersIn: ";,")).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count > 1, var last = parts.popLast() {
                if last.lowercased().hasPrefix("and ") { last = String(last.dropFirst(4)) }
                if let r = last.range(of: " and ", options: [.backwards, .caseInsensitive]) {
                    parts.append(String(last[..<r.lowerBound])); parts.append(String(last[r.upperBound...]))
                } else {
                    parts.append(last)
                }
            } else if let r = l.range(of: " and ", options: [.backwards, .caseInsensitive]) {
                let a = String(l[..<r.lowerBound]), b = String(l[r.upperBound...])
                if startsWithVerb(a), startsWithVerb(b) { parts = [a, b] }
            }
            // "call mom on Friday, Nov 7": a piece that's only a date goes back on the one before.
            var merged: [String] = []
            for p in parts.map({ $0.trimmingCharacters(in: .whitespaces) }) where !p.isEmpty {
                if let f = DateFinder.find(in: p), !merged.isEmpty,
                   p.distance(from: f.range.lowerBound, to: f.range.upperBound) >= p.count - 3 {
                    merged[merged.count - 1] += ", " + p
                } else {
                    merged.append(p)
                }
            }
            out += merged
        }
        return out
    }

    private static func startsWithVerb(_ s: String) -> Bool {
        verbs.contains(s.lowercased().split(separator: " ").first.map(String.init) ?? "")
    }

    /// One line of a list read as a to-do, whatever it would read as alone.
    static func todo(_ line: String) -> CaptureGuess {
        var g = read(line)
        if g.kind != .reminder {
            let lower = line.lowercased()
            let found = DateFinder.find(in: line)
            var title = line
            if let f = found { title.replaceSubrange(f.range, with: "") }
            g = CaptureGuess(kind: .reminder, text: capitalized(title.trimmingCharacters(in: .whitespaces)),
                             due: found?.date, dueHasTime: found?.hasTime ?? false,
                             horizon: Horizon.stated(in: lower) ?? .thisWeek)
        }
        return g
    }

    static func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}

enum ModelCapture {
    private struct Reply: Decodable {
        var kind: String?
        var text: String?
        var by: String?
        var person: String?
    }

    private static let instructions = """
    You sort one line someone typed into their own app. Reply with only a JSON object: \
    "kind": "reminder" (something to do), "note" (an idea or info to keep), "person" (a fact about a named person), \
    or "occasion" (someone's birthday or anniversary). \
    "text": for a reminder, the task as a short imperative ("Call the landlord about the lease"); \
    for a note or person, the line tidied but with nothing added. \
    "by": for a reminder, when it most likely needs doing by: "today" (urgent, or a quick thing for tonight), \
    "tomorrow", "this_week" (most errands and calls), "next_week", "this_month" (paperwork, renewals, bigger chores), \
    or "someday" (no real deadline). Else null. \
    "person": for kind person, the name exactly as typed, else null. Never invent details, dates or times.
    """

    /// Splits a line into separate to-dos. Nil without the model; pieces that reuse none of the line's words are dropped.
    static func todos(in text: String) async -> [String]? {
        struct T: Decodable { var todos: [String]? }
        let instructions = """
        Someone typed one or more to-dos into their own app. Reply with only a JSON object {"todos": [...]}: \
        each separate thing to do as a short imperative, in their own words, keeping any day or time they gave with it. \
        Don't add, merge or reword beyond that. One thing gives a list of one.
        """
        guard let r = await OnDevice.json(T.self, instructions: instructions, prompt: text),
              let list = r.todos?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }),
              !list.isEmpty else { return nil }
        let typed = Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let kept = list.filter { item in
            !Set(item.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)).isDisjoint(with: typed)
        }
        return kept.count == list.count ? kept : nil
    }

    /// Just the "by when" guess for one to-do in a list.
    static func horizon(for text: String, now: Date = .now) async -> Horizon? {
        struct H: Decodable { var by: String? }
        let instructions = """
        Someone wrote a to-do in their own app. Reply with only a JSON object {"by": ...} saying when it most likely \
        needs doing by: "today" (urgent, or a quick thing for tonight), "tomorrow", "this_week" (most errands and calls), \
        "next_week", "this_month" (paperwork, renewals, bigger chores), or "someday" (no real deadline).
        """
        guard let r = await OnDevice.json(H.self, instructions: instructions,
                                          prompt: "Now: \(OnDevice.nowLine(now)).\nTo-do: \(text)") else { return nil }
        return r.by.flatMap(Horizon.init(rawValue:))
    }

    static func read(_ text: String, now: Date) async -> CaptureGuess? {
        guard let r = await OnDevice.json(Reply.self, instructions: instructions,
                                          prompt: "Now: \(OnDevice.nowLine(now)).\nLine: \(text)") else { return nil }
        guard let kind = r.kind.flatMap(CaptureGuess.Kind.init(rawValue:)) else { return nil }
        var g = CaptureGuess(kind: kind, text: r.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        if kind == .reminder, let h = r.by.flatMap(Horizon.init(rawValue:)) { g.horizon = h }
        if kind == .person { g.person = r.person }
        if kind == .person, g.person?.isEmpty ?? true { g.kind = .note }
        return g
    }
}

// MARK: - Tidying a note

struct NoteTidy: Equatable {
    struct Todo: Equatable, Identifiable {
        var id: String { text }
        var text: String
        var due: Date?
    }

    var title: String
    var tags: [String]
    var todos: [Todo]
}

enum NoteTidier {
    private struct Reply: Decodable {
        struct T: Decodable { var text: String?; var due: String? }
        var title: String?
        var tags: [String]?
        var todos: [T]?
    }

    private static let instructions = """
    You tidy one personal note. Reply with only a JSON object: "title" (a short title, at most 5 words; \
    keep the note's own title if it has a good one), "tags" (up to 3 lowercase one-word tags), \
    "todos" (each concrete thing the note says to do, as {"text": a short imperative, "due": "YYYY-MM-DD" if the note gives a day, else null}; \
    an empty list if there are none). Use only what the note says.
    """

    static func tidy(_ note: Note, now: Date = .now) async -> NoteTidy {
        let rules = rulesTidy(note)
        let prompt = "Today: \(OnDevice.nowLine(now)).\nTitle: \(note.title)\nNote:\n\(note.body)"
        guard let r = await OnDevice.json(Reply.self, instructions: instructions, prompt: prompt) else { return rules }
        let title = r.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = (r.tags ?? []).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let noteWords = words(note.title + " " + note.body)
        let todos = (r.todos ?? []).compactMap { t -> NoteTidy.Todo? in
            guard let text = t.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            // The small model sometimes invents to-dos. Keep only ones that reuse the note's own words.
            guard !words(text).isDisjoint(with: noteWords) else { return nil }
            // Dates come from the detector on the to-do's text, not from the model.
            return NoteTidy.Todo(text: text, due: DateFinder.find(in: text)?.date)
        }
        return NoteTidy(title: title.isEmpty ? rules.title : title, tags: Array(tags.prefix(3)), todos: todos)
    }

    private static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 3 })
    }

    /// Without the model: a title from the first line, and lines that read like to-dos.
    static func rulesTidy(_ note: Note) -> NoteTidy {
        let lines = note.body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let title = note.title.isEmpty ? String((lines.first ?? "Note").prefix(40)) : note.title
        var todos: [NoteTidy.Todo] = []
        let sentences = note.body.split(whereSeparator: { ".\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for s in sentences {
            var t = s
            for prefix in ["- [ ] ", "[ ] ", "- ", "• ", "todo: ", "TODO: ", "TODO "] where t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count))
            }
            let g = RuleCapture.read(t)
            if g.kind == .reminder, !g.text.isEmpty { todos.append(.init(text: g.text, due: g.due)) }
        }
        return NoteTidy(title: title, tags: [], todos: todos)
    }
}

// MARK: - Drafting a text from what you know

enum TextDrafter {
    static func draft(for occasion: Occasion, years: Int?, notes: [String], fallback: String) async -> String {
        guard !notes.isEmpty else { return fallback }
        let what = occasion.kind == .birthday ? "birthday" : "wedding anniversary"
        let instructions = """
        You write one short, warm text message from the user to a friend or family member for their \(what). \
        Write it in the first person, casual, one or two sentences, no hashtags, no emoji unless the notes use them. \
        You may mention one or two things from the notes if they fit naturally. Never invent facts. Reply with the message only.
        """
        var prompt = "To: \(Names.join(occasion.firstNames))\n"
        if let years { prompt += occasion.kind == .birthday ? "Turning: \(years)\n" : "Years married: \(years)\n" }
        prompt += "Notes:\n" + notes.prefix(8).map { "- \($0)" }.joined(separator: "\n")
        guard var text = await OnDevice.respond(instructions: instructions, prompt: prompt) else { return fallback }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“” \n"))
        return text.isEmpty ? fallback : text
    }
}

// MARK: - The day in two sentences

struct DayFacts {
    var occasionsToday: [String] = []   // "Priya turns 31"
    var dayKind: String = ""            // "lift day"
    var nextWorkout: String?            // "Workout B, Lunge, overhead press, pulldown"
    var liftedToday = false
    var firstEvent: String?             // "10:30 AM Standup"
    var eventCount = 0
    var reminderCount = 0
    var firstReminder: String?          // "Call the landlord at 2:00 PM"
}

enum DayRundown {
    /// Built from the facts alone. The on-device model made things up here ("you ran this morning"),
    /// so it doesn't write this card.
    static func rundown(_ f: DayFacts) -> String { plain(f) }

    static func plain(_ f: DayFacts) -> String {
        var parts: [String] = []
        if let o = f.occasionsToday.first {
            parts.append(f.occasionsToday.count > 1 ? "\(o), plus \(f.occasionsToday.count - 1) more today." : "\(o) today.")
        }
        if f.liftedToday {
            parts.append("You've already lifted today.")
        } else if f.dayKind == "lift day", let w = f.nextWorkout {
            parts.append("It's a lift day: \(w) is up.")
        } else if f.dayKind == "run day" {
            parts.append("It's a run day, no lifting.")
        } else {
            parts.append("It's a rest day.")
        }
        if let e = f.firstEvent {
            parts.append(f.eventCount > 1 ? "\(f.eventCount) things on the calendar, starting with \(e)." : "On the calendar: \(e).")
        }
        if f.reminderCount > 0 {
            parts.append(f.reminderCount == 1 ? "One reminder due." : "\(f.reminderCount) reminders due.")
        }
        return parts.joined(separator: " ")
    }
}
