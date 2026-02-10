//
//  DeleteConfirmView.swift
//  OutPick
//
//  Created by 김가윤 on 9/24/25.
//

import UIKit

/// 공통 확인(Confirm) 오버레이 (딤 + 카드 + 애니메이션) 를 자체적으로 관리하는 뷰
final class ConfirmView: UIView {
    // MARK: - Public API
    enum ConfirmStyle { case destructive, prominent }
    private var identifierPrefix: String = "ConfirmView"
    private var style: ConfirmStyle = .destructive
    
    var onConfirm: (() -> Void)?
    
    /// 딤을 탭하면 닫을지 여부 (기본 true)
    var allowTapOutsideToCancel: Bool = true
    
    /// 메시지/버튼 문구 변경
    func configure(message: String,
                   negativeTitle: String = "아니요",
                   positiveTitle: String = "네") {
        messageLabel.text = message
        if #available(iOS 15.0, *) {
            noButton.configuration?.title = negativeTitle
            yesButton.configuration?.title = positiveTitle
        } else {
            noButton.setTitle(negativeTitle, for: .normal)
            yesButton.setTitle(positiveTitle, for: .normal)
        }
    }
    
    /// 제목 + 본문 구성 지원 (기존과 호환)
    func configure(title: String?,
                   message: String,
                   negativeTitle: String = "아니요",
                   positiveTitle: String = "네") {
        titleLabel.text = title
        messageLabel.text = message
        if #available(iOS 15.0, *) {
            noButton.configuration?.title = negativeTitle
            yesButton.configuration?.title = positiveTitle
        } else {
            noButton.setTitle(negativeTitle, for: .normal)
            yesButton.setTitle(positiveTitle, for: .normal)
        }
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
    
    /// 편의 팩토리(신규): 스타일/식별자 지정 가능
    @discardableResult
    static func present(in parent: UIView,
                        message: String,
                        negativeTitle: String = "아니요",
                        positiveTitle: String = "네",
                        allowTapOutsideToCancel: Bool = true,
                        style: ConfirmStyle = .destructive,
                        identifier: String? = nil,
                        onConfirm: @escaping () -> Void) -> ConfirmView {
        let v = ConfirmView()
        v.allowTapOutsideToCancel = allowTapOutsideToCancel
        v.onConfirm = onConfirm
        v.style = style
        v.identifierPrefix = identifier ?? "ConfirmView"
        v.configure(message: message, negativeTitle: negativeTitle, positiveTitle: positiveTitle)
        v.applyStyle()
        // 동적 접근성 식별자 적용
        v.container.accessibilityIdentifier = v.identifierPrefix
        v.noButton.accessibilityIdentifier = "\(v.identifierPrefix).NoButton"
        v.yesButton.accessibilityIdentifier = "\(v.identifierPrefix).YesButton"
        v.show(in: parent)
        return v
    }
    
    /// 삭제 전용 프리셋
    @discardableResult
    static func presentDelete(in parent: UIView,
                              message: String = "삭제 시 모든 사용자의 화면에서 메시지가 삭제되며\n‘삭제된 메시지입니다.’로 표기됩니다.",
                              onConfirm: @escaping () -> Void) -> ConfirmView {
        return present(in: parent,
                       message: message,
                       negativeTitle: "아니요",
                       positiveTitle: "네",
                       allowTapOutsideToCancel: true,
                       style: .destructive,
                       identifier: "DeleteConfirmView",
                       onConfirm: onConfirm)
    }
    
    /// 방 나가기 전용 프리셋
    @discardableResult
    static func presentLeave(in parent: UIView,
                             isOwner: Bool,
                             title: String = "채팅을 종료하시겠어요?",
                             ownerMessage: String = "방장으로 종료하면 모든 채팅 내역 복구 불가능합니다.",
                             memberMessage: String = "채팅방을 나가면 대화 목록에서 사리지며, 모든 채팅 내역 복구 불가능합니다.",
                             onConfirm: @escaping () -> Void) -> ConfirmView {
        
        let finalMessage: String = isOwner ? ownerMessage : memberMessage
        
        print(isOwner, finalMessage)
        
        let v = present(in: parent,
                        message: finalMessage,
                        negativeTitle: "취소",
                        positiveTitle: "나가기",
                        allowTapOutsideToCancel: true,
                        style: .destructive,
                        identifier: "LeaveConfirmView",
                        onConfirm: onConfirm)
        
        // 제목 포함 구성으로 업데이트
        v.configure(title: title,
                    message: finalMessage,
                    negativeTitle: "취소",
                    positiveTitle: "나가기")
        return v
    }
    
    /// 공지 등록 전용 프리셋 (신규: 제목/설명 분리)
    @discardableResult
    static func presentAnnouncement(in parent: UIView,
                                    title: String = "이 내용을 공지로 등록할까요?",
                                    description: String = "공지 등록을 누르면 공지로 등록되며 이전 공지는 사라집니다.",
                                    onConfirm: @escaping () -> Void) -> ConfirmView {
        // 우선 기본 프리셋으로 뷰를 생성한 뒤, 제목/설명을 설정한다
        let v = present(in: parent,
                        message: description,
                        negativeTitle: "아니요",
                        positiveTitle: "공지 등록",
                        allowTapOutsideToCancel: true,
                        style: .prominent,
                        identifier: "AnnouncementConfirmView",
                        onConfirm: onConfirm)
        // 제목까지 구성
        v.configure(title: title, message: description, negativeTitle: "아니요", positiveTitle: "공지 등록")
        return v
    }

    // 공지 해제 전용 프리셋
    static func presentDismissAnnouncement(in parent: UIView,
                                           message: String = "공지를 삭제하시겠어요?",
                                           onConfirm: @escaping () -> Void) -> ConfirmView {
        
        return present(in: parent,
                       message: message,
                       negativeTitle: "아니요",
                       positiveTitle: "네",
                       allowTapOutsideToCancel: true,
                       style: .prominent,
                       identifier: "DissmissAnnouncement",
                       onConfirm: onConfirm)
    }
    
    // MARK: - UI
    private let container = UIView()
    private let titleLabel = UILabel()
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
        container.accessibilityIdentifier = identifierPrefix
        addSubview(container)
        
        // 제목 라벨
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.accessibilityIdentifier = "\(identifierPrefix).Title"
        
        // 메세지 라벨
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.accessibilityIdentifier = "\(identifierPrefix).Message"
        
        // 버튼 스택
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        // 확인 버튼 (빨강, 흰 글씨)
        var yesCfg = UIButton.Configuration.filled()
        yesCfg.title = "네"
        yesCfg.baseBackgroundColor = .systemBlue
        yesCfg.baseForegroundColor = .label
        yesCfg.cornerStyle = .medium
        yesCfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        yesCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }
        yesButton.configuration = yesCfg
        
        // 취소 버튼 (연한 배경, 레이블 색상)
        var noCfg = UIButton.Configuration.gray()
        noCfg.title = "아니요"
        noCfg.baseBackgroundColor = .tertiarySystemBackground
        noCfg.baseForegroundColor = .label
        noCfg.cornerStyle = .medium
        noCfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        noButton.configuration = noCfg
        noButton.accessibilityIdentifier = "\(identifierPrefix).NoButton"
        yesButton.accessibilityIdentifier = "\(identifierPrefix).YesButton"
        
        noButton.addTarget(self, action: #selector(tapNo), for: .touchUpInside)
        yesButton.addTarget(self, action: #selector(tapYes), for: .touchUpInside)
        
        // 현재 스타일 적용
        applyStyle()
        
        // 인디케이터
        activity.hidesWhenStopped = true
        activity.translatesAutoresizingMaskIntoConstraints = false
        
        // 서브뷰 추가
        container.addSubview(titleLabel)
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
            
            // 제목
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            
            // 메시지 (제목 아래)
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
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
    
    private func applyStyle() {
        switch style {
        case .destructive:
            yesButton.configuration?.baseBackgroundColor = .systemRed
            yesButton.configuration?.baseForegroundColor = .black
        case .prominent:
            yesButton.configuration?.baseBackgroundColor = .systemBlue
            yesButton.configuration?.baseForegroundColor = .black
        }
    }
    
    @objc private func backgroundTapped() {
        guard allowTapOutsideToCancel else { return }
        dismiss()
    }
    
    @objc private func tapNo() {
        dismiss()
    }
    
    @objc private func tapYes() {
        onConfirm?()
        dismiss()
    }
}
