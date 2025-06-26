//
//  ChatEditViewController.swift
//  OutPick
//
//  Created by 김가윤 on 6/14/25.
//

import UIKit

class RoomEditViewController: UIViewController {
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
    
    init(room: ChatRoom) {
        self.room = room
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
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        tableView.register(EditRoomImageTableViewCell.self, forCellReuseIdentifier: EditRoomImageTableViewCell.identifier)
        tableView.register(EditRoomNameTableViewCell.self, forCellReuseIdentifier: EditRoomNameTableViewCell.identifier)
        tableView.register(EditRoomDesTableViewCell.self, forCellReuseIdentifier: EditRoomDesTableViewCell.identifier)
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { tableView, indexPath, item in
            switch item {
            case .image:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EditRoomImageTableViewCell.identifier, for: indexPath) as? EditRoomImageTableViewCell else {
                    fatalError("\(EditRoomImageTableViewCell.self) 설정 에러")
                }
                
                return cell
            case .name:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EditRoomNameTableViewCell.identifier, for: indexPath) as? EditRoomNameTableViewCell else {
                    fatalError("\(EditRoomNameTableViewCell.self) 설정 에러")
                }
                cell.configure(self.room)
                
                return cell
            case .description:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EditRoomDesTableViewCell.identifier, for: indexPath) as? EditRoomDesTableViewCell else {
                    fatalError("\(EditRoomDesTableViewCell.self) 설정 에러")
                }
                cell.configure(self.room)
                
                return cell
            }
        }
    }
}

private extension RoomEditViewController {
    @MainActor
    func setupCustomNavigationBar() {
        self.view.addSubview(customNavigationBar)
        
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
        
        customNavigationBar.configure(leftViews: [UIButton.navBackButton(action: backBtnTapped)],
                                      centerViews: [UILabel.navTitle("오픈채팅 관리")],
                                      rightViews: [])
    }
    
    private func backBtnTapped() {
        self.dismiss(animated: true)
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
