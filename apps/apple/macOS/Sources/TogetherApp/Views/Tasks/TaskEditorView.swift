import SwiftUI
import TogetherCore

struct TaskEditorView: View {
    @ObservedObject var model: ApplicationModel
    let task: TodoTask?
    @StateObject private var draft: TaskEditorDraft

    init(model: ApplicationModel, task: TodoTask?) {
        self.model = model; self.task = task
        _draft = StateObject(wrappedValue: TaskEditorDraft(task: task, engine: model.engine))
    }
    var body: some View {
        let titleIsEmpty = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 20) {
            Text(task == nil ? Copy.text("copy.action.718e58cc20d6") : Copy.text("copy.navigation.dda79d5a0e25")).font(.title2.weight(.semibold))
            Form {
                TextField(Copy.text("copy.guidance.c3405f8c7d9d"), text: $draft.title).accessibilityIdentifier("task.title")
                TogetherMultilineField(Copy.text("copy.guidance.daede9881787"), text: $draft.notes).accessibilityIdentifier("task.notes").lineLimit(6)
                Picker(Copy.text("copy.guidance.a525346277ed"), selection: $draft.assignedTo) {
                    Text(Copy.text("copy.status.f358a5db68a2")).tag(Optional<UUID>.none)
                    ForEach(model.engine.snapshot.profiles.values.sorted { $0.userId.uuidString < $1.userId.uuidString }) { profile in Text(profile.displayName).tag(Optional(profile.userId)) }
                }
                Toggle(Copy.text("copy.guidance.15f26621cdce"), isOn: $draft.hasDue)
                if let task {
                    Toggle(Copy.text("nav.completed"), isOn: $draft.isCompleted)
                        .togetherCheckboxToggle().disabled(task.visibleStatus(at: model.currentDate) == .scheduled).accessibilityIdentifier("task.completed")
                }
                if draft.hasDue { DatePicker(Copy.text("copy.guidance.1f29b74ad60c"), selection: $draft.due) }
                Picker(Copy.text("copy.guidance.609cf2fdf6ff"), selection: $draft.recurrenceMode) { Text(Copy.text("copy.guidance.ebdc3594be5c")).tag("none"); Text(Copy.text("copy.guidance.7c1555a09cc0")).tag("regular"); Text(Copy.text("copy.guidance.dabbb0b4041f")).tag("flexible") }
                if draft.recurrenceMode == "regular" {
                    Stepper(Copy.format("copy.guidance.1652b36ef8c9", String(describing: draft.interval)), value: $draft.interval, in: 1...99)
                    Picker(Copy.text("copy.guidance.80b19d68b149"), selection: $draft.unit) { Text(Copy.text("copy.guidance.5a730047d83f")).tag(RecurrenceUnit.day); Text(Copy.text("copy.guidance.977e8de6b21d")).tag(RecurrenceUnit.week); Text(Copy.text("copy.guidance.37ebdc8c2ff9")).tag(RecurrenceUnit.month) }
                    Text(Copy.text("copy.status.ef29accda79a")).font(.caption).foregroundColor(.secondary)
                } else if draft.recurrenceMode == "flexible" {
                    Text(Copy.text("copy.empty_state.73069fd00aeb")).font(.caption).foregroundColor(.secondary)
                }
            }.togetherGroupedForm()
            HStack {
                Button(Copy.text("copy.action.2cd0f3be8738")) { model.dismissSheet() }.togetherTouchTarget().keyboardShortcut(.cancelAction).accessibilityIdentifier("sheet.cancel")
                Spacer()
                Button(Copy.text("copy.action.a3030bf8f16d")) {
                    model.perform {
                        let recurring = RecurrenceMode(rawValue: draft.recurrenceMode).map { RecurrenceDraft(mode: $0, unit: draft.unit, interval: draft.interval) }
                        if let task {
                            try model.engine.editTask(task.id, title: draft.title, notes: draft.notes, assignedTo: draft.assignedTo, dueAt: draft.hasDue ? draft.due : nil, recurrence: recurring)
                            if draft.isCompleted != draft.initialCompletion, let current = model.engine.snapshot.tasks[task.id], (current.status == .completed) != draft.isCompleted { try model.setTaskCompleted(current, completed: draft.isCompleted) }
                        }
                        else { try model.engine.createTask(title: draft.title, notes: draft.notes, assignedTo: draft.assignedTo, dueAt: draft.hasDue ? draft.due : nil, recurrence: recurring) }
                        model.dismissSheet()
                    }
                }.togetherTouchTarget().togetherProminentButton().keyboardShortcut(.defaultAction).disabled(titleIsEmpty).accessibilityIdentifier("task.save")
            }
        }.togetherPadding(24).togetherSheetSize(width: 550)
    }
}

struct NextTimeView: View {
    @ObservedObject var model: ApplicationModel
    let taskId: UUID
    @State private var date = Date().addingTimeInterval(86400)
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if os(macOS)
            Text(Copy.text("copy.status.626ba31a7939")).font(.title2.weight(.semibold))
            Text(Copy.text("copy.guidance.08a8bfd082bf")).foregroundColor(.secondary)
            DatePicker(Copy.text("copy.guidance.01b9bfedf5b1"), selection: $date, in: Date()...).datePickerStyle(.graphical)
            #else
            VStack(alignment: .leading, spacing: 20) {
                    Text(Copy.text("copy.status.626ba31a7939")).font(.title2.weight(.semibold))
                    Text(Copy.text("copy.guidance.08a8bfd082bf")).foregroundColor(.secondary)
                    DatePicker(Copy.text("copy.guidance.01b9bfedf5b1"), selection: $date, in: Date()...).datePickerStyle(.compact)
            }.frame(maxWidth: .infinity, alignment: .leading).togetherScrollableOnPhone()
            #endif
            HStack {
                Button(Copy.text("copy.action.882574c28ed5")) { model.dismissSheet() }.togetherTouchTarget().keyboardShortcut(.cancelAction).accessibilityIdentifier("sheet.cancel")
                Spacer()
                Button(Copy.text("copy.action.36f33adaf094")) { model.perform { try model.engine.setNextTime(taskId, date: date); model.dismissSheet() } }.togetherTouchTarget().togetherProminentButton()
            }
        }.togetherPadding(24).togetherSheetSize(width: 430)
    }
}
