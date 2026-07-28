# Profile Entrypoints

## 목적

새 사용자 온보딩, 계정 bootstrap, 공개 프로필 조회, avatar 업로드와 사용자 프로필 상세의 진입점을 정리한다.

## 앱 bootstrap과 온보딩 route

- 앱 조립: `OutPick/App/AppCompositionRoot.swift`
  - 계정·공개 프로필·스타일 무드 Repository와 `LoadCurrentUserBootstrapUseCase`, `CompleteOnboardingUseCase`를 생성한다.
- 앱 route: `OutPick/App/AppCoordinator.swift`
  - `needsOnboarding`, `ready`, `deletionPending`을 분기한다.
  - 온보딩 완료 후 `UserPublicProfile`을 세션에 저장하고 Chat/Lookbook bootstrap을 시작한다.
- 온보딩 조립: `OutPick/Features/Profile/ProfileCompositionRoot.swift`
- 온보딩 화면 전환: `OutPick/Features/Profile/ProfileCoordinator.swift`
  - 닉네임 → 선택적 아바타 → 관심 스타일 → 완료 순서와 draft를 소유한다.
  - 닉네임 확인이 성공한 경우에만 아바타 화면을 push한다.
  - `OnboardingTransitionAnimator`를 navigation delegate에 연결한다.

## 온보딩 화면과 상태

- 프로필 입력:
  - `OutPick/Features/Profile/ViewModels/ProfileSetupViewModel.swift`
  - `OutPick/Features/Profile/Views/ProfileSetupViewController.swift`
  - `01/03` 닉네임 2~20자를 입력하고 큰 타이포그래피에 반영한다.
  - 다음 탭에서 `CheckNicknameAvailabilityUseCase`를 실행하며 중복·조회 실패는 현재 화면에 표시한다.
- 아바타:
  - `OutPick/Features/Profile/ViewModels/AvatarSetupViewModel.swift`
  - `OutPick/Features/Profile/Views/AvatarSetupViewController.swift`
  - `02/03` 시스템 사진 선택기를 사용자 액션 때 열고 선택/해제/건너뛰기를 처리한다.
- 관심 무드:
  - `OutPick/Features/Profile/ViewModels/StyleMoodOnboardingViewModel.swift`
  - `OutPick/Features/Profile/Views/StyleMoodOnboardingViewController.swift`
  - `OutPick/Features/StyleMood/Views/StyleMoodPickerView.swift`
  - `03/03` 검색어가 없으면 featured, 검색 중에는 전체 active 이름 필터를 표시하며 1~5개 선택만 완료 가능하다.
  - 로딩과 `OutPick 시작하기` 저장 중 진행 표시는 `OutPickTheme.ColorToken.accent`를 사용한다.
- 공통 텍스트 카드:
  - `OutPick/Features/StyleMood/Views/StyleMoodTextCard.swift`
- 공통 에디토리얼 UI/전환:
  - `OutPick/Features/Profile/Views/OnboardingEditorialHeaderView.swift`
  - `OutPick/Features/Profile/Transitions/OnboardingTransitionAnimator.swift`
  - Reduce Motion에서는 이동·stagger 없이 fade만 사용한다.

## 도메인·DTO·Mapper

- 비공개 계정:
  - Domain `OutPick/Features/Profile/Domain/UserAccount.swift`
  - DTO `OutPick/Features/Profile/DTO/UserAccountDTO.swift`
  - Mapper `OutPick/Features/Profile/Mapper/UserAccountMapper.swift`
- 공개 프로필:
  - Domain `OutPick/Features/Profile/Domain/UserPublicProfile.swift`
  - DTO `OutPick/Features/Profile/DTO/UserPublicProfileDTO.swift`
  - Mapper `OutPick/Features/Profile/Mapper/UserPublicProfileMapper.swift`
- 온보딩 입력:
  - `OutPick/Features/Profile/Domain/OnboardingDraft.swift`
- 스타일 무드:
  - `OutPick/Features/StyleMood/Domain/StyleMood.swift`
  - `OutPick/Features/StyleMood/Domain/StyleMoodGroup.swift`
  - `OutPick/Features/StyleMood/Models/StyleMoodDTO.swift`

성별·생년월일과 기존 단일 `users` 프로필 DTO/codec/mapper는 clean break로 제거했다.

## Repository와 UseCase

- 계정 read:
  - `CurrentUserAccountRepositoryProtocol.swift`
  - `FirestoreCurrentUserAccountRepository.swift`
- 공개 프로필 read:
  - `UserPublicProfileRepositoryProtocol.swift`
  - `FirestoreUserPublicProfileRepository.swift`
