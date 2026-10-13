import SwiftUI
import TogetherCore

private struct AdvisorStep {
    let title: String
    let text: String
    let icon: String
}
struct AdvisorView: View {
    let model: ApplicationModel
    @State private var step = 0
    @State private var neverAgain = false
    @TogetherMotionPreference private var reduceMotion
    @Namespace private var geometry
    private let steps = [
        AdvisorStep(title: Copy.text("copy.navigation.0e2226b5235f"), text: Copy.text("copy.guidance.a98b94457fae"), icon: "heart.fill"),
        AdvisorStep(title: Copy.text("copy.navigation.2d9f8587bda1"), text: Copy.text("copy.guidance.9da8edd95702"), icon: "checklist"),
        AdvisorStep(title: Copy.text("copy.status.762adf000094"), text: Copy.text("copy.guidance.66dd26b15065"), icon: "repeat"),
        AdvisorStep(title: Copy.text("copy.navigation.403cc21502eb"), text: Copy.text("copy.guidance.0a03873c8d2f"), icon: "sparkles"),
        AdvisorStep(title: Copy.text("copy.status.0657ef66163c"), text: Copy.text("copy.guidance.a0fdf83d30c9"), icon: "person.crop.circle"),
        AdvisorStep(title: Copy.text("copy.status.46f890d7fe72"), text: Copy.text("copy.guidance.b61a3a85f709"), icon: "envelope.badge.fill"),
        AdvisorStep(title: Copy.text("copy.status.f7c98742cb56"), text: Copy.text("copy.guidance.e88ca18d56f1"), icon: "link")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text(Copy.text("copy.action.58383b09e244")).font(.headline); Spacer(); Text(Copy.format("copy.guidance.f7fe73b265ee", String(describing: step + 1), String(describing: steps.count))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: steps[step].icon).font(.system(size: 42, weight: .light)).foregroundStyle(TogetherTheme.rose).matchedGeometryEffect(id: "advisor-icon", in: geometry)
                Text(steps[step].title).font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(steps[step].text).font(.body).lineSpacing(5).foregroundStyle(.secondary).frame(minHeight: 80, alignment: .top)
            }.id(step).transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
            HStack(spacing: 5) { ForEach(steps.indices, id: \.self) { index in Capsule().fill(index <= step ? TogetherTheme.rose : .secondary.opacity(0.18)).frame(height: 3) } }
            Toggle(Copy.text("copy.guidance.59f48b3f4a8e"), isOn: $neverAgain).disabled(model.preferences.neverShowAdvisorAgain)
                .onAppear { neverAgain = model.preferences.neverShowAdvisorAgain }
            HStack {
                Button(Copy.text("copy.action.a57b08a480b8")) { withAnimation(TogetherTheme.motion(reduceMotion)) { step -= 1 } }.disabled(step == 0)
                Button(Copy.text("copy.action.28d03596d24e")) { finish() }
                Spacer()
                Button(step == steps.count - 1 ? Copy.text("copy.action.a6c7a84baa67") : Copy.text("copy.action.1ff57a29d7c9")) {
                    if step == steps.count - 1 { finish() } else { withAnimation(TogetherTheme.motion(reduceMotion)) { step += 1 } }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 510).tint(TogetherTheme.rose)
    }
    private func finish() { model.preferences.finishAdvisor(neverAgain: neverAgain); model.dismissSheet() }
}
