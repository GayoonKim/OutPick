//
//  BootLoadingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

final class BootLoadingViewController: UIViewController {

    private let message: String?

    /// - Parameter message: nil 또는 빈 문자열이면 문구 없이 인디케이터만 표시합니다.
    init(message: String? = nil) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = (trimmed?.isEmpty == true) ? nil : trimmed
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = nil
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let indicator: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .medium)
        v.hidesWhenStopped = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addSubview(indicator)
        view.addSubview(loadingLabel)

        if let message {
            loadingLabel.text = message
            loadingLabel.isHidden = false
        } else {
            // 문구가 없으면 라벨을 숨겨 인디케이터만 깔끔하게 보여줌
            loadingLabel.text = nil
            loadingLabel.isHidden = true
        }

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: indicator.bottomAnchor, constant: 10)
        ])

        indicator.startAnimating()
    }
}
