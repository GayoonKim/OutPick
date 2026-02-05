//
//  FirstProfileViewController.swift
//  OutPick
//

import UIKit

/// 프로필 설정 1단계(성별/생년월일) 화면
final class FirstProfileViewController: UIViewController {

    private let viewModel: FirstProfileViewModel

    // MARK: - UI

    private let titleLabel = UILabel()

    private let genderHintLabel = UILabel()
    private let maleButton = UIButton(type: .system)
    private let femaleButton = UIButton(type: .system)

    private let birthHintLabel = UILabel()
    private let datePicker = UIDatePicker()

    private let nextButton = UIButton(type: .system)

    // MARK: - Init

    init(viewModel: FirstProfileViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - LifeCycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupUI()
        bind()

        // ✅ 중요: 사용자가 피커를 건드리지 않아도 birthdate가 nil이 되지 않게 초기값을 ViewModel에 반영
        viewModel.setBirthdate(datePicker.date)
        
        print("✅ FirstProfileViewController loaded:", String(describing: type(of: self)))
    }

    // MARK: - Setup

    private func setupUI() {
        // Title
        titleLabel.text = "프로필 설정"
        titleLabel.font = .boldSystemFont(ofSize: 22)
        titleLabel.numberOfLines = 1

        // Hints
        genderHintLabel.text = "성별을 선택해 주세요"
        genderHintLabel.font = .systemFont(ofSize: 13)
        genderHintLabel.textColor = .secondaryLabel

        birthHintLabel.text = "생년월일을 선택해 주세요"
        birthHintLabel.font = .systemFont(ofSize: 13)
        birthHintLabel.textColor = .secondaryLabel

        // Gender buttons
        configureGenderButton(maleButton, title: "남성", value: "male")
        configureGenderButton(femaleButton, title: "여성", value: "female")

        let genderStack = UIStackView(arrangedSubviews: [maleButton, femaleButton])
        genderStack.axis = .horizontal
        genderStack.spacing = 12
        genderStack.distribution = .fillEqually

        // DatePicker
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.datePickerMode = .date
        datePicker.locale = Locale(identifier: "ko_KR")

        // max date
        datePicker.maximumDate = viewModel.state.maxBirthdate
        datePicker.date = viewModel.state.maxBirthdate
        datePicker.addTarget(self, action: #selector(birthdateChanged(_:)), for: .valueChanged)

        // Next button (bottom pinned)
        nextButton.setTitle("다음  1/2", for: .normal)
        nextButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        nextButton.layer.cornerRadius = 12
        nextButton.backgroundColor = .label
        nextButton.setTitleColor(.systemBackground, for: .normal)
        nextButton.setTitleColor(.systemBackground.withAlphaComponent(0.7), for: .disabled)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        // Root stack (content only)
        let root = UIStackView(arrangedSubviews: [
            titleLabel,
            genderHintLabel,
            genderStack,
            birthHintLabel,
            datePicker
        ])
        root.axis = .vertical
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(root)
        view.addSubview(nextButton)

        nextButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: nextButton.topAnchor, constant: -16),

            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            nextButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        // 초기 상태
        applyGenderSelection(selected: nil)
        nextButton.isEnabled = false
        nextButton.alpha = 0.5
    }

    private func configureGenderButton(_ button: UIButton, title: String, value: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        button.backgroundColor = .secondarySystemBackground
        button.setTitleColor(.label, for: .normal)
        button.accessibilityIdentifier = value
        button.addTarget(self, action: #selector(genderTapped(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    // MARK: - Bind

    private func bind() {
        viewModel.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.nextButton.isEnabled = state.isNextEnabled
            self.nextButton.alpha = state.isNextEnabled ? 1.0 : 0.5
            self.applyGenderSelection(selected: state.selectedGender)
        }

        // 최초 상태 반영
        viewModel.onStateChanged?(viewModel.state)
    }

    // MARK: - Actions

    @objc private func genderTapped(_ sender: UIButton) {
        guard let value = sender.accessibilityIdentifier else { return }
        viewModel.selectGender(value)
    }

    @objc private func birthdateChanged(_ sender: UIDatePicker) {
        viewModel.setBirthdate(sender.date)
    }

    @objc private func nextTapped() {
        viewModel.tapNext()
    }

    // MARK: - UI Helpers

    private func applyGenderSelection(selected: String?) {
        let isMale = (selected == "male")
        let isFemale = (selected == "female")

        styleGenderButton(maleButton, selected: isMale)
        styleGenderButton(femaleButton, selected: isFemale)
    }

    private func styleGenderButton(_ button: UIButton, selected: Bool) {
        if selected {
            button.backgroundColor = .label
            button.setTitleColor(.systemBackground, for: .normal)
            button.layer.borderColor = UIColor.label.cgColor
        } else {
            button.backgroundColor = .secondarySystemBackground
            button.setTitleColor(.label, for: .normal)
            button.layer.borderColor = UIColor.separator.cgColor
        }
    }
}
