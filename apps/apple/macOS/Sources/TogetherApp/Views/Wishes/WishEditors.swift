import SwiftUI
import TogetherCore

struct GrantEditorView: View {
    @ObservedObject var model: ApplicationModel
    @State private var fulfiller: UUID
    @State private var quantity = 1
    @State private var date = Date()
    @State private var notes = ""
    init(model: ApplicationModel) { self.model = model; _fulfiller = State(initialValue: model.engine.identity.descriptor.userId) }
    private var beneficiary: UUID? { model.engine.sharedSpace.memberIds.first { $0 != fulfiller } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Copy.text("copy.action.2c183d9579b2")).font(.title2.weight(.semibold))
            Form {
                Picker(Copy.text("copy.guidance.08dcdf90fcc3"), selection: $fulfiller) { ForEach(model.engine.sharedSpace.memberIds, id: \.self) { id in Text(model.name(id)).tag(id) } }
                if let beneficiary { TogetherLabeledContent(Copy.text("copy.guidance.0c6275143832"), value: model.name(beneficiary)) }
                Stepper(Copy.format("copy.guidance.07f35068c6b0", String(describing: quantity)), value: $quantity, in: 1...1000)
                DatePicker(Copy.text("copy.guidance.e275ab5889fc"), selection: $date, displayedComponents: .date)
                TogetherMultilineField(Copy.text("copy.guidance.daede9881787"), text: $notes)
            }.togetherGroupedForm()
            HStack { Button(Copy.text("copy.action.2cd0f3be8738")) { model.dismissSheet() }; Spacer(); Button(Copy.text("copy.action.68db52a61059")) {
                model.perform { guard let beneficiary else { throw TogetherError.invalid(Copy.text("copy.error.f542f9884467")) }; try model.engine.grant(fulfiller: fulfiller, beneficiary: beneficiary, quantity: quantity, date: CivilDate(date), notes: notes); model.dismissSheet() }
            }.togetherProminentButton().disabled(beneficiary == nil) }
        }.togetherPadding(24).togetherSheetSize(width: 500)
    }
}
struct WishEditorView: View {
    @ObservedObject var model: ApplicationModel
    let grantId: UUID
    @State private var title = ""
    @State private var details = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Copy.text("copy.action.2b5c98884cf4")).font(.title2.weight(.semibold))
            Text(Copy.text("copy.status.3cfd61f73f08")).font(.callout).foregroundColor(.secondary)
            TextField(Copy.text("copy.guidance.c28964cec0df"), text: $title).textFieldStyle(.roundedBorder)
            TogetherMultilineField(Copy.text("copy.guidance.d4dfacae27fe"), text: $details).lineLimit(8).textFieldStyle(.roundedBorder)
            HStack { Button(Copy.text("copy.action.2cd0f3be8738")) { model.dismissSheet() }; Spacer(); Button(Copy.text("copy.action.2b072511a379")) { model.perform { try model.engine.createWish(grantId: grantId, title: title, description: details); model.dismissSheet() } }.togetherProminentButton().disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.togetherPadding(24).togetherSheetSize(width: 500)
    }
}
struct GrantAdjustmentView: View {
    @ObservedObject var model: ApplicationModel
    let grantId: UUID
    @State private var delta = 1
    @State private var notes = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Copy.text("copy.action.b1318a136ca8")).font(.title2.weight(.semibold))
            Text(Copy.text("copy.status.01b6f9e2d127")).foregroundColor(.secondary)
            Stepper(Copy.format("copy.guidance.18308177f358", String(describing: delta > 0 ? Copy.text("copy.guidance.a318c24216de") : ""), String(describing: delta)), value: $delta, in: -1000...1000)
            TogetherMultilineField(Copy.text("copy.guidance.cb63ca2a4003"), text: $notes).textFieldStyle(.roundedBorder)
            HStack { Button(Copy.text("copy.action.2cd0f3be8738")) { model.dismissSheet() }; Spacer(); Button(Copy.text("copy.action.2388bd52fae3")) { model.perform { try model.engine.adjustGrant(grantId, delta: delta, notes: notes); model.dismissSheet() } }.togetherProminentButton().disabled(delta == 0 || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.togetherPadding(24).togetherSheetSize(width: 500)
    }
}
