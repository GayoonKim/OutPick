import Foundation
import Security

protocol AccountDeletionReceiptStoring {
    func save(_ receipt: AccountDeletionReceipt) throws
    func load() throws -> AccountDeletionReceipt?
    func delete() throws
}

enum AccountDeletionReceiptStoreError: Error, Equatable {
    case encodingFailed
    case keychain(OSStatus)
}

final class AccountDeletionReceiptStore: AccountDeletionReceiptStoring {
    private let service: String
    private let account = "Receipt"

    init(service: String = "OutPick.AccountDeletion") {
        self.service = service
    }

    func save(_ receipt: AccountDeletionReceipt) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(receipt)
        } catch {
            throw AccountDeletionReceiptStoreError.encodingFailed
        }

        let query = baseQuery()
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccountDeletionReceiptStoreError.keychain(status)
        }
    }

    func load() throws -> AccountDeletionReceipt? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AccountDeletionReceiptStoreError.keychain(status)
        }
        do {
            return try JSONDecoder().decode(AccountDeletionReceipt.self, from: data)
        } catch {
            throw AccountDeletionReceiptStoreError.encodingFailed
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountDeletionReceiptStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
