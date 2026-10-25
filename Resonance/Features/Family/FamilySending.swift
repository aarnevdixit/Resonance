//
//  FamilySending.swift
//  Resonance
//
//  Sends texts and starts calls to family through the iPhone's own Messages and Phone
//  apps. Any screen can attach `.familySender($request)` and set a request.
//  - On an iPhone: the Messages sheet opens with the recipients and words filled in;
//    one tap on Send delivers it (iOS always asks for that tap).
//  - Where Messages isn't available (the Simulator, an iPad without SMS): a fallback
//    sheet shows the message with Copy and Share, so nothing is lost.
//  Every text that is sent (or handed to Messages) is written to the Family activity log.
//
//  Note: uses MessageUI and ContactsUI, two Apple frameworks not listed in CLAUDE.md.
//  They add no network code of their own; texts go out through Apple's Messages app.
//

import SwiftUI
import SwiftData
import MessageUI
import ContactsUI

/// Someone to send to.
struct Recipient: Hashable {
    var name: String
    var phone: String
}

/// A text waiting to be sent.
struct FamilySendRequest: Identifiable {
    let id = UUID()
    var kind: CareMessage.Kind
    var body: String
    var recipients: [Recipient]

    var names: String { recipients.map(\.name).joined(separator: ", ") }

    init(kind: CareMessage.Kind, body: String, contacts: [CareContact]) {
        self.kind = kind
        self.body = body
        self.recipients = contacts.map { Recipient(name: $0.name, phone: $0.phone) }
    }
}

enum FamilyLog {
    static func record(_ request: FamilySendRequest, in context: ModelContext, note: String? = nil) {
        let body = request.body.isEmpty ? "Opened a text message" : request.body
        let text = note.map { "\($0): \(body)" } ?? body
        context.insert(CareEvent(kind: request.kind.rawValue, text: text, recipients: request.names))
        try? context.save()
    }

    static func recordCall(to name: String, in context: ModelContext) {
        context.insert(CareEvent(kind: CareMessage.Kind.call.rawValue, text: "Called \(name)", recipients: name))
        try? context.save()
    }
}

extension View {
    /// Presents Messages (or a fallback) whenever `request` is set.
    func familySender(_ request: Binding<FamilySendRequest?>) -> some View {
        modifier(FamilySenderModifier(request: request))
    }
}

private struct FamilySenderModifier: ViewModifier {
    @Binding var request: FamilySendRequest?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(item: $request) { req in
            if MessageComposer.canSend && !req.recipients.isEmpty {
                MessageComposer(request: req) { sent in
                    if sent { FamilyLog.record(req, in: modelContext) }
                    request = nil
                }
                .ignoresSafeArea()
            } else {
                FallbackSendView(request: req) { request = nil }
            }
        }
    }
}

/// Apple's Messages sheet.
struct MessageComposer: UIViewControllerRepresentable {
    let request: FamilySendRequest
    let onFinish: (Bool) -> Void

    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = request.recipients.map { PhoneNumber.dialable($0.phone) }
        controller.body = request.body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish(result == .sent)
        }
    }
}

/// Shown where Messages can't open (the Simulator, or no family added yet).
private struct FallbackSendView: View {
    let request: FamilySendRequest
    let onDone: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @AppStorage("selectedTab") private var selectedTab = AppTab.today.rawValue
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if request.recipients.isEmpty {
                        Label("Add a family member on the Family tab to send texts with one tap.",
                              systemImage: "person.crop.circle.badge.plus")
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                        Button {
                            selectedTab = AppTab.family.rawValue
                            onDone()
                        } label: {
                            Label("Add family now", systemImage: "person.2.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Label("To: \(request.names)", systemImage: "person.2.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                    }

                    Text(request.body)
                        .font(.title3)
                        .foregroundStyle(AppTheme.ink)
                        .padding(AppTheme.padding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.violetSoft, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)

                    if !MessageComposer.canSend {
                        Text("Texting isn't available on this device (for example in the Simulator). On an iPhone, the Messages app opens with this text ready to send.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !request.recipients.isEmpty,
                       let url = CareMessage.smsURL(numbers: request.recipients.map(\.phone), body: request.body) {
                        Button {
                            openURL(url) { accepted in
                                if accepted {
                                    FamilyLog.record(request, in: modelContext)
                                    onDone()
                                }
                            }
                        } label: {
                            Label("Open Messages", systemImage: "message.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    ShareLink(item: request.body) {
                        Label("Share another way", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        UIPasteboard.general.string = request.body
                        copied = true
                        FamilyLog.record(request, in: modelContext, note: "Copied")
                    } label: {
                        Label(copied ? "Copied" : "Copy the message", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(AppTheme.padding)
            }
            .screenBackground()
            .navigationTitle("Send to family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Calling

/// Starts a phone call through the Phone app. iOS asks the person to confirm the call.
struct CallAction {
    let openURL: OpenURLAction
    let context: ModelContext

    /// Returns false when calls aren't possible here (the Simulator), so the screen can explain.
    func call(_ contact: CareContact, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let url = CareMessage.telURL(contact.phone) else { completion(false); return }
        openURL(url) { accepted in
            if accepted { FamilyLog.recordCall(to: contact.name, in: context) }
            completion(accepted)
        }
    }
}

// MARK: - Contacts picker

/// Shows the system contact picker. No Contacts permission is needed: the person picks
/// one phone number and only that is shared with Resonance.
/// Presented from the top view controller, which is more reliable than embedding the
/// picker in a SwiftUI sheet.
@MainActor
enum ContactPicker {
    private static var delegate: PickerDelegate?

    static func present(onPick: @escaping (_ name: String, _ phone: String) -> Void) {
        guard let top = topViewController() else { return }
        let picker = CNContactPickerViewController()
        let handler = PickerDelegate { name, phone in
            onPick(name, phone)
            delegate = nil
        } onCancel: {
            delegate = nil
        }
        delegate = handler
        picker.delegate = handler
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        top.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class PickerDelegate: NSObject, CNContactPickerDelegate {
        let onPick: (String, String) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        private func name(of contact: CNContact) -> String {
            let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            return full.isEmpty ? contact.organizationName : full
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            if let number = contact.phoneNumbers.first?.value.stringValue {
                onPick(name(of: contact), number)
            } else {
                onCancel()
            }
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            if let number = (contactProperty.value as? CNPhoneNumber)?.stringValue {
                onPick(name(of: contactProperty.contact), number)
            } else {
                onCancel()
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
