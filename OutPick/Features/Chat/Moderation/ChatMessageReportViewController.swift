import UIKit

@MainActor
final class ChatMessageReportViewController: UIViewController, UITextViewDelegate {
    var onCancel: (() -> Void)?
    var onCompletion: ((ChatMessageReportViewModel.Completion) -> Void)?

    private let viewModel: ChatMessageReportViewModel
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let reasonStack = UIStackView()
    private let detailTextView = UITextView()
    private let detailPlaceholderLabel = UILabel()
    private let countLabel = UILabel()
    private let errorLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private var reasonButtons: [ChatModerationReportReason: UIButton] = [:]

    init(viewModel: ChatMessageReportViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "취소",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        setupLayout()
        setupKeyboardDismissal()
        viewModel.onStateChange = { [weak self] state in self?.render(state) }
        render(.idle)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory
                != traitCollection.preferredContentSizeCategory else { return }
        updateAdaptiveControlTypography()
    }

    private func setupLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 22),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -36)
        ])

        let header = makeHeader()
        contentStack.addArrangedSubview(header)
        contentStack.setCustomSpacing(28, after: header)

        let scopeCard = makeScopeCard()
        contentStack.addArrangedSubview(scopeCard)
        contentStack.setCustomSpacing(32, after: scopeCard)

        let reasonHeader = makeSectionHeader(index: "01", title: "신고 사유")
        contentStack.addArrangedSubview(reasonHeader)
        contentStack.setCustomSpacing(14, after: reasonHeader)

        reasonStack.axis = .vertical
        reasonStack.spacing = 10
        contentStack.addArrangedSubview(reasonStack)
        for reason in ChatModerationReportReason.allCases {
            let button = makeReasonButton(for: reason)
            reasonButtons[reason] = button
            reasonStack.addArrangedSubview(button)
        }
        contentStack.setCustomSpacing(32, after: reasonStack)

        let detailHeader = makeSectionHeader(index: "02", title: "상세 내용")
        contentStack.addArrangedSubview(detailHeader)
        contentStack.setCustomSpacing(6, after: detailHeader)

        let optionalLabel = UILabel()
        optionalLabel.text = "선택 사항 · 필요한 내용을 500자 이내로 적어주세요."
        optionalLabel.font = .preferredFont(forTextStyle: .caption1)
        optionalLabel.textColor = OutPickTheme.ColorToken.textTertiary
        optionalLabel.numberOfLines = 0
        optionalLabel.adjustsFontForContentSizeCategory = true
        contentStack.addArrangedSubview(optionalLabel)
        contentStack.setCustomSpacing(14, after: optionalLabel)

        let detailContainer = makeDetailContainer()
        contentStack.addArrangedSubview(detailContainer)
        contentStack.setCustomSpacing(14, after: detailContainer)

        errorLabel.numberOfLines = 0
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = OutPickTheme.ColorToken.destructive
        errorLabel.isHidden = true
        contentStack.addArrangedSubview(errorLabel)
        contentStack.setCustomSpacing(18, after: errorLabel)

        configureSubmitButton()
        contentStack.addArrangedSubview(submitButton)
    }

    private func makeHeader() -> UIView {
        let eyebrowLabel = UILabel()
        eyebrowLabel.text = "COMMUNITY REPORT"
        eyebrowLabel.font = Self.scaledMonospacedFont(
            size: 11,
            weight: .semibold,
            textStyle: .caption1,
            compatibleWith: traitCollection
        )
        eyebrowLabel.textColor = OutPickTheme.ColorToken.accent
        eyebrowLabel.adjustsFontForContentSizeCategory = true

        let titleLabel = UILabel()
        titleLabel.text = "메시지 신고"
        titleLabel.font = Self.editorialFont(size: 36, weight: .bold, textStyle: .largeTitle)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true

        let subtitleLabel = UILabel()
        subtitleLabel.text = "안전한 대화를 위해 신고 내용을 알려주세요."
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = OutPickTheme.ColorToken.textSecondary
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        let accentLine = UIView()
        accentLine.backgroundColor = OutPickTheme.ColorToken.accent
        accentLine.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accentLine.widthAnchor.constraint(equalToConstant: 44),
            accentLine.heightAnchor.constraint(equalToConstant: 2)
        ])

        let stack = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, subtitleLabel, accentLine])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(12, after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)
        return stack
    }

    private func makeScopeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1
        card.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor

        let captionLabel = UILabel()
        captionLabel.text = "REPORT SCOPE"
        captionLabel.font = Self.scaledMonospacedFont(
            size: 10,
            weight: .semibold,
            textStyle: .caption2,
            compatibleWith: traitCollection
        )
        captionLabel.textColor = OutPickTheme.ColorToken.accent
        captionLabel.adjustsFontForContentSizeCategory = true

        let explanationLabel = UILabel()
        explanationLabel.numberOfLines = 0
        explanationLabel.font = .preferredFont(forTextStyle: .subheadline)
        explanationLabel.adjustsFontForContentSizeCategory = true
        explanationLabel.textColor = OutPickTheme.ColorToken.textPrimary
        explanationLabel.text = viewModel.isMediaContext
            ? "현재 보고 있는 사진 한 장이 아니라 이 사진들이 포함된 메시지 전체를 신고합니다."
            : "신고 사유와 메시지 전체 내용이 운영팀 검토 자료로 전달됩니다."

        let stack = UIStackView(arrangedSubviews: [captionLabel, explanationLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])
        return card
    }

    private func makeSectionHeader(index: String, title: String) -> UIView {
        let indexLabel = UILabel()
        indexLabel.text = index
        indexLabel.font = Self.scaledMonospacedFont(
            size: 11,
            weight: .bold,
            textStyle: .caption1,
            compatibleWith: traitCollection
        )
        indexLabel.textColor = OutPickTheme.ColorToken.accent
        indexLabel.adjustsFontForContentSizeCategory = true
        indexLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Self.editorialFont(size: 23, weight: .semibold, textStyle: .title2)
        titleLabel.textColor = OutPickTheme.ColorToken.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true

        let line = UIView()
        line.backgroundColor = OutPickTheme.ColorToken.borderSubtle

        let stack = UIStackView(arrangedSubviews: [indexLabel, titleLabel, line])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return stack
    }

    private func makeReasonButton(for reason: ChatModerationReportReason) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = reasonConfiguration(for: reason, isSelected: false)
        button.contentHorizontalAlignment = .leading
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1
        button.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor
        button.clipsToBounds = true
        button.accessibilityLabel = reason.displayTitle
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.select(reason) }, for: .touchUpInside)
        return button
    }

    private func reasonConfiguration(
        for reason: ChatModerationReportReason,
        isSelected: Bool
    ) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = reason.displayTitle
        configuration.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        configuration.imagePadding = 12
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        configuration.baseBackgroundColor = isSelected
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.surfaceBase
        configuration.baseForegroundColor = isSelected
            ? OutPickTheme.ColorToken.backgroundBase
            : OutPickTheme.ColorToken.textPrimary
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            let baseFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            attributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: baseFont,
                compatibleWith: self.traitCollection
            )
            return attributes
        }
        let scaledSymbolSize = UIFontMetrics(forTextStyle: .body).scaledValue(
            for: 18,
            compatibleWith: traitCollection
        )
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: min(scaledSymbolSize, 30),
            weight: .regular
        )
        return configuration
    }

    private func makeDetailContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = OutPickTheme.ColorToken.surfaceBase
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 1
        container.layer.borderColor = OutPickTheme.ColorToken.borderSubtle.cgColor

        detailTextView.backgroundColor = .clear
        detailTextView.font = .preferredFont(forTextStyle: .body)
        detailTextView.adjustsFontForContentSizeCategory = true
        detailTextView.textColor = OutPickTheme.ColorToken.textPrimary
        detailTextView.tintColor = OutPickTheme.ColorToken.accent
        detailTextView.delegate = self
        detailTextView.accessibilityLabel = "신고 상세 내용"
        detailTextView.textContainerInset = .zero
        detailTextView.textContainer.lineFragmentPadding = 0

        detailPlaceholderLabel.text = "운영팀이 확인할 내용을 입력해 주세요."
        detailPlaceholderLabel.font = .preferredFont(forTextStyle: .body)
        detailPlaceholderLabel.adjustsFontForContentSizeCategory = true
        detailPlaceholderLabel.textColor = OutPickTheme.ColorToken.textTertiary
        detailPlaceholderLabel.numberOfLines = 0
        detailPlaceholderLabel.isUserInteractionEnabled = false

        countLabel.text = "0 / 500"
        countLabel.textAlignment = .right
        countLabel.font = Self.scaledMonospacedFont(
            size: 11,
            weight: .medium,
            textStyle: .caption1,
            compatibleWith: traitCollection
        )
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = OutPickTheme.ColorToken.textTertiary

        [detailTextView, detailPlaceholderLabel, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            detailTextView.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            detailTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            detailTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            detailTextView.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -12),
            detailPlaceholderLabel.topAnchor.constraint(equalTo: detailTextView.topAnchor),
            detailPlaceholderLabel.leadingAnchor.constraint(equalTo: detailTextView.leadingAnchor),
            detailPlaceholderLabel.trailingAnchor.constraint(equalTo: detailTextView.trailingAnchor),
            detailPlaceholderLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: countLabel.topAnchor,
                constant: -12
            ),
            countLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            countLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func configureSubmitButton() {
        submitButton.configuration = makeSubmitButtonConfiguration()
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        updateSubmitButton(for: .idle)
    }

    private func makeSubmitButtonConfiguration() -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "신고"
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 20, bottom: 15, trailing: 20)
        configuration.baseBackgroundColor = OutPickTheme.ColorToken.accent
        configuration.baseForegroundColor = OutPickTheme.ColorToken.backgroundBase
        configuration.cornerStyle = .capsule
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            let baseFont = UIFont.systemFont(ofSize: 16, weight: .bold)
            attributes.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
                for: baseFont,
                compatibleWith: self.traitCollection
            )
            return attributes
        }
        return configuration
    }

    private func setupKeyboardDismissal() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    private func select(_ reason: ChatModerationReportReason) {
        viewModel.selectedReason = reason
        for (candidate, button) in reasonButtons {
            let isSelected = candidate == reason
            button.configuration = reasonConfiguration(for: candidate, isSelected: isSelected)
            button.layer.borderColor = (
                isSelected ? OutPickTheme.ColorToken.accent : OutPickTheme.ColorToken.borderSubtle
            ).cgColor
            button.accessibilityValue = isSelected ? "선택됨" : nil
        }
        setError(nil)
        updateSubmitButton(for: viewModel.state)
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView.text.count > 500 {
            textView.text = String(textView.text.prefix(500))
        }
        viewModel.detail = textView.text
        detailPlaceholderLabel.isHidden = !textView.text.isEmpty
        countLabel.text = "\(textView.text.count) / 500"
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func submitTapped() {
        view.endEditing(true)
        Task { [weak self] in
            guard let self, let completion = await viewModel.submit() else { return }
            onCompletion?(completion)
        }
    }

    private func render(_ state: ChatMessageReportViewModel.State) {
        updateSubmitButton(for: state)
        switch state {
        case .idle:
            setError(nil)
        case .submitting:
            setError(nil)
        case .error(let message):
            setError(message)
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func updateSubmitButton(for state: ChatMessageReportViewModel.State) {
        let isSubmitting = state == .submitting
        let isEnabled = viewModel.selectedReason != nil && !isSubmitting
        submitButton.isEnabled = isEnabled
        submitButton.configuration?.baseBackgroundColor = isEnabled
            ? OutPickTheme.ColorToken.accent
            : OutPickTheme.ColorToken.surfaceElevated
        submitButton.configuration?.baseForegroundColor = isEnabled
            ? OutPickTheme.ColorToken.backgroundBase
            : OutPickTheme.ColorToken.textDisabled
        submitButton.accessibilityHint = viewModel.selectedReason == nil
            ? "신고 사유를 선택하면 활성화됩니다."
            : nil
    }

    private func updateAdaptiveControlTypography() {
        for (reason, button) in reasonButtons {
            let isSelected = viewModel.selectedReason == reason
            button.configuration = reasonConfiguration(for: reason, isSelected: isSelected)
        }
        submitButton.configuration = makeSubmitButtonConfiguration()
        updateSubmitButton(for: viewModel.state)
    }

    private func setError(_ message: String?) {
        errorLabel.text = message
        errorLabel.isHidden = message == nil
    }

    private static func editorialFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let serif = base.fontDescriptor.withDesign(.serif).map {
            UIFont(descriptor: $0, size: size)
        } ?? base
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: serif)
    }

    private static func scaledMonospacedFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        compatibleWith traitCollection: UITraitCollection
    ) -> UIFont {
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: base,
            compatibleWith: traitCollection
        )
    }
}

extension ChatMessageReportViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView: UIView? = touch.view
        while let currentView = touchedView {
            if currentView === detailTextView {
                return false
            }
            touchedView = currentView.superview
        }
        return true
    }
}

private extension ChatModerationReportReason {
    var displayTitle: String {
        switch self {
        case .harassment: "욕설·괴롭힘"
        case .hate: "혐오 표현"
        case .sexual: "성적 콘텐츠"
        case .spam: "스팸·광고"
        case .privacy: "개인정보 노출"
        case .illegalDangerous: "불법·위험"
        case .other: "기타"
        }
    }
}
