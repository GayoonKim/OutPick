import UIKit

@MainActor
final class BlockedUsersViewController: UIViewController {
    private let viewModel: BlockedUsersViewModel
    private let avatarImageManager: any AvatarImageManaging
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerContainer = UIView()
    private let header = MyPageEditorialHeaderView()
    private let countLabel = UILabel()
    private let errorLabel = UILabel()
    private let statusTitle = UILabel()
    private let statusDescription = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private let refreshControl = UIRefreshControl()
    private var renderedIDs: [String] = []

    init(viewModel: BlockedUsersViewModel, avatarImageManager: any AvatarImageManaging) {
        self.viewModel = viewModel
        self.avatarImageManager = avatarImageManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        viewModel.onStateChanged = { [weak self] state in self?.apply(state) }
        apply(viewModel.state)
        Task { await viewModel.load() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeHeader()
    }

    private func configureUI() {
        navigationItem.title = ""
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.showsVerticalScrollIndicator = false
        tableView.alwaysBounceVertical = true
        tableView.dataSource = self
        tableView.register(BlockedUserCell.self, forCellReuseIdentifier: BlockedUserCell.reuseID)
        tableView.refreshControl = refreshControl
        refreshControl.tintColor = OutPickTheme.ColorToken.accent
        refreshControl.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        header.configure(eyebrow: "PRIVACY", title: "차단한 사용자",
                         subtitle: "내가 보고 싶은 콘텐츠를 위한 선택")
        countLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = OutPickTheme.ColorToken.textSecondary
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.numberOfLines = 0
        errorLabel.adjustsFontForContentSizeCategory = true
        let line = UIView()
        line.backgroundColor = OutPickTheme.ColorToken.borderStrong
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        let stack = UIStackView(arrangedSubviews: [header, countLabel, errorLabel, line])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(30, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor)
        ])
        tableView.tableHeaderView = headerContainer

        statusTitle.font = MyPageEditorialStyle.serifFont(size: 23, weight: .semibold)
        statusTitle.textColor = OutPickTheme.ColorToken.textPrimary
        statusDescription.font = .preferredFont(forTextStyle: .subheadline)
        statusDescription.textColor = OutPickTheme.ColorToken.textSecondary
        [statusTitle, statusDescription].forEach {
            $0.numberOfLines = 0
            $0.textAlignment = .center
            $0.adjustsFontForContentSizeCategory = true
        }
        spinner.color = OutPickTheme.ColorToken.accent
        retryButton.setTitle("다시 불러오기", for: .normal)
        retryButton.tintColor = OutPickTheme.ColorToken.accent
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retryButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
    }

    private func resizeHeader() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let size = headerContainer.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        guard headerContainer.frame.size != CGSize(width: width, height: size.height) else { return }
        headerContainer.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableHeaderView = headerContainer
    }

    private func apply(_ state: BlockedUsersViewModel.State) {
        countLabel.text = state.hasLoaded ? "\(state.users.count)명" : " "
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil || state.users.isEmpty
        if !state.isLoading { refreshControl.endRefreshing() }
        let ids = state.users.map { $0.blockedUserID.value }
        if renderedIDs != ids {
            renderedIDs = ids
            tableView.reloadData()
        } else {
            for case let cell as BlockedUserCell in tableView.visibleCells {
                guard let index = tableView.indexPath(for: cell)?.row,
                      state.users.indices.contains(index) else { continue }
                configure(cell, user: state.users[index])
            }
        }
        updateStatus(state)
        resizeHeader()
    }

    private func updateStatus(_ state: BlockedUsersViewModel.State) {
        guard state.users.isEmpty else {
            spinner.stopAnimating()
            tableView.tableFooterView = nil
            return
        }
        let loading = state.isLoading || (!state.hasLoaded && state.errorMessage == nil)
        loading ? spinner.startAnimating() : spinner.stopAnimating()
        statusTitle.text = loading ? "목록을 불러오고 있어요" :
            (state.errorMessage == nil ? "차단한 사용자가 없어요" : "잠시 연결을 확인해 주세요")
        statusDescription.text = state.errorMessage ??
            (loading ? nil : "차단한 계정이 생기면 이곳에서\n확인하고 해제할 수 있어요.")
        retryButton.isHidden = state.errorMessage == nil || loading
        let stack = UIStackView(arrangedSubviews: [spinner, statusTitle, statusDescription, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let footer = UIView()
        footer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 64),
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -40)
        ])
        let width = max(tableView.bounds.width, view.bounds.width)
        let size = footer.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        footer.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableFooterView = footer
    }

    private func configure(_ cell: BlockedUserCell, user: UserBlock) {
        let state = viewModel.state
        let id = user.blockedUserID.value
        cell.configure(userID: id, nickname: state.nickname(for: user),
                       avatarPath: state.profiles[id]?.avatarThumbPath,
                       isUnblocking: state.unblockingIDs.contains(id),
                       isEnabled: !state.isLoading, manager: avatarImageManager)
        cell.onUnblock = { [weak self] in self?.confirmUnblock(user) }
        Task { await viewModel.loadProfile(for: user) }
    }

    private func confirmUnblock(_ user: UserBlock) {
        let alert = UIAlertController(title: "차단을 해제할까요?",
            message: "\(viewModel.state.nickname(for: user))님의 콘텐츠가 새로 불러오는 화면부터 다시 표시됩니다.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "차단 해제", style: .default) { [weak self] _ in
            Task { await self?.viewModel.unblock(user) }
        })
        present(alert, animated: true)
    }

    @objc private func reload() { Task { await viewModel.load() } }
}

extension BlockedUsersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.state.users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: BlockedUserCell.reuseID,
                                                       for: indexPath) as? BlockedUserCell else {
            return UITableViewCell()
        }
        configure(cell, user: viewModel.state.users[indexPath.row])
        return cell
    }
}
