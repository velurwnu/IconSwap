import SwiftUI

/// Shown once on first launch (blocking, no cancel) and reopened from
/// settings to change the key later. Never pre-fills the existing key —
/// Keychain reads give back the secret, so showing it back in a plain
/// text field would be an easy way to leak it over someone's shoulder.
struct APIKeySheet: View {
    enum Mode {
        case onboarding
        case edit
    }

    let mode: Mode
    var onSave: (String) -> Void
    var onCancel: (() -> Void)?

    @State private var keyText = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmedKey: String {
        keyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .onboarding ? "Нужен API-ключ macosicons.com" : "Изменить API-ключ")
                .font(.headline)
            Text("Ключ используется для поиска иконок на macosicons.com и хранится в Keychain. Получить его можно бесплатно на сайте.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Link("Получить API-ключ на macosicons.com", destination: URL(string: "https://macosicons.com")!)
                .font(.callout)
            SecureField("API-ключ", text: $keyText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
            HStack {
                if mode == .edit {
                    Button("Отмена") {
                        onCancel?()
                        dismiss()
                    }
                }
                Spacer()
                Button("Сохранить") {
                    onSave(trimmedKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedKey.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
