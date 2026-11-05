import Foundation
import Testing
@testable import Occasions

private let gregorian: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    gregorian.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

private func contact(
    _ id: String, _ given: String, _ family: String = "",
    birthday: MonthDay? = nil, anniversaries: [MonthDay] = [], partners: [String] = [],
    phones: [String] = ["+15550000000"]
) -> ContactSnapshot {
    ContactSnapshot(id: id, givenName: given, familyName: family, nickname: "", phones: phones,
                    birthday: birthday, anniversaries: anniversaries, partnerNames: partners)
}

@Suite struct MonthDayTests {
    @Test func dropsApplePlaceholderYear() {
        #expect(MonthDay(components: DateComponents(year: 1604, month: 3, day: 9))?.year == nil)
        #expect(MonthDay(components: DateComponents(year: 1990, month: 3, day: 9))?.year == 1990)
        #expect(MonthDay(components: DateComponents(month: 3, day: 9))?.year == nil)
    }

    @Test func rejectsIncomplete() {
        #expect(MonthDay(components: DateComponents(month: 3)) == nil)
        #expect(MonthDay(components: DateComponents(month: 13, day: 1)) == nil)
    }
}

@Suite struct RecurrenceTests {
    @Test func leapDayObservedOnFeb28() {
        let md = MonthDay(month: 2, day: 29)
        #expect(DayKey(Recurrence.date(of: md, inYear: 2027, calendar: gregorian), calendar: gregorian).rawValue == "2027-02-28")
        #expect(DayKey(Recurrence.date(of: md, inYear: 2028, calendar: gregorian), calendar: gregorian).rawValue == "2028-02-29")
    }

    @Test func nextIncludesToday() {
        let md = MonthDay(month: 11, day: 4)
        let next = Recurrence.next(md, onOrAfter: date(2026, 11, 4, hour: 23), calendar: gregorian)
        #expect(DayKey(next, calendar: gregorian).rawValue == "2026-11-04")
        #expect(Recurrence.daysUntil(next, from: date(2026, 11, 4, hour: 23), calendar: gregorian) == 0)
    }

    @Test func nextRollsToNextYear() {
        let next = Recurrence.next(MonthDay(month: 1, day: 2), onOrAfter: date(2026, 11, 4), calendar: gregorian)
        #expect(DayKey(next, calendar: gregorian).rawValue == "2027-01-02")
    }
}

@Suite struct OccasionBuilderTests {
    @Test func birthdayPerContact() {
        let occasions = OccasionBuilder.build(from: [
            contact("a", "Priya", birthday: MonthDay(month: 5, day: 1)),
            contact("b", "Sam"),
        ])
        #expect(occasions.count == 1)
        #expect(occasions[0].title == "Priya's birthday")
    }

    @Test func coupleAnniversaryMergedAcrossBothCards() {
        let anniv = MonthDay(month: 6, day: 20, year: 2015)
        let occasions = OccasionBuilder.build(from: [
            contact("a", "Alex", "Kim", anniversaries: [anniv], partners: ["Sam Lee"]),
            contact("b", "Sam", "Lee", anniversaries: [MonthDay(month: 6, day: 20)]),
        ])
        #expect(occasions.count == 1)
        #expect(occasions[0].people.map(\.givenName) == ["Alex", "Sam"])
        #expect(occasions[0].date.year == 2015)
        #expect(occasions[0].title == "Alex & Sam's anniversary")
    }

    @Test func partnerFoundFromTheOtherCard() {
        let occasions = OccasionBuilder.build(from: [
            contact("a", "Alex", anniversaries: [MonthDay(month: 6, day: 20)]),
            contact("b", "Sam", partners: ["Alex"]),
        ])
        #expect(occasions.first?.people.count == 2)
    }

    @Test func idIgnoresDateSoEditsKeepMute() {
        let a = Occasion(kind: .birthday, people: [contact("a", "P").person], date: MonthDay(month: 1, day: 1))
        let b = Occasion(kind: .birthday, people: [contact("a", "P").person], date: MonthDay(month: 2, day: 2))
        #expect(a.id == b.id)
        #expect(a.id.count == 16)
    }
}

@Suite struct StatsTests {
    private let priya = Occasion(kind: .birthday, people: [contact("a", "Priya").person], date: MonthDay(month: 3, day: 1))
    private let sam = Occasion(kind: .birthday, people: [contact("b", "Sam").person], date: MonthDay(month: 3, day: 10))
    private let jo = Occasion(kind: .birthday, people: [contact("c", "Jo").person], date: MonthDay(month: 3, day: 20))

