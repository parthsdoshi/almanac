import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, when this iPhone has it (iOS 26 with Apple
/// Intelligence on). Every caller has a plain fallback, so the app works
/// the same without it, just less cleverly.
enum OnDevice {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func respond(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let reply = try await session.respond(to: prompt)
                let text = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// Asks for a JSON object and decodes the first {...} in the reply.
    static func json<T: Decodable>(_ type: T.Type, instructions: String, prompt: String) async -> T? {
        guard let raw = await respond(instructions: instructions, prompt: prompt),
              let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close,
              let data = String(raw[open...close]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// "Thursday, November 5, 2026, 10:30 PM", for telling the model what today is.
    static func nowLine(_ now: Date = .now) -> String {
        now.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
    }

    /// Parses "2026-11-09T14:00" or "2026-11-09" in the phone's time zone.
    static func localDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty, s.lowercased() != "null" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

/// Finds a date (and time, if typed) in a line of text.
enum DateFinder {
    struct Found {
        let date: Date
        let hasTime: Bool
        let range: Range<String.Index>
    }

    static func find(in text: String) -> Found? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = NSRange(text.startIndex..., in: text)
        guard let m = detector.firstMatch(in: text, range: ns), let date = m.date,
              let range = Range(m.range, in: text) else { return nil }
        let piece = text[range].lowercased()
        let hasTime = piece.range(of: #"\d(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\d{1,2}:\d{2}|noon|midnight|morning|evening|tonight|afternoon"#,
                                  options: .regularExpression) != nil
        return Found(date: date, hasTime: hasTime, range: range)
    }
}
