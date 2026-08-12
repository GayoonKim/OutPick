import UIKit

@MainActor
final class ChatRoomBannedUsersViewController: UIViewController {
    private let viewModel: ChatRoomBannedUsersViewModel
    var onBack: (() -> Void)?

    private let backButton = UIButton(type: .system)
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let accentLine = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    init(viewModel: ChatRoomBannedUsersViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        loadInitial()
    }

    private func configureUI() {
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        navigationItem.hidesBackButton = true

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = OutPickTheme.ColorToken.iconPrimary
        backButton.accessibilityLabel = "뒤로"
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)

        eyebrowLabel.text = "ROOM CONTROL"
        eyebrowLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrowLabel.textColor = OutPickTheme.ColorToken.accent
        eyebrowLabel.adjustsFontForContentSizeCategory = true

        titleLabel.text = "차단 사용자"
        titleLabel.font = Self.serifFont(size: 34, weight: .bold)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true

        accentLine.backgroundColor = OutPickTheme.ColorToken.accent

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.alwaysBounceVertical = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.register(BannedUserCell.self, forCellReuseIdentifier: BannedUserCell.reuseIdentifier)

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = OutPickTheme.ColorToken.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true

        retryButton.setTitle("다시 시도", for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        retryButton.tintColor = OutPickTheme.ColorToken.accent
        retryButton.addTarget(self, action: #selector(didTapRetry), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, accentLine])
        headerStack.axis = .vertical
        headerStack.spacing = 8
        headerStack.setCustomSpacing(18, after: titleLabel)

        let statusStack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, retryButton])
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 12

        [backButton, headerStack, tableView, statusStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        accentLine.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            headerStack.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            accentLine.heightAnchor.constraint(equalToConstant: 2),
            accentLine.widthAnchor.constraint(equalToConstant: 44),

            tableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusStack.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            statusStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            statusStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])

        render()
    }

    private func loadInitial() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            renderLoading()
            do {
                try await viewModel.loadInitial()
                render()
            } catch {
                renderError()
            }
        }
    }

    private func loadMoreIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self, viewModel.hasMore else { return }
            do {
                try await viewModel.loadMore()
                render()
            } catch {
                showTransientError()
            }
        }
    }

    private func confirmUnban(_ entry: ChatRoomBanEntry) {
        let name = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name : nil) ?? "이 사용자"
        let alert = UIAlertController(
            title: "차단을 해제할까요?",
            message: "\(displayName)은 다시 채팅방에 참여할 수 있게 됩니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "해제", style: .default) { [weak self] _ in
            self?.unban(entry)
        })
        present(alert, animated: true)
    }

    private func unban(_ entry: ChatRoomBanEntry) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            tableView.reloadData()
            do {
                try await viewModel.unban(entry)
                render()
            } catch {
                tableView.reloadData()
                showTransientError()
            }
        }
    }

    private func renderLoading() {
        tableView.isHidden = true
        statusLabel.text = "차단 사용자를 불러오는 중이에요"
        retryButton.isHidden = true
        statusLabel.isHidden = false
        activityIndicator.startAnimating()
    }

    private func renderError() {
        tableView.isHidden = true
        activityIndicator.stopAnimating()
        statusLabel.text = "차단 사용자를 불러오지 못했어요."
        statusLabel.isHidden = false
        retryButton.isHidden = false
    }

    private func render() {
        activityIndicator.stopAnimating()
        retryButton.isHidden = true
        let count = viewModel.entries.count
        statusLabel.text = "차단된 사용자가 없어요."
        statusLabel.isHidden = count > 0
        tableView.isHidden = count == 0
        tableView.reloadData()
    }

    private func showTransientError() {
        let alert = UIAlertController(
            title: "처리하지 못했어요",
            message: "잠시 후 다시 시도해 주세요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    @objc private func didTapBack() {
        if let onBack {
            onBack()
        } else if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func didTapRetry() {
        loadInitial()
    }

    fileprivate static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension ChatRoomBannedUsersViewController: UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: BannedUserCell.reuseIdentifier,
            for: indexPath
        ) as? BannedUserCell else { return UITableViewCell() }
        let entry = viewModel.entries[indexPath.row]
        cell.configure(entry: entry, isWorking: viewModel.isRemoving(entry))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = viewModel.entries[indexPath.row]
        guard !viewModel.isRemoving(entry) else { return }
        confirmUnban(entry)
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        guard let last = indexPaths.map(\.row).max(),
              last >= max(0, viewModel.entries.count - 5) else { return }
        loadMoreIfNeeded()
    }
}

private final class BannedUserCell: UITableViewCell {
    static let reuseIdentifier = "BannedUserCell"

    private let profileImageView = UIImageView()
    private let nameLabel = UILabel()
    private let metadataLabel = UILabel()
    private let actionLabel = UILabel()
    private let separator = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(entry: ChatRoomBanEntry, isWorking: Bool) {
        let trimmedName = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? "알 수 없는 사용자"
        nameLabel.text = name
        profileImageView.image = UIImage(named: "Default_Profile")

        let reason = ChatRoomMemberRemovalReason(rawValue: entry.reasonCode)?.title ?? "기타"
        if let bannedAt = entry.bannedAt {
            metadataLabel.text = "\(reason) · \(Self.dateFormatter.string(from: bannedAt))"
        } else {
            metadataLabel.text = reason
        }

        actionLabel.isHidden = isWorking
        if isWorking {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        accessibilityLabel = "\(name), \(metadataLabel.text ?? ""), 해제"
    }

    private func configureUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        profileImageView.contentMode = .scaleAspectFill
        profileImageView.backgroundColor = OutPickTheme.ColorToken.surfaceElevated
        profileImageView.layer.cornerRadius = 24
        profileImageView.clipsToBounds = true

        nameLabel.font = ChatRoomBannedUsersViewController.serifFont(size: 20, weight: .semibold)
        nameLabel.textColor = OutPickTheme.ColorToken.textPrimary
        nameLabel.adjustsFontForContentSizeCategory = true

        metadataLabel.font = .preferredFont(forTextStyle: .caption1)
        metadataLabel.textColor = OutPickTheme.ColorToken.textSecondary
        metadataLabel.adjustsFontForContentSizeCategory = true

        actionLabel.text = "해제"
        actionLabel.font = .systemFont(ofSize: 13, weight: .bold)
        actionLabel.textColor = OutPickTheme.ColorToken.accent
        actionLabel.setContentHuggingPriority(.required, for: .horizontal)
        separator.backgroundColor = OutPickTheme.ColorToken.borderSubtle

        let labels = UIStackView(arrangedSubviews: [nameLabel, metadataLabel])
        labels.axis = .vertical
        labels.spacing = 5

        let trailing = UIStackView(arrangedSubviews: [actionLabel, activityIndicator])
        trailing.axis = .horizontal
        trailing.alignment = .center

        let row = UIStackView(arrangedSubviews: [profileImageView, labels, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14

        [row, separator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -16),
            profileImageView.widthAnchor.constraint(equalToConstant: 48),
            profileImageView.heightAnchor.constraint(equalToConstant: 48),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter
    }()
}
