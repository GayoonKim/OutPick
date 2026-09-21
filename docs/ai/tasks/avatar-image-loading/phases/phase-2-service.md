# Phase 2 — 아바타 정책·DI·세션 수명

## 목표

사용처 정책·원본 로딩·무효화를 서비스 경계로 제공하고 세션 정리를 연결한다.

## 변경 파일 후보

- OutPick/Features/Chat/Services/ImageLoading/AvatarImage{Managing,Service}.swift
- 신규 후보: 같은 폴더의 AvatarImageRequest.swift, AvatarImageCachePolicy.swift, AvatarImageSessionController.swift.
- OutPick/App/{AppCompositionRoot,AppCoordinator,AppSessionRuntime}.swift, App/Session/{CurrentUserSessionStore,JoinedRoomsSessionStore}.swift
- Profile/UserProfileDetail{CompositionRoot,Coordinator}.swift, MyPage/{MyPageContainer,MyPageCoordinator}.swift, Chat/{ChatContainer,ChatCoordinator}.swift, Lookbook/LookbookContainer.swift의 실제 조립 지점.
- Profile/Domain/{AvatarImageSource.swift,UseCases/UpdatePublicProfileUseCase.swift}, 기존 ChatProfileSyncManager·CommentAuthorProfileStore의 최신 프로필 적용 접합부.
- MyPage/AccountDeletionLocalDataScrubber.swift, 필요한 경우 Login/Application/LoginManager.swift의 세션 종료 접합부.
- 신규 AvatarImageServiceTests.swift, AvatarImageSessionTests.swift 및 기존 profile/cache fake 호환 수정.

## 구현 순서

1. explicit request/context로 저장 정책과 thumbnail/original을 전달한다. View가 membership Repository를 생성하지 않는다.
2. 같은 앱 서비스의 메모리·디스크를 공유하고 Profile Coordinator로 출발 정책을 전달한다. 프로토콜 변경 시 전체 conformer/fake 컴파일을 함께 보완한다.
3. 현재 세션 세대와 사용자별 마지막 authoritative avatar source를 연결한다. seed/미조회와 명시적 nil을 구분하고 기존 프로필 최신화 시점에만 무효화한다.
4. 사진 수정 성공 후 이전 경로 무효화; 수정 실패는 기존 캐시 유지. 오래된 프로필 snapshot이 무효화한 경로를 다시 요청하는지 확인한다.
5. 로그아웃/전환은 이전 요청을 차단→캐시/대기 쓰기 정리→새 세션 허용 순서로 연결한다. 계정 삭제의 기존 전체 scrub 포함을 유지한다.
6. 이번 아바타 로컬 경로도 합의한 자원/수명으로 처리하되 사진 선택·업로드 변환 자체는 확장하지 않는다.

## 완료 기준·검증

사용처별 정책 표와 실제 DI 일치, 새 서버 요청0, 사진 제거가 seed fallback으로 복구되지 않음, 로그아웃 도중 늦은 결과/승격으로 이전 캐시 재생성0, 새 세션 캐시가 이전 clear로 삭제되지 않음. 서비스/session deterministic 테스트 및 관련 기존 profile 테스트 실행·전체 테스트 target 컴파일.

## 논의 필요·의존성

출발 정책 없는 route는 Phase0에서 결정. 최신 프로필 제거 의미를 고칠 때 metadata TTL/서버 구독 정책까지 바꾸지 않는다. 서비스와 DI가 모든 화면의 전제이므로 다음 phase보다 먼저 완료한다.
