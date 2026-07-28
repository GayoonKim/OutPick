import Foundation
import UIKit

struct OnboardingAvatarDraft {
    let thumbnail: UIImage
    let originalFileURL: URL
    let sha256: String
}

struct OnboardingDraft {
    let nickname: String
    let avatar: OnboardingAvatarDraft?
}
