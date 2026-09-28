import SendKit

#if os(macOS)
import AppKit

@MainActor
public enum MailComposer {
    /// Opens a new message in the default mail app. Cc/Bcc aren't supported by `NSSharingService`.
    public static func present(_ draft: MailDraft) throws {
        guard let service = NSSharingService(named: .composeEmail) else {
            throw SendError("No mail app is available to compose the message.")
        }
        service.recipients = draft.to
        service.subject = draft.subject
        let items: [Any] = [draft.body as NSString] + draft.attachments.map { $0.url as NSURL }
        guard service.canPerform(withItems: items) else {
            throw SendError("The mail app can't create this message.")
        }
        service.perform(withItems: items)
    }
}

#elseif os(iOS)
import MessageUI
import UIKit

@MainActor
public enum MailComposer {
    public static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    public static func makeController(_ draft: MailDraft, delegate: MFMailComposeViewControllerDelegate) throws -> MFMailComposeViewController {
        guard canSendMail else {
            throw SendError("No mail account is set up on this device. Add one in Settings, or switch this endpoint to SMTP.")
        }
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = delegate
        controller.setToRecipients(draft.to)
        controller.setCcRecipients(draft.cc)
        controller.setBccRecipients(draft.bcc)
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        for file in draft.attachments {
            controller.addAttachmentData(try file.data(), mimeType: file.mimeType, fileName: file.filename)
        }
        return controller
    }
}
#endif
