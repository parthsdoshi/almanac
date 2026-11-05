import Foundation

/// Name lookup over contacts, used to link spouses for couple anniversaries
/// and to match calendar birthday events to contacts.
struct NameIndex {
    private var byFullName: [String: [ContactSnapshot]] = [:]
    private var byGivenName: [String: [ContactSnapshot]] = [:]
    private var byNickname: [String: [ContactSnapshot]] = [:]
    private var reversePartner: [String: ContactSnapshot] = [:]

    init(_ contacts: [ContactSnapshot]) {
        for c in contacts {
            byFullName[Self.normalize("\(c.givenName) \(c.familyName)"), default: []].append(c)
            if !c.givenName.isEmpty { byGivenName[Self.normalize(c.givenName), default: []].append(c) }
            if !c.nickname.isEmpty { byNickname[Self.normalize(c.nickname), default: []].append(c) }
        }
        // If A lists B as spouse, B's partner is A even when B lists nobody.
        for c in contacts {
            for name in c.partnerNames {
                if let p = resolve(name), p.id != c.id, reversePartner[p.id] == nil {
                    reversePartner[p.id] = c
                }
            }
        }
    }

    /// A unique match by full name, then given name, then nickname. Ambiguous names return nil.
    func resolve(_ name: String) -> ContactSnapshot? {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return nil }
        for table in [byFullName, byGivenName, byNickname] {
            if let matches = table[key] {
                return matches.count == 1 ? matches[0] : nil
            }
        }
        return nil
    }

    func partner(of contact: ContactSnapshot) -> ContactSnapshot? {
        for name in contact.partnerNames {
            if let p = resolve(name), p.id != contact.id { return p }
        }
        return reversePartner[contact.id]
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

enum OccasionBuilder {
    /// One occasion per birthday, and one per couple anniversary.
    /// An anniversary on a contact is paired with their spouse/partner (if that
    /// person is in Contacts), and the copy on the partner's card is merged in.
    static func build(from contacts: [ContactSnapshot]) -> [Occasion] {
        let index = NameIndex(contacts)
        var byID: [String: Occasion] = [:]

        for c in contacts {
            if let birthday = c.birthday {
                let o = Occasion(kind: .birthday, people: [c.person], date: birthday)
                byID[o.id] = o
            }
            for (n, anniversary) in c.anniversaries.enumerated() {
                var people = [c]
                if let partner = index.partner(of: c) { people.append(partner) }
                people.sort { ($0.givenName, $0.id) < ($1.givenName, $1.id) }
                let o = Occasion(kind: .anniversary, people: people.map(\.person), date: anniversary, discriminator: n)
                // Same couple from the other card: keep whichever copy knows the year.
                if let existing = byID[o.id], existing.date.year != nil || anniversary.year == nil { continue }
                byID[o.id] = o
            }
        }
        return Array(byID.values)
    }
}
