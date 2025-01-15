//
//  FirebaseError.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import UIKit

enum FirebaseError: Error {
    case NickNameDuplicate
    case FailedToSaveProfile
    case FailedToFetchProfile
    case unknownError
}

enum StorageError: Error {
    case FailedToUploadImage
    case FailedToFetchImage
    case FailedToUploadVideo
    case FailedToFetchVideo
}
