//
//  RoomCreationError.swift
//  OutPick
//
//  Created by 김가윤 on 3/8/25.
//

import Foundation

enum RoomCreationError: Error {
    case duplicateName
    case saveFailed
    case imageUploadFailed
}
