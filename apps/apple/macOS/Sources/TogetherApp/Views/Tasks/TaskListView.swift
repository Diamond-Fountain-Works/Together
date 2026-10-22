import SwiftUI
import TogetherCore

struct TaskListView: View {
    @Bindable var model: ApplicationModel
    @TogetherMotionPreference private var reduceMotion
    @State private var deleting: TodoTask?

    private var tasks: [TodoTask] {
        let base: [TodoTask]
        switch model.taskFilter {
        case .pending: base = model.pendingTasks
        case .completed: base = model.completedTasks
        }
        return base.filter { task in
            model.taskSearch.isEmpty || task.title.localizedCaseInsensitiveContains(model.taskSearch) || task.notes.localizedCaseInsensitiveContains(model.taskSearch)
        }
    }
    var body: some View {
        let activeFilter = model.taskFilter
        let visibleIds = Set(tasks.map(\.id))
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Picker(Copy.text("plans.filter.label"), selection: $model.taskFilter) {
                    ForEach(TaskListFilter.allCases) { filter in
                        Text(filter.title).tag(filter).accessibilityIdentifier("plans.filter." + filter.rawValue)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240).accessibilityIdentifier("plans.taskFilter")
                Spacer(minLength: 12)
                TextField(Copy.text("copy.guidance.5d02c355dcc5"), text: $model.taskSearch)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 220).accessibilityIdentifier("plans.taskSearch")
            }.padding(.horizontal, 30)
            ScrollViewReader { proxy in
            List {
                if tasks.isEmpty {
                    ContentUnavailableView {
                        Label(model.taskSearch.isEmpty ? model.taskFilter.emptyTitle : Copy.text("plans.empty.search"), systemImage: "checklist")
                    } actions: {
                        if !model.taskSearch.isEmpty {
                            Button(Copy.text("plans.action.clearSearch")) { model.taskSearch = "" }
                        } else if model.taskFilter != .pending {
                            Button(Copy.text("plans.action.viewPending")) { model.taskFilter = .pending }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 280).accessibilityIdentifier("plans.tasks.empty")
                }
                    ForEach(tasks) { task in
                        TogetherCard {
                            HStack(alignment: .top, spacing: 14) {
                                Button { withAnimation(TogetherTheme.motion(reduceMotion)) { model.toggle(task) } } label: {
                                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : task.visibleStatus(at: model.currentDate) == .scheduled ? "clock" : "circle")
                                        .font(.system(size: 21)).foregroundStyle(task.status == .completed ? TogetherTheme.rose : .secondary)
                                }.buttonStyle(.plain).disabled(task.visibleStatus(at: model.currentDate) == .scheduled)
                                    .accessibilityIdentifier("task.toggle." + task.id.uuidString).help(task.visibleStatus(at: model.currentDate) == .scheduled ? Copy.text("copy.guidance.cdbeaea998d1") : Copy.text("copy.guidance.91b5dcb6e512"))
                                Button { model.taskScrollAnchors[activeFilter] = task.id; model.show(.task(task.id)) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(task.title).font(.headline).strikethrough(task.status == .completed).foregroundStyle(.primary)
                                        if !task.notes.isEmpty { Text(task.notes).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                                        HStack(spacing: 12) {
                                            if let assigned = task.assignedTo { Label(model.name(assigned), systemImage: "person").font(.caption) }
                                            if let due = task.dueAt { Label(Copy.date(due, includeTime: true), systemImage: "calendar").font(.caption) }
                                            if let id = task.recurrenceRuleId, let rule = model.engine.snapshot.rules[id] { Label(rule.mode == .flexible ? Copy.text("copy.status.9622d2850be8") : Copy.format("copy.guidance.26272e530d64", String(describing: rule.interval), rule.unit.displayName), systemImage: "repeat").font(.caption) }
                                        }.foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("task.open." + task.id.uuidString)
                                Menu {
                                    Button(Copy.text("copy.action.051836569928")) { model.show(.task(task.id)) }
                                    if let id = task.recurrenceRuleId, model.engine.snapshot.rules[id]?.mode == .flexible { Button(Copy.text("copy.status.626ba31a7939")) { model.show(.nextTime(task.id)) } }
                                    Button(Copy.text("copy.action.29dfebea0fda"), role: .destructive) { deleting = task }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                            }
                        }
                        .id(task.id)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .transition(reduceMotion ? .identity : .opacity)
                    }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .padding(.horizontal, 30).padding(.bottom, 24)
                .animation(TogetherTheme.quickMotion(reduceMotion), value: tasks.map(\.id))
                .onAppear {
                    if let id = model.taskScrollAnchors[activeFilter], visibleIds.contains(id) { proxy.scrollTo(id, anchor: .top) }
                }
            .id(activeFilter)
            }
        }
        .confirmationDialog(Copy.text("copy.guidance.abb2240a2b17"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(Copy.text("copy.action.2f9daa828907"), role: .destructive) { if let task = deleting { model.perform { try model.engine.deleteTask(task.id) } }; deleting = nil }
            Button(Copy.text("copy.action.2cd0f3be8738"), role: .cancel) { deleting = nil }
        }
    }
}
