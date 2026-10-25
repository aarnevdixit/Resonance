//
//  CareScheduleView.swift
//  Resonance
//
//  The daily care schedule: medicines, turning, water, mouth care, breathing equipment.
//  Each reminder is a notification on this iPhone at the same time every day.
//

import SwiftUI
import SwiftData
import UserNotifications

struct CareScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\CareReminder.hour), SortDescriptor(\CareReminder.minute)]) private var reminders: [CareReminder]
    @State private var showAdd = false
    @State private var notificationsOff = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                if reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No reminders yet")
                            .font(.headline)
                        Text("Add medicines, turning in bed, water or breathing equipment. The phone reminds you at the same time every day.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(reminders) { reminder in
                    ReminderRow(reminder: reminder) {
                        Task { await sync(reminder) }
                    }
                }
                .onDelete(perform: delete)
            } footer: {
                if !reminders.isEmpty {
                    Text("Touch and hold a reminder when it appears to mark it Done (it shows in Activity on the Family tab) or to be reminded again in 10 minutes. Swipe left on a reminder here, or tap Edit, to remove it.")
                }
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Add a reminder", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(minHeight: AppTheme.minTapSize)
                }
            }

            if notificationsOff {
                Section {
                    Label("Notifications are off for Resonance. Turn them on in Settings > Notifications > Resonance so reminders can appear.",
                          systemImage: "bell.slash.fill")
                        .foregroundStyle(AppTheme.warning)
                }
            }
        }
        .tint(AppTheme.accent)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Care schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !reminders.isEmpty {
                EditButton()
                    .frame(minWidth: AppTheme.minTapSize, minHeight: AppTheme.minTapSize)
                    .accessibilityHint("Shows delete buttons for the reminders")
            }
        }
        // Make sure every reminder that is on really has its notification (after a restore,
        // a reinstall, or notifications being turned back on in Settings).
        .task { await syncAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await syncAll() } }
        }
        .sheet(isPresented: $showAdd) {
            AddReminderView { title, kind, hour, minute in
                let reminder = CareReminder(title: title, kind: kind, hour: hour, minute: minute)
                modelContext.insert(reminder)
                try? modelContext.save()
                Task { await sync(reminder) }
            }
        }
    }

    private func sync(_ reminder: CareReminder) async {
        guard reminder.modelContext != nil, !reminder.isDeleted else { return }
        try? modelContext.save()
        if reminder.enabled {
            let allowed = await CareSchedule.requestPermission()
            notificationsOff = !allowed
            guard allowed else { return }
        }
        // It may have been removed while the permission prompt was open.
        guard reminder.modelContext != nil, !reminder.isDeleted else { return }
        await CareSchedule.sync(reminder)
    }

    private func syncAll() async {
        let enabled = reminders.filter(\.enabled)
        guard !enabled.isEmpty else { notificationsOff = false; return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOff = settings.authorizationStatus == .denied
        guard !notificationsOff else { return }
        for reminder in enabled where reminder.modelContext != nil && !reminder.isDeleted {
            await CareSchedule.sync(reminder)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let reminder = reminders[index]
            CareSchedule.remove(reminder)
            modelContext.delete(reminder)
        }
        try? modelContext.save()
    }
}

private struct ReminderRow: View {
    @Bindable var reminder: CareReminder
    let changed: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: reminder.reminderKind.icon,
                      color: reminder.enabled ? AppTheme.accent : .secondary, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.headline)
                    .foregroundStyle(reminder.enabled ? AppTheme.ink : .secondary)
                Text("Every day at \(reminder.timeText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("On", isOn: $reminder.enabled)
                .labelsHidden()
                .accessibilityLabel("\(reminder.title) reminder")
                .onChange(of: reminder.enabled) { _, _ in changed() }
        }
        .frame(minHeight: AppTheme.minTapSize)
    }
}

/// Pick a kind, a title and a time.
private struct AddReminderView: View {
    let onAdd: (_ title: String, _ kind: CareReminderKind, _ hour: Int, _ minute: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CareReminderKind = .medication
    @State private var title = CareReminderKind.medication.suggestedTitle
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(CareReminderKind.allCases) { option in
                            Button {
                                if title.isEmpty || title == kind.suggestedTitle { title = option.suggestedTitle }
                                kind = option
                            } label: {
                                Label(option.label, systemImage: option.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                                    .foregroundStyle(kind == option ? Color.white : AppTheme.accent)
                                    .background(kind == option ? AppTheme.accent : AppTheme.violetSoft,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("What for?")
                }
                Section {
                    TextField("Reminder, e.g. \"Riluzole, 1 tablet\"", text: $title)
                        .frame(minHeight: AppTheme.minTapSize)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .frame(minHeight: AppTheme.minTapSize)
                } footer: {
                    Text("Repeats every day. You can turn it off or remove it at any time.")
                }
            }
            .tint(AppTheme.accent)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onAdd(title.trimmingCharacters(in: .whitespaces), kind, parts.hour ?? 9, parts.minute ?? 0)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// The next few reminders, for the Family tab.
struct CareScheduleCard: View {
    /// On Today the card only appears once there is something scheduled.
    var hideWhenEmpty = false
    @Query private var reminders: [CareReminder]

    var body: some View {
        let next = CareSchedule.upcoming(reminders.map { (title: $0.title, hour: $0.hour, minute: $0.minute, enabled: $0.enabled) },
                                         now: Date())
        if !(hideWhenEmpty && next.isEmpty) {
            card(next)
        }
    }

    private func card(_ next: [CareSchedule.Upcoming]) -> some View {
        NavigationLink {
            CareScheduleView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "clock.badge.checkmark.fill", color: AppTheme.blue, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Care schedule")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text(next.isEmpty ? "Medicines, turning, water: daily reminders" : "\(next.count) daily reminder\(next.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                ForEach(Array(next.prefix(3).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text((Calendar.current.isDateInToday(item.date) ? "" : "Tomorrow ")
                             + item.date.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.blue)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(AppTheme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceStyle()
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    NavigationStack { CareScheduleView() }
        .modelContainer(for: CareReminder.self, inMemory: true)
}
