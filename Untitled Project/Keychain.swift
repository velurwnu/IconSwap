import Foundation
import Security

enum KeychainError: LocalizedError {
    case notFound
    case unexpectedData
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "API-ключ macosicons не найден в Keychain (service: IconSwap, account: macosicons-api)."
        case .unexpectedData:
            return "Не удалось прочитать API-ключ из Keychain: неожиданный формат данных."
        case .osStatus(let status):
            return "Keychain вернул ошибку (\(status)) при чтении API-ключа."
        }
    }
}

enum Keychain {
    static func readAPIKey(service: String = "IconSwap", account: String = "macosicons-api") throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return key
    }
}
