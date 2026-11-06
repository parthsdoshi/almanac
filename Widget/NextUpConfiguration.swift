import AppIntents
import WidgetKit

/// Who the Next up widget counts down to. Long-press the widget, Edit Widget.
enum NextUpAudience: String, AppEnum {
    case everyone, starred

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "People"
    static let caseDisplayRepresentations: [NextUpAudience: DisplayRepresentation] = [
        .everyone: "Everyone",
        .starred: "Starred only",
    ]
}

struct NextUpConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Next up"
    static let description = IntentDescription("Choose whose birthdays and anniversaries the widget counts down to.")

    @Parameter(title: "Show", default: .everyone)
    var show: NextUpAudience

    init() {}
    init(show: NextUpAudience) { self.show = show }
}
