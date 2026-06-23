//
//  ChatVideoPlayerViewController.swift
//  OutPick
//
//  Created by Codex on 6/19/26.
//

import UIKit
import AVKit

final class ChatVideoPlayerViewController: UIViewController {
    private let playbackAsset: ChatVideoPlaybackAsset
    private let videoResolver: ChatVideoPlaybackResolving
    private let photoLibrarySaver: PhotoLibrarySaving
    private let playerViewController = AVPlayerViewController()

    init(
        playbackAsset: ChatVideoPlaybackAsset,
        videoResolver: ChatVideoPlaybackResolving,
        photoLibrarySaver: PhotoLibrarySaving
    ) {
        self.playbackAsset = playbackAsset
        self.videoResolver = videoResolver
        self.photoLibrarySaver = photoLibrarySaver
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePlayer()
        configureSaveButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playerViewController.player?.play()
    }

    private func configurePlayer() {
        let player = AVPlayer(url: playbackAsset.url)
        playerViewController.player = player
        addChild(playerViewController)
        view.addSubview(playerViewController.view)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        playerViewController.didMove(toParent: self)
    }

    private func configureSaveButton() {
        guard let overlay = playerViewController.contentOverlayView else { return }

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button.layer.cornerRadius = 22
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task { await self.handleSaveTapped() }
        }, for: .touchUpInside)

        overlay.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -24),
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    @MainActor
    private func handleSaveTapped() async {
        let hud = CircularProgressHUD.show(in: view, title: nil)
        hud.setProgress(0.15)

        do {
            let fileURL = try await videoResolver.localFileURLForSaving(
                localURL: playbackAsset.url,
                storagePath: playbackAsset.storagePath,
                onProgress: { fraction in
                    Task { @MainActor in
                        hud.setProgress(0.15 + 0.75 * fraction)
                    }
                }
            )
            try await photoLibrarySaver.saveVideo(fileURL: fileURL)
            hud.setProgress(1.0)
            hud.dismiss()
            AlertManager.showAlertNoHandler(
                title: "저장 완료",
                message: "사진 앱에 동영상을 저장했습니다.",
                viewController: self
            )
        } catch {
            hud.dismiss()
            AlertManager.showAlertNoHandler(
                title: "저장 실패",
                message: error.localizedDescription,
                viewController: self
            )
        }
    }
}
