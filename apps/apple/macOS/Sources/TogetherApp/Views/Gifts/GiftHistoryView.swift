import SwiftUI
import TogetherCore

struct GiftHistoryView: View {
    @ObservedObject var model: ApplicationModel
    @State private var deleting: DailyLoveGift?
    private var gifts: [DailyLoveGift] { model.engine.snapshot.gifts.values.filter { $0.isEffective && $0.deletedAt == nil }.sorted { $0.sentAt > $1.sentAt } }
    var body: some View {
        let pendingDeletion = deleting
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(Copy.text("copy.action.1555373b2da2")).font(.title2.weight(.semibold)); Spacer(); Button(Copy.text("copy.action.c0b3fbff51cc")) { model.dismissSheet() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("gift.history.close") }
            if gifts.isEmpty { TogetherEmptyState(Copy.text("copy.empty_state.bea225cddc76"), systemImage: TogetherSymbols.name("envelope")) }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(gifts) { gift in
                        TogetherCard {
                            HStack(alignment: .top, spacing: 12) {
                                AvatarView(profile: model.engine.snapshot.profiles[gift.senderId], size: 42, engine: model.engine)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.engine.snapshot.profiles[gift.senderId]?.displayName ?? Copy.text("copy.status.034fc48ba584")).font(.headline)
                                    Text(gift.textContent ?? (gift.audioAssetId != nil ? Copy.text("copy.status.17441747251a") : Copy.text("copy.status.57dc4c554054"))).lineLimit(2).foregroundColor(.secondary)
                                    Text(Copy.date(gift.sentAt, includeTime: true)).font(.caption).foregroundColor(Color.secondary.opacity(0.65))
                                    if gift.senderId == model.engine.identity.descriptor.userId { Text(model.engine.deliveryState(gift).displayName).font(.caption).foregroundColor(TogetherTheme.rose) }
                                    else if model.engine.presentation(gift.id).openedAt == nil { Text(Copy.text("copy.status.a0a4c71b52cc")).font(.caption).foregroundColor(TogetherTheme.rose) }
                                }; Spacer()
                                VStack(spacing: 12) {
                                    Button(model.engine.giftReady(gift) ? Copy.text("copy.action.db8db0530432") : Copy.text("copy.action.3f4d60ed6945")) {
                                        if model.engine.giftReady(gift) { model.replaceSheet(.giftReveal([gift.id], false)) } else { model.synchronize() }
                                    }.disabled(!model.engine.giftReady(gift) && !model.isOnline).accessibilityIdentifier("gift.history.open." + gift.id.uuidString)
                                    if gift.senderId == model.engine.identity.descriptor.userId { TogetherRoleButton(Copy.text("copy.action.926a50b98ece"), role: .destructive) { deleting = gift }.buttonStyle(.borderless) }
                                }
                            }
                        }
                    }
                }
            }.frame(minHeight: 240, maxHeight: 470)
        }.togetherPadding(26).togetherSheetSize(width: 640)
        .togetherConfirmation(Copy.text("copy.guidance.244e9103eea5"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            confirmationTitle: Copy.text("copy.action.8719fc9a0abf")) {
                if let gift = pendingDeletion { model.perform { try model.engine.deleteGift(gift.id) } }; deleting = nil
            }
    }
}
