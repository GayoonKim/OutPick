//
//  ChatCoordinator.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import UIKit

struct ChatRoomClosurePresentationState {
    private var presentedRoomIDs = Set<String>()

    mutating func begin(roomID: String) -> Bool {
        guard !roomID.isEmpty else { return false }
        return presentedRoomIDs.insert(roomID).inserted
    }
}

@MainActor
protocol ChatRoomClosureListUpdating: AnyObject {
    func removeClosedRoom(roomID: String)
}

@MainActor
protocol ChatRoomRouting: AnyObject {
    func showSettings(from source: ChatViewController)
    func showUserProfile(from source: ChatViewController, userID: String, nickname: String, avatarPath: String?)
    func showMessageReport(from source: ChatViewController, messageID: String)
    func openLookbookSharedContent(from source: ChatViewController, sharedContent: LookbookSharedContent)
    func showImageViewer(
        from source: ChatViewController,
        messageID: String,
        canReport: Bool,
        pages: [SimpleImageViewerVC.ProgressivePage],
        startIndex: Int,
        cachedImageProvider: SimpleImageViewerVC.CachedImageProvider?,
        loadImageProvider: SimpleImageViewerVC.LoadImageProvider?,
        loadImageDataProvider: SimpleImageViewerVC.LoadImageDataProvider?
    )
    func showVideoPlayer(from source: ChatViewController, messageID: String, path: String)
    func dismissPresentedMedia(from source: ChatViewController, deletedMessageIDs: Set<String>)
    func handleRoomExit(from source: ChatViewController, roomID: String)
    func handleRoomClosure(from source: ChatViewController, event: RealtimeRoomClosureEvent)
}

@MainActor
final class ChatCoordinator {
    private struct PresentedMediaContext {
        weak var controller: UIViewController?
        let messageID: String
    }


    private struct NavigationSnapshot: Equatable {
        let revision: UInt64
        let viewControllerIDs: [ObjectIdentifier]
    }

    private enum RoutingError: Error {
        case navigationUnavailable
    }

    private let container: ChatContainer
    private var userProfileDetailCoordinator: UserProfileDetailCoordinator?
    private var navigationRevisions: [ObjectIdentifier: UInt64] = [:]
    private var roomClosurePresentationState = ChatRoomClosurePresentationState()
    private var presentedMediaContexts: [ObjectIdentifier: PresentedMediaContext] = [:]
    private let openRoomRequests = ChatOpenRoomRequestRegistry<
        ObjectIdentifier,
        NavigationSnapshot
    >()
    weak var appContentRouter: (any AppContentRouting)?

    init(container: ChatContainer) {
        self.container = container
    }

    func makeRoomListRoot() -> UIViewController {
        let listVC = RoomListsCollectionViewController(
            collectionViewLayout: UICollectionViewFlowLayout(),
            viewModel: container.makeRoomListsViewModel(),
            currentUserProvider: container.currentUserProvider,
            roomImageManager: container.makeRoomImageManager(),
            avatarImageManager: container.makeAvatarImageManager()
        )

        listVC.onSelectRoom = { [weak self, weak listVC] room in
            guard let self, let source = listVC else { return }
            self.presentChatRoom(room: room, from: source)
        }
        listVC.onCreateRoom = { [weak self, weak listVC] in
            guard let self, let source = listVC else { return }
            self.presentCreateRoom(from: source)
        }
        listVC.onSearchRoom = { [weak self, weak listVC] in
            guard let self, let source = listVC else { return }
            self.presentSearch(from: source)
        }

        let nav = ChatNavigationController(rootViewController: listVC)
        nav.isNavigationBarHidden = true
        return nav
    }

