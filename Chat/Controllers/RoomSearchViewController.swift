//
//  RoomSearchViewController.swift
//  OutPick
//
//  Created by 김가윤 on 9/28/25.
//

import UIKit
import Combine
import FirebaseStorage

class RoomSearchViewController: UIViewController {
    
    private var cancellables = Set<AnyCancellable>()

    private lazy var customNavigationBar: CustomNavigationBarView = {
        let customNavigationBar = CustomNavigationBarView()
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        return customNavigationBar
    }()

    // MARK: - Search UI
    private let searchContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 12
        v.layer.masksToBounds = true
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .secondaryLabel
        return iv
    }()

    private let searchTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "방 이름이나 키워드 검색"
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = .search
        tf.borderStyle = .none
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.enablesReturnKeyAutomatically = true
        return tf
    }()

    /// 외부에서 검색어 변경을 구독하고 싶을 때 사용
    var onSearchTextChange: ((String) -> Void)?

    // MARK: - Recent Searches
    private let recentHeaderContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let recentTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "최근 검색어"
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let toggleSaveSwitch: UISwitch = {
        let sw = UISwitch()
        sw.translatesAutoresizingMaskIntoConstraints = false
        sw.isOn = true
        return sw
    }()
    
    private lazy var recentSearchesCollection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.showsHorizontalScrollIndicator = false
        cv.backgroundColor = .clear
        return cv
    }()

    
    private var recentSearches: [String] = []
    private var searchResultsCollection: UICollectionView!
    private var searchResults: [ChatRoom] = []
    private var isLoadingMore = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        
        setupNavigationBar()
        setupSearchBar()
        setupRecentSearchUI()
        setupSearchResultsCollection()
        if let saved = UserDefaults.standard.stringArray(forKey: "recentSearches") {
            recentSearches = saved
        }
        self.updateRecentPlaceholder()
        toggleSaveSwitch.addTarget(self, action: #selector(toggleSaveSwitchChanged(_:)), for: .valueChanged)
        bindPublishers()
    }
    
    private func setupSearchResultsCollection() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 8

        searchResultsCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        searchResultsCollection.translatesAutoresizingMaskIntoConstraints = false
        searchResultsCollection.backgroundColor = .clear
        view.addSubview(searchResultsCollection)

        let placeholderLabel = UILabel()
        placeholderLabel.text = "일치하는 채팅방이 없어요."
        placeholderLabel.textAlignment = .center
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.font = .systemFont(ofSize: 14)
        searchResultsCollection.backgroundView = placeholderLabel
        searchResultsCollection.backgroundView?.isHidden = true

        NSLayoutConstraint.activate([
            searchResultsCollection.topAnchor.constraint(equalTo: recentSearchesCollection.bottomAnchor, constant: 16),
            searchResultsCollection.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            searchResultsCollection.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            searchResultsCollection.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        searchResultsCollection.dataSource = self
        searchResultsCollection.delegate = self
        searchResultsCollection.register(SearchResultRoomCell.self, forCellWithReuseIdentifier: "SearchResultCell")
    }
    
    @objc private func toggleSaveSwitchChanged(_ sender: UISwitch) {
        if !sender.isOn {
            // Clear recent searches when turning off
            recentSearches.removeAll()
            UserDefaults.standard.removeObject(forKey: "recentSearches")
            recentSearchesCollection.reloadData()
            self.updateRecentPlaceholder()
        }
    }
    
    private func bindPublishers() {
        NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification, object: searchTextField)
            .compactMap { ($0.object as? UITextField)?.text }
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }
                Task {
                    do {
                        let rooms = try await FirebaseManager.shared.searchRooms(keyword: text, reset: true)
                        await MainActor.run {
                            self.searchResults = rooms
                            self.searchResultsCollection.reloadData()
                            
                            // ✅ 검색 결과 없으면 placeholder 보이기
                            self.searchResultsCollection.backgroundView?.isHidden = !rooms.isEmpty
                            print(#function, "✅✅✅✅✅rooms: \(rooms)")
                        }
                    } catch {
                        print("검색 실패: \(error)")
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    private func setupNavigationBar() {
        self.view.addSubview(customNavigationBar)
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        customNavigationBar.configure(leftViews: [UIButton.navBackButton(action: backBtnTapped)],
                                      centerViews: [UILabel.navTitle("검색")],
                                      rightViews: [])
        searchTextField.delegate = self
    }

    @MainActor
    private func setupSearchBar() {
        view.addSubview(searchContainer)
        searchContainer.addSubview(searchIconView)
        searchContainer.addSubview(searchTextField)

        NSLayoutConstraint.activate([
            // Container just under the custom nav bar
            searchContainer.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            searchContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),

            // Icon
            searchIconView.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 12),
            searchIconView.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: 20),
            searchIconView.heightAnchor.constraint(equalToConstant: 20),

            // TextField
            searchTextField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 8),
            searchTextField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchTextField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }
    
    @MainActor
    private func setupRecentSearchUI() {
        view.addSubview(recentHeaderContainer)
        recentHeaderContainer.addSubview(recentTitleLabel)
        recentHeaderContainer.addSubview(toggleSaveSwitch)
        view.addSubview(recentSearchesCollection)

        NSLayoutConstraint.activate([
            // Header container below search bar
            recentHeaderContainer.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 16),
            recentHeaderContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            recentHeaderContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            recentHeaderContainer.heightAnchor.constraint(equalToConstant: 24),

            // Title label at left
            recentTitleLabel.leadingAnchor.constraint(equalTo: recentHeaderContainer.leadingAnchor),
            recentTitleLabel.centerYAnchor.constraint(equalTo: recentHeaderContainer.centerYAnchor),

            // Switch at right
            toggleSaveSwitch.trailingAnchor.constraint(equalTo: recentHeaderContainer.trailingAnchor),
            toggleSaveSwitch.centerYAnchor.constraint(equalTo: recentHeaderContainer.centerYAnchor),

            // Collection below header
            recentSearchesCollection.topAnchor.constraint(equalTo: recentHeaderContainer.bottomAnchor, constant: 8),
            recentSearchesCollection.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            recentSearchesCollection.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            recentSearchesCollection.heightAnchor.constraint(equalToConstant: 40),
        ])

        recentSearchesCollection.dataSource = self
        recentSearchesCollection.delegate = self
        recentSearchesCollection.register(RecentSearchChipCell.self, forCellWithReuseIdentifier: "RecentSearchChipCell")
        
        let placeholderLabel = UILabel()
        placeholderLabel.text = "최근 검색어가 없어요."
        placeholderLabel.textAlignment = .center
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.font = .systemFont(ofSize: 14)
        recentSearchesCollection.backgroundView = placeholderLabel
    }
    
    private func updateRecentPlaceholder() {
        if recentSearches.isEmpty {
            recentSearchesCollection.backgroundView?.isHidden = false
        } else {
            recentSearchesCollection.backgroundView?.isHidden = true
        }
    }
    
    @MainActor
    private func backBtnTapped() {
        self.dismiss(animated: true)
    }
}

