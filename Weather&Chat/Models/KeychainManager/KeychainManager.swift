//
//  KeytchainManager.swift
//  OutPick
//
//  Created by 김가윤 on 4/14/25.
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    func save(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecValueData as String   : data
        ]
        
        // 이미 있는 거 지우고 새로 저장
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        
        print("Keychain 저장 성공")
    }
    
    func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account,
            kSecReturnData as String  : true,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]
        
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            print("Keychain에서 불러오기 성공")
            return item as? Data
        } else {
            print("Keychain에서 불러오기 실패")
            return nil
        }
    }
    
    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : account
        ]
        SecItemDelete(query as CFDictionary)
        
        print("Keychain 삭제 성공")
    }
}