    func makeJoinedRoomsRoot() -> UIViewController {
        let joinedVC = JoinedRoomsViewController(
            viewModel: container.makeJoinedRoomsViewModel(),
            roomImageManager: container.makeRoomImageManager()
        )
        print(#function, joinedVC)
        joinedVC.onOpenRoom = { [weak self, weak joinedVC] room in
            guard let self, let source = joinedVC else { return }
            self.presentChatRoom(room: room, from: source)
        }
        joinedVC.onCreateRoom = { [weak self, weak joinedVC] in
            guard let self, let source = joinedVC else { return }
            self.presentCreateRoom(from: source)
        }
        joinedVC.onSearchRoom = { [weak self, weak joinedVC] in
            guard let self, let source = joinedVC else { return }
            self.presentSearch(from: source)
        }

        let nav = ChatNavigationController(rootViewController: joinedVC)
        nav.isNavigationBarHidden = true
        return nav
    }

    private func presentChatRoom(room: ChatRoom, from source: UIViewController) {
        guard let nav = navigationController(startingFrom: source) else {
            assertionFailure("ChatCoordinator requires a UINavigationController-owned Chat route.")
            return
        }
        presentChatRoom(room: room, in: nav)
    }

    func openRoom(roomID: String, from source: UIViewController) async throws {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        guard let nav = navigationController(startingFrom: source) else {
            throw RoutingError.navigationUnavailable
        }
        guard (nav.topViewController as? ChatViewController)?.room?.id != roomID else {
            return
        }

        let stackID = ObjectIdentifier(nav)
        let snapshot = navigationSnapshot(for: nav)
        let acquisition = openRoomRequests.acquire(
            stackID: stackID,
            roomID: roomID,
            snapshot: snapshot,
            makeTask: { request in
                self.makeOpenRoomTask(
                    roomID: roomID,
                    request: request,
                    stackID: stackID,
                    navigationController: nav
                )
            }
        )

        defer {
            openRoomRequests.finish(stackID: stackID, token: acquisition.request.token)
        }
        try await acquisition.task.value
    }

    private func presentCreateRoom(from source: UIViewController) {
        let createVC = ChatCompositionRoot.makeRoomCreateViewController(
            repositories: container.firebaseRepositories,
            roomImageManager: container.makeRoomImageManager(),
            mediaProcessor: container.makeMediaProcessor(),
            makeCreatedRoomViewController: { [weak self] room in
                self?.makeChatRoomViewController(room: room, isRoomSaving: true)
            }
        )
        push(createVC, from: source)
    }

    private func presentSearch(from source: UIViewController) {
        let searchVC = RoomSearchViewController(viewModel: container.makeRoomSearchViewModel())
        searchVC.onSelectRoom = { [weak self, weak searchVC] room in
            guard let self, let searchVC else { return }
            self.presentChatRoomFromSearch(room: room, searchVC: searchVC)
        }
        push(searchVC, from: source)
    }

    private func presentChatRoomFromSearch(room: ChatRoom, searchVC: RoomSearchViewController) {
        presentChatRoom(room: room, from: searchVC)
    }

    private func presentRoomEdit(from source: ChatRoomSettingViewController, room: ChatRoom) {
        let editVC = ChatCompositionRoot.makeRoomEditViewController(
            room: room,
            repositories: container.firebaseRepositories,
            roomImageManager: container.makeRoomImageManager(),
            mediaProcessor: container.makeMediaProcessor(),
            onRoomEdited: { [weak source] updatedRoom in
                guard let source else { return }
                await source.applyEditedRoom(updatedRoom)
            }
        )
        editVC.modalPresentationStyle = .fullScreen
        source.present(editVC, animated: true)
    }

    private func showBannedUsers(from source: ChatViewController, room: ChatRoom) {
        let viewController = ChatRoomBannedUsersViewController(
            viewModel: container.makeChatRoomBannedUsersViewModel(roomID: room.id)
        )
        viewController.modalPresentationStyle = .fullScreen
        viewController.onBack = { [weak viewController] in
            viewController?.dismiss(animated: true)
        }
        source.present(viewController, animated: true)
    }

    private func makeChatRoomViewController(room: ChatRoom, isRoomSaving: Bool) -> ChatViewController {
        let chatRoomVC = ChatViewController(
            mediaUploadUseCase: container.makeChatMediaUploadUseCase(),
            outgoingOutboxUseCase: container.makeChatOutgoingOutboxUseCase(),
            attachmentImageLoader: container.makeAttachmentImageLoader(),
            videoAssetLoader: container.makeChatVideoAssetLoader(),
            storageURLResolver: container.makeStorageURLResolver(),
            videoThumbnailGenerator: container.makeChatVideoThumbnailGenerator(),
            mediaProcessor: container.makeMediaProcessor(),
            avatarImageManager: container.makeAvatarImageManager(),
            profileSyncManager: container.makeProfileSyncManager(),
            viewModel: container.makeChatRoomViewModel(room: room)
        )

        chatRoomVC.isRoomSaving = isRoomSaving
        chatRoomVC.router = self
        chatRoomVC.onRouteRemoved = { [weak self] source in
            self?.finishChatRoute(source)
        }
        chatRoomVC.modalPresentationStyle = .fullScreen
        chatRoomVC.hidesBottomBarWhenPushed = true
        return chatRoomVC
    }

    private func push(_ viewController: UIViewController, from source: UIViewController) {
        guard let nav = navigationController(startingFrom: source) else {
            assertionFailure("ChatCoordinator requires a UINavigationController-owned Chat route.")
            return
        }
        nav.setNavigationBarHidden(true, animated: false)
        nav.interactivePopGestureRecognizer?.isEnabled = true
        viewController.hidesBottomBarWhenPushed = true
        nav.pushViewController(viewController, animated: true)
        incrementNavigationRevision(for: nav)
    }

    private func presentChatRoom(room: ChatRoom, in nav: UINavigationController) {
        let currentViewControllers = nav.viewControllers
        let currentChatRoomIDs = currentViewControllers.map { viewController in
            (viewController as? ChatViewController)?.room?.id
        }

        switch ChatNavigationStackPolicy.action(
            currentChatRoomIDs: currentChatRoomIDs,
            destinationRoomID: room.id
        ) {
        case .noOp:
            return

        case .place(let retainedIndices, let replacedChatIndices):
            let replacedChatRoutes = replacedChatIndices.compactMap { index in
                currentViewControllers[index] as? ChatViewController
            }
            replacedChatRoutes.forEach(finishChatRoute)

            let chatRoomVC = makeChatRoomViewController(room: room, isRoomSaving: false)
            let retainedViewControllers = retainedIndices.map { currentViewControllers[$0] }

            nav.setNavigationBarHidden(true, animated: false)
            nav.interactivePopGestureRecognizer?.isEnabled = true
            chatRoomVC.hidesBottomBarWhenPushed = true

            if replacedChatRoutes.isEmpty {
                nav.pushViewController(chatRoomVC, animated: true)
            } else {
                nav.setViewControllers(retainedViewControllers + [chatRoomVC], animated: true)
            }
            incrementNavigationRevision(for: nav)
        }
    }

    private func makeOpenRoomTask(
        roomID: String,
        request: ChatOpenRoomRequestState<ObjectIdentifier, NavigationSnapshot>.Request,
        stackID: ObjectIdentifier,
        navigationController: UINavigationController
    ) -> Task<Void, Error> {
        Task { @MainActor [weak self, weak navigationController] in
            guard let self else { return }

            let room: ChatRoom
            do {
                let rooms = try await container.roomRepository.fetchRoomsWithIDs(byIDs: [roomID])
                guard let fetchedRoom = rooms.first, fetchedRoom.id == roomID else {
                    throw FirebaseError.FailedToFetchRoom
                }
                room = fetchedRoom
            } catch {
                guard let navigationController else { return }
                let currentSnapshot = navigationSnapshot(for: navigationController)
                guard openRoomRequests.isCurrent(
                    stackID: stackID,
                    token: request.token,
                    snapshot: currentSnapshot
                ) else {
                    return
                }
                throw error
            }

            guard let navigationController else {
                guard openRoomRequests.isCurrent(
                    stackID: stackID,
                    token: request.token,
                    snapshot: request.snapshot
                ) else {
                    return
                }
                throw RoutingError.navigationUnavailable
            }

            let currentSnapshot = navigationSnapshot(for: navigationController)
            guard openRoomRequests.isCurrent(
                stackID: stackID,
                token: request.token,
                snapshot: currentSnapshot
            ) else {
                return
            }

            presentChatRoom(room: room, in: navigationController)
        }
    }

    private func navigationSnapshot(for nav: UINavigationController) -> NavigationSnapshot {
        let stackID = ObjectIdentifier(nav)
        return NavigationSnapshot(
            revision: navigationRevisions[stackID, default: 0],
            viewControllerIDs: nav.viewControllers.map(ObjectIdentifier.init)
        )
    }

    private func incrementNavigationRevision(for nav: UINavigationController) {
        let stackID = ObjectIdentifier(nav)
        navigationRevisions[stackID, default: 0] &+= 1
    }

    private func finishChatRoute(_ source: ChatViewController) {
        source.finishRouteLifecycleForCoordinator()
    }

    private func closeRoomRoute(
        from source: ChatViewController,
        closedRoomID: String? = nil
    ) {
        guard let nav = source.navigationController,
              let sourceIndex = nav.viewControllers.firstIndex(where: { $0 === source }) else {
            source.dismissSettingPanel { [weak source] in
                source?.dismiss(animated: true)
            }
            return
        }

        let isPrecededByRoomCreation = sourceIndex > 0 &&
            nav.viewControllers[sourceIndex - 1] is RoomCreateViewController
        let retainedIndices = ChatNavigationStackPolicy.retainedIndicesAfterClosingRoom(
            sourceIndex: sourceIndex,
            isPrecededByRoomCreation: isPrecededByRoomCreation
        )
        let retainedViewControllers = retainedIndices.map { nav.viewControllers[$0] }
        guard retainedViewControllers.isEmpty == false else { return }

        if let closedRoomID {
            retainedViewControllers
                .compactMap { $0 as? any ChatRoomClosureListUpdating }
                .forEach { $0.removeClosedRoom(roomID: closedRoomID) }
        }

        source.dismissSettingPanel { [weak self, weak source, weak nav] in
            guard let self, let source, let nav else { return }
            self.finishChatRoute(source)
            nav.setViewControllers(retainedViewControllers, animated: true)
            self.incrementNavigationRevision(for: nav)
        }
    }

    private func navigationController(startingFrom source: UIViewController) -> UINavigationController? {
        if let nav = source.navigationController {
            return nav
        }

        var current: UIViewController? = source
        while let presenting = current?.presentingViewController {
            if let nav = presenting as? UINavigationController {
                return nav
            }
            if let nav = presenting.navigationController {
                return nav
            }
            current = presenting
        }

        return nil
    }

    private func presentUserProfile(
        from source: UIViewController,
        userID: String,
        nickname: String,
        avatarPath: String?
    ) {
        let coordinator = UserProfileDetailCoordinator(
            presentingViewController: source,
            avatarImageManager: container.makeAvatarImageManager(),
            currentUserProvider: container.currentUserProvider,
            publicProfileRepository: container.publicProfileRepository,
            photoLibrarySaver: container.makePhotoLibrarySaver(),
            blockUserUseCase: container.makeBlockUserUseCase(),
            userBlockVisibilityStore: container.userBlockVisibilityStore,
            onFinish: { [weak self] in
                self?.userProfileDetailCoordinator = nil
            }
        )
        userProfileDetailCoordinator = coordinator
        coordinator.start(userID: userID, nickname: nickname, avatarPath: avatarPath)
    }

    private func presentMessageReport(
        from presenter: UIViewController,
        source: ChatViewController,
        roomID: String,
        messageID: String,
        isMediaContext: Bool
    ) {
        let reportViewController = ChatMessageReportViewController(
            viewModel: container.makeMessageReportViewModel(
                roomID: roomID,
                messageID: messageID,
                isMediaContext: isMediaContext
            )
        )
        let navigationController = UINavigationController(rootViewController: reportViewController)
        navigationController.modalPresentationStyle = .formSheet
        reportViewController.onCancel = { [weak navigationController] in
            navigationController?.dismiss(animated: true)
        }
        reportViewController.onCompletion = { [weak source, weak navigationController] completion in
            navigationController?.dismiss(animated: true) {
                guard let source else { return }
                switch completion {
                case .accepted:
                    source.showRoutingFailure("신고가 접수되었어요")
                case .processing:
                    source.showRoutingFailure("신고를 처리 중이에요")
                case .alreadyReported:
                    source.showRoutingFailure("이미 신고한 메시지예요")
                case .messageAlreadyDeleted:
                    source.showRoutingFailure("이미 삭제된 메시지예요")
                    Task { @MainActor [weak source] in
                        await source?.reconcileDeletionAfterReport()
                    }
                }
            }
        }
        presenter.present(navigationController, animated: true)
    }
}

extension ChatCoordinator: ChatRoomRouting {
    func showSettings(from source: ChatViewController) {
        guard let room = source.room else { return }

        weak var settingVC: ChatRoomSettingViewController?
        let panelVC = ChatCompositionRoot.makeChatRoomSettingPanel(
            room: room,
            repositories: container.firebaseRepositories,
            publicProfileRepository: container.publicProfileRepository,
            participantsRepository: container.makeLocalParticipantsRepository(),
            localMediaRepository: container.makeLocalMediaRepository(),
            attachmentImageLoader: container.makeAttachmentImageLoader(),
            videoResolver: container.makeChatVideoPlaybackResolver(),
            photoLibrarySaver: container.makePhotoLibrarySaver(),
            roomImageManager: container.makeRoomImageManager(),
            avatarImageManager: container.makeAvatarImageManager(),
            currentUserProvider: container.currentUserProvider,
            networkStatusProvider: container.makeNetworkStatusProvider(),
            exitUseCase: container.makeChatRoomExitUseCase(),
            memberModerationUseCase: container.makeChatRoomMemberModerationUseCase(),
            userBlockVisibilityStore: container.userBlockVisibilityStore,
            onEvent: { [weak self, weak source] event in
                switch event {
                case .roomUpdated(let updatedRoom):
                    source?.applyUpdatedRoom(updatedRoom)

                case .roomExited(let roomID):
                    guard let self, let source else { return }
                    self.handleRoomExit(from: source, roomID: roomID)

                case .requestEditRoom(let room):
                    guard let self, let settingVC else { return }
                    self.presentRoomEdit(from: settingVC, room: room)

                case .requestShowUserProfile(let user):
                    guard let self, let settingVC else { return }
                    self.presentUserProfile(
                        from: settingVC,
                        userID: user.userID,
                        nickname: user.nickname,
                        avatarPath: user.profileImagePath
                    )

                case .requestShowBannedUsers:
                    guard let self, let source else { return }
                    self.showBannedUsers(from: source, room: room)
                }
            }
        )
        settingVC = panelVC
        source.presentSettingPanel(panelVC)
    }

