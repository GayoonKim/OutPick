import UIKit

/// UIKit 표시 위치가 사라지면 소비자 요청만 취소하고 같은 사진의 완료 결과는 유지한다.
final class AvatarImageView: UIImageView {
    let presentation = AvatarImagePresentationState()
    var automaticallyLoads = true

    func configure(userID: String, path: String?, manager: AvatarImageManaging, original: Bool = false) {
        bindPresentation()
        presentation.configure(userID: userID, path: path, manager: manager, start: automaticallyLoads && window != nil, original: original)
    }

    func configure(identity: AvatarImageIdentity, loader: @escaping () async throws -> UIImage?) {
        bindPresentation()
        presentation.configure(identity: identity, start: window != nil, loader: loader)
    }

    private func bindPresentation() {
        presentation.onImageChanged = { [weak self] image in
            self?.image = image ?? UIImage(named: "Default_Profile")
        }
    }

    func resetAvatar() { presentation.reset(); image = UIImage(named: "Default_Profile") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { presentation.suspend() } else if automaticallyLoads { presentation.resume() }
    }
}
