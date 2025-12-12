//
//  FirebaseError.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import UIKit

enum FirebaseError: Error {
    case Duplicate
    case FailedToSaveProfile
    case FailedToFetchProfile
    case FailedToFetchAllDocumentIDs
    case FailedToFetchRoom
    case FailedToParseRoomData
    case unknownError
}

enum StorageError: Error {
    case FailedToUploadImage
    case FailedToFetchImage
    case FailedToConvertImage
    case FailedToUploadVideo
    case FailedToFetchVideo
}
