import XCTest
import UIKit
@testable import OutPick

@MainActor
final class ChatMediaUploadProgressViewTests: XCTestCase {
    func testWaitingReplacesSpinnerWithStaticCountAndResetsOnReuse() throws {
        let view = ChatMediaUploadProgressView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        view.show(progress: nil)
        view.showWaiting(count: 30)
        XCTAssertEqual(view.accessibilityLabel, "전송 대기")
        XCTAssertEqual(view.accessibilityValue, "30장")
        let badge = try XCTUnwrap(view.subviews.first)
        XCTAssertTrue((badge.layer.sublayers ?? []).allSatisfy { $0.animation(forKey: "pending") == nil })
        XCTAssertEqual(badge.subviews.compactMap { $0 as? UILabel }.first?.text, "30장")
        view.show(progress: 0.2)
        XCTAssertTrue(badge.subviews.compactMap { $0 as? UILabel }.allSatisfy(\.isHidden))
        XCTAssertEqual(view.accessibilityValue, "20%")
        view.reset()
        XCTAssertTrue(view.isHidden)
    }
    func testUploadFinishedStillShowsPendingUntilConfirmed() {
        let view = ChatMediaUploadProgressView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        view.show(progress: 0.5)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.accessibilityValue, "50%")
        view.show(progress: 1)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.accessibilityLabel, "전송 완료 확인 중")
        XCTAssertNil(view.accessibilityValue)
        view.reset()
        XCTAssertTrue(view.isHidden)
        XCTAssertNil(view.accessibilityLabel)
    }

    func testCellFailureAndReuseClearSpinnerState() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let overlay = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? ChatMediaUploadProgressView }.first)
        cell.applyMediaUploadRecoveryState(.processing)
        XCTAssertFalse(overlay.isHidden)
        cell.applyMediaUploadRecoveryState(.failed)
        XCTAssertEqual(overlay.accessibilityLabel, "전송 실패")
        cell.prepareForReuse()
        XCTAssertTrue(overlay.isHidden)
        cell.applyMediaUploadRecoveryState(.uploading(0.25))
        XCTAssertEqual(overlay.accessibilityValue, "25%")
        cell.applyMediaUploadRecoveryState(.none)
        XCTAssertTrue(overlay.isHidden)
    }

    func testAppearanceAttachment() {
        let canvas = UIView(frame: CGRect(x: 0, y: 0, width: 780, height: 230))
        canvas.backgroundColor = .black
        for (index, progress) in [0.55, 1.0, -1.0].enumerated() {
            let photo = UIView(frame: CGRect(x: 10 + index * 260, y: 10, width: 240, height: 180))
            photo.backgroundColor = .systemTeal
            let sun = UIView(frame: CGRect(x: 140, y: 25, width: 55, height: 55))
            sun.backgroundColor = .systemYellow
            sun.layer.cornerRadius = 27.5
            photo.addSubview(sun)
            let overlay = ChatMediaUploadProgressView(frame: photo.bounds)
            photo.addSubview(overlay)
            if progress >= 0 { overlay.show(progress: progress) }
            canvas.addSubview(photo)
            let label = UILabel(frame: CGRect(x: 10 + index * 260, y: 195, width: 240, height: 25))
            label.text = ["업로드 중", "서버 확인 중", "성공 확정"][index]
            label.textColor = .white
            label.textAlignment = .center
            canvas.addSubview(label)
        }
        canvas.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
            canvas.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "전송 상태 표시 비교"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
