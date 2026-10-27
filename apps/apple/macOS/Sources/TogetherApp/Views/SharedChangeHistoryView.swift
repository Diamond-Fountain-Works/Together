import SwiftUI
import TogetherCore

@MainActor extension ApplicationModel {
  func refreshSharedChanges() {
    changeReviewTask?.cancel()
    changeReviewTask = Task { @MainActor in
      do {
        let events = try await changeReview.events(context: engine.context, limit: Int.max)
        let state = try await changeReview.state()
        let displaying = Set(changeBannerEvents.map(\.id))
        guard !Task.isCancelled else { return }
        let financialState = try engine.financialReviewState()
        let displayedFinance = Set(financialBannerChanges.map(\.id))
        financialBannerChanges = engine.financialChanges(
          projectedEvents: events, limit: max(150, events.count)
        ).filter {
          $0.resolution != .superseded && $0.actorId != engine.identity.descriptor.userId
            && (displayedFinance.contains($0.id)
              || !financialState.presentedOperationIds.contains($0.id))
        }
        changeBannerEvents = events.filter {
          $0.resolution != .superseded && !isFinanceChange($0.type)
            && $0.origin(local: engine.identity.descriptor) != .thisDevice
            && state.dispositions[$0.id] == nil
            && (displaying.contains($0.id) || !state.presentedOperationIds.contains($0.id))
        }
      } catch { if !Task.isCancelled { errorMessage = Copy.userError(error) } }
    }
  }
  func markSharedBannerPresented() {
    let ids = changeBannerEvents.map(\.id)
    markFinancialBannerPresented()
    Task {
      do { try await changeReview.markPresented(ids) } catch {
        errorMessage = Copy.userError(error)
      }
    }
  }
  func dismissSharedBanner() {
    let ids = changeBannerEvents.map(\.id)
    changeBannerEvents = []
    dismissFinancialBanner()
    Task {
      do { try await changeReview.mark(ids, as: .dismissed) } catch {
        errorMessage = Copy.userError(error)
      }
    }
  }
  func openChange(_ event: ChangeEvent) {
    Task {
      do { try await changeReview.mark([event.id], as: .reviewed) } catch {
        errorMessage = Copy.userError(error)
        return
      }
      switch event.type {
      case .task:
        section = .plans
        replaceSheet(.task(event.entityId))
      case .profile:
        section = .settings
        dismissSheet()
      case .wishGrant:
        section = .wishes
        replaceSheet(.grantDetail(event.entityId))
      case .wishItem:
        if let grant = engine.snapshot.wishes[event.entityId]?.grantId {
          section = .wishes
          replaceSheet(.grantDetail(grant))
        }
      case .grantAdjustment:
        if let grant = engine.snapshot.adjustments.first(where: { $0.id == event.entityId })?
          .grantId
        {
          section = .wishes
          replaceSheet(.grantDetail(grant))
        }
      case .loveGift:
        if let gift = engine.receivedGifts.first(where: { $0.id == event.entityId }),
          engine.giftReady(gift)
        {
          replaceSheet(.giftReveal([event.entityId], false))
        } else {
          replaceSheet(.giftHistory)
        }
      case .expense:
        section = .finances
        replaceSheet(.finance(.expense(event.entityId)))
      case .reserveEntry:
        section = .finances
        replaceSheet(.finance(.deposit(event.entityId, false)))
      case .recurringBill:
        section = .finances
        replaceSheet(.finance(.bill(event.entityId)))
      default:
        section = .finances
        replaceSheet(.finance(.changes))
      }
    }
  }
}
private func isFinanceChange(_ type: EntityType) -> Bool {
  [
    .reserveEntry, .expense, .recurringBill, .billRevision, .billOccurrence, .financeSettings,
    .paymentMethod, .dateEvent,
  ].contains(type)
}

