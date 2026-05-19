//
//  UIDevice+PersistentDeviceID.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

extension UIDevice {
    static var persistentDeviceID: String {
        if let saved = KeychainManager.shared.read(service: "OutPick", account: "PersistentDeviceID"),
           let id = String(data: saved, encoding: .utf8) {
            return id
        }
        let newID = UUID().uuidString
        KeychainManager.shared.save(Data(newID.utf8), service: "OutPick", account: "PersistentDeviceID")
        return newID
    }
}
