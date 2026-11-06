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
    var due: Date?
    var dueHasTime = false
    /// Name as typed, for a person note.
    var person: String?
}

enum CaptureReader {
    static func read(_ text: String, now: Date = .now) async -> CaptureGuess {
        let rules = RuleCapture.read(text)
        guard let model = await ModelCapture.read(text, now: now) else { return rules }
        var g = model
        // The date detector is exact; trust it over the model's date.
        if rules.due != nil, g.kind == .reminder {
            g.due = rules.due
            g.dueHasTime = rules.dueHasTime
        }
        if g.text.isEmpty { g.text = rules.text }
        return g
    }
}

enum RuleCapture {
    private static let reminderStarts = [
        "remind me to ", "remind me ", "reminder to ", "reminder: ", "todo ", "todo: ", "to do: ", "to-do: ",
        "don't forget to ", "dont forget to ", "remember to ",
    ]
    private static let verbs: Set<String> = [
        "call", "text", "email", "buy", "book", "pay", "pick", "send", "schedule", "cancel", "renew", "order",
        "return", "check", "confirm", "ask", "follow", "submit", "file", "sign", "reply", "fix", "clean", "get",
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
                                due: found?.date, dueHasTime: found?.hasTime ?? false)
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

    private static func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}

enum ModelCapture {
    private struct Reply: Decodable {
        var kind: String?
        var text: String?
        var due: String?
        var person: String?
    }

    private static let instructions = """
    You sort one line someone typed into their own app. Reply with only a JSON object: \
    "kind": "reminder" (something to do), "note" (an idea or info to keep), "person" (a fact about a named person), \
    or "occasion" (someone's birthday or anniversary). \
    "text": for a reminder, the task as a short imperative ("Call the landlord about the lease"); \
    for a note or person, the line tidied but with nothing added. \
    "due": for a reminder with a stated day or time, "YYYY-MM-DDTHH:MM" (or "YYYY-MM-DD" with no time), else null. \
    "person": for kind person, the name exactly as typed, else null. Never invent details.
    """

    static func read(_ text: String, now: Date) async -> CaptureGuess? {
        guard let r = await OnDevice.json(Reply.self, instructions: instructions,
                                          prompt: "Now: \(OnDevice.nowLine(now)).\nLine: \(text)") else { return nil }
        guard let kind = r.kind.flatMap(CaptureGuess.Kind.init(rawValue:)) else { return nil }
        var g = CaptureGuess(kind: kind, text: r.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        if kind == .reminder, let d = OnDevice.localDate(r.due) {
            g.due = d
            g.dueHasTime = r.due?.contains("T") ?? false
        }
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
        let todos = (r.todos ?? []).compactMap { t -> NoteTidy.Todo? in
            guard let text = t.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return NoteTidy.Todo(text: text, due: OnDevice.localDate(t.due))
        }
        return NoteTidy(title: title.isEmpty ? rules.title : title, tags: Array(tags.prefix(3)), todos: todos)
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
    static func rundown(_ f: DayFacts) async -> String {
        let template = plain(f)
        guard OnDevice.isAvailable else { return template }
        var lines: [String] = []
        for o in f.occasionsToday { lines.append("Today: \(o)") }
        lines.append("It's a \(f.dayKind)." + (f.liftedToday ? " Already lifted today." : ""))
        if let w = f.nextWorkout, f.dayKind == "lift day", !f.liftedToday { lines.append("Next lift: \(w)") }
        if let e = f.firstEvent { lines.append("Calendar: \(f.eventCount) events, first is \(e)") }
        if f.reminderCount > 0 { lines.append("Reminders due today: \(f.reminderCount)" + (f.firstReminder.map { ", first: \($0)" } ?? "")) }
        let instructions = """
        You write a two-sentence rundown of someone's day for the top of their own app, talking to them as "you". \
        Plain and friendly, no greeting, no exclamation marks, no emoji. Mention a birthday or anniversary first if there is one. \
        Use only the facts given.
        """
        let text = await OnDevice.respond(instructions: instructions, prompt: lines.joined(separator: "\n"))
        return text ?? template
    }

    static func plain(_ f: DayFacts) -> String {
        var parts: [String] = []
        if let o = f.occasionsToday.first {
            parts.append(f.occasionsToday.count > 1 ? "\(o), plus \(f.occasionsToday.count - 1) more today." : "\(o) today.")
        }
        if f.liftedToday {
            parts.append("You've already lifted today.")
        } else if f.dayKind == "lift day", let w = f.nextWorkout {
            parts.append("It's a lift day: \(w) is up.")
        } else {
            parts.append("It's a \(f.dayKind).")
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
