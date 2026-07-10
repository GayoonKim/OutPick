# Profile Entrypoints

## 목적

프로필 생성/수정, 사용자 프로필 상세, avatar source, profile repository/mapper를 수정할 때 어느 파일을 먼저 보면 되는지 정리한다.

## 프로필 조립과 라우팅

- Profile composition root: `OutPick/Features/Profile/ProfileCompositionRoot.swift`
  - 프로필 생성/수정 플로우 조립을 확인한다.
- Profile coordinator: `OutPick/Features/Profile/ProfileCoordinator.swift`
  - 첫 번째/두 번째 프로필 화면 전환과 완료 route를 확인한다.
- User profile detail composition root: `OutPick/Features/Profile/UserProfileDetailCompositionRoot.swift`
  - 사용자 프로필 상세 화면 조립, avatar manager, current user provider, photo library saver 주입 경계를 확인한다.
- User profile detail coordinator: `OutPick/Features/Profile/UserProfileDetailCoordinator.swift`
  - 상세 화면 presentation/navigation과 Chat 접합부에서 avatar manager, current user provider, photo library saver 전달을 확인한다.

## 프로필 생성/수정 화면

- First profile view controller: `OutPick/Features/Profile/Views/FirstProfileViewController.swift`
  - 첫 프로필 입력 화면 UI와 이벤트를 확인한다.
- First profile view model: `OutPick/Features/Profile/ViewModels/FirstProfileViewModel.swift`
  - 첫 프로필 입력 state와 validation을 확인한다.
- Second profile view controller: `OutPick/Features/Profile/Views/SecondProfileViewController.swift`
  - 두 번째 프로필 입력/이미지 선택 UI를 확인한다.
  - 로컬 draft UserDefaults 저장/복원, back button 저장, UIKit interactive pop 완료 시 draft 저장, 저장 중 swipe-back 차단을 확인한다.
  - 닉네임 입력 외 영역 탭 시 키보드 dismiss는 `KeyboardDismissSupport.installKeyboardDismissTapGesture()`로 처리한다.
- Second profile view model: `OutPick/Features/Profile/ViewModels/SecondProfileViewModel.swift`
  - avatar/profile draft 저장 흐름을 확인한다.
  - 저장 완료 후 current user session profile 갱신은 상위 완료 콜백 경계와 연결된다.

## 사용자 프로필 상세

- Detail view controller: `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`
  - 다른 사용자 프로필 표시 UI와 avatar tap 확대 viewer 진입을 확인한다.
  - avatar 확대는 공용 `ImageViewerPage`/`SimpleImageViewerVC`를 사용하고, Photos 저장은 주입받은 `PhotoLibrarySaving`을 사용한다.
- Detail view model: `OutPick/Features/Profile/ViewModels/UserProfileDetailViewModel.swift`
  - canonical user ID 기반 프로필 로드, avatar 표시 state, 현재 사용자 판정을 확인한다.
- Load detail use case: `OutPick/Features/Profile/Domain/UseCases/LoadUserProfileDetailUseCase.swift`
  - 상세 프로필 로딩 orchestration을 확인한다.
- Detail repository protocol/implementation:
  - `OutPick/Features/Profile/Repository/UserProfileDetailRepositoryProtocol.swift`
  - `OutPick/Features/Profile/Repository/UserProfileDetailRepository.swift`
  - Firestore user profile 상세 조회 구현을 확인한다.

## 도메인, DTO, mapper

- Domain model: `OutPick/Features/Profile/Domain/UserProfile.swift`
  - 앱 내부 사용자 프로필 모델을 확인한다.
- Draft model: `OutPick/Features/Profile/Domain/UserProfileDraft.swift`
  - 프로필 생성/수정 중간 state를 확인한다.
- Avatar source: `OutPick/Features/Profile/Domain/AvatarImageSource.swift`
  - avatar 이미지 source/type 정책을 확인한다.
- DTO: `OutPick/Features/Profile/DTO/UserProfileDTO.swift`
  - Firestore 저장/조회 payload를 확인한다.
- Firestore codec: `OutPick/Features/Profile/Mapper/UserProfileFirestoreCodec.swift`
  - Firestore document encode/decode를 확인한다.
- Mapper: `OutPick/Features/Profile/Mapper/UserProfileMapper.swift`
  - DTO와 domain model 변환을 확인한다.

## Repository

- User profile repository protocol: `OutPick/Features/Profile/Repository/UserProfileRepositoryProtocol.swift`
  - 프로필 저장/조회 계약을 확인한다.
- User profile repository: `OutPick/Features/Profile/Repository/UserProfileRepository.swift`
  - Firestore user profile 저장/조회 구현을 확인한다.
  - 프로필 문서는 `users/{canonicalUserID}` 직접 조회/저장을 사용한다.
  - 이메일/provider field 기반 fallback query는 사용하지 않는다.

## Avatar DI 접합부

- 앱 공용 avatar interface: `OutPick/Features/Chat/Services/ImageLoading/AvatarImageManaging.swift`
  - Chat, Lookbook, Profile 상세가 공유하는 avatar image interface를 확인한다.
- Avatar service implementation: `OutPick/Features/Chat/Services/ImageLoading/AvatarImageService.swift`
  - avatar image loading/cache 구현을 확인한다.
- Current user provider: `OutPick/App/Session/CurrentUserProvider.swift`
  - Profile 상세의 현재 사용자 판정에 필요한 `canonicalUserID` 제공 계약을 확인한다.
- Current user session store: `OutPick/App/Session/CurrentUserSessionStore.swift`
  - 앱 세션 current profile snapshot source를 확인한다.
- 현재 설계 결정: `docs/ai/tasks/chat-view-controller-layering/decisions.md`
  - `Provider/Avatar DI 일괄 정리` 섹션을 확인한다.