    func showUserProfile(from source: ChatViewController, userID: String, nickname: String, avatarPath: String?) {
        presentUserProfile(from: source, userID: userID, nickname: nickname, avatarPath: avatarPath)
    }

    func showMessageReport(from source: ChatViewController, messageID: String) {
        guard let roomID = source.room?.id, !roomID.isEmpty, !messageID.isEmpty else { return }
        presentMessageReport(
            from: source,
            source: source,
            roomID: roomID,
            messageID: messageID,
            isMediaContext: false
        )
    }

    func openLookbookSharedContent(from source: ChatViewController, sharedContent: LookbookSharedContent) {
        Task { @MainActor [weak self, weak source] in
            guard let self, let source, let appContentRouter else { return }
            do {
                try await appContentRouter.openLookbookSharedContent(sharedContent)
            } catch {
                source.showRoutingFailure("룩북으로 이동할 수 없습니다.")
                print("❌ 룩북 공유 카드 이동 실패:", error)
            }
        }
    }

    func showImageViewer(
        from source: ChatViewController,
        messageID: String,
        canReport: Bool,
        pages: [SimpleImageViewerVC.ProgressivePage],
        startIndex: Int,
        cachedImageProvider: SimpleImageViewerVC.CachedImageProvider?,
        loadImageProvider: SimpleImageViewerVC.LoadImageProvider?,
        loadImageDataProvider: SimpleImageViewerVC.LoadImageDataProvider?
    ) {
        guard !pages.isEmpty else { return }
        let viewer = SimpleImageViewerVC(
            pages: pages,
            startIndex: startIndex,
            cachedImageProvider: cachedImageProvider,
            loadImageProvider: loadImageProvider,
            loadImageDataProvider: loadImageDataProvider,
            photoLibrarySaver: container.makePhotoLibrarySaver(),
            onReport: canReport ? { [weak self, weak source] viewer in
                    guard let self, let source, let roomID = source.room?.id else { return }
                    self.presentMessageReport(
                        from: viewer,
                        source: source,
                        roomID: roomID,
                        messageID: messageID,
                        isMediaContext: true
                    )
                } : nil
        )
        viewer.modalPresentationStyle = .fullScreen
        viewer.modalTransitionStyle = .crossDissolve
        trackPresentedMedia(viewer, messageID: messageID)
        source.present(viewer, animated: true)
    }

