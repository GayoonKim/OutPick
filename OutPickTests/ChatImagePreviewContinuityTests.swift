import XCTest
import UIKit
@testable import OutPick

@MainActor
final class ChatImagePreviewContinuityTests: XCTestCase {
    func testIdentitySurvivesServerPathAndHashChangeButSeparatesAttachments() {
        let local = item(path: "file:///tmp/local.jpg")
        let remote = item(path: "chat/remote.jpg", hash: "server-hash")
        XCTAssertEqual(local.id, remote.id)
        XCTAssertNotEqual(local.id, item(path: "chat/remote.jpg", index: 1).id)
        XCTAssertNotEqual(local.id, item(path: "chat/remote.jpg", messageID: "other").id)
    }

    func testDisplayedImageSurvivesConfirmationWithoutAnotherLoad() throws {
        let cell = ChatImagePreviewCell(frame: .zero)
        let photo = UIImage()
        cell.configure(with: item(path: "file:///tmp/local.jpg"), image: photo, thumbnailLoader: nil)
        cell.configure(with: item(path: "chat/remote.jpg"), image: nil, thumbnailLoader: { _ in
            XCTFail("표시된 동일 첨부를 다시 로딩하면 안 됩니다.")
            return nil
        })
        XCTAssertTrue(try imageView(in: cell).image === photo)
    }

    func testInFlightLocalSuccessIsKeptAcrossConfirmation() async throws {
        let cell = ChatImagePreviewCell(frame: .zero)
        let started = expectation(description: "로컬 로딩 시작")
        let finished = expectation(description: "최신 callback으로 완료")
        var pending: CheckedContinuation<UIImage?, Never>?
        let loader: ChatImagePreviewCell.ThumbnailLoader = { _ in
            await withCheckedContinuation {
                pending = $0
                started.fulfill()
            }
        }
        cell.configure(with: item(path: "file:///tmp/local.jpg"), image: nil, thumbnailLoader: loader)
        await fulfillment(of: [started], timeout: 1)
        cell.configure(with: item(path: "chat/remote.jpg"), image: nil, thumbnailLoader: { _ in
            XCTFail("진행 중인 로컬 로딩을 유지해야 합니다.")
            return nil
        }, onImageLoaded: { _ in finished.fulfill() })
        let photo = UIImage()
        pending?.resume(returning: photo)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(try imageView(in: cell).image === photo)
    }

    func testLocalFailureAfterConfirmationFallsBackToLatestPath() async throws {
        let cell = ChatImagePreviewCell(frame: .zero)
        let started = expectation(description: "로컬 로딩 시작")
        let finished = expectation(description: "원격 복구 완료")
        var pending: CheckedContinuation<UIImage?, Never>?
        cell.configure(with: item(path: "file:///tmp/local.jpg"), image: nil, thumbnailLoader: { _ in
            await withCheckedContinuation {
                pending = $0
                started.fulfill()
            }
        })
        await fulfillment(of: [started], timeout: 1)
        let photo = UIImage()
        let remote = item(path: "chat/remote.jpg")
        cell.configure(with: remote, image: nil, thumbnailLoader: { requested in
            XCTAssertEqual(requested.previewPaths, remote.previewPaths)
            return photo
        }, onImageLoaded: { _ in finished.fulfill() })
        pending?.resume(returning: nil)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(try imageView(in: cell).image === photo)
    }

    func testReuseClearsPhotoAndRejectsLateResponseEvenForSameID() async throws {
        let cell = ChatImagePreviewCell(frame: .zero)
        let started = expectation(description: "이전 요청 시작")
        let stale = expectation(description: "취소된 callback 금지")
        stale.isInverted = true
        var pending: CheckedContinuation<UIImage?, Never>?
        let attachment = item(path: "file:///tmp/local.jpg")
        cell.configure(with: attachment, image: nil, thumbnailLoader: { _ in
            await withCheckedContinuation {
                pending = $0
                started.fulfill()
            }
        }, onImageLoaded: { _ in stale.fulfill() })
        await fulfillment(of: [started], timeout: 1)
        cell.prepareForReuse()
        XCTAssertNil(try imageView(in: cell).image)
        let photo = UIImage()
        cell.configure(with: attachment, image: photo, thumbnailLoader: nil)
        pending?.resume(returning: UIImage())
        await fulfillment(of: [stale], timeout: 0.1)
        XCTAssertTrue(try imageView(in: cell).image === photo)
        cell.configure(with: item(path: "chat/other.jpg", messageID: "other"), image: nil, thumbnailLoader: nil)
        XCTAssertNil(try imageView(in: cell).image)
    }

    func testCollectionKeepsLayoutAndImageWhileUpdatingRemotePayload() async throws {
        let preview = ChatImagePreviewCollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(preview)
        window.isHidden = false
        defer { window.isHidden = true }
        let loaded = expectation(description: "첫 이미지 로딩")
        let photo = UIImage()
        preview.updateCollectionView([item(path: "file:///tmp/local.jpg")], 240, [1], thumbnailLoader: { _ in
            loaded.fulfill()
            return photo
        })
        preview.layoutIfNeeded()
        let collection = try XCTUnwrap(preview.subviews.first as? UICollectionView)
        collection.layoutIfNeeded()
        await fulfillment(of: [loaded], timeout: 1)
        let layout = collection.collectionViewLayout
        preview.updateCollectionView([item(path: "chat/remote.jpg")], 240, [1], thumbnailLoader: { _ in
            XCTFail("확정 시 이미지 재로딩 금지")
            return nil
        })
        XCTAssertTrue(collection.collectionViewLayout === layout)
        XCTAssertTrue(preview.currentImages().first.flatMap { $0 } === photo)
        preview.updateCollectionView([], 0, [], thumbnailLoader: nil)
        XCTAssertTrue(preview.currentImages().isEmpty)
        let reloaded = expectation(description: "재입장 시 최신 경로 로딩")
        let remote = item(path: "chat/remote.jpg")
        preview.updateCollectionView([remote], 240, [1], thumbnailLoader: { requested in
            XCTAssertEqual(requested.previewPaths, remote.previewPaths)
            reloaded.fulfill()
            return photo
        })
        collection.layoutIfNeeded()
        await fulfillment(of: [reloaded], timeout: 1)
    }

    private func imageView(in cell: ChatImagePreviewCell) throws -> UIImageView {
        try XCTUnwrap(cell.contentView.subviews.first as? UIImageView)
    }

    private func item(path: String, index: Int = 0, messageID: String = "message", hash: String = "local-hash") -> ChatImagePreviewItem {
        let attachment = Attachment(type: .image, index: index, pathThumb: path, pathOriginal: path,
                                    width: 100, height: 100, bytesOriginal: 100, hash: hash)
        return ChatImagePreviewItem(id: ChatImagePreviewItem.stableID(messageID: messageID, attachment: attachment),
                                    displayIndex: index, attachment: attachment, durationText: nil)
    }
}
