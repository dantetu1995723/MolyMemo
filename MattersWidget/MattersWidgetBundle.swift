import WidgetKit
import SwiftUI

@main
struct MattersWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeetingRecordingWidget()
        MeetingRecordingLiveActivity()
    }
}
