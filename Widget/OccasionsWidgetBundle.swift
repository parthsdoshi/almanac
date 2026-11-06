import SwiftUI
import WidgetKit

@main
struct OccasionsWidgetBundle: WidgetBundle {
    var body: some Widget {
        OccasionLiveActivity()
        WorkoutLiveActivity()
        NextOccasionWidget()
    }
}
