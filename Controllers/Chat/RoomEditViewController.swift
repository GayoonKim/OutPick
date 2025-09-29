//
//  ChatEditViewController.swift
//  OutPick
//
//  Created by 김가윤 on 6/14/25.
//

import UIKit
import Combine
import PhotosUI

class RoomEditViewController: UIViewController, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let customNavigationBar: CustomNavigationBarView = {
        let navBar = CustomNavigationBarView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        return navBar
    }()
    
    enum Section {
        case image
        case name
        case description
    }
    
    enum Item: Hashable {
        case image
        case name
        case description
    }
    
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!
    
    var room: ChatRoom
    
    private var cancellables = Set<AnyCancellable>()
    private var cellCancelables: [IndexPath: AnyCancellable] = [:]
    
    private var currentKeyboardHeight: CGFloat?
    
    private var selectedImage: UIImage?
    private var afterRoomname: String = ""
    private var afterDescription: String = ""
    private var convertImageTask: Task<Void, Error>? = nil
    
    var onCompleteEdit: ((UIImage?, String, String) async throws -> Void)?
    
    init(room: ChatRoom) {
        self.room = room
        self.afterRoomname = self.room.roomName
        self.afterDescription = self.room.roomDescription
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        
        setupCustomNavigationBar()
        configureTableView()
        configureDataSource()
        applyInitialSnapshot()
        updateCompleteBtnState()
        
        
    }
    
    private func applyInitialSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.image ,.name, .description])
        snapshot.appendItems( [.image], toSection: .image)
        snapshot.appendItems([.name], toSection: .name)
        snapshot.appendItems([.description], toSection: .description)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func configureTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.backgroundColor = .white

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        tableView.register(EditRoomImageTableViewCell.self, forCellReuseIdentifier: EditRoomImageTableViewCell.identifier)
        tableView.register(EditRoomNameTableViewCell.self, forCellReuseIdentifier: EditRoomNameTableViewCell.identifier)
        tableView.register(EditRoomDesTableViewCell.self, forCellReuseIdentifier: EditRoomDesTableViewCell.identifier)
        
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.keyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }
    
    private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let keyboardHeight = keyboardFrame.height
        self.currentKeyboardHeight = keyboardHeight
        tableView.contentInset.bottom = keyboardHeight + 5
        tableView.verticalScrollIndicatorInsets.bottom = keyboardHeight + 5
    }
    
    private func keyboardWillHide(_ notification: Notification) {
        self.tableView.contentInset.bottom = 0
        self.tableView.verticalScrollIndicatorInsets.bottom = 0
        self.currentKeyboardHeight = nil
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { tableView, indexPath, item in
            switch item {
            case .image:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EditRoomImageTableViewCell.identifier, for: indexPath) as? EditRoomImageTableViewCell else {
                    fatalError("\(EditRoomImageTableViewCell.self) 설정 에러")
                }
                cell.configure(self.room, selectedImage: self.selectedImage)
                
                cell.onImgViewTapped = { [weak self] in
                    guard let self = self else { return }
                    self.presentImgEditActionSheet()
                }
                
                return cell
            case .name:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EditRoomNameTableViewCell.identifier, for: indexPath) as? EditRoomNameTableViewCell else {
                    fatalError("\(EditRoomNameTableViewCell.self) 설정 에러")
                }
                cell.configure(self.room)
                
                cell.nameTextChanged
                    .receive(on: RunLoop.main)
                    .sink { [weak self] text in
                        guard let self = self else { return }
//                        self.room.roomName = text
                        self.afterRoomname = text
                        self.updateCompleteBtnState()
                    }
                    .store(in: &self.cancellables)
                
                return cell
            case .description:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EditRoomDesTableViewCell.identifier, for: indexPath) as? EditRoomDesTableViewCell else {
                    fatalError("\(EditRoomDesTableViewCell.self) 설정 에러")
                }
                cell.configure(self.room)
                
                let cancellable = cell.textViewChanged
                    .receive(on: RunLoop.main)
                    .sink { [weak self] result in
                        guard let self = self else { return }
                        
//                        self.room.roomDescription = result.1
                        self.afterDescription = result.1
                        self.updateCompleteBtnState()
                        
                        self.tableView.beginUpdates()
                        self.tableView.endUpdates()
                        
                        let keyboardHeight = self.currentKeyboardHeight ?? 0
                        let keyboardMinY = self.view.bounds.height - keyboardHeight
                        let convertedMaxY = self.tableView.convert(result.0, to: self.view).maxY
                        
                        if convertedMaxY > keyboardMinY {
                            self.tableView.scrollRectToVisible(result.0, animated: true)
                        }
                        
                    }
                self.cellCancelables[indexPath] = cancellable
                
                return cell
            }
        }
    }
    
    private func updateCompleteBtnState() {
        if let button = customNavigationBar.rightStack.arrangedSubviews
            .compactMap({ $0 as? UIButton })
            .first(where: { $0.currentTitle == "완료" }) {
            let isNameValid = self.afterRoomname != "채팅방 이름 (필수)" && self.afterRoomname != self.room.roomName
            let isDescriptionValid = self.afterDescription != self.room.roomDescription
            
            button.isEnabled = isNameValid || isDescriptionValid
        }
    }
    
    private func presentImgEditActionSheet() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "사진 선택", style: .default, handler: { _ in
            self.openPHPicker()
        }))
        
        alert.addAction(UIAlertAction(title: "사진 촬영", style: .default, handler: { _ in
            self.openCamera()
        }))
        
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive, handler: { _ in
            self.removeImage()
        }))
        
        alert.addAction(UIAlertAction(title: "취소", style: .cancel, handler: nil))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        self.present(alert, animated: true)
    }
    
    private func openPHPicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images])
        configuration.selectionLimit = 1
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.allowsEditing = true
            imagePicker.sourceType = .camera
        
            present(imagePicker, animated: true, completion: nil)
        }
    }
    
    private func removeImage() {
        selectedImage = nil
        self.room.roomImagePath = ""
        
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems([.image])
        dataSource.apply(snapshot, animatingDifferences: false)
    }
                
    @MainActor
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        for result in results {
            let itemProvider = result.itemProvider
            
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                convertImageTask = Task {
                    do {
//                        let image = try await MediaManager.shared.convertImage(result)
//                        self.selectedImage = image
//                        let prevImgName = self.room.roomImagePath
                        
                        var snapshot = dataSource.snapshot()
                        snapshot.reloadItems([.image])
                        await dataSource.apply(snapshot, animatingDifferences: true)
                    } catch {
                        AlertManager.showAlertNoHandler(title: "이미지 변환 실패", message: "이미지를 다시 선택해 주세요/", viewController: self)
                    }
                }
                
                convertImageTask = nil
            }
        }

    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
