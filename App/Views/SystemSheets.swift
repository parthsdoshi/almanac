import Contacts
import ContactsUI
import EventKit
import EventKitUI
import SwiftUI

/// Apple's own contact card, editable, in a sheet. This is where you link or
/// delete duplicate cards.
struct ContactCardSheet: UIViewControllerRepresentable {
    let contactID: String
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = CNContactStore()
        let root: UIViewController
        if let contact = try? store.unifiedContact(
            withIdentifier: contactID,
            keysToFetch: [CNContactViewController.descriptorForRequiredKeys()]
        ) {
            let card = CNContactViewController(for: contact)
            card.contactStore = store
            card.allowsEditing = true
            card.allowsActions = true
            root = card
        } else {
            root = MissingItemViewController(text: "This contact isn't in your contacts anymore.")
        }
        let done = onDone
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in done() })
        return UINavigationController(rootViewController: root)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

/// Apple's calendar event view, read-only, in a sheet.
struct CalendarEventSheet: UIViewControllerRepresentable {
    let event: EKEvent?
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let root: UIViewController
        if let event {
            let view = EKEventViewController()
            view.event = event
            view.allowsEditing = false
            view.allowsCalendarPreview = true
            root = view
        } else {
            root = MissingItemViewController(text: "This event isn't in your calendar anymore.")
        }
        let done = onDone
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in done() })
        return UINavigationController(rootViewController: root)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

private final class MissingItemViewController: UIViewController {
    private let text: String
    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Palette.paper
        let label = UILabel()
        label.text = text
        label.textColor = Theme.Palette.inkSoft
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }
}

/// Searchable list of your contacts, for pointing a calendar suggestion at a
/// different person. Built from the contacts the app already read.
struct ContactChooser: View {
    let contacts: [ContactSnapshot]
    let onPick: (ContactSnapshot) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ContactSnapshot] {
        let named = contacts.filter { !Self.name($0).isEmpty }
        let sorted = named.sorted { Self.name($0).localizedCaseInsensitiveCompare(Self.name($1)) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { Self.name($0).localizedCaseInsensitiveContains(query) || $0.nickname.localizedCaseInsensitiveContains(query) }
    }

    static func name(_ c: ContactSnapshot) -> String {
        [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.id) { c in
                Button {
                    onPick(c)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.name(c))
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(Theme.Colors.ink)
                        if let b = c.birthday {
                            Text("Has a birthday: \(Self.dateText(b))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.inkSoft)
                        }
                    }
                }
                .listRowBackground(Theme.Colors.card)
            }
            .paperBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Choose a contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    static func dateText(_ d: MonthDay) -> String {
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: d.month, day: d.day)) ?? .now
        return date.formatted(.dateTime.month(.wide).day())
    }
}
