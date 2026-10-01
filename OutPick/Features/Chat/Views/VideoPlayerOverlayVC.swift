//
//  VideoPlayerOverlayVC.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import AVKit
import UIKit

final class VideoPlayerOverlayVC: UIViewController {
    private let playback: ChatVideoPlaybackSession
    private let videoResolver: ChatVideoPlaybackResolving
    private let photoLibrarySaver: PhotoLibrarySaving
    private let playerVC = AVPlayerViewController()
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private var saveTask: Task<Void, Never>?
    private var closed = false
    private let statusView = ChatVideoPlaybackStatusView()

    init(
        playbackAsset: ChatVideoPlaybackAsset,
        videoResolver: ChatVideoPlaybackResolving,
        photoLibrarySaver: PhotoLibrarySaving
    ) {
        self.playback = ChatVideoPlaybackSession(asset: playbackAsset, resolver: videoResolver)
        self.videoResolver = videoResolver
        self.photoLibrarySaver = photoLibrarySaver
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        playerVC.didMove(toParent: self)
        playerVC.player = playback.player
        playerVC.showsPlaybackControls = true

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let xcfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.image = UIImage(systemName: "xmark", withConfiguration: xcfg)
        closeConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        closeButton.configuration = closeConfiguration
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        let scfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        var saveConfiguration = UIButton.Configuration.plain()
        saveConfiguration.image = UIImage(systemName: "square.and.arrow.down", withConfiguration: scfg)
        saveConfiguration.title = "저장"
        saveConfiguration.imagePadding = 8
        saveConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        saveButton.configuration = saveConfiguration
        saveButton.tintColor = .white
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        saveButton.layer.cornerRadius = 18
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        view.addSubview(saveButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),

            saveButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            saveButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -20)
        ])
        statusView.attach(to: view)
        statusView.onRetry = { [weak self] in self?.playback.retry() }
        statusView.onClose = { [weak self] in self?.closeTapped() }
        playback.onState = { [weak self] state in self?.renderPlayback(state) }
        renderPlayback(playback.state)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playback.start()
    }

    @objc private func closeTapped() {
        closeMedia()
        playerVC.player?.pause()
        dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { closeMedia() }
    }

    private func closeMedia() {
        guard !closed else { return }
        closed = true
        saveTask?.cancel()
        playback.close()
        playerVC.player = nil
    }

    deinit { saveTask?.cancel() }

    private func renderPlayback(_ state: ChatVideoPlaybackSession.State) {
        statusView.render(state)
        saveButton.isEnabled = playback.canSave && saveTask == nil
        playerVC.showsPlaybackControls = state == .ready
        if state == .expired || state == .closed {
            saveTask?.cancel()
            playerVC.player = nil
        }
    }

    @objc private func saveTapped() {
        guard saveTask == nil, !closed, playback.canSave, let playbackAsset = playback.asset else { return }
        saveButton.isEnabled = false
        saveTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.saveTask = nil; self.saveButton.isEnabled = self.playback.canSave }
            do {
                let lease = try await self.videoResolver.acquireFileForSaving(playbackAsset)
                do {
                    try Task.checkCancellation()
                    guard !self.closed, self.playback.canSave, lease.isValid else { throw CancellationError() }
                    try await self.photoLibrarySaver.saveOriginal(lease, isVideo: true)
                    await lease.release()
                } catch { await lease.release(); throw error }
                guard !self.closed, !Task.isCancelled else { return }
                self.showToast("저장 완료")
            } catch {
                guard !self.closed, !Task.isCancelled, !(error is CancellationError) else { return }
                self.showToast("저장 실패")
            }
        }
    }

    private func showToast(_ message: String) {
        MediaSaveToast.show(message, in: view)
    }
}