//        if let editedImage = info[.editedImage] as? UIImage {
//            
//        } else if let originalImage = info[.originalImage] as? UIImage {
//            
//        }
        
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

private extension RoomEditViewController {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        let completeBtn = UIButton(type: .system)
        completeBtn.setTitle("완료", for: .normal)
        completeBtn.setTitleColor(.black, for: .normal)
        completeBtn.setTitleColor(.placeholderText, for: .disabled)
        completeBtn.addTarget(self, action: #selector(completeBtnTapped), for: .touchUpInside)
        
        customNavigationBar.configure(leftViews: [UIButton.navBackButton(action: backBtnTapped)],
                                      centerViews: [UILabel.navTitle("오픈채팅 관리")],
                                      rightViews: [completeBtn])
    }
    
    private func backBtnTapped() {
        self.dismiss(animated: true)
    }
    
    @objc private func completeBtnTapped() {
        Task { @MainActor in
            do {
                LoadingIndicator.shared.start(on: self)
                
                try await onCompleteEdit?(self.selectedImage, self.afterRoomname, self.afterDescription)
                
                LoadingIndicator.shared.stop()
                self.dismiss(animated: true)
            } catch {
                LoadingIndicator.shared.stop()
                AlertManager.showAlertNoHandler(title: "방 수정 실패", message: error.localizedDescription, viewController: self)
            }
        }
    }
}

extension RoomEditViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        switch section {
        case 0:
            NSLayoutConstraint.activate([
                spacer.heightAnchor.constraint(equalToConstant: 25)
            ])
            
            return spacer
            
        case 1:
            NSLayoutConstraint.activate([
                spacer.heightAnchor.constraint(equalToConstant: 10)
            ])
            
            return spacer
        default:
            NSLayoutConstraint.activate([
                spacer.heightAnchor.constraint(equalToConstant: 0)
            ])
            
            return spacer
        }
    }
}
