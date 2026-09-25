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

    static func hasAPIKey(service: String = "IconSwap", account: String = "macosicons-api") -> Bool {
        (try? readAPIKey(service: service, account: account)) != nil
    }

    /// Update-then-add: a plain SecItemAdd would fail with errSecDuplicateItem
    /// on every key change after the first, since the account already exists.
    static func saveAPIKey(_ key: String, service: String = "IconSwap", account: String = "macosicons-api") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
            return
        }
        guard updateStatus == errSecSuccess else { throw KeychainError.osStatus(updateStatus) }
    }
}