struct SharedChangeBanner: View {
  @ObservedObject var model: ApplicationModel
  private var ids: [UUID] {
    Array(Set(model.changeBannerEvents.map(\.id) + model.financialBannerChanges.map(\.id)))
  }
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: TogetherSymbols.name("arrow.triangle.2.circlepath")).foregroundColor(TogetherTheme.rose)
      Text(Copy.format("sync.changes.count", String(ids.count)))
      Spacer()
      Button(Copy.text("copy.action.db8db0530432")) {
        model.show(.changes)
        model.markSharedBannerPresented()
        model.changeBannerEvents = []
        model.dismissFinancialBanner()
      }.accessibilityIdentifier("sync.changes.view")
      Button {
        model.dismissSharedBanner()
      } label: {
        Image(systemName: TogetherSymbols.name("xmark"))
      }.buttonStyle(.plain).accessibilityLabel(Copy.text("copy.action.3fd47edce45b"))
    }.padding(16).togetherMaterialSurface().accessibilityIdentifier("sync.changes.banner")
      .onAppear { model.markSharedBannerPresented() }.onChange(of: ids) { _ in
        model.markSharedBannerPresented()
      }
  }
}
private enum ChangeDomain: String, CaseIterable, Identifiable {
  case all, tasks, wishes, profiles, gifts, finances
  var id: String { rawValue }
  var title: String {
    switch self {
    case .all: Copy.text("finance.filter.all")
    case .tasks: Copy.text("nav.plans")
    case .wishes: Copy.text("nav.wishes")
    case .profiles: Copy.text("sync.changes.profiles")
    case .gifts: Copy.text("copy.action.1555373b2da2")
    case .finances: Copy.text("finance.title")
    }
  }
  func includes(_ event: ChangeEvent) -> Bool {
    switch self {
    case .all: true
    case .tasks: event.type == .task
    case .wishes: [.wishGrant, .wishItem, .grantAdjustment].contains(event.type)
    case .profiles: event.type == .profile
    case .gifts: event.type == .loveGift
    case .finances: isFinanceChange(event.type)
    }
  }
}
struct SharedChangeHistoryView: View {
  @ObservedObject var model: ApplicationModel
  @State private var events: [ChangeEvent] = []
  @State private var state = ChangeReviewState()
  @State private var domain = ChangeDomain.all
  @State private var loading = true
  init(model: ApplicationModel) {
    self.model = model
    #if DEBUG && os(macOS)
      if UIFixture.enabled, let fixture = try? UIFixture(), fixture.page == "changes",
        !fixture.populated
      {
        _domain = State(initialValue: .tasks)
      }
    #endif
  }
  private var visible: [ChangeEvent] { events.filter(domain.includes) }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      TogetherAdaptiveStack(spacing: 12, desktop: .init()) {
        Text(Copy.text("sync.changes.title")).font(.title2.weight(.semibold))
        #if os(macOS)
        Spacer()
        #endif
        Picker(Copy.text("finance.filter.all"), selection: $domain) {
          ForEach(ChangeDomain.allCases) { Text($0.title).tag($0) }
        }.labelsHidden().frame(maxWidth: 210).accessibilityIdentifier("sync.changes.filter")
      }
      if loading {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if visible.isEmpty {
        TogetherEmptyState(
          Copy.text("sync.changes.empty"), systemImage: TogetherSymbols.name("clock.arrow.circlepath")).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) { ForEach(visible) { event in row(event) } }
        }.accessibilityIdentifier("sync.changes.list")
      }
      TogetherAccessibleStack(desktop: .init()) {
        Button(Copy.text("sync.review.action")) {
          Task {
            do {
              try await model.changeReview.mark(visible.map(\.id), as: .reviewed)
              state = try await model.changeReview.state()
            } catch { model.errorMessage = Copy.userError(error) }
          }
        }.disabled(visible.isEmpty).accessibilityIdentifier("sync.changes.review")
        #if os(macOS)
        Spacer()
        #endif
        Button(Copy.text("copy.action.3fd47edce45b")) { model.dismissSheet() }.keyboardShortcut(
          .cancelAction
        ).accessibilityIdentifier("sync.changes.close")
      }
    }.togetherPadding(28)
    #if os(macOS)
    .frame(
      minWidth: 620, idealWidth: 700, maxWidth: 760, minHeight: 500, idealHeight: 660,
      maxHeight: 720
    )
    #else
    .togetherSheetSize(width: 760)
    #endif
    .togetherTask(id: model.engine.changeNumber) {
      do {
        events = try await model.changeReview.events(context: model.engine.context)
        state = try await model.changeReview.state()
        loading = false
      } catch {
        model.errorMessage = Copy.userError(error)
        loading = false
      }
    }
  }
  private func row(_ event: ChangeEvent) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      TogetherAdaptiveStack(spacing: 6, desktop: .init(alignment: .firstTextBaseline)) {
        Text(model.name(event.actorId)).font(.headline)
        Text(
          Copy.text("sync.origin." + event.origin(local: model.engine.identity.descriptor).rawValue)
        ).font(.caption).foregroundColor(.secondary)
        #if os(macOS)
        Spacer()
        #endif
        Text(Copy.date(event.occurredAt)).font(.caption).foregroundColor(.secondary)
      }
      TogetherAdaptiveStack(spacing: 8, desktop: .init()) {
        Text(action(event))
        Text(domainName(event)).foregroundColor(.secondary)
        if !event.title.isEmpty { Text(verbatim: event.title).lineLimit(2) }
        #if os(macOS)
        Spacer()
        #endif
        if event.resolution != .effective {
          Text(Copy.text("sync.resolution." + event.resolution.rawValue)).font(.caption)
            .foregroundColor(.secondary)
        }
        if let disposition = state.dispositions[event.id] {
          Text(
            Copy.text(disposition == .reviewed ? "sync.review.reviewed" : "sync.review.dismissed")
          ).font(.caption).foregroundColor(.secondary)
        }
        Button(Copy.text("copy.action.db8db0530432")) { model.openChange(event) }
          .accessibilityIdentifier("sync.change.open." + event.id.uuidString)
      }
      if event.type != .loveGift {
        let candidates =
          event.action == .create
          ? ["amount", "quantity"]
          : [
            "title", "displayName", "notes", "description", "status", "amount", "quantity", "dueAt",
            "assignedTo", "payment", "active", "grantedOn",
          ]
        let fields = candidates.filter { event.before[$0] != event.after[$0] }
        ForEach(fields, id: \.self) { key in
          VStack(alignment: .leading, spacing: 4) {
            Text(fieldName(key)).font(.caption).foregroundColor(.secondary)
            TogetherAdaptiveStack(spacing: 8, desktop: .init(alignment: .top)) {
              Text(verbatim: value(event.before[key], field: key)).foregroundColor(.secondary)
              Image(systemName: TogetherSymbols.name("arrow.right")).foregroundColor(Color.secondary.opacity(0.65))
              Text(verbatim: value(event.after[key], field: key))
            }.font(.callout).togetherTextSelection().frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      Divider()
    }.accessibilityElement(children: .contain).accessibilityIdentifier(
      "sync.change." + event.id.uuidString)
  }
  private func domainName(_ event: ChangeEvent) -> String {
    switch event.type {
    case .profile: Copy.text("sync.changes.profiles")
    case .task: Copy.text("nav.plans")
    case .wishGrant, .wishItem, .grantAdjustment: Copy.text("nav.wishes")
    case .loveGift: Copy.text("sync.domain.gifts")
    default: Copy.text("finance.title")
    }
  }
  private func action(_ event: ChangeEvent) -> String {
    event.action == .patch
      ? Copy.text("finance.action.changes") : Copy.text("sync.action." + event.action.rawValue)
  }
  private func fieldName(_ field: String) -> String {
    switch field {
    case "title": Copy.text("copy.guidance.c3405f8c7d9d")
    case "displayName": Copy.text("copy.guidance.7a1e2b964b67")
    case "notes", "description": Copy.text("copy.guidance.daede9881787")
    case "dueAt": Copy.text("copy.guidance.15f26621cdce")
    case "assignedTo": Copy.text("copy.guidance.a525346277ed")
    case "payment": Copy.text("finance.payment.title")
    case "grantedOn": Copy.text("finance.field.date")
    case "active": Copy.text("sync.field.status")
    case "quantity": Copy.text("sync.field.quantity")
    case "status": Copy.text("sync.field.status")
    default: Copy.text("finance.amount.actualCNY")
    }
  }
  private func value(_ value: LogValue?, field: String) -> String {
    guard let value else { return Copy.text("role.unknown") }
    if field == "assignedTo", let user = value.uuid { return model.name(user) }
    if field == "payment", case .data(let bytes) = value,
      let payment = try? CanonicalJSON.decode(FinancePayment.self, from: bytes)
    {
      return model.financialPaymentName(payment)
    }
    switch value {
    case .null: return Copy.text("role.unknown")
    case .string(let text):
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return Copy.text("role.unknown")
      }
      // Status words are protocol values only in a status field. A task title
      // or note such as "pending" is user content and stays exactly as written.
      guard field == "status" else { return text }
      switch text {
      case "pending": return Copy.text("copy.status.7f750504c5ba")
      case "completed": return Copy.text("copy.guidance.f28461bb49c8")
      case "scheduled": return Copy.text("presentation.status.scheduled")
      case "completionRequested": return Copy.text("status.wish.requested")
      case "open", "fulfilled", "conflict": return Copy.text("status.wish." + text)
      case "provisional", "reconciled", "skipped": return Copy.text("finance.status." + text)
      default: return text
      }
    case .integer(let number): return String(number)
    case .boolean(let flag):
      return Copy.text(flag ? "finance.status.active" : "finance.status.paused")
    case .date(let date):
      return Copy.date(date, includeTime: field == "dueAt")
    case .data(let bytes):
      if let amount = try? CanonicalJSON.decode(FinanceAmount.self, from: bytes) {
        return FinanceMoney.display(amount.finalCNYMinor)
      }
      return Copy.text("role.unknown")
    }
  }
}