extension RoomSearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let text = textField.text ?? ""
        if toggleSaveSwitch.isOn, !text.isEmpty {
            if let idx = recentSearches.firstIndex(of: text) {
                recentSearches.remove(at: idx)
            }
            recentSearches.insert(text, at: 0)
            UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
            recentSearchesCollection.reloadData()
            self.updateRecentPlaceholder()
        }
        onSearchTextChange?(text)
 
        
        return true
    }
}

extension RoomSearchViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == recentSearchesCollection {
            return recentSearches.count
        } else if collectionView == searchResultsCollection {
            return searchResults.count
        }
        return 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == recentSearchesCollection {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "RecentSearchChipCell", for: indexPath) as! RecentSearchChipCell
            cell.configure(with: recentSearches[indexPath.item]) { [weak self] in
                guard let self = self else { return }
                self.recentSearches.remove(at: indexPath.item)
                UserDefaults.standard.set(self.recentSearches, forKey: "recentSearches")
                self.recentSearchesCollection.reloadData()
                self.updateRecentPlaceholder()
            }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SearchResultCell", for: indexPath) as! SearchResultRoomCell
            let room = searchResults[indexPath.item]
            cell.configure(with: room)
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == recentSearchesCollection {
            let selected = recentSearches[indexPath.item]
            searchTextField.text = selected
            if toggleSaveSwitch.isOn {
                if let idx = recentSearches.firstIndex(of: selected) {
                    recentSearches.remove(at: idx)
                }
                recentSearches.insert(selected, at: 0)
                UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
                recentSearchesCollection.reloadData()
                self.updateRecentPlaceholder()
            }
            onSearchTextChange?(selected)
        } else if collectionView == searchResultsCollection {
            let room = searchResults[indexPath.item]
            // ✅ 방 셀 클릭 시 원하는 동작 (예: 채팅방으로 이동)
            print("선택된 방: \(room.roomName)")
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let chatRoomVC = storyboard.instantiateViewController(withIdentifier: "chatRoomVC") as? ChatViewController else { return }
            chatRoomVC.room = room
            chatRoomVC.isRoomSaving = false
            chatRoomVC.modalPresentationStyle = .fullScreen
            
            guard let presenter = presentingViewController else { return }
            dismiss(animated: false) {
                
                chatRoomVC.modalPresentationStyle = .fullScreen
                presenter.present(chatRoomVC, animated: true)
            }
            
//            ChatModalTransitionManager.present(chatRoomVC, from: self)
        }
    }

    // Size for chip cells
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == recentSearchesCollection {
            let text = recentSearches[indexPath.item]
            let size = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            return CGSize(width: size.width + 40, height: 32)
        } else {
            return CGSize(width: collectionView.bounds.width, height: 80)
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == searchResultsCollection else { return }
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.frame.size.height
        
        if offsetY > contentHeight - height * 2, !isLoadingMore {
            isLoadingMore = true
            Task {
                do {
                    let more = try await FirebaseManager.shared.loadMoreSearchRooms()
                    await MainActor.run {
                        self.searchResults.append(contentsOf: more)
                        self.searchResultsCollection.reloadData()
                        self.isLoadingMore = false
                        // ✅ 검색 결과 없음 여부 갱신
                        self.searchResultsCollection.backgroundView?.isHidden = !self.searchResults.isEmpty
                    }
                } catch {
                    print("추가 로드 실패: \(error)")
                    await MainActor.run { self.isLoadingMore = false }
                }
            }
        }
    }
}

