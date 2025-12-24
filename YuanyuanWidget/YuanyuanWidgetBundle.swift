import WidgetKit
import SwiftUI

@main
struct YuanyuanWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeetingRecordingWidget()
        MeetingRecordingLiveActivity()
        ScreenshotSendLiveActivity()
    }
}
