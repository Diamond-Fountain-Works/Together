import SwiftUI
import TogetherCore

struct WishesView: View {
    @ObservedObject var model: ApplicationModel
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
                    TogetherEmptyState {
                        Label(Copy.text("plans.empty.unpairedWishes"), systemImage: TogetherSymbols.name("link"))
                    } actions: {
                        Button(Copy.text("nav.connection")) { model.section = .connection }
                    }.frame(minHeight: 230).accessibilityIdentifier("plans.wishes.unpaired")
                } else {
                    TogetherAdaptiveStack(spacing: 14) {
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
                        Text(Copy.text("copy.empty_state.2dfc21ff5af0")).foregroundColor(.secondary)
                    }
                }
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day).font(.subheadline.weight(.medium)).foregroundColor(.secondary)
                            ForEach(grants.filter { $0.grantedOn.iso == day }) { grant in
                                grantRow(grant)
                            }
                        }.id(day)
                    }
                }.togetherScrollTargetLayout().togetherAnimation(TogetherTheme.quickMotion(reduceMotion), value: grants.map(\.id))
                if !model.engine.snapshot.conflicts.isEmpty {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(Copy.text("copy.status.b29a53070d95"), systemImage: TogetherSymbols.name("exclamationmark.triangle")).foregroundColor(.orange)
                            ForEach(model.engine.snapshot.conflicts) { conflict in Text(Copy.domainMessage(conflict.reason)).font(.caption) }
                        }
                    }
                }
            }.togetherHorizontalPadding(30).padding(.bottom, 30)
        }.togetherScrollPosition(id: $model.grantScrollAnchor, anchor: .top)
    }
    private func directionCard(fulfiller: UUID, beneficiary: UUID) -> some View {
        let direction = grants.filter { $0.fulfillerId == fulfiller && $0.beneficiaryId == beneficiary }
        let total = direction.reduce(0) { $0 + model.engine.snapshot.balance(for: $1.id).total }
        let fulfilled = direction.reduce(0) { $0 + model.engine.snapshot.balance(for: $1.id).fulfilled }
        let left = model.engine.snapshot.profiles[fulfiller], right = model.engine.snapshot.profiles[beneficiary]
        return TogetherCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(Copy.format("copy.guidance.3e122095ba88", left?.role.displayName ?? model.name(fulfiller), right?.role.displayName ?? model.name(beneficiary))).font(.headline)
                Text(Copy.format("copy.guidance.3e122095ba88", model.name(fulfiller), model.name(beneficiary))).font(.caption).foregroundColor(.secondary)
                TogetherAccessibleStack(spacing: 12) {
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
                TogetherAdaptiveStack(spacing: 12, desktop: .init(spacing: 16)) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(Copy.format("plans.grant.quantity", String(grant.quantity))).font(.headline).foregroundColor(.primary)
                        Text(Copy.format("copy.guidance.3e122095ba88", model.name(grant.fulfillerId), model.name(grant.beneficiaryId))).font(.callout).foregroundColor(.secondary)
                    }
                    #if os(macOS)
                    Spacer()
                    #endif
                    #if os(macOS)
                    Text(Copy.format("plans.grant.balance", String(balance.fulfilled), String(balance.remaining))).font(.caption).foregroundColor(.secondary)
                    Image(systemName: TogetherSymbols.name("chevron.right")).font(.caption).foregroundColor(Color.secondary.opacity(0.65))
                    #else
                    HStack {
                        Text(Copy.format("plans.grant.balance", String(balance.fulfilled), String(balance.remaining))).font(.caption).foregroundColor(.secondary)
                        Image(systemName: TogetherSymbols.name("chevron.right")).font(.caption).foregroundColor(Color.secondary.opacity(0.65))
                    }
                    #endif
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("wish.grant.open." + grant.id.uuidString)
    }
    private func statistic(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(Copy.format("copy.status.ee17b0047b75", String(value))).font(.title2.weight(.semibold).monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
