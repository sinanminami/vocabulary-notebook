import Foundation
import Security

public protocol APIKeyStore: Sendable {
    func read() throws -> String?
    func save(_ apiKey: String) throws
    func delete() throws
}

public enum APIKeyStoreError: Error, Equatable, Sendable {
    case invalidValue
    case keychain(OSStatus)
}

extension APIKeyStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidValue:
            "API Key 不能为空。"
        case let .keychain(status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain 操作失败（\(status)）。"
        }
    }
}

public final class KeychainAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String, account: String = "gemini-api-key") {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.keychain(status)
        }
        return value
    }

    public func save(_ apiKey: String) throws {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            throw APIKeyStoreError.invalidValue
        }

        let lookup: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insertion = lookup
            insertion[kSecValueData] = data
            insertion[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw APIKeyStoreError.keychain(updateStatus)
        }
    }

    public func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(status)
        }
    }
}
