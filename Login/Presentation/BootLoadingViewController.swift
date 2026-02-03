//
//  BootLoadingViewController.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

final class BootLoadingViewController: UIViewController {

    private let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "로그인 중..."
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .darkGray
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
        view.backgroundColor = .white

        view.addSubview(indicator)
        view.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: indicator.bottomAnchor, constant: 10)
        ])

        indicator.startAnimating()
    }
}
