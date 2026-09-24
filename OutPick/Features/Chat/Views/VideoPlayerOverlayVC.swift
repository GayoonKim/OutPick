//
//  VideoPlayerOverlayVC.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import AVKit
import UIKit

final class VideoPlayerOverlayVC: UIViewController {
    private let playbackAsset: ChatVideoPlaybackAsset
    private let videoResolver: ChatVideoPlaybackResolving
    private let photoLibrarySaver: PhotoLibrarySaving
    private let playerVC = AVPlayerViewController()
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private var saveTask: Task<Void, Never>?
    private var closed = false

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
        playerVC.player = AVPlayer(url: playbackAsset.url)
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playerVC.player?.play()
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
        playerVC.player?.pause()
        playerVC.player = nil
        if let lease = playbackAsset.fileLease { Task { await lease.release() } }
    }

    deinit { saveTask?.cancel() }

    @objc private func saveTapped() {
        guard saveTask == nil, !closed else { return }
        saveButton.isEnabled = false
        saveTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.saveTask = nil; self.saveButton.isEnabled = true }
            do {
                let lease = try await self.videoResolver.acquireFileForSaving(self.playbackAsset)
                do {
                    try Task.checkCancellation()
                    guard !self.closed, lease.isValid else { throw CancellationError() }
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
