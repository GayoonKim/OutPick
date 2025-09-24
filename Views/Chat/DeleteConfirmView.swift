//
//  DeleteConfirmView.swift
//  OutPick
//
//  Created by 김가윤 on 9/24/25.
//

import UIKit

/// 삭제 확인 오버레이 (딤 + 카드 + 애니메이션) 를 자체적으로 관리하는 뷰
final class DeleteConfirmView: UIView {
    // MARK: - Public API
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    /// 딤을 탭하면 닫을지 여부 (기본 true)
    var allowTapOutsideToCancel: Bool = true

    /// 메시지/버튼 문구 변경
    func configure(message: String,
                   negativeTitle: String = "아니요",
                   positiveTitle: String = "네") {
        messageLabel.text = message
        noButton.setTitle(negativeTitle, for: .normal)
        yesButton.setTitle(positiveTitle, for: .normal)
    }

    /// 로딩 상태 토글 (확인/취소 비활성 + 인디케이터 표시)
    func setLoading(_ loading: Bool) {
        yesButton.isEnabled = !loading
        noButton.isEnabled = !loading
        loading ? activity.startAnimating() : activity.stopAnimating()
    }

    /// 부모 뷰 위에 표시 (오토레이아웃 + 등장 애니메이션)
    func show(in parent: UIView, animated: Bool = true) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])

        // 등장 애니메이션
        if animated {
            self.alpha = 0
            container.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                self.alpha = 1
                self.container.transform = .identity
            }
        }
    }

    /// 닫기 (퇴장 애니메이션 포함)
    func dismiss(animated: Bool = true) {
        let animations = {
            self.alpha = 0
            self.container.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
        let completion: (Bool) -> Void = { _ in
            self.removeFromSuperview()
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn], animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }

    /// 편의 팩토리: 곧바로 표시
    @discardableResult
    static func present(in parent: UIView,
                        message: String = "삭제 시 모든 사용자의 화면에서 메시지가 삭제되며\n‘삭제된 메시지입니다.’로 표기됩니다.",
                        negativeTitle: String = "아니요",
                        positiveTitle: String = "네",
                        allowTapOutsideToCancel: Bool = true,
                        onConfirm: @escaping () -> Void,
                        onCancel: (() -> Void)? = nil) -> DeleteConfirmView {
        let v = DeleteConfirmView()
        v.allowTapOutsideToCancel = allowTapOutsideToCancel
        v.onConfirm = onConfirm
        v.onCancel = onCancel
        v.configure(message: message, negativeTitle: negativeTitle, positiveTitle: positiveTitle)
        v.show(in: parent)
        return v
    }

    // MARK: - UI
    private let container = UIView()
    private let messageLabel = UILabel()
    private let buttonStack = UIStackView()
    private let noButton = UIButton(type: .system)
    private let yesButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setupUI() }

    // MARK: - Private
    private func setupUI() {
        // 딤 배경
        backgroundColor = UIColor.black.withAlphaComponent(0.35)

        // 카드
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 16
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        // 메세지 라벨
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        // 버튼 스택
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        // 버튼들
        noButton.setTitle("아니요", for: .normal)
        yesButton.setTitle("네", for: .normal)
        yesButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        yesButton.backgroundColor = .systemRed
        yesButton.setTitleColor(.white, for: .normal)
        yesButton.layer.cornerRadius = 10
        noButton.backgroundColor = .tertiarySystemBackground
        noButton.setTitleColor(.label, for: .normal)
        noButton.layer.cornerRadius = 10
        [noButton, yesButton].forEach { $0.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12) }

        noButton.addTarget(self, action: #selector(tapNo), for: .touchUpInside)
        yesButton.addTarget(self, action: #selector(tapYes), for: .touchUpInside)

        // 인디케이터
        activity.hidesWhenStopped = true
        activity.translatesAutoresizingMaskIntoConstraints = false

        // 서브뷰 추가
        container.addSubview(messageLabel)
        container.addSubview(buttonStack)
        container.addSubview(activity)
        buttonStack.addArrangedSubview(noButton)
        buttonStack.addArrangedSubview(yesButton)

        // 레이아웃
        NSLayoutConstraint.activate([
            // 컨테이너 위치/크기
            container.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            container.centerXAnchor.constraint(equalTo: centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            trailingAnchor.constraint(greaterThanOrEqualTo: container.trailingAnchor, constant: 24),
            container.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.86),

            // 메시지
            messageLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            // 버튼 스택
            buttonStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            buttonStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            // 인디케이터 (메시지 중앙에 겹쳐 표기)
            activity.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor)
        ])

        // 딤 탭으로 닫기
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        addGestureRecognizer(tap)
    }

    @objc private func backgroundTapped() {
        guard allowTapOutsideToCancel else { return }
        onCancel?()
        dismiss()
    }

    @objc private func tapNo() {
        onCancel?()
        dismiss()
    }

    @objc private func tapYes() {
        onConfirm?()
        dismiss()
    }
}
