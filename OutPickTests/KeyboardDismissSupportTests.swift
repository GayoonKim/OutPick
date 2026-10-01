import Testing
import UIKit
@testable import OutPick

@MainActor
struct KeyboardDismissSupportTests {
    @Test func excludesChatSendButtonFromWindowDismissal() throws {
        let window = UIWindow()
        let inputView = ChatUIView()
        window.addSubview(inputView)
        inputView.sendButton.isEnabled = true
        let gesture = try installDismissGesture(in: window)

        #expect(try receivesDismissTap(on: inputView.sendButton, gesture: gesture) == false)
    }

    @Test func excludesChatSendButtonDescendantFromWindowDismissal() throws {
        let window = UIWindow()
        let inputView = ChatUIView()
        window.addSubview(inputView)
        inputView.sendButton.isEnabled = true
        let icon = try #require(inputView.sendButton.imageView)
        let gesture = try installDismissGesture(in: window)

        #expect(try receivesDismissTap(on: icon, gesture: gesture) == false)
    }

    @Test func preservesTextInputTouches() throws {
        let window = UIWindow()
        let textView = UITextView()
        let textField = UITextField()
        let textContent = UIView()
        window.addSubview(textView)
        window.addSubview(textField)
        textView.addSubview(textContent)
        let gesture = try installDismissGesture(in: window)

        #expect(try receivesDismissTap(on: textView, gesture: gesture) == false)
        #expect(try receivesDismissTap(on: textField, gesture: gesture) == false)
        #expect(try receivesDismissTap(on: textContent, gesture: gesture) == false)
    }

    @Test func continuesReceivingConversationBackgroundTouches() throws {
        let window = UIWindow()
        let background = UIView()
        window.addSubview(background)
        let gesture = try installDismissGesture(in: window)

        #expect(try receivesDismissTap(on: background, gesture: gesture))
    }

    private func installDismissGesture(in window: UIWindow) throws -> UITapGestureRecognizer {
        // UIWindow의 시스템 제스처가 아니라 공통 지원 코드가 추가한 제스처를 검사한다.
        let existing = Set((window.gestureRecognizers ?? []).map(ObjectIdentifier.init))
        window.installKeyboardDismissTapGesture()
        return try #require(window.gestureRecognizers?.first {
            !existing.contains(ObjectIdentifier($0))
        } as? UITapGestureRecognizer)
    }

    private func receivesDismissTap(on touchedView: UIView, gesture: UITapGestureRecognizer) throws -> Bool {
        let delegate = try #require(gesture.delegate)
        return try #require(delegate.gestureRecognizer?(
            gesture,
            shouldReceive: KeyboardDismissTestTouch(touchedView: touchedView)
        ))
    }
}

@MainActor
private final class KeyboardDismissTestTouch: UITouch {
    private let touchedView: UIView

    init(touchedView: UIView) {
        self.touchedView = touchedView
        super.init()
    }

    override var view: UIView? { touchedView }
}
