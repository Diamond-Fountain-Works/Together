import Foundation
import TogetherCore

enum PlansMode: String, CaseIterable, Identifiable {
    case tasks, wishes
    var id: String { rawValue }
    var title: String { Copy.text(self == .tasks ? "nav.tasks" : "nav.wishes") }
}

enum TaskListFilter: String, CaseIterable, Identifiable {
    case pending, completed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pending: Copy.text("plans.filter.pending")
        case .completed: Copy.text("nav.completed")
        }
    }
    var emptyTitle: String {
        switch self {
        case .pending: Copy.text("plans.empty.pending")
        case .completed: Copy.text("plans.empty.completed")
        }
    }
}
