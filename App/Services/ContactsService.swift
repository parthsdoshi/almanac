import Contacts
import Foundation

/// Plain value copy of the bits of a CNContact we use, so the occasion logic
/// is testable without a contact store.
struct ContactSnapshot: Hashable, Sendable {
    let id: String
    let givenName: String
    let familyName: String
    let nickname: String
    let phones: [String]          // best first
    let birthday: MonthDay?
    let anniversaries: [MonthDay]
    let partnerNames: [String]    // names from spouse/partner relations

    var person: Person {
        Person(contactID: id, givenName: givenName, familyName: familyName, phoneNumbers: phones)
    }
}

extension ContactSnapshot {
    init(_ contact: CNContact) {
        self.init(
            id: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            nickname: contact.nickname,
            phones: Self.orderedPhones(contact.phoneNumbers),
            birthday: contact.birthday.flatMap(MonthDay.init(components:)),
            anniversaries: contact.dates
                .filter { Self.isAnniversary($0.label) }
                .compactMap { MonthDay(components: $0.value as DateComponents) },
            partnerNames: contact.contactRelations
                .filter { Self.isPartner($0.label) }
                .map { $0.value.name }
        )
    }

    private static func orderedPhones(_ numbers: [CNLabeledValue<CNPhoneNumber>]) -> [String] {
        func rank(_ label: String?) -> Int {
            switch label {
            case CNLabelPhoneNumberiPhone: 0
            case CNLabelPhoneNumberMobile: 1
            case CNLabelPhoneNumberMain: 2
            default: 3
            }
        }
        return numbers
            .enumerated()
            .sorted { (rank($0.element.label), $0.offset) < (rank($1.element.label), $1.offset) }
            .map { $0.element.value.stringValue }
    }

    private static func isAnniversary(_ label: String?) -> Bool {
        guard let label else { return false }
        if label == CNLabelDateAnniversary { return true }
        return label.lowercased().contains("anniversary")
    }

    private static func isPartner(_ label: String?) -> Bool {
        guard let label else { return false }
        let system: Set<String> = [
            CNLabelContactRelationSpouse, CNLabelContactRelationPartner,
            CNLabelContactRelationHusband, CNLabelContactRelationWife,
        ]
        if system.contains(label) { return true }
        return ["spouse", "partner", "husband", "wife"].contains(label.lowercased())
    }
}

struct ContactsService {
    enum Access: Equatable {
        case notDetermined, denied, limited, full
        var canRead: Bool { self == .full || self == .limited }
    }

    private let store = CNContactStore()

    static func currentAccess() -> Access {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .full
        case .denied, .restricted: return .denied
        default:
            if #available(iOS 18.0, *), status == .limited { return .limited }
            return .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    /// Blocking. Call off the main actor.
    func fetchSnapshots() throws -> [ContactSnapshot] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactNicknameKey, CNContactPhoneNumbersKey, CNContactBirthdayKey,
            CNContactDatesKey, CNContactRelationsKey,
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        var result: [ContactSnapshot] = []
        try store.enumerateContacts(with: request) { contact, _ in
            result.append(ContactSnapshot(contact))
        }
        return result
    }

    /// Which account each contact card lives in ("iCloud", "Gmail", "On My iPhone"),
    /// keyed by card id. Linked cards are listed separately; a unified contact's id
    /// is usually one of them. Blocking. Call off the main actor.
    func fetchSources() -> [String: String] {
        guard let containers = try? store.containers(matching: nil) else { return [:] }
        var result: [String: String] = [:]
        for container in containers {
            let label = Self.label(for: container)
            let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
            request.unifyResults = false
            try? store.enumerateContacts(with: request) { contact, _ in
                result[contact.identifier] = label
            }
        }
        return result
    }

    private static func label(for container: CNContainer) -> String {
        switch container.name {
        case "Card", "iCloud": return "iCloud"
        case "": break
        default: return container.name
        }
        switch container.type {
        case .local: return "On My iPhone"
        case .exchange: return "Exchange"
        case .cardDAV: return "an online account"
        default: return "Contacts"
        }
    }

    /// Adds a year-less birthday to an existing contact.
    func setBirthday(_ date: MonthDay, contactID: String) throws {
        let contact = try store.unifiedContact(
            withIdentifier: contactID,
            keysToFetch: [CNContactBirthdayKey as CNKeyDescriptor]
        )
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
        mutable.birthday = DateComponents(month: date.month, day: date.day)
        let request = CNSaveRequest()
        request.update(mutable)
        try store.execute(request)
    }

    /// Sets a birthday (with the year when known) on an existing contact, replacing any.
    func setBirthday(_ date: MonthDay, includingYear: Bool, contactID: String) throws {
        let contact = try store.unifiedContact(
            withIdentifier: contactID,
            keysToFetch: [CNContactBirthdayKey as CNKeyDescriptor]
        )
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
        mutable.birthday = DateComponents(year: includingYear ? date.year : nil, month: date.month, day: date.day)
        let request = CNSaveRequest()
        request.update(mutable)
        try store.execute(request)
    }

    /// Adds an anniversary date to an existing contact.
    func addAnniversary(_ date: MonthDay, contactID: String) throws {
        let contact = try store.unifiedContact(
            withIdentifier: contactID,
            keysToFetch: [CNContactDatesKey as CNKeyDescriptor]
        )
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
        let value = DateComponents(year: date.year, month: date.month, day: date.day) as NSDateComponents
        mutable.dates.append(CNLabeledValue(label: CNLabelDateAnniversary, value: value))
        let request = CNSaveRequest()
        request.update(mutable)
        try store.execute(request)
    }

    /// Creates a contact with a name and either a birthday or an anniversary.
    func createContact(name: String, kind: OccasionKind, date: MonthDay) throws {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        let contact = CNMutableContact()
        contact.givenName = parts.first ?? name
        contact.familyName = parts.count > 1 ? parts[1] : ""
        let components = DateComponents(year: date.year, month: date.month, day: date.day)
        switch kind {
        case .birthday: contact.birthday = components
        case .anniversary: contact.dates = [CNLabeledValue(label: CNLabelDateAnniversary, value: components as NSDateComponents)]
        }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
    }

    /// Creates a new contact with just a name and a year-less birthday.
    func createContact(name: String, birthday: MonthDay) throws {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        let contact = CNMutableContact()
        contact.givenName = parts.first ?? name
        contact.familyName = parts.count > 1 ? parts[1] : ""
        contact.birthday = DateComponents(month: birthday.month, day: birthday.day)
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
    }
}