    func showVideoPlayer(from source: ChatViewController, messageID: String, path: String) {
        Task { @MainActor [weak self, weak source] in
            guard let self, let source else { return }

            do {
                let videoResolver = container.makeChatVideoPlaybackResolver()
                let playbackAsset = try await videoResolver.playbackAsset(forPath: path)
                let playerViewController = ChatVideoPlayerViewController(
                    playbackAsset: playbackAsset,
                    videoResolver: videoResolver,
                    photoLibrarySaver: container.makePhotoLibrarySaver()
                )
                playerViewController.modalPresentationStyle = .fullScreen
                self.trackPresentedMedia(playerViewController, messageID: messageID)
                source.present(playerViewController, animated: true)
            } catch {
                AlertManager.showAlertNoHandler(
                    title: "재생 실패",
                    message: "동영상을 불러오지 못했습니다.\n\(error.localizedDescription)",
                    viewController: source
                )
            }
        }
    }

    func dismissPresentedMedia(
        from source: ChatViewController,
        deletedMessageIDs: Set<String>
    ) {
        guard let presented = source.presentedViewController else { return }
        let identifier = ObjectIdentifier(presented)
        guard let context = presentedMediaContexts[identifier],
              context.controller === presented,
              deletedMessageIDs.contains(context.messageID) else { return }
        presentedMediaContexts.removeValue(forKey: identifier)
        presented.dismiss(animated: true)
    }

