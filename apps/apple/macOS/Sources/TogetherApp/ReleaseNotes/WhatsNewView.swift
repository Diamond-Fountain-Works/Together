import SwiftUI
import TogetherCore

struct ReleaseEntry: Codable {
    let version: String
    let highlights: [ReleaseHighlight]
}
struct ReleaseHighlight: Codable, Identifiable {
    var id: String { titleKey }
    let titleKey: String
    let detailsKey: String
    let icon: String
}
struct WhatsNewView: View {
    let model: ApplicationModel
    private var release: ReleaseEntry? {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"), let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([ReleaseEntry].self, from: data) else { return nil }
        return entries.first { $0.version == model.version }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(Copy.text("copy.action.561b17edc33d")).font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(Copy.format("copy.status.c74259555cfc", String(describing: model.version))).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 22) { if let release {
                ForEach(release.highlights) { item in
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: item.icon).font(.system(size: 24, weight: .light)).foregroundStyle(TogetherTheme.rose).frame(width: 32)
                        VStack(alignment: .leading, spacing: 6) { Text(Copy.text(item.titleKey)).font(.headline); Text(Copy.text(item.detailsKey)).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            } else { Text(Copy.text("copy.status.a9ee56abd8fc")).foregroundStyle(.secondary) } } }.frame(maxHeight: 440)
            HStack { Spacer(); Button(Copy.text("copy.action.c0b3fbff51cc")) { model.preferences.sawRelease(version: model.version); model.dismissSheet() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 530).tint(TogetherTheme.rose)
    }
}
