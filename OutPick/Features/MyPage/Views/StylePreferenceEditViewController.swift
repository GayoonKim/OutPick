import UIKit

final class StylePreferenceEditViewController: UIViewController, UISearchBarDelegate {
    private let viewModel: StylePreferenceEditViewModel
    private let headerView = MyPageEditorialHeaderView()
    private let searchBar = UISearchBar()
    private let selectionLabel = UILabel()
    private let pickerView = StyleMoodPickerView()
    private let saveButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()

    init(viewModel: StylePreferenceEditViewModel) {
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
        bind()
        viewModel.load()
    }

    private func configureUI() {
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        navigationItem.title = ""
        navigationController?.setNavigationBarHidden(false, animated: false)
        headerView.configure(
            eyebrow: "MY STYLE",
            title: "마음이 가는\n스타일",
            subtitle: "최대 5개까지 골라 나의 취향을 완성해요"
        )
        searchBar.placeholder = "스타일 이름 검색"
        searchBar.delegate = self
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        searchBar.searchTextField.textColor = OutPickTheme.ColorToken.textPrimary
        searchBar.searchTextField.tintColor = OutPickTheme.ColorToken.accent
        searchBar.searchTextField.layer.cornerRadius = 17
        searchBar.searchTextField.clipsToBounds = true
        selectionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        selectionLabel.textColor = OutPickTheme.ColorToken.accent
        MyPageEditorialStyle.configurePrimaryButton(saveButton, title: "관심 스타일 저장")
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        activityIndicator.color = OutPickTheme.ColorToken.accent
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        pickerView.onToggleMood = { [weak self] id in self?.viewModel.toggleMood(id: id) }

        [headerView, searchBar, selectionLabel, pickerView, messageLabel, saveButton, activityIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 22),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            selectionLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            selectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            pickerView.topAnchor.constraint(equalTo: selectionLabel.bottomAnchor, constant: 12),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            pickerView.bottomAnchor.constraint(equalTo: messageLabel.topAnchor, constant: -8),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            messageLabel.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -10),
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in self?.apply(state) }
        apply(viewModel.state)
    }

    private func apply(_ state: StylePreferenceEditViewModel.State) {
        selectionLabel.text = state.selectionText
        pickerView.apply(moods: state.visibleMoods, selectedMoodIDs: state.selectedMoodIDs)
        messageLabel.text = state.errorMessage ?? state.emptyMessage
        messageLabel.textColor = state.errorMessage == nil
            ? OutPickTheme.ColorToken.textSecondary
            : OutPickTheme.ColorToken.destructive
        messageLabel.isHidden = messageLabel.text == nil
        MyPageEditorialStyle.applyPrimaryButtonState(saveButton, isEnabled: state.isSaveEnabled)
        state.isLoading || state.isSaving
            ? activityIndicator.startAnimating()
            : activityIndicator.stopAnimating()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.setSearchQuery(searchText)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        viewModel.saveTapped()
    }
}
