import SwiftUI
import TogetherCore

struct OurPlansView: View {
    @ObservedObject var model: ApplicationModel
    @TogetherMotionPreference private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if os(macOS)
            PageHeading(title: model.section.title, subtitle: "")
                .togetherHorizontalPadding(30).padding(.top, 30)
            #endif
            ZStack(alignment: .topLeading) {
                TaskListView(model: model)
                    .opacity(model.plansMode == .tasks ? 1 : 0)
                    .offset(y: reduceMotion || model.plansMode == .tasks ? 0 : 8)
                    .allowsHitTesting(model.plansMode == .tasks).accessibilityHidden(model.plansMode != .tasks)
                WishesView(model: model)
                    .opacity(model.plansMode == .wishes ? 1 : 0)
                    .offset(y: reduceMotion || model.plansMode == .wishes ? 0 : 8)
                    .allowsHitTesting(model.plansMode == .wishes).accessibilityHidden(model.plansMode != .wishes)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .togetherAnimation(TogetherTheme.standardMotion(reduceMotion), value: model.plansMode)
        .onChange(of: model.plansMode) { _ in model.noteUserInteraction() }
        .onChange(of: model.taskFilter) { _ in model.noteUserInteraction() }
    }
}
