//
//  FamilyView.swift
//  Resonance
//
//  The Family tab: the people who help, one-tap calls and texts, quick updates,
//  a daily summary, and a log of every alert and message sent.
//  Family receive everything as ordinary text messages on their own phones, so they
//  don't need to install anything.
//

import SwiftUI
import SwiftData

struct FamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\CareContact.createdAt)]) private var contacts: [CareContact]
    @Query(sort: \CareEvent.date, order: .reverse) private var events: [CareEvent]
    @Query private var profiles: [Profile]
    @Query(sort: \VoiceSession.date, order: .reverse) private var voice: [VoiceSession]
    @Query(sort: \MotorSession.date, order: .reverse) private var motor: [MotorSession]
    @Query(sort: \FunctionCheck.date, order: .reverse) private var checks: [FunctionCheck]
    @Query(sort: \FeelingEntry.date, order: .reverse) private var feelings: [FeelingEntry]

    @State private var sendRequest: FamilySendRequest?
    @State private var showAddManually = false
    @State private var picked: PickedContact?
    @State private var editing: CareContact?
    @State private var callProblem = false
    @State private var showProfile = false

    private var name: String { profiles.first?.name ?? "" }
    private var sorted: [CareContact] { contacts.sorted { $0.isPrimary && !$1.isPrimary } }
    private var alertContacts: [CareContact] { sorted.filter(\.receivesAlerts) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero

                    if contacts.isEmpty {
                        emptyState
                    } else {
                        SectionTitle(text: "Your circle", trailing: "\(contacts.count) \(contacts.count == 1 ? "person" : "people")")
                        ForEach(sorted) { contact in
                            ContactCard(contact: contact,
                                        call: { call(contact) },
                                        text: { compose(.message, "", to: [contact]) },
                                        edit: { editing = contact })
                        }
                        addButtons
                    }

                    NavigationLink {
                        HeadControlSetupView()
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "message.badge.filled.fill", color: AppTheme.coral, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Alerts that text family by themselves")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(AppTheme.ink)
                                Text(profiles.first?.alertShortcutEnabled == true
                                     ? "On: the alert runs your Resonance Alert shortcut"
                                     : "Off: set up a shortcut once, no tap needed after that")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(AppTheme.padding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surfaceStyle()
                    }
                    .buttonStyle(PressableStyle())

                    SectionTitle(text: "Quick updates")
                    Text("Tap one to text it to everyone in your circle.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    quickGrid

                    feelingsCard

                    CareScheduleCard()

                    CareQuestionsCard()

                    dailyUpdateCard

                    activity

                    CaregiverTipsCard(name: name)
                }
                .padding(AppTheme.padding)
            }
            .screenBackground()
            .navigationTitle("Family")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileButton(name: name) { showProfile = true }
                }
            }
            .familySender($sendRequest)
            .sheet(isPresented: $showAddManually) {
                ContactEditView(contact: nil) { name, phone, relation, primary, alerts in
                    add(name: name, phone: phone, relation: relation, primary: primary, alerts: alerts)
                }
            }
            .sheet(item: $picked) { item in
                ContactEditView(contact: nil, prefillName: item.name, prefillPhone: item.phone) { name, phone, relation, primary, alerts in
                    add(name: name, phone: phone, relation: relation, primary: primary, alerts: alerts)
                }
            }
            .sheet(item: $editing) { contact in
                ContactEditView(contact: contact) { name, phone, relation, primary, alerts in
                    contact.name = name
                    contact.phone = phone
                    contact.relation = relation
                    contact.receivesAlerts = alerts
                    setPrimary(contact, primary)
                    try? modelContext.save()
                }
            }
            .sheet(isPresented: $showProfile) { ProfileView(isSheet: true) }
            .alert("Calling isn't available on this device", isPresented: $callProblem) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("On an iPhone, this starts a phone call. iOS asks you to confirm before it dials.")
            }
        }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: -10) {
                ForEach(sorted.prefix(4)) { contact in
                    Avatar(initials: contact.initials, size: 44, onGradient: true)
                }
                if contacts.isEmpty {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                Spacer()
            }
            Text(contacts.isEmpty ? "Keep family close" : "Your family can see what you need")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("Alerts, needs and messages go to their phones as ordinary texts, so they don't need the app. Nothing is sent without your confirmation.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                compose(.alert, CareMessage.alert(name: name, date: Date()), to: alertContacts)
            } label: {
                Label("Ask for help now", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minTapSize)
                    .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Texts everyone who gets alerts that you need help now.")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .shadow(color: AppTheme.violetDeep.opacity(0.22), radius: 16, y: 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add the people who help you", systemImage: "person.crop.circle.badge.plus")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text("A spouse, child, friend or nurse. They'll get your alerts and messages, and you can call them with one tap. You can add several.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            addButtons
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
    }

    private var addButtons: some View {
        HStack(spacing: 10) {
            Button {
                // Picking a contact opens the form, so relation and "call first" can be set too.
                ContactPicker.present { pickedName, phone in
                    // Wait for the picker to finish closing, or SwiftUI may refuse to show the form.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        picked = PickedContact(name: pickedName, phone: phone)
                    }
                }
            } label: {
                Label("Contacts", systemImage: "person.crop.circle")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(SecondaryButtonStyle())
            Button { showAddManually = true } label: {
                Label("Add number", systemImage: "plus")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var quickGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(CareMessage.quickUpdates, id: \.text) { item in
                Button {
                    compose(item.kind, CareMessage.quick(item.text, name: name, date: Date()), to: sorted)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        IconBadge(systemImage: item.icon, color: item.kind == .need ? AppTheme.amber : AppTheme.accent, size: 38)
                        Text(item.text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .surfaceStyle()
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Send: \(item.text)")
            }
        }
    }

    private var dailyText: String {
        let records = InsightsBuilder.records(voice: voice, motor: motor, checks: checks)
        let snapshot = InsightsBuilder.snapshot(from: records)
        let week = WeeklyProgress(voice: voice, motor: motor, checks: checks)
        let done = WeeklyStep.allCases.filter { week.done.contains($0) }.map(\.title)
        let changes = snapshot.insights.filter { $0.status == .noticeableChange }.map(\.def.name)
        let feeling = checks.first(where: { Calendar.current.isDateInToday($0.date) && !$0.isDemo })
            .map { ["Very low", "Low", "Okay", "Good", "Very good"][min(max($0.mood, 1), 5) - 1] }
        return CareMessage.dailyUpdate(name: name, date: Date(), functionIndex: snapshot.functionIndex,
                                       doneThisWeek: done, changes: changes, feeling: feeling,
                                       feelingsThisWeek: FeelingSummary.line(feelingCounts))
    }

    private var feelingCounts: [FeelingSummary.Count] {
        FeelingSummary.recent(feelings.map { (date: $0.date, feeling: $0.feeling) }, now: Date())
    }

    /// The feelings shared on the Talk board this week, as faces.
    @ViewBuilder
    private var feelingsCard: some View {
        let counts = feelingCounts
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "face.smiling", color: AppTheme.violet, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feelings this week")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Shared with the Feel button on the Talk board")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(counts, id: \.feeling) { item in
                            VStack(spacing: 2) {
                                Text(item.feeling.emoji).font(.system(size: 30))
                                Text(item.feeling.label).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.ink)
                                Text(item.times == 1 ? "once" : "\(item.times) times")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minWidth: 72, minHeight: 84)
                            .background(item.feeling.isPleasant ? AppTheme.mint.opacity(0.14) : AppTheme.canvas,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(AppTheme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceStyle()
        }
    }

    private var dailyUpdateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconBadge(systemImage: "heart.text.square.fill", color: AppTheme.mint, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily update")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("A short summary of today, written for family")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(dailyText)
                .font(.callout)
                .foregroundStyle(AppTheme.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                compose(.update, dailyText, to: sorted)
            } label: {
                Label("Send today's update", systemImage: "paperplane.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: AppTheme.mint))
            NavigationLink {
                ReportPreviewView()
            } label: {
                Label("Share the Care Report", systemImage: "doc.richtext.fill")
            }
            .buttonStyle(SecondaryButtonStyle(color: AppTheme.mint))
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
    }

    @ViewBuilder
    private var activity: some View {
        SectionTitle(text: "Activity", trailing: events.isEmpty ? nil : "Latest first")
        if events.isEmpty {
            Text("Alerts, calls and messages will be listed here, so everyone knows what has been sent.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(AppTheme.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceStyle()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(events.prefix(12).enumerated()), id: \.element.id) { index, event in
                    EventRow(event: event)
                    if index < min(events.count, 12) - 1 { Divider().padding(.leading, 62) }
                }
            }
            .padding(.vertical, 6)
            .surfaceStyle()
        }
    }

    // MARK: Actions

    /// A plain "Text" from a contact card opens an empty message to that person.
    private func compose(_ kind: CareMessage.Kind, _ body: String, to people: [CareContact]) {
        sendRequest = FamilySendRequest(kind: kind, body: body, contacts: people)
    }

    private func call(_ contact: CareContact) {
        CallAction(openURL: openURL, context: modelContext).call(contact) { ok in
            if !ok { callProblem = true }
        }
    }

    private func add(name: String, phone: String, relation: String, primary: Bool = false, alerts: Bool = true) {
        let contact = CareContact(name: name.isEmpty ? "Family" : name, phone: phone, relation: relation)
        contact.receivesAlerts = alerts
        modelContext.insert(contact)
        setPrimary(contact, primary || contacts.isEmpty)
        try? modelContext.save()
    }

    /// Only one person is first to call.
    private func setPrimary(_ contact: CareContact, _ primary: Bool) {
        if primary {
            for other in contacts where other !== contact { other.isPrimary = false }
        }
        contact.isPrimary = primary
    }
}

// MARK: - Pieces

/// Round initials avatar.
struct Avatar: View {
    let initials: String
    var size: CGFloat = 48
    var onGradient = false

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(onGradient ? AppTheme.violetDeep : .white)
            .frame(width: size, height: size)
            .background(onGradient ? AnyShapeStyle(Color.white) : AnyShapeStyle(AppTheme.heroGradient), in: Circle())
            .overlay(Circle().stroke(onGradient ? AppTheme.violet : .clear, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// The person's avatar in the top corner; opens Profile and settings.
struct ProfileButton: View {
    let name: String
    let action: () -> Void

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
    }

    var body: some View {
        Button(action: action) {
            Group {
                if initial.isEmpty {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppTheme.accent)
                } else {
                    Text(initial)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.heroGradient, in: Circle())
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Profile and settings")
    }
}

private struct ContactCard: View {
    let contact: CareContact
    let call: () -> Void
    let text: () -> Void
    let edit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    Avatar(initials: contact.initials, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(contact.name)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                            if contact.isPrimary {
                                Text("Called first")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.violetSoft, in: Capsule())
                            }
                        }
                        Text([contact.relation, contact.phone.replacingOccurrences(of: " ", with: "\u{00A0}")]
                                .filter { !$0.isEmpty }.joined(separator: " · "))   // phone never splits across lines
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !contact.receivesAlerts {
                            Text("Doesn't get alerts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(contact.name), \(contact.relation). Edit")

            HStack(spacing: 10) {
                Button(action: call) {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: AppTheme.mint))
                .accessibilityLabel("Call \(contact.name)")
                Button(action: text) {
                    Label("Text", systemImage: "message.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Text \(contact.name)")
            }
        }
        .padding(AppTheme.padding)
        .surfaceStyle()
    }
}

private struct EventRow: View {
    let event: CareEvent

    private var kind: CareMessage.Kind { CareMessage.Kind(rawValue: event.kind) ?? .message }
    private var color: Color {
        switch kind {
        case .alert: return AppTheme.coral
        case .need: return AppTheme.amber
        case .call, .care: return AppTheme.mint
        default: return AppTheme.accent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: kind.icon, color: color, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                    Spacer()
                    Text(event.date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(event.text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(3)
                Text(event.recipients.isEmpty ? "On this iPhone only, not sent" : "To \(event.recipients)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppTheme.padding)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// A contact chosen in the system picker, waiting for the add form.
struct PickedContact: Identifiable {
    let id = UUID()
    var name: String
    var phone: String
}

/// Add or edit one person.
struct ContactEditView: View {
    let contact: CareContact?
    var prefillName = ""
    var prefillPhone = ""
    let onSave: (_ name: String, _ phone: String, _ relation: String, _ primary: Bool, _ alerts: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var phone = ""
    @State private var relation = ""
    @State private var primary = false
    @State private var alerts = true
    @State private var confirmDelete = false

    private let relations = ["Spouse", "Partner", "Daughter", "Son", "Parent", "Sibling", "Friend", "Nurse", "Caregiver"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .frame(minHeight: AppTheme.minTapSize)
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .frame(minHeight: AppTheme.minTapSize)
                    if !phone.isEmpty && !PhoneNumber.isValid(phone) {
                        Text("Enter a phone number with digits.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(relations, id: \.self) { item in
                                Button(item) { relation = item }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: AppTheme.minTapSize)
                                    .foregroundStyle(relation == item ? .white : AppTheme.accent)
                                    .background(relation == item ? AppTheme.accent : AppTheme.violetSoft, in: Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    TextField("Or type it", text: $relation)
                        .frame(minHeight: AppTheme.minTapSize)
                } header: {
                    Text("Who are they to you?")
                }
                Section {
                    Toggle("Call this person first", isOn: $primary)
                        .frame(minHeight: AppTheme.minTapSize)
                    Toggle("Send them alerts", isOn: $alerts)
                        .frame(minHeight: AppTheme.minTapSize)
                } footer: {
                    Text("The alert screen shows a big Call button for the person called first, and a Text button for everyone who gets alerts.")
                }
                if contact != nil {
                    Section {
                        Button("Remove from my circle", role: .destructive) { confirmDelete = true }
                            .frame(minHeight: AppTheme.minTapSize)
                    }
                }
            }
            .tint(AppTheme.accent)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(contact == nil ? "Add someone" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespaces), phone.trimmingCharacters(in: .whitespaces),
                               relation.trimmingCharacters(in: .whitespaces), primary, alerts)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !PhoneNumber.isValid(phone))
                }
            }
            .confirmationDialog("Remove \(name)? They won't get alerts anymore.", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let contact { modelContext.delete(contact); try? modelContext.save() }
                    dismiss()
                }
            }
            .onAppear {
                if let contact {
                    name = contact.name
                    phone = contact.phone
                    relation = contact.relation
                    primary = contact.isPrimary
                    alerts = contact.receivesAlerts
                } else {
                    name = prefillName
                    phone = prefillPhone
                }
            }
        }
    }
}

/// Short guidance for family members who pick up the phone.
private struct CaregiverTipsCard: View {
    let name: String
    @State private var expanded = false

    private var who: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "your family member" : name }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "person.2.wave.2.fill", color: AppTheme.blue, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tips for family")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Show this to the people who help")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: AppTheme.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            if expanded {
                tip("Ask yes-or-no questions", "\(who.capitalizedFirst) can answer with the big Yes and No buttons at the top of the Talk board.")
                tip("Give time to answer", "Choosing words by head movement or switch takes longer. Wait, and don't finish the sentence unless asked.")
                tip("Know the alert", "A loud repeating voice and flashing screen means \(who) needs someone nearby now. It does not call 911.")
                tip("Keep the phone in reach", "Charged, unlocked to Resonance, and on a stand at face height when using head control.")
                tip("Look at the weekly summary", "Changes that matter are flagged gently. Bring the Care Report to clinic visits.")
            }
        }
        .padding(AppTheme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#Preview {
    FamilyView()
        .modelContainer(for: [CareContact.self, CareEvent.self, Profile.self, VoiceSession.self,
                              MotorSession.self, FunctionCheck.self], inMemory: true)
}
