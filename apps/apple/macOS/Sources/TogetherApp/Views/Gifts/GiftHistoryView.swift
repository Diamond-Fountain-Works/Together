import SwiftUI
import TogetherCore

struct GiftHistoryView: View {
    let model: ApplicationModel
    @State private var deleting: DailyLoveGift?
    private var gifts: [DailyLoveGift] { model.engine.snapshot.gifts.values.filter { $0.isEffective && $0.deletedAt == nil }.sorted { $0.sentAt > $1.sentAt } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(Copy.text("copy.action.1555373b2da2")).font(.title2.weight(.semibold)); Spacer(); Button(Copy.text("copy.action.c0b3fbff51cc")) { model.dismissSheet() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("gift.history.close") }
            if gifts.isEmpty { ContentUnavailableView(Copy.text("copy.empty_state.bea225cddc76"), systemImage: "envelope") }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(gifts) { gift in
                        TogetherCard {
                            HStack(alignment: .top, spacing: 12) {
                                AvatarView(profile: model.engine.snapshot.profiles[gift.senderId], size: 42, engine: model.engine)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.engine.snapshot.profiles[gift.senderId]?.displayName ?? Copy.text("copy.status.034fc48ba584")).font(.headline)
                                    Text(gift.textContent ?? (gift.audioAssetId != nil ? Copy.text("copy.status.17441747251a") : Copy.text("copy.status.57dc4c554054"))).lineLimit(2).foregroundStyle(.secondary)
                                    Text(gift.sentAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.tertiary)
                                    if gift.senderId == model.engine.identity.descriptor.userId { Text(model.engine.deliveryState(gift).displayName).font(.caption).foregroundStyle(TogetherTheme.rose) }
                                    else if model.engine.presentation(gift.id).openedAt == nil { Text(Copy.text("copy.status.a0a4c71b52cc")).font(.caption).foregroundStyle(TogetherTheme.rose) }
                                }; Spacer()
                                VStack(spacing: 12) {
                                    Button(model.engine.giftReady(gift) ? Copy.text("copy.action.db8db0530432") : Copy.text("copy.action.3f4d60ed6945")) {
                                        if model.engine.giftReady(gift) { model.replaceSheet(.giftReveal([gift.id], false)) } else { model.network.synchronize() }
                                    }.disabled(!model.engine.giftReady(gift) && !model.network.isOnline).accessibilityIdentifier("gift.history.open." + gift.id.uuidString)
                                    if gift.senderId == model.engine.identity.descriptor.userId { Button(Copy.text("copy.action.926a50b98ece"), role: .destructive) { deleting = gift }.buttonStyle(.borderless) }
                                }
                            }
                        }
                    }
                }
            }.frame(minHeight: 240, maxHeight: 470)
        }.padding(26).frame(width: 640)
        .confirmationDialog(Copy.text("copy.guidance.244e9103eea5"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(Copy.text("copy.action.8719fc9a0abf"), role: .destructive) { if let gift = deleting { model.perform { try model.engine.deleteGift(gift.id) } }; deleting = nil }
        }
    }
}
