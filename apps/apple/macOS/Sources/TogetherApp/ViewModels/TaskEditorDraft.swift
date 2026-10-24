import Foundation
import Combine
import TogetherCore

/// Sheet-owned editing state. Commit still uses the existing task domain service.
@MainActor final class TaskEditorDraft: ObservableObject {
    @Published var title: String
    @Published var notes: String
    @Published var assignedTo: UUID?
    @Published var hasDue: Bool
    @Published var due: Date
    @Published var recurrenceMode: String
    @Published var unit: RecurrenceUnit
    @Published var interval: Int
    @Published var isCompleted: Bool
    let initialCompletion: Bool

    init(task: TodoTask?, engine: ReplicaEngine) {
        title = task?.title ?? ""
        notes = task?.notes ?? ""
        assignedTo = task?.assignedTo ?? engine.identity.descriptor.userId
        hasDue = task?.dueAt != nil
        due = task?.dueAt ?? engine.dateProvider.now().addingTimeInterval(86400)
        let rule = task?.recurrenceRuleId.flatMap { engine.snapshot.rules[$0] }
        recurrenceMode = rule?.mode.rawValue ?? "none"
        unit = rule?.unit ?? .day
        interval = rule?.interval ?? 1
        let completion = task?.status == .completed
        isCompleted = completion
        initialCompletion = completion
    }
}
