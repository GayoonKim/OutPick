//
//  UserDefaultsManager.swift
//  OutPick
//
//  Created by 김가윤 on 10/29/24.
//

import UIKit

class UserDefaultsManager {
    
    enum UserDefaultsKeys: String, CaseIterable {
        case email
    }
    
    static func setData<T>(value: T, key: UserDefaultsKeys) {
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: key.rawValue)
    }
    
    static func getData<T>(type: T.Type, forKey: UserDefaultsKeys) -> T?{
        let defaults = UserDefaults.standard
        let value = defaults.object(forKey: forKey.rawValue) as? T
        return value
    }
}
