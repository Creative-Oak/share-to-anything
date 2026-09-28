import Foundation

/// Renders an RFC 5322 message with attachments (multipart/mixed, base64 parts).
struct MIMEMessage {
    struct Attachment {
        var filename: String
        var mimeType: String
        var data: Data
    }

    var fromAddress: String
    var fromName: String
    var to: [String]
    var cc: [String]
    var subject: String
    var body: String
    var attachments: [Attachment]
    var date = Date()
    var boundary = "STA-\(UUID().uuidString)"
    var messageID = "<\(UUID().uuidString)@sharetoanything>"

    func render() -> Data {
        var lines: [String] = []
        let from = fromName.isEmpty ? fromAddress : "\(Self.encodeWord(fromName)) <\(fromAddress)>"
        lines.append("From: \(from)")
        lines.append("To: \(to.joined(separator: ", "))")
        if !cc.isEmpty { lines.append("Cc: \(cc.joined(separator: ", "))") }
        lines.append("Subject: \(Self.encodeWord(subject))")
        lines.append("Date: \(Self.rfc2822Date(date))")
        lines.append("Message-ID: \(messageID)")
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        lines.append("")
        lines.append("--\(boundary)")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: base64")
        lines.append("")
        lines.append(Self.base64Lines(Data(body.utf8)))
        for attachment in attachments {
            let asciiName = Self.asciiFallback(attachment.filename)
            lines.append("--\(boundary)")
            lines.append("Content-Type: \(attachment.mimeType); name=\"\(asciiName)\"")
            lines.append("Content-Transfer-Encoding: base64")
            lines.append("Content-Disposition: attachment; filename=\"\(asciiName)\"; filename*=UTF-8''\(Self.percentEncode(attachment.filename))")
            lines.append("")
            lines.append(Self.base64Lines(attachment.data))
        }
        lines.append("--\(boundary)--")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    /// RFC 2047 encoded-word for non-ASCII header text.
    static func encodeWord(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { !$0.isASCII || $0.value < 32 }) else { return text }
        return "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }

    static func asciiFallback(_ name: String) -> String {
        let expanded = name.replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "Ø", with: "O")
            .replacingOccurrences(of: "æ", with: "ae").replacingOccurrences(of: "Æ", with: "Ae")
        let folded = expanded.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? expanded
        return String(folded.unicodeScalars.map { $0.isASCII && $0 != "\"" && $0.value >= 32 ? Character($0) : "_" })
    }

    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func base64Lines(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
    }

    static func rfc2822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
