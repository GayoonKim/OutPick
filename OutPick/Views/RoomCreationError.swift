//
//  RoomCreationError.swift
//  OutPick
//
//  Created by 김가윤 on 10/25/24.
//

import Foundation

enum RoomCreationError: Error {
    case duplicateName
    case saveFailed
    case imageUploadFailed
}
