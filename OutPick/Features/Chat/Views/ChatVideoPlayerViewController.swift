//
//  ChatVideoPlayerViewController.swift
//  OutPick
//
//  Created by Codex on 6/19/26.
//

import UIKit
import AVKit

final class ChatVideoPlayerViewController: UIViewController {
    private let playback: ChatVideoPlaybackSession
    private let videoResolver: ChatVideoPlaybackResolving
    private let photoLibrarySaver: PhotoLibrarySaving
    private let playerViewController = AVPlayerViewController()
    private var saveTask: Task<Void, Never>?
    private var closed = false
    private let saveButton = UIButton(type: .system)
    private let statusView = ChatVideoPlaybackStatusView()

    init(
        playbackAsset: ChatVideoPlaybackAsset?,
        videoResolver: ChatVideoPlaybackResolving,
        photoLibrarySaver: PhotoLibrarySaving
    ) {
        self.playback = ChatVideoPlaybackSession(asset: playbackAsset, resolver: videoResolver)
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
        statusView.attach(to: view)
        statusView.onRetry = { [weak self] in self?.playback.retry() }
        statusView.onClose = { [weak self] in self?.dismiss(animated: true) }
        playback.onState = { [weak self] state in self?.renderPlayback(state) }
        renderPlayback(playback.state)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playback.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else { return }
        closed = true
        saveTask?.cancel()
        playback.close()
        playerViewController.player = nil
    }

    deinit { saveTask?.cancel() }

    private func configurePlayer() {
        playerViewController.player = playback.player
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

        let button = saveButton
        button.accessibilityIdentifier = "chatVideoSaveButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "square.and.arrow.down"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button.layer.cornerRadius = 22
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            guard self.saveTask == nil, !self.closed, self.playback.canSave else { return }
            self.saveTask = Task { await self.handleSaveTapped() }
        }, for: .touchUpInside)

        overlay.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -24),
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func renderPlayback(_ state: ChatVideoPlaybackSession.State) {
        statusView.render(state)
        saveButton.isEnabled = playback.canSave && saveTask == nil
        playerViewController.showsPlaybackControls = state == .ready
        if state == .expired || state == .closed {
            saveTask?.cancel()
            playerViewController.player = nil
        }
    }

    @MainActor
    private func handleSaveTapped() async {
        defer { saveTask = nil; saveButton.isEnabled = playback.canSave }
        guard let playbackAsset = playback.asset, playback.canSave else { return }
        let hud = CircularProgressHUD.show(in: view, title: nil)
        hud.setProgress(0.15)

        do {
            let lease = try await videoResolver.acquireFileForSaving(playbackAsset)
            do {
                try Task.checkCancellation()
                guard !closed, playback.canSave, lease.isValid else { throw CancellationError() }
                try await photoLibrarySaver.saveOriginal(lease, isVideo: true)
                await lease.release()
            } catch { await lease.release(); throw error }
            hud.setProgress(1.0)
            hud.dismiss()
            guard !closed, !Task.isCancelled else { return }
            MediaSaveToast.show("저장 완료", in: view)
        } catch {
            hud.dismiss()
            guard !closed, !Task.isCancelled, !(error is CancellationError) else { return }
            MediaSaveToast.show("저장 실패", in: view)
        }
    }
}
