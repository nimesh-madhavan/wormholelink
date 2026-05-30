import Foundation
import Security

enum KeychainSecretKind: String {
    case tunnelPassword = "tunnel-password"
    case tunnelPassphrase = "tunnel-passphrase"
    case adminPassword = "admin-password"
}

final class KeychainService {
    private let serviceName = "com.wormholelink.app"

    func save(secret: String, kind: KeychainSecretKind, account: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(kind: kind, account: account)

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    func readSecret(kind: KeychainSecretKind, account: String) throws -> String? {
        var query = baseQuery(kind: kind, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }

        guard let data = item as? Data else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    func deleteSecret(kind: KeychainSecretKind, account: String) {
        SecItemDelete(baseQuery(kind: kind, account: account) as CFDictionary)
    }

    private func baseQuery(kind: KeychainSecretKind, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrLabel as String: "WormholeLink \(kind.rawValue)",
            kSecAttrAccount as String: "\(kind.rawValue):\(account)"
        ]
    }
}

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }

            return "Keychain error \(status)"
        }
    }
}