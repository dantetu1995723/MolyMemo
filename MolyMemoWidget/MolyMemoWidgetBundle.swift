import WidgetKit
import SwiftUI

@main
struct MolyMemoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeetingRecordingWidget()
        MeetingRecordingLiveActivity()
        ScreenshotSendLiveActivity()
    }
}
