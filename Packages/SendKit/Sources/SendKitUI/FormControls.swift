import SendKit
import SwiftUI

/// A labeled text row. macOS grouped forms label text fields natively; iOS only shows the
/// placeholder, so there the label is added with `LabeledContent` (or above, for multi-line).
struct Field: View {
    enum Content { case text, email, url, code }

    var label: String
    @Binding var text: String
    var prompt: String?
    var content: Content = .text
    var multiline = false

    init(_ label: String, text: Binding<String>, prompt: String? = nil, content: Content = .text, multiline: Bool = false) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.content = content
        self.multiline = multiline
    }

    var body: some View {
        #if os(macOS)
        field
        #else
        if multiline {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                field
            }
        } else {
            LabeledContent(label) {
                field.multilineTextAlignment(.trailing)
            }
        }
        #endif
    }

    private var field: some View {
        TextField(label, text: $text, prompt: prompt.map { Text($0) }, axis: multiline ? .vertical : .horizontal)
            .lineLimit(multiline ? 3...12 : 1...1)
            .font(content == .code ? .body.monospaced() : .body)
            .autocorrectionDisabled(content != .text)
            #if os(iOS)
            .textInputAutocapitalization(content == .text ? .sentences : .never)
            .keyboardType(content == .email ? .emailAddress : content == .url ? .URL : .default)
            #endif
    }
}

/// A labeled integer row.
struct NumberField: View {
    var label: String
    @Binding var value: Int

    init(_ label: String, value: Binding<Int>) {
        self.label = label
        _value = value
    }

    var body: some View {
        #if os(macOS)
        TextField(label, value: $value, format: .number.grouping(.never))
        #else
        LabeledContent(label) {
            TextField(label, value: $value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
        }
        #endif
    }
}

/// A secure field backed directly by the Keychain.
struct SecretField: View {
    var label: String
    var key: String
    @State private var value: String

    init(_ label: String, key: String) {
        self.label = label
        self.key = key
        _value = State(initialValue: SecretStore.shared.get(key) ?? "")
    }

    var body: some View {
        LabeledSecureField(label, text: $value)
            .onChange(of: value) { _, newValue in SecretStore.shared.set(newValue, for: key) }
    }
}

struct LabeledSecureField: View {
    var label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        _text = text
    }

    var body: some View {
        #if os(macOS)
        SecureField(label, text: $text)
        #else
        LabeledContent(label) {
            SecureField(label, text: $text, prompt: Text("Not set"))
                .multilineTextAlignment(.trailing)
        }
        #endif
    }
}

/// Icon choice for an endpoint, from symbols that suit the use case.
struct SymbolPicker: View {
    @Binding var selection: String

    static let symbols = [
        "doc.text.magnifyingglass", "doc.text", "receipt", "creditcard", "banknote", "building.columns",
        "envelope", "paperplane", "tray.and.arrow.up", "network", "cloud", "server.rack",
        "folder", "archivebox", "briefcase", "person.crop.circle", "cart", "bolt",
    ]

    var body: some View {
        Picker("Icon", selection: $selection) {
            ForEach(Self.symbols.contains(selection) ? Self.symbols : [selection] + Self.symbols, id: \.self) { symbol in
                Label(symbol, systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .tag(symbol)
            }
        }
        .pickerStyle(.menu)
    }
}
