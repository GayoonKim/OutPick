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
    private var roomsMap: [String: ChatRoom] = [:]
    private var roomsListener: ListenerRegistration?
    private var monthlyRoomListeners: [String: ListenerRegistration] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
    }
    
    private func listenForChatRooms() {
        
        removeAllListeners()
        
        roomsListener = db.collection("Rooms").addSnapshotListener { [weak self] snapshot, error in
            
            guard let self = self, let documents = snapshot?.documents else {
                print("월별 문서 목록 불러오기 실패: \(error!.localizedDescription)")
                return
            }
            
            Task{
                
                await self.setupMonthlyListeners(documents: documents)
                
            }
            
        }
        
    }
    
    private func setupMonthlyListeners(documents: [QueryDocumentSnapshot]) async {
        return await withThrowingTaskGroup(of: Void.self) { group in
            for document in documents {
                let monthID = document.documentID
                group.addTask { [weak self] in
                    
                    guard let self = self else { return }
                    await self.listenToMonthlyRooms(monthID: monthID)
                    
                }
            }
        }
    }
    
    private func listenToMonthlyRooms(monthID: String) async {
        let monthlyRoomsRef = db.collection("Rooms").document(monthID).collection("\(monthID) Rooms")
        monthlyRoomListeners[monthID]?.remove()
        
        let listener = monthlyRoomsRef.addSnapshotListener { [weak self] snapshot, error in
            
            guard let self = self, let snapshot = snapshot else {
                print("\(monthID)월 채팅방 목록 불러오기 실패: \(error!.localizedDescription)")
                return
            }
            
            Task {
                await self.processChanges(snapshot: snapshot)
            }
            
        }
        
        monthlyRoomListeners[monthID] = listener
    }
    
    private func processChanges(snapshot: QuerySnapshot) async {
        await withThrowingTaskGroup(of: ChatRoom?.self) { group in
            for change in snapshot.documentChanges {
                group.addTask { [weak self] in
                    
                    guard let self = self else { return nil}
                    let document = change.document
                    let data = document.data()
                    
                    if change.type == .removed {
                        if let roomName = data["roomName"] as? String,
                           let index = await self.chatRooms.first(where: { $0.roomName == roomName }) {
                            self.chatRooms.remove(at: index)
                        }
                    }
                    return nil
                }
            }
        }
    }
    
    private func removeAllListeners() {
        
        roomsListener?.remove()
        roomsListener = nil
        
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
