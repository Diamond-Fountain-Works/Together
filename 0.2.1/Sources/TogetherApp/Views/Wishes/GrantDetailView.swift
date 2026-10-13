import SwiftUI
import TogetherCore

struct GrantDetailView: View {
    let model: ApplicationModel
    let grantId: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Copy.text("plans.grant.details")).font(.title2.weight(.semibold))
            ScrollView {
                if let grant = model.engine.snapshot.grants[grantId] { GrantContentView(model: model, grant: grant) }
            }
            HStack {
                Spacer()
                Button(Copy.text("copy.action.3fd47edce45b")) { model.dismissSheet() }
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("wish.grant.detail.close")
            }
        }.padding(26).frame(width: 620, height: 620)
    }
}

private struct GrantContentView: View {
    let model: ApplicationModel
    let grant: WishGrant
    private var balance: GrantBalance { model.engine.snapshot.balance(for: grant.id) }
    private var wishes: [WishItem] { model.engine.snapshot.wishes.values.filter { $0.grantId == grant.id }.sorted { $0.createdAt < $1.createdAt } }
    var body: some View {
        TogetherCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(grant.grantedOn.display).font(.headline)
                        Text(Copy.format("copy.guidance.4b7a5cfdcc8b", String(describing: model.name(grant.fulfillerId)), String(describing: model.name(grant.beneficiaryId)), String(describing: grant.quantity))).font(.callout)
                        if !grant.notes.isEmpty { Text(grant.notes).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if grant.beneficiaryId == model.engine.identity.descriptor.userId || grant.createdBy == model.engine.identity.descriptor.userId { Menu {
                        
                        if grant.createdBy == model.engine.identity.descriptor.userId { Button(Copy.text("copy.action.b1318a136ca8")) { model.replaceSheet(.adjustment(grant.id)) } }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize() }
                }
                Text(Copy.format("copy.guidance.11c84b5da239", String(describing: balance.total), String(describing: balance.fulfilled), String(describing: balance.remaining), String(describing: balance.availableToDefine))).font(.caption).foregroundStyle(.secondary)
                ForEach(model.engine.snapshot.adjustments.filter { $0.grantId == grant.id }) { adjustment in
                    Text(Copy.format("copy.guidance.fc1abea23df7", String(describing: adjustment.delta > 0 ? "+" : ""), String(describing: adjustment.delta), String(describing: adjustment.notes), String(describing: adjustment.isEffective ? "" : "（冲突，未生效）"))).font(.caption).foregroundStyle(adjustment.isEffective ? Color.secondary : Color.orange)
                }
                if grant.beneficiaryId == model.engine.identity.descriptor.userId && balance.availableToDefine > 0 {
                    Button(Copy.text("copy.action.2b5c98884cf4"), systemImage: "plus") { model.replaceSheet(.wish(grant.id)) }.buttonStyle(.borderless)
                }
                ForEach(wishes) { wish in
                    Divider()
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(wish.title).font(.headline)
                            if !wish.description.isEmpty { Text(wish.description).font(.callout).foregroundStyle(.secondary) }
                            Text(status(wish)).font(.caption).foregroundStyle(wish.status == .conflict ? .orange : .secondary)
                            if let date = wish.fulfilledAt { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if wish.status == .open && wish.fulfillerId == model.engine.identity.descriptor.userId {
                            Button(Copy.text("copy.action.484f849e7525")) { model.perform { try model.engine.requestFulfillment(wish.id) } }.buttonStyle(.bordered)
                        }
                        if wish.status == .completionRequested && wish.beneficiaryId == model.engine.identity.descriptor.userId {
                            VStack {
                                Button(Copy.text("copy.action.dad277e51ae2")) { model.perform { try model.engine.confirmFulfillment(wish.id) } }.buttonStyle(.borderedProminent)
                                Button(Copy.text("copy.action.042811378798")) { model.perform { try model.engine.rejectFulfillment(wish.id) } }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
    }
    private func status(_ wish: WishItem) -> String {
        switch wish.status { case .open: Copy.text("status.wish.open"); case .completionRequested: Copy.text("status.wish.requested"); case .fulfilled: Copy.text("status.wish.fulfilled"); case .conflict: wish.conflictReason ?? Copy.text("status.wish.conflict") }
    }
}
