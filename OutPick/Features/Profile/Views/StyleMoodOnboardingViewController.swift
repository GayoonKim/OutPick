import UIKit

final class StyleMoodOnboardingViewController: UIViewController {
    private let viewModel: StyleMoodOnboardingViewModel

    private let backButton = UIButton(type: .system)
    private let headerView = OnboardingEditorialHeaderView()
    private let searchBar = UISearchBar()
    private let selectionLabel = UILabel()
    private let pickerView = StyleMoodPickerView()
    private let emptyLabel = UILabel()
    private let errorLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let completeButton = UIButton(type: .system)

    init(viewModel: StyleMoodOnboardingViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        configureUI()
        bind()
        viewModel.load()
    }

    private func configureUI() {
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = OutPickTheme.ColorToken.textPrimary
        backButton.accessibilityLabel = "이전"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        headerView.configure(
            step: "03 / 03",
            title: "마음이 가는\n스타일을 골라요",
            subtitle: "선택한 무드를 바탕으로 취향에 맞는 브랜드를 보여드려요"
        )

        searchBar.delegate = self
        searchBar.placeholder = "스타일 검색"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.tintColor = OutPickTheme.ColorToken.accent
        searchBar.searchTextField.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        searchBar.searchTextField.textColor = OutPickTheme.ColorToken.textPrimary
        searchBar.searchTextField.layer.cornerRadius = 12
        searchBar.searchTextField.clipsToBounds = true
        searchBar.accessibilityLabel = "관심 스타일 검색"

        selectionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        selectionLabel.textColor = OutPickTheme.ColorToken.accent
        selectionLabel.textAlignment = .right

        pickerView.onToggleMood = { [weak self] moodID in
            self?.viewModel.toggleMood(id: moodID)
        }

        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = OutPickTheme.ColorToken.textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true

        activityIndicator.color = OutPickTheme.ColorToken.accent

        completeButton.setTitle("OutPick 시작하기", for: .normal)
        completeButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        completeButton.layer.cornerRadius = 14
        completeButton.addTarget(self, action: #selector(completeTapped), for: .touchUpInside)

        [
            backButton, headerView, searchBar, selectionLabel, pickerView,
            emptyLabel, errorLabel, activityIndicator, completeButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            headerView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 4),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 18),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            searchBar.heightAnchor.constraint(equalToConstant: 48),

            selectionLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            selectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            selectionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            pickerView.topAnchor.constraint(equalTo: selectionLabel.bottomAnchor, constant: 10),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            pickerView.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: pickerView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: pickerView.centerYAnchor),

            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            errorLabel.bottomAnchor.constraint(equalTo: completeButton.topAnchor, constant: -10),

            completeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            completeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            completeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            completeButton.heightAnchor.constraint(equalToConstant: 54),

            activityIndicator.centerXAnchor.constraint(equalTo: pickerView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: pickerView.centerYAnchor)
        ])
    }

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            self?.apply(state)
        }
        apply(viewModel.state)
    }

    private func apply(_ state: StyleMoodOnboardingViewModel.State) {
        selectionLabel.text = "\(state.selectionText) SELECTED"
        pickerView.apply(
            moods: state.visibleMoods,
            selectedMoodIDs: state.selectedMoodIDs
        )
        emptyLabel.text = state.emptyMessage
        emptyLabel.isHidden = state.emptyMessage == nil || state.isLoading
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        backButton.isEnabled = state.isSaving == false
        searchBar.isUserInteractionEnabled = state.isSaving == false
        completeButton.isEnabled = state.isCompleteEnabled
        completeButton.backgroundColor = state.isCompleteEnabled
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.surfaceElevated
        completeButton.setTitleColor(
            state.isCompleteEnabled
                ? OutPickTheme.ColorToken.backgroundBase
                : OutPickTheme.ColorToken.textDisabled,
            for: .normal
        )
        if state.isLoading || state.isSaving {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    @objc private func backTapped() {
        viewModel.backTapped()
    }

    @objc private func completeTapped() {
        searchBar.resignFirstResponder()
        viewModel.completeTapped()
    }
}

extension StyleMoodOnboardingViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.setSearchQuery(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
