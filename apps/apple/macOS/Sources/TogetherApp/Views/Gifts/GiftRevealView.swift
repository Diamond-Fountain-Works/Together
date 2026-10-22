import SwiftUI
import TogetherCore

struct GiftRevealView: View {
    let model: ApplicationModel
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
                Text(gifts.count > 1 ? Copy.format("copy.emotional.07940efad8c3", String(describing: gifts.count)) : Copy.text("copy.emotional.c35685beea5a")).font(.caption).foregroundStyle(.secondary)
                Spacer(); Button(Copy.text("copy.action.3fd47edce45b"), systemImage: "xmark") { close() }.labelStyle(.iconOnly).buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityIdentifier("gift.close")
            }.padding(24)
            if let gift {
                ScrollView {
                    VStack(spacing: 22) {
                        Image(systemName: opened ? "heart.fill" : "envelope.badge.fill")
                            .font(.system(size: opened ? 42 : 72, weight: .ultraLight)).foregroundStyle(TogetherTheme.rose)
                            .matchedGeometryEffect(id: "gift-seal", in: envelope)
                            .padding(.top, opened ? 2 : 60)
                            .accessibilityHidden(true)
                        if opened {
                            GiftContentsView(model: model, gift: gift)
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
                            Text(LoveCopy.ending(sender: role(gift)))
                                .font(.callout.weight(.light)).foregroundStyle(TogetherTheme.rose).padding(.top, 12)
                                .transition(.opacity).animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.16), value: opened)
                        } else {
                            Text(LoveCopy.introduction(sender: role(gift))).font(.title2.weight(.medium)).multilineTextAlignment(.center)
                            Text(Copy.text("copy.status.99d1094feca8")).foregroundStyle(.secondary)
                            Button(Copy.text("copy.emotional.0fe0176cc04d")) {
                                model.perform { try model.engine.markGiftOpened(gift.id) }
                                withAnimation(TogetherTheme.motion(reduceMotion)) { opened = true }
                            }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 16).accessibilityIdentifier("gift.open")
                        }
                    }.padding(.horizontal, 36).padding(.bottom, 28).frame(maxWidth: .infinity)
                }.frame(minHeight: 330, maxHeight: 500)
                if opened {
                    VStack(spacing: 14) {
                        if gifts.count > 1 {
                            HStack {
                                Button(Copy.text("copy.action.d77339465930")) { change(-1) }.disabled(index == 0)
                                Spacer(); Text(Copy.format("copy.guidance.f7fe73b265ee", String(describing: index + 1), String(describing: gifts.count))).font(.caption.monospacedDigit()).foregroundStyle(.secondary); Spacer()
                                Button(Copy.text("copy.action.eca2213cf87f")) { change(1) }.disabled(index >= gifts.count - 1)
                            }
                        }
                        HStack {
                            if gift.recipientId == model.engine.identity.descriptor.userId {
                                Button(Copy.text("copy.emotional.8bd6be42784c")) { model.reply(to: gift.id) }
                            }
                            Spacer(); Button(Copy.text("copy.emotional.b26ee65bfb3b")) { close() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction).accessibilityIdentifier("gift.received")
                        }
                        if model.engine.hasSentGift(on: model.currentDate), gift.recipientId == model.engine.identity.descriptor.userId {
                            Text(Copy.text("copy.emotional.13049016bf03")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(24).background(.thinMaterial)
                        .transition(.opacity).animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.22), value: opened)
                }
            } else {
                ContentUnavailableView(Copy.text("copy.empty_state.7ff1ed89807d"), systemImage: "envelope")
                Button(Copy.text("copy.action.3fd47edce45b")) { close() }.padding(24)
            }
        }
        .frame(width: 660)
        .background(LinearGradient(colors: [TogetherTheme.rose.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        .onAppear {
            model.giftRevealDidAppear(automatic: automatic)
            if automatic { for gift in gifts { model.perform { try model.engine.markGiftPresented(gift.id, automatic: true) } } }
        }
    }
    private func role(_ gift: DailyLoveGift) -> RelationshipLabel { model.engine.snapshot.profiles[gift.senderId]?.role ?? .unknown }
    private func close() { withAnimation(TogetherTheme.motion(reduceMotion)) { model.dismissSheet() } }
    private func change(_ offset: Int) { withAnimation(TogetherTheme.motion(reduceMotion)) { index += offset; opened = false } }
}

struct GiftContentsView: View {
    let model: ApplicationModel
    let gift: DailyLoveGift
    private var profile: UserProfile? { model.engine.snapshot.profiles[gift.senderId] }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                AvatarView(profile: profile, size: 48, engine: model.engine)
                VStack(alignment: .leading, spacing: 5) { Text(profile?.displayName ?? Copy.text("copy.status.034fc48ba584")).font(.headline); Text(Copy.date(gift.sentAt, includeTime: true)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("gift.sentDate") }
                Spacer()
            }
            Text(LoveCopy.title(sender: profile?.role ?? .unknown, hasText: gift.hasText)).font(.title2.weight(.medium))
            if let text = gift.textContent, gift.hasText { Text(text).font(.system(size: 19)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("gift.privateText") }
            if let id = gift.audioAssetId, let asset = model.engine.snapshot.mediaAssets[id] {
                Text(Copy.text("copy.emotional.c6b12f8ce310")).font(.callout).foregroundStyle(.secondary)
                AudioPlayerView(url: model.engine.mediaStore.originalURL(asset))
            }
            if let id = gift.photoAssetId, let asset = model.engine.snapshot.mediaAssets[id] {
                Text(Copy.text("copy.emotional.99e20304bca5")).font(.callout).foregroundStyle(.secondary)
                MediaPhotoView(engine: model.engine, asset: asset).frame(maxHeight: 320)
                Button(Copy.text("copy.action.3b1ccae783f1"), systemImage: "square.and.arrow.down") { model.savePhoto(asset) }
                    .disabled(!model.engine.mediaStore.hasVerified(asset)).accessibilityIdentifier("gift.savePhoto")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