    private func trackPresentedMedia(_ controller: UIViewController, messageID: String) {
        presentedMediaContexts = presentedMediaContexts.filter { $0.value.controller != nil }
        presentedMediaContexts[ObjectIdentifier(controller)] = PresentedMediaContext(
            controller: controller,
            messageID: messageID
        )
    }

    func handleRoomExit(from source: ChatViewController, roomID: String) {
        container.roomRepository.removeLocalRoom(roomID: roomID)
        guard source.isCurrentRoom(roomID: roomID) else {
            source.dismissSettingPanel()
            return
        }
        closeRoomRoute(from: source)
    }

    func handleRoomClosure(from source: ChatViewController, event: RealtimeRoomClosureEvent) {
        if event.closureType == ChatRoomClosureType.closedByOwner.rawValue,
           source.room?.creatorUID == container.currentUserProvider.canonicalUserID {
            container.roomRepository.removeLocalRoom(roomID: event.roomID)
            guard source.isCurrentRoom(roomID: event.roomID) else {
                source.dismissSettingPanel()
                return
            }
            closeRoomRoute(from: source, closedRoomID: event.roomID)
            return
        }
        guard source.isCurrentRoom(roomID: event.roomID) else {
            source.dismissSettingPanel()
            return
        }
        guard roomClosurePresentationState.begin(roomID: event.roomID) else {
            return
        }
        let roomName = source.room?.roomName ?? "채팅방"
        let message: String?
        switch event.closureType {
        case ChatRoomClosureType.closedByModeration.rawValue:
            message = "운영 정책에 따라 이용이 종료됐어요."
        case ChatRoomClosureType.closedByOwner.rawValue:
            message = "방장이 채팅방을 종료했어요."
        default:
            message = nil
        }
        let alert = UIAlertController(
            title: "“\(roomName)” 채팅방이 종료됐어요",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default) { [weak self, weak source] _ in
            guard let self, let source else { return }
            self.container.roomRepository.removeLocalRoom(roomID: event.roomID)
            self.closeRoomRoute(from: source, closedRoomID: event.roomID)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.container.roomClosureAcknowledgementUseCase
                        .acknowledge(roomID: event.roomID)
                } catch {
                    #if DEBUG
                    print("[ChatCoordinator] 방 종료 확인 처리 실패 roomID=\(event.roomID): \(error)")
                    #endif
                }
            }
        })
        if let presentedViewController = source.presentedViewController {
            presentedViewController.dismiss(animated: true) { [weak source] in
                source?.present(alert, animated: true)
            }
        } else {
            source.present(alert, animated: true)
        }
    }
}
