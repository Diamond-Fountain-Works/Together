import SwiftUI
import TogetherCore

struct GiftRevealView: View {
    @ObservedObject var model: ApplicationModel
    let giftIds: [UUID]
    var automatic: Bool = false
    @State private var index = 0
    @State private var opened = false
    @TogetherMotionPreference private var reduceMotion
    @Namespace private var envelope
    private var gifts: [DailyLoveGift] {
        giftIds.compactMap { model.engine.snapshot.gifts[$0] }.filter {
            $0.deletedAt == nil && $0.isEffective && model.engine.giftReady($0) && ($0.senderId == model.engine.identity.descriptor.userId || model.engine.validReceivedGift($0))
        }
    }
    private var gift: DailyLoveGift? { gifts.indices.contains(index) ? gifts[index] : gifts.first }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(gifts.count > 1 ? Copy.format("copy.emotional.07940efad8c3", String(describing: gifts.count)) : Copy.text("copy.emotional.c35685beea5a")).font(.caption).foregroundColor(.secondary)
                Spacer(); TogetherIconButton(Copy.text("copy.action.3fd47edce45b"), systemImage: TogetherSymbols.name("xmark")) { close() }.labelStyle(.iconOnly).togetherTouchTarget().buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityIdentifier("gift.close")
            }.togetherPadding(24)
            if let gift {
                ScrollView {
                    VStack(spacing: 22) {
                        Image(systemName: TogetherSymbols.name(opened ? "heart.fill" : "envelope.badge.fill"))
                            .font(.system(size: opened ? 42 : 72, weight: .ultraLight)).foregroundColor(TogetherTheme.rose)
                            .matchedGeometryEffect(id: "gift-seal", in: envelope)
                            .padding(.top, opened ? 2 : 60)
                            .accessibilityHidden(true)
                        if opened {
                            GiftContentsView(model: model, gift: gift)
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
                            Text(LoveCopy.ending(sender: role(gift)))
                                .font(.callout.weight(.light)).foregroundColor(TogetherTheme.rose).padding(.top, 12)
                                .transition(.opacity).togetherAnimation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.16), value: opened)
                            #if os(iOS)
                            giftActions(gift)
                            #endif
                        } else {
                            Text(LoveCopy.introduction(sender: role(gift))).font(.title2.weight(.medium)).multilineTextAlignment(.center)
                            Button(Copy.text("copy.emotional.0fe0176cc04d")) {
                                model.perform { try model.engine.markGiftOpened(gift.id) }
                                withAnimation(TogetherTheme.motion(reduceMotion)) { opened = true }
                            }.togetherProminentButton().togetherLargeControl().padding(.top, 16).accessibilityIdentifier("gift.open")
                        }
                    }.togetherHorizontalPadding(36).padding(.bottom, 28).frame(maxWidth: .infinity)
                }.frame(minHeight: TogetherPlatform.giftContentMinimumHeight, maxHeight: 500)
                #if os(macOS)
                if opened { giftActions(gift) }
                #endif
            } else {
                TogetherEmptyState(Copy.text("copy.empty_state.7ff1ed89807d"), systemImage: TogetherSymbols.name("envelope"))
                Button(Copy.text("copy.action.3fd47edce45b")) { close() }.togetherPadding(24)
            }
        }
        .togetherSheetSize(width: 660)
        .background(LinearGradient(gradient: Gradient(colors: [TogetherTheme.rose.opacity(0.12), .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
        .onAppear {
            model.giftRevealDidAppear(automatic: automatic)
            if automatic { for gift in gifts { model.perform { try model.engine.markGiftPresented(gift.id, automatic: true) } } }
        }
    }
    private func giftActions(_ gift: DailyLoveGift) -> some View {
        VStack(spacing: 14) {
            if gifts.count > 1 {
                HStack {
                    Button(Copy.text("copy.action.d77339465930")) { change(-1) }.disabled(index == 0)
                    Spacer()
                    Text(Copy.format("copy.guidance.f7fe73b265ee", String(index + 1), String(gifts.count))).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    Spacer()
                    Button(Copy.text("copy.action.eca2213cf87f")) { change(1) }.disabled(index >= gifts.count - 1)
                }
            }
            TogetherAdaptiveStack(spacing: 12, desktop: .init()) {
                if gift.recipientId == model.engine.identity.descriptor.userId {
                    Button(Copy.text("copy.emotional.8bd6be42784c")) { model.reply(to: gift.id) }.togetherTouchTarget()
                }
                #if os(macOS)
                Spacer()
                #endif
                Button(Copy.text("copy.emotional.b26ee65bfb3b")) { close() }
                    .togetherProminentButton().togetherLargeControl().togetherTouchTarget()
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("gift.received")
            }
            if model.engine.hasSentGift(on: model.currentDate), gift.recipientId == model.engine.identity.descriptor.userId {
                Text(Copy.text("copy.emotional.13049016bf03")).font(.caption).foregroundColor(.secondary)
            }
        }.togetherPadding(24).togetherMaterialSurface()
            .transition(.opacity).togetherAnimation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.22), value: opened)
    }
    private func role(_ gift: DailyLoveGift) -> RelationshipLabel { model.engine.snapshot.profiles[gift.senderId]?.role ?? .unknown }
    private func close() { withAnimation(TogetherTheme.motion(reduceMotion)) { model.dismissSheet() } }
    private func change(_ offset: Int) { withAnimation(TogetherTheme.motion(reduceMotion)) { index += offset; opened = false } }
}

struct GiftContentsView: View {
    @ObservedObject var model: ApplicationModel
    let gift: DailyLoveGift
    private var profile: UserProfile? { model.engine.snapshot.profiles[gift.senderId] }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                AvatarView(profile: profile, size: 48, engine: model.engine)
                VStack(alignment: .leading, spacing: 5) { Text(profile?.displayName ?? Copy.text("copy.status.034fc48ba584")).font(.headline); Text(Copy.date(gift.sentAt, includeTime: true)).font(.caption).foregroundColor(.secondary).accessibilityIdentifier("gift.sentDate") }
                Spacer()
            }
            Text(LoveCopy.title(sender: profile?.role ?? .unknown, hasText: gift.hasText)).font(.title2.weight(.medium))
            if let text = gift.textContent, gift.hasText { giftText(text).lineSpacing(6).togetherTextSelection().fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("gift.privateText") }
            if let id = gift.audioAssetId, let asset = model.engine.snapshot.mediaAssets[id] {
                Text(Copy.text("copy.emotional.c6b12f8ce310")).font(.callout).foregroundColor(.secondary)
                AudioPlayerView(url: model.engine.mediaStore.originalURL(asset))
            }
            if let id = gift.photoAssetId, let asset = model.engine.snapshot.mediaAssets[id] {
                Text(Copy.text("copy.emotional.99e20304bca5")).font(.callout).foregroundColor(.secondary)
                MediaPhotoView(engine: model.engine, asset: asset).frame(maxHeight: 320)
                TogetherIconButton(Copy.text("copy.action.3b1ccae783f1"), systemImage: TogetherSymbols.name("square.and.arrow.down")) { model.savePhoto(asset) }
                    .disabled(!model.engine.mediaStore.hasVerified(asset)).accessibilityIdentifier("gift.savePhoto")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func giftText(_ text: String) -> Text {
        #if os(iOS)
        Text(text).font(.body)
        #else
        Text(text).font(.system(size: 19))
        #endif
    }
}
