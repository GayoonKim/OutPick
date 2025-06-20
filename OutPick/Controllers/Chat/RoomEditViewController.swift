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
        case main
    }
    
    enum Item: Hashable {
        case name
//        case description
//        case image
    }
    
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!
    
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
        snapshot.appendSections([.main])
        snapshot.appendItems([.name], toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func configureTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        tableView.register(EditRoomNameTableViewCell.self, forCellReuseIdentifier: EditRoomNameTableViewCell.identifier)
        
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { tableView, indexPath, item in
            switch item {
            case .name:
                guard let cell = tableView.dequeueReusableCell(withIdentifier: EditRoomNameTableViewCell.identifier, for: indexPath) as? EditRoomNameTableViewCell else {
                    fatalError("셀 설정 에러")
                }
                
                return cell
//            case .description:
//                print("D")
//            case .image:
//                print("I")
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
                                      centerViews: [UILabel.navTitle("오픈채팅 정보")],
                                      rightViews: [])
    }
    
    private func backBtnTapped() {
        self.dismiss(animated: true)
    }
}