class RecentSearchChipCell: UICollectionViewCell {
    private let label = UILabel()
    private let deleteButton = UIButton(type: .system)
    var onDelete: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemGray5
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true

        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.setTitle("x", for: .normal)
        deleteButton.setTitleColor(.secondaryLabel, for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        contentView.addSubview(label)
        contentView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            deleteButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with text: String, onDelete: @escaping () -> Void) {
        label.text = text
        self.onDelete = onDelete
    }

    @objc private func deleteTapped() {
        onDelete?()
    }
}



// MARK: - SearchResultRoomCell
class SearchResultRoomCell: UICollectionViewCell {
    private let roomImageView = UIImageView()
    private let roomNameLabel = UILabel()
    private let participantsLabel = UILabel()
    private let lastMessageTimeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.systemGray5.cgColor
        

        // 이미지뷰 (둥근 사각형)
        roomImageView.translatesAutoresizingMaskIntoConstraints = false
        roomImageView.layer.cornerRadius = 8
        roomImageView.clipsToBounds = true
        roomImageView.contentMode = .scaleAspectFill

        // 방 이름
        roomNameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        roomNameLabel.textColor = .label
        roomNameLabel.translatesAutoresizingMaskIntoConstraints = false

        // 참여자 수
        participantsLabel.font = .systemFont(ofSize: 13)
        participantsLabel.textColor = .secondaryLabel
        participantsLabel.translatesAutoresizingMaskIntoConstraints = false

        // 마지막 메시지 시간
        lastMessageTimeLabel.font = .systemFont(ofSize: 13)
        lastMessageTimeLabel.textColor = .secondaryLabel
        lastMessageTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        lastMessageTimeLabel.textAlignment = .right

        contentView.addSubview(roomImageView)
        contentView.addSubview(roomNameLabel)
        contentView.addSubview(participantsLabel)
        contentView.addSubview(lastMessageTimeLabel)

        NSLayoutConstraint.activate([
            roomImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            roomImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            roomImageView.widthAnchor.constraint(equalToConstant: 60),
            roomImageView.heightAnchor.constraint(equalToConstant: 60),

            roomNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            roomNameLabel.leadingAnchor.constraint(equalTo: roomImageView.trailingAnchor, constant: 12),
            roomNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),

            participantsLabel.topAnchor.constraint(equalTo: roomNameLabel.bottomAnchor, constant: 6),
            participantsLabel.leadingAnchor.constraint(equalTo: roomNameLabel.leadingAnchor),
            participantsLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),

            lastMessageTimeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            lastMessageTimeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with room: ChatRoom) {
        roomNameLabel.text = room.roomName
        participantsLabel.text = "참여자 수: \(room.participants.count)"

        if let date = room.lastMessageAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            lastMessageTimeLabel.text = formatter.string(from: date)
        } else {
            lastMessageTimeLabel.text = ""
        }

        if let path = room.thumbPath {
            let ref = Storage.storage().reference(withPath: path)
            ref.downloadURL { url, _ in
                if let url = url {
                    URLSession.shared.dataTask(with: url) { data, _, _ in
                        if let data = data {
                            DispatchQueue.main.async {
                                self.roomImageView.image = UIImage(data: data)
                            }
                        }
                    }.resume()
                } else {
                    DispatchQueue.main.async {
                        self.roomImageView.image = UIImage(systemName: "person.3.fill")
                        self.roomImageView.tintColor = .secondaryLabel
                    }
                }
            }
        } else {
            roomImageView.image = UIImage(systemName: "person.3.fill")
            roomImageView.tintColor = .secondaryLabel
        }
    }
}
