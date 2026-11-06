import CoreGraphics
import Foundation
import Vision

/// Reads a photo of a card, invite or flyer into Jot lines.
///
/// Vision reads the printed words on every iPhone. On iOS 27, when the
/// on-device model can see images, it also looks at the photo and the words
/// and suggests to-dos. Whatever it suggests has to share words with what's
/// printed, and a date stays only if that day is printed too, so it can't
/// invent a party or a deadline.
enum PhotoReader {
    struct Read: Equatable {
        /// One to-do or note per line, ready to drop into Jot.
        var lines: [String]
        /// Everything Vision read, top to bottom.
        var printed: [String]
    }

    static func read(_ image: CGImage, now: Date = .now) async -> Read {
        let printed = await recognizedLines(in: image)
        guard !printed.isEmpty else { return Read(lines: [], printed: []) }
        if OnDevice.canSeeImages, let items = await modelItems(image, printed: printed, now: now) {
            let kept = keep(items, printed: printed)
            if !kept.isEmpty { return Read(lines: kept, printed: printed) }
        }
        return Read(lines: ruleLines(printed), printed: printed)
    }

    // MARK: Vision

    static func recognizedLines(in image: CGImage) async -> [String] {
        await withCheckedContinuation { (done: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    // Top to bottom (Vision's y runs up from the bottom), then left to right.
                    let sorted = observations.sorted {
                        let a = $0.boundingBox, b = $1.boundingBox
                        if abs(a.midY - b.midY) > 0.01 { return a.midY > b.midY }
                        return a.minX < b.minX
                    }
                    let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    done.resume(returning: Array(lines.prefix(80)))
                } catch {
                    done.resume(returning: [])
                }
            }
        }
    }

    // MARK: Model (iOS 27)

    private struct Reply: Decodable { var items: [String]? }

    private static func modelItems(_ image: CGImage, printed: [String], now: Date) async -> [String]? {
        let instructions = """
        You read a photo of a card, invitation, flyer, letter or note for someone \
        and list what they should remember or do because of it. Reply with JSON only: \
        {"items": ["..."]}. Each item is one short to-do in plain words, like \
        "RSVP to Sam and Lee's wedding by December 1". Use only what the photo says. \
        Keep any date exactly as printed. If there is nothing to do, reply {"items": []}.
        """
        let prompt = """
        Today is \(OnDevice.nowLine(now)).
        The printed words, as read from the photo:
        \(printed.joined(separator: "\n"))
        """
        guard let reply = await OnDevice.json(Reply.self, instructions: instructions, prompt: prompt, image: image) else { return nil }
        return (reply.items ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: Guards

    /// Keeps model items that share a real word with the print, and drops any
    /// date the print doesn't have.
    static func keep(_ items: [String], printed: [String]) -> [String] {
        let printedText = printed.joined(separator: "\n")
        let printedWords = words(printedText)
        let printedDays = days(in: printedText)
        var out: [String] = []
        for raw in items.prefix(12) {
            guard !words(raw).isDisjoint(with: printedWords) else { continue }
            var item = raw
            if let found = DateFinder.find(in: item) {
                let day = Calendar.current.startOfDay(for: found.date)
                if !printedDays.contains(day) {
                    item.removeSubrange(found.range)
                    item = tidy(item)
                }
            }
            if !item.isEmpty, !out.contains(item) { out.append(item) }
        }
        return out
    }

    /// Without the model: printed lines that carry a date or ask for something.
    /// If none do, the whole print as one line, which Jot reads as a note.
    static func ruleLines(_ printed: [String]) -> [String] {
        let asks = ["rsvp", "please", "due", "bring", "pay", "call", "reply", "register", "sign up", "by "]
        let picked = printed.filter { line in
            let lower = line.lowercased()
            return DateFinder.find(in: line) != nil || asks.contains { lower.contains($0) }
        }
        if !picked.isEmpty { return Array(picked.prefix(12)) }
        return [printed.joined(separator: " ")]
    }

    private static let stop: Set<String> = ["the", "and", "for", "you", "your", "with", "from", "this", "that", "are", "our", "will", "have", "please", "join"]

    private static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !stop.contains($0) })
    }

    private static func days(in text: String) -> Set<Date> {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let ns = NSRange(text.startIndex..., in: text)
        return Set(detector.matches(in: text, range: ns).compactMap { $0.date }.map { Calendar.current.startOfDay(for: $0) })
    }

    private static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+(by|on|at|before)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
    }
}
