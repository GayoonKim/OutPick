//
//  PracViewController.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/25.
//

import UIKit
import AVKit
import Foundation
import AVFoundation
import Alamofire
import PhotosUI
import Kingfisher
import Firebase
import FirebaseStorage
import SwiftUI

class PracViewController: UIViewController, UINavigationControllerDelegate {
    
    @IBOutlet weak var testImageView0: UIImageView!
    @IBOutlet weak var testImageView1: UIImageView!
    
    @IBOutlet weak var playBtn: UIButton!
    @IBOutlet weak var testProgressView: UIProgressView!
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    private var selectedVideos: [String] = []
    private var selectedImages: [URL] = []
    
    private var convertVideosTask: Task<Void, Error>? = nil
    private var convertImagesTask: Task<Void, Error>? = nil
    
    deinit {
        convertVideosTask?.cancel()
        convertImagesTask?.cancel()
    }
    
    private var chatRooms: [ChatRoom] = []
//    private var roomsMap: [String: ChatRoom] = [:]
//    private var roomsListener: ListenerRegistration?
    private var monthlyRoomListeners: [String: ListenerRegistration] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            try await listenToRooms()
        }
        
        
        
    }
    
    private func createRoom(data: [String:Any]) async throws -> ChatRoom {
        
        guard let roomName = data["roomName"] as? String,
              let roomDescription = data["roomDescription"] as? String,
              let participants = data["participantIDs"] as? [String],
              let creatorID = data["creatorID"] as? String,
              let timestamp = data["createdAt"] as? Timestamp,
              let roomImageName = data["roomImageName"] as? String else {
            print("채팅방 데이터 파싱 실패: \(data)")
            throw FirebaseError.FailedToParseRoomData
        }
        
        Task {
            do {
                let _ = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: roomImageName, location: ImageLocation.RoomImage, createdDate: timestamp.dateValue())
            } catch {
                retry(asyncTask: { let _ = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: roomImageName, location: ImageLocation.RoomImage, createdDate: timestamp.dateValue())  }) { result in
                    switch result {
                    case .success():
                        print("이미지 캐싱 재시도 성공")
                        return
                    case .failure(let error):
                        print("이미지 캐싱 재시도 실패: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        return ChatRoom(roomName: roomName, roomDescription: roomDescription, participants: participants, creatorID: creatorID, createdAt: timestamp.dateValue(), roomImageName: roomImageName)
        
    }
    
    private func processRoomChanges(documentChanges: [DocumentChange]) async throws {
        print("RoomChange 호출")
        
        do {
            try await withThrowingTaskGroup(of: (DocumentChangeType, ChatRoom).self, returning: Void.self) { group in
                for change in documentChanges {
                    group.addTask {
                        let document = change.document
                        let data = document.data()
                        
                        let room = try await self.createRoom(data: data)
                        return (change.type, room)
                        
                    }
                }
                
                for try await (changeType, room) in group {
                    switch changeType {
                        
                    case .added:
                        print("추가")
                        self.chatRooms.append(room)
                        
                    case .modified:
                        print("수정")
                        if let index = self.chatRooms.firstIndex(where: { $0.roomName == room.roomName }) {
                            self.chatRooms[index] = room
                        }
                        
                    case .removed:
                        print("삭제")
                        self.chatRooms.removeAll(where: { $0.roomName == room.roomName })
                        
                    }
                }
                
            }
        } catch {
            
            retry(asyncTask: { try await self.processRoomChanges(documentChanges: documentChanges)}) { result in
                switch result {
                    
                case .success():
                    print("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 성공")
                    return
                    
                case .failure(let error):
                    print ("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 실패: \(error.localizedDescription)")
                    AlertManager.showAlert(title: "네트워크 오류", message: "네트워크 오류로 오픈채팅 목록을 불러오는데 실패했습니다. 네트워크 연결을 확인해 주세요.", viewController: self)
                    return
                    
                }
            }
            
        }
        
    }
    
    private func processAllRooms(documents: [QueryDocumentSnapshot]) async throws {
        print("AllRooms 호출")
        
        do {
            try await withThrowingTaskGroup(of: ChatRoom.self, returning: Void.self) { group in
                for document in documents {
                    group.addTask {
                        
                        let data = document.data()
                        let chatRoom = try await self.createRoom(data: data)
                        
                        return chatRoom
                        
                    }
                }
                
                for try await room in group {
                    self.chatRooms.append(room)
                }
                
            }
        } catch {
            retry(asyncTask: { try await self.processAllRooms(documents: documents)}) { result in
                switch result {
                    
                case .success():
                    print("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 성공")
                    return
                    
                case .failure(let error):
                    print ("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 실패: \(error.localizedDescription)")
                    AlertManager.showAlert(title: "네트워크 오류", message: "네트워크 오류로 오픈채팅 목록을 불러오는데 실패했습니다. 네트워크 연결을 확인해 주세요.", viewController: self)
                    return
                    
                }
            }
        }
        
    }
    
    private func listenToMonthlyRoom(monthID: String) async throws -> ListenerRegistration {
        
        let listerner = db.collection("Rooms").document(monthID).collection("\(monthID) Rooms").addSnapshotListener { (querySnapshot, error) in
            
            guard let querySnapshot = querySnapshot, error == nil else {
                print("월별 문서 하위 컬렉션 실시간 리스너 설정 실패: \(error!.localizedDescription)")
                retry(asyncTask: { let _ = try await self.listenToMonthlyRoom(monthID: monthID )}) { result in
                    switch result {
                        
                    case .success():
                        print("월별 문서 하위 컬렉션 실시간 리스너 재설정 성공")
                        return
                        
                    case .failure(let error):
                        print ("월별 문서 하위 컬렉션 실시간 리스너 재설정 실패: \(error.localizedDescription)")
                        AlertManager.showAlert(title: "네트워크 오류", message: "네트워크 오류로 오픈채팅 목록을 불러오는데 실패했습니다. 네트워크 연결을 확인해 주세요.", viewController: self)
                        return
                    }
                }
                return
            }
            
            if querySnapshot.documentChanges.isEmpty {
                let documents = querySnapshot.documents
                Task {
                    try await self.processAllRooms(documents: documents)
                }
                
            } else {
                let documentChanges = querySnapshot.documentChanges
                Task {
                    try await self.processRoomChanges(documentChanges: documentChanges)
                }
            }
            
        }
        
        return listerner
        
    }

    private func listenToMonthlyRooms(monthIDs: [String]) async throws {
        
        do {
            try await withThrowingTaskGroup(of: (String, ListenerRegistration).self, returning: Void.self) { group in
                for monthID in monthIDs {
                    group.addTask {
                        
                        let listener = try await self.listenToMonthlyRoom(monthID: monthID)
                        return (monthID, listener)
                        
                    }
                }
                
                for try await (monthID, listener) in group {
                    monthlyRoomListeners[monthID] = listener
                }
                
            }
            
            
        } catch {
            retry(asyncTask: { try await self.listenToMonthlyRooms(monthIDs: monthIDs) }) { result in
                switch result {
                 
                case .success():
                    print("월별 하위 컬렉션 리스너 재설정 성공")
                    return
                    
                case .failure(let error):
                    print("월별 하위 컬렉션 리스너 재설정 실패: \(error.localizedDescription)")
                    return
                    
                }
            }
            
        }
        
    }
    
    func listenToRooms(/*completion: @escaping ([ChatRoom]) -> Void*/) async throws{
        
        //기존 모든 리스너 제거
        removeAllListeners()
        
//        Task {
            do {
                
                // 모든 월별 문서 ID 불러오기
                let monthIDs = try await FirebaseManager.shared.fetchAllDocIDs(collectionName: "Rooms")
                
                // 모든 월별 문서의 하위 컬렉션 리스너 설정
                try await listenToMonthlyRooms(monthIDs: monthIDs)
                
                print("호출 끝")
                
            } catch {
                
                retry(asyncTask: listenToRooms) { result in
                    switch result {
                        
                    case .success():
                        print("월별 문서 불러오기 재시도 성공")
                        return
                        
                    case .failure(let error):
                        print("월별 문서 목록 불러오기 실패: \(error.localizedDescription)")
                        return
                        
                    }
                }
                
            }
//        }
        
        
    }
        
    
    
    private func removeAllListeners() {
        
//        roomsListener?.remove()
//        roomsListener = nil
        
        for listener in monthlyRoomListeners.values {
            listener.remove()
        }
        monthlyRoomListeners.removeAll()
        
    }
    
    @IBAction func albumBtnTapped(_ sender: UIButton) {
        openPHPicker()
    }
    
    
    private func openPHPicker() {
        
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
        
    }
    
    func playVideo(from url: URL) {
        
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        present(playerViewController, animated: true) {
            player.play()
        }
        
    }
    
}

extension PracViewController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        var resultsForVideos: [PHPickerResult] = []
        var resultsForImages: [PHPickerResult] = []
        
        for result in results {
            let itemProvider = result.itemProvider
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                
                resultsForVideos.append(result)
                
            } else if itemProvider.canLoadObject(ofClass: UIImage.self) {
                
                resultsForImages.append(result)
                
            }
            
        }
        
        if !resultsForVideos.isEmpty {
            convertVideosTask = Task {
                do {
                    
                    let compressedURLs = try await MediaManager.shared.dealWithVideos(resultsForVideos)
                    
                    self.selectedVideos = try await FirebaseStorageManager.shared.uploadVideosToStorage(compressedURLs)
                    
                } catch {
                    
                    print("비디오 불러오기 실패: \(error.localizedDescription)")
                    
                }
                
                convertVideosTask = nil
                
            }
        }
        
        if !resultsForImages.isEmpty {
            convertImagesTask = Task {
                do {
                    
                    let images = try await MediaManager.shared.dealWithImages(resultsForImages)
                    let imageNames = try await FirebaseStorageManager.shared.uploadImagesToStorage(images: images, location: ImageLocation.Test)
                    
                    
                } catch MediaError.FailedToConvertImage {
                    
                    AlertManager.showAlert(title: "이미지 변환 실패", message: "이미지를 다시 선택해 주세요/", viewController: self)
                    
                } catch StorageError.FailedToUploadImage {
                    
                    print("이미지 업로드 실패")
                    
                } catch StorageError.FailedToFetchImage {
                    
                    print("이미지 불러오기 실패")
                    
                }
            }
            
            convertImagesTask = nil
            
        }
        
    }
    
}


extension PracViewController: UIImagePickerControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        if let editedImage = info[.editedImage] as? UIImage {
            self.testImageView0.image = editedImage
        } else if let originalImage = info[.originalImage] as? UIImage {
            self.testImageView0.image = originalImage
        }
        
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
}

//struct PracViewControllerRepresentable: UIViewControllerRepresentable {
//
//    func makeUIViewController(context: Context) -> PracViewController {
//        <#code#>
//    }
//
//    func updateUIViewController(_ uiViewController: PracViewController, context: Context) {
//        <#code#>
//    }
//
//}