    @Test func countsActedMissedPendingAndSkipsMuted() {
        let actions = [ActionRecord(occasionID: priya.id, instanceDay: DayKey(rawValue: "2027-03-01"), kind: .call, at: .now)]
        let stats = StatsCalculator.compute(
            occasions: [priya, sam, jo], muted: [sam.id], actions: actions,
            trackingStart: date(2027, 1, 1), today: date(2027, 3, 20), calendar: gregorian
        )
        #expect(stats.acted == 1)
        #expect(stats.missed == 0)
        #expect(stats.pending == 1)
        #expect(stats.actedRate == 1.0)
    }

    @Test func ignoresDatesBeforeTrackingStarted() {
        let stats = StatsCalculator.compute(
            occasions: [priya], muted: [], actions: [],
            trackingStart: date(2027, 3, 5), today: date(2028, 3, 5), calendar: gregorian
        )
        #expect(stats.missed == 1) // 2028 only
    }

    @Test func earlyAndLateActionsAttachToTheRightYear() {
        #expect(StatsCalculator.instanceDay(for: priya, actingAt: date(2027, 2, 25), calendar: gregorian).rawValue == "2027-03-01")
        #expect(StatsCalculator.instanceDay(for: priya, actingAt: date(2027, 3, 3), calendar: gregorian).rawValue == "2027-03-01")
    }
}

@Suite struct NotificationPlannerTests {
    @Test func plansLeadAndDayOfAtSendHour() {
        let o = Occasion(kind: .birthday, people: [contact("a", "Priya").person], date: MonthDay(month: 11, day: 10))
        var settings = Settings()
        settings.leadDays = 3
        settings.sendHour = 9
        let items = NotificationPlanner.plan(occasions: [o], settings: settings, includeDayOf: true,
                                             now: date(2026, 11, 4), calendar: gregorian)
        #expect(items.count == 2)
        #expect(items[0].fireComponents.day == 7)
        #expect(items[0].fireComponents.hour == 9)
        #expect(items[0].title == "Priya's birthday is in 3 days")
        #expect(items[1].fireComponents.day == 10)
    }

    @Test func skipsLeadThatAlreadyPassed() {
        let o = Occasion(kind: .birthday, people: [contact("a", "Priya").person], date: MonthDay(month: 11, day: 5))
        let items = NotificationPlanner.plan(occasions: [o], settings: Settings(), includeDayOf: false,
                                             now: date(2026, 11, 4), calendar: gregorian)
        #expect(items.isEmpty)
    }
}

@Suite struct BirthdayTitleParserTests {
    @Test(arguments: [
        ("Priya's Birthday", "Priya"),
        ("James' bday", "James"),
        ("Birthday - Priya Shah", "Priya Shah"),
        ("Bday: Sam", "Sam"),
        ("🎂 Jo birthday", "Jo"),
        ("Happy Birthday Alex!", "Alex"),
    ])
    func parses(title: String, name: String) {
        #expect(BirthdayTitleParser.name(from: title) == name)
    }

    @Test(arguments: ["My birthday", "Birthday dinner", "Team offsite", "Priya's birthday party"])
    func ignores(title: String) {
        #expect(BirthdayTitleParser.name(from: title) == nil)
    }

    @Test func suggestionsSkipContactsThatHaveBirthdays() {
        let contacts = [
            contact("a", "Priya", "Shah", birthday: MonthDay(month: 1, day: 1)),
            contact("b", "Sam", "Lee"),
        ]
        let s = SuggestionMatcher.suggestions(
            from: [.init(name: "Priya", date: MonthDay(month: 1, day: 1)),
                   .init(name: "Sam Lee", date: MonthDay(month: 4, day: 2)),
                   .init(name: "Sam Lee", date: MonthDay(month: 4, day: 2)),
                   .init(name: "Unknown Person", date: MonthDay(month: 7, day: 7))],
            contacts: contacts, dismissed: []
        )
        #expect(s.map(\.name) == ["Sam Lee", "Unknown Person"])
        #expect(s[0].contactID == "b")
        #expect(s[1].contactID == nil)
    }
}

@Suite struct DeepLinkTests {
    @Test func roundTrips() {
        let url = DeepLink.url(occasionID: "abc123", action: .call)
        #expect(url.absoluteString == "occasions://occasion/abc123/call")
        let parsed = DeepLink.parse(url)
        #expect(parsed?.occasionID == "abc123")
        #expect(parsed?.action == .call)
    }

    @Test func rejectsOthers() {
        #expect(DeepLink.parse(URL(string: "occasions://occasion/abc")!) == nil)
        #expect(DeepLink.parse(URL(string: "https://example.com/occasion/a/call")!) == nil)
    }

    @Test func headlineMatchesServer() {
        #expect(Names.headline(kind: .anniversary, names: ["Alex", "Sam"]) == "Alex & Sam's anniversary")
        #expect(Names.join(["A", "B", "C"]) == "A, B & C")
    }
}
