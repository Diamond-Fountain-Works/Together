import SwiftUI
import TogetherCore

struct HomeView: View {
    let model: ApplicationModel
    private var unfulfilled: Int { model.engine.snapshot.grants.values.reduce(0) { $0 + model.engine.snapshot.balance(for: $1.id).remaining } }
    private var recentGrants: [WishGrant] { Array(model.engine.snapshot.grants.values.sorted { $0.createdAt > $1.createdAt }.prefix(1)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Copy.text("copy.status.330e6de0a0e3"), subtitle: "")
                TogetherCard {
                    HStack(spacing: 22) {
                        person(model.engine.ownProfile, fallback: Copy.text("status.profile.self"), online: true)
                        Divider().frame(height: 46)
                        person(model.engine.partnerProfile, fallback: model.engine.context.peer == nil ? Copy.text("status.profile.waitingPartner") : Copy.text("status.profile.waitingSync"), online: model.partnerIsOnline)
                        Spacer()
                    }
                }
                HStack(spacing: 14) {
                    metric(Copy.text("plans.filter.pending"), value: model.pendingTasks.count, icon: "checklist", id: "home.pending") { openTasks() }
                    if !model.upcomingTasks.isEmpty {
                        metric(Copy.text("nav.upcoming"), value: model.upcomingTasks.count, icon: "calendar", id: "home.upcoming") { openTasks() }
                    }
                    metric(Copy.text("copy.status.cad05cf5be73"), value: unfulfilled, icon: "sparkles", id: "home.wishes") { model.openPlans(.wishes) }
                }
                if !model.upcomingTasks.isEmpty { TogetherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Button { openTasks() } label: {
                            HStack { Text(Copy.text("nav.upcoming")).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain).accessibilityIdentifier("home.upcoming.open")
                        ForEach(model.upcomingTasks.prefix(3)) { task in
                            Button { model.show(.task(task.id)) } label: {
                                HStack { Text(task.title); Spacer(); if let date = task.dueAt { Text(date, style: .date).foregroundStyle(.secondary) } }
                            }.buttonStyle(.plain).accessibilityIdentifier("home.task.open." + task.id.uuidString)
                        }
                    }
                } }
                if !recentGrants.isEmpty { TogetherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Button { model.openPlans(.wishes) } label: {
                            HStack { Text(Copy.text("copy.status.a7363b44d657")).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain).accessibilityIdentifier("home.recentGrant.open")
                        ForEach(recentGrants) { grant in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Copy.format("copy.guidance.3e122095ba88", String(describing: model.name(grant.fulfillerId)), String(describing: model.name(grant.beneficiaryId))))
                                    Text(grant.grantedOn.display).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Text(Copy.format("copy.status.ce04cf69d965", String(describing: grant.quantity))).font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(TogetherTheme.rose)
                            }
                        }
                    }
                } }
                if !model.engine.snapshot.conflicts.isEmpty {
                    Label(Copy.format("copy.guidance.2d4ab3c1d821", String(describing: model.engine.snapshot.conflicts.count)), systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
            }.padding(30).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func openTasks() { model.taskSearch = ""; model.openPlans(.tasks) }
    private func person(_ profile: UserProfile?, fallback: String, online: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 54, engine: model.engine)
            VStack(alignment: .leading, spacing: 5) {
                Text(profile?.displayName ?? fallback).font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(online ? .green : .secondary).frame(width: 5, height: 5)
                    Text(profile == nil ? (model.engine.context.peer == nil ? Copy.text("copy.status.43461ae7bd32") : Copy.text("copy.status.710764256c01")) : (online ? Copy.text("copy.status.0d21bd52022c") : Copy.text("status.connection.offline"))).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func metric(_ title: String, value: Int, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TogetherCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Label(title, systemImage: icon); Spacer(); Image(systemName: "chevron.right") }.font(.caption).foregroundStyle(.secondary)
                    Text(Copy.format("copy.status.ee17b0047b75", String(describing: value))).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.primary)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