- 프로필 mutation callable:
  - `ProfileMutationRepositoryProtocol.swift`
  - `CloudFunctionsProfileMutationRepository.swift`
- 닉네임 사전 확인:
  - `Domain/UseCases/CheckNicknameAvailabilityUseCase.swift`
  - 사전 확인은 닉네임을 예약하지 않으며 최종 `completeOnboarding`이 transaction에서 다시 검증한다.
- 아바타 업로드 최소 경계:
  - `ProfileAvatarUploader.swift`
  - `ProfileAvatarCleanupStore.swift`는 공개 경로 갱신 후 실패한 이전 Storage 객체 정리를 재시도한다.
- 스타일 무드 read:
  - `StyleMoodRepositoryProtocol.swift`
  - `FirestoreStyleMoodRepository.swift`
- bootstrap:
  - `LoadCurrentUserBootstrapUseCase.swift`
- 온보딩 완료:
  - `CompleteOnboardingUseCase.swift`
  - 먼저 `completeOnboarding`으로 계정·공개 프로필을 생성한다.
  - 선택한 아바타는 active 계정 생성 뒤 Storage에 올리고 `updatePublicProfile`로 경로를 기록한다.
  - 아바타 실패는 계정 완료를 되돌리지 않고 부분 실패로 반환한다.

## 마이페이지 편집

- 조립/route:
  - `OutPick/Features/MyPage/MyPageCompositionRoot.swift`
  - `MyPageContainer.swift`, `MyPageCoordinator.swift`
- 화면/상태:
  - `MyPageViewModel.swift`, `Controller/MyPageViewController.swift`
  - `ProfileEditViewModel.swift`, `Views/ProfileEditViewController.swift`
  - `StylePreferenceEditViewModel.swift`, `Views/StylePreferenceEditViewController.swift`
  - `Views/MyPageEditorialComponents.swift`: 공통 serif/monospaced 계층, mood chip, hairline action row, primary CTA
- mutation:
  - `UpdatePublicProfileUseCase.swift`: 닉네임 사전 확인, 아바타 유지·변경·제거, 이전 Storage 정리
  - `UpdateStylePreferencesUseCase.swift`: active 관심 무드 1~5개 저장
- 프로필 이미지 변경은 새 파일 업로드 → 공개 경로 갱신 → 이전 파일 삭제 순서다. 삭제 실패 경로는 로컬 cleanup store에 기록하고 다음 마이페이지 진입 때 재시도한다.
- 세 화면은 좌측 정렬 에디토리얼 헤더, 원형 avatar, outlined mood chip, hairline row와 하단 accent CTA를 공유한다. Reduce Motion에서는 루트 진입 이동 애니메이션을 생략한다.

## 공개 프로필 직접 소비 경계

- 현재 세션은 `UserPublicProfile`을 직접 보유한다.
- Chat profile sync/participant, Lookbook 댓글 작성자, 사용자 상세는 `UserPublicProfileRepositoryProtocol`을 직접 사용한다.
- legacy `UserProfile`과 `UserProfileCompatibilityAdapter`는 제거했다.
- 루트 `users/{uid}`에 email/device/profile 값을 쓰지 않는다. device/push state는 기존 하위 문서만 사용한다.

## 사용자 프로필 상세

- 조립/route:
  - `UserProfileDetailCompositionRoot.swift`
  - `UserProfileDetailCoordinator.swift`
- 화면/상태:
  - `Views/UserProfileDetailViewController.swift`
  - `ViewModels/UserProfileDetailViewModel.swift`
- read orchestration:
  - `Domain/UseCases/LoadUserProfileDetailUseCase.swift`
  - `Repository/UserProfileDetailRepository.swift`
- avatar:
  - `Domain/AvatarImageSource.swift`
  - 공용 `AvatarImageManaging`/`AvatarImageService`

상세 modal의 edge dismiss는 기존 `ChatModalTransitionManager`를 사용한다.

## 검증

- `OutPickTests/ProfileSetupViewModelTests.swift`
- `OutPickTests/AvatarSetupViewModelTests.swift`
- `OutPickTests/StyleMoodOnboardingViewModelTests.swift`
- `OutPickTests/LoadCurrentUserBootstrapUseCaseTests.swift`
- `OutPickTests/CompleteOnboardingUseCaseTests.swift`
- `OutPickTests/CloudFunctions/CloudFunctionsProfileMutationRepositoryTests.swift`
- `OutPickTests/UpdatePublicProfileUseCaseTests.swift`
- `OutPickTests/ProfileEditViewModelTests.swift`
- `OutPickTests/StylePreferenceEditViewModelTests.swift`
- 서버·rules 검증은 `docs/ai/entrypoints/FIREBASE.md`와 현재 task QA 문서를 따른다.
