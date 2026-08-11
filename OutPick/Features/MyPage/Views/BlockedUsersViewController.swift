import UIKit

@MainActor
final class BlockedUsersViewController: UIViewController {
    private let viewModel: BlockedUsersViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(viewModel: BlockedUsersViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "차단한 사용자"
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        navigationController?.setNavigationBarHidden(false, animated: false)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        viewModel.onStateChanged = { [weak self] _ in self?.tableView.reloadData() }
        Task { await viewModel.load() }
    }
}

extension BlockedUsersViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.state.users.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "BlockedUserCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let user = viewModel.state.users[indexPath.row]
        cell.textLabel?.text = user.blockedUserNicknameSnapshot ?? "알 수 없는 사용자"
        cell.detailTextLabel?.text = "차단 해제"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = viewModel.state.users[indexPath.row]
        let alert = UIAlertController(
            title: "차단을 해제할까요?",
            message: "이후 새로 불러오는 콘텐츠부터 다시 표시됩니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "차단 해제", style: .default) { [weak self] _ in
            Task { await self?.viewModel.unblock(user) }
        })
        present(alert, animated: true)
    }
}
