import SwiftUI
import TogetherCore

struct WishesView: View {
    @Bindable var model: ApplicationModel
    @TogetherMotionPreference private var reduceMotion
    private var grants: [WishGrant] {
        model.engine.snapshot.grants.values.sorted {
            $0.grantedOn == $1.grantedOn ? ($0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt) : $0.grantedOn > $1.grantedOn
        }
    }
    private var days: [String] { Array(Set(grants.map { $0.grantedOn.iso })).sorted(by: >) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.engine.context.peer == nil {
                    ContentUnavailableView {
                        Label(Copy.text("plans.empty.unpairedWishes"), systemImage: "link")
                    } actions: {
                        Button(Copy.text("nav.connection")) { model.section = .connection }
                    }.frame(minHeight: 230).accessibilityIdentifier("plans.wishes.unpaired")
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(model.engine.sharedSpace.memberIds, id: \.self) { fulfiller in
                            if let beneficiary = model.engine.sharedSpace.memberIds.first(where: { $0 != fulfiller }) {
                                directionCard(fulfiller: fulfiller, beneficiary: beneficiary)
                            }
                        }
                    }
                }
                if model.engine.context.peer != nil {
                    Text(Copy.text("copy.status.47ada653c100")).font(.headline)
                    if grants.isEmpty {
                        Text(Copy.text("copy.empty_state.2dfc21ff5af0")).foregroundStyle(.secondary)
                    }
                }
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            ForEach(grants.filter { $0.grantedOn.iso == day }) { grant in
                                grantRow(grant)
                            }
                        }.id(day)
                    }
                }.scrollTargetLayout().animation(TogetherTheme.quickMotion(reduceMotion), value: grants.map(\.id))
                if !model.engine.snapshot.conflicts.isEmpty {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(Copy.text("copy.status.b29a53070d95"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            ForEach(model.engine.snapshot.conflicts) { conflict in Text(Copy.domainMessage(conflict.reason)).font(.caption) }
                        }
                    }
                }
            }.padding(.horizontal, 30).padding(.bottom, 30)
        }.scrollPosition(id: $model.grantScrollAnchor, anchor: .top)
    }
    private func directionCard(fulfiller: UUID, beneficiary: UUID) -> some View {
        let direction = grants.filter { $0.fulfillerId == fulfiller && $0.beneficiaryId == beneficiary }
        let total = direction.reduce(0) { $0 + model.engine.snapshot.balance(for: $1.id).total }
        let fulfilled = direction.reduce(0) { $0 + model.engine.snapshot.balance(for: $1.id).fulfilled }
        let left = model.engine.snapshot.profiles[fulfiller], right = model.engine.snapshot.profiles[beneficiary]
        return TogetherCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(Copy.format("copy.guidance.3e122095ba88", left?.role.displayName ?? model.name(fulfiller), right?.role.displayName ?? model.name(beneficiary))).font(.headline)
                Text(Copy.format("copy.guidance.3e122095ba88", model.name(fulfiller), model.name(beneficiary))).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    statistic(Copy.text("status.grant.total"), total)
                    statistic(Copy.text("status.grant.fulfilled"), fulfilled)
                    statistic(Copy.text("status.grant.remaining"), total - fulfilled)
                }
            }
        }
    }
    private func grantRow(_ grant: WishGrant) -> some View {
        let balance = model.engine.snapshot.balance(for: grant.id)
        return Button { model.show(.grantDetail(grant.id)) } label: {
            TogetherCard {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(Copy.format("plans.grant.quantity", String(grant.quantity))).font(.headline).foregroundStyle(.primary)
                        Text(Copy.format("copy.guidance.3e122095ba88", model.name(grant.fulfillerId), model.name(grant.beneficiaryId))).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Copy.format("plans.grant.balance", String(balance.fulfilled), String(balance.remaining))).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("wish.grant.open." + grant.id.uuidString)
    }
    private func statistic(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Copy.format("copy.status.ee17b0047b75", String(value))).font(.title2.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
