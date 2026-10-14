import Foundation
import Observation
import TogetherCore

/// Sheet-owned editing state. Commit still uses the existing task domain service.
@MainActor @Observable final class TaskEditorDraft {
    var title: String
    var notes: String
    var assignedTo: UUID?
    var hasDue: Bool
    var due: Date
    var recurrenceMode: String
    var unit: RecurrenceUnit
    var interval: Int
    var isCompleted: Bool
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
