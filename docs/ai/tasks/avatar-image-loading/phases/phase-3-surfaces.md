# Phase 3 — 화면 표시와 확대 원본

## 목표

전체 아바타 화면에 같은 사진 유지·다른 결과 차단·실패 상태와 원본 수명 정책을 적용한다.

## 변경 파일 후보

- MyPage/Controller/MyPageViewController.swift, MyPage/Views/ProfileEditViewController.swift
- Profile/Views/UserProfileDetailViewController.swift, Profile/Domain/AvatarImageSource.swift
- Chat/Views/Cell/{ChatMessageCell,RoomListCollectionViewCell}.swift, Chat/Views/Cell/ChatRoomSetting/ParticipantListCell.swift
- Chat/Controllers/{ChatViewController,RoomListsCollectionViewController,ChatRoomSettingViewController}.swift
- Lookbook/Views/PostDetail/{CommentSafetyAvatarView,PostCommentCardView,CommentUserProfileDetailView}.swift 및 실제 사용자 상세 전달 경로
- Infra/Media/ImageViewer/{SimpleImageViewerVC,ImageViewerChromeView}.swift는 프로필 provider/종료/재시도 계약에 필요한 최소 변경만.
- 신규 AvatarImagePresentationState.swift/Tests.swift 후보; 기존 ImageViewerStateTests.swift 회귀.

## 구현 순서

1. 사용자·경로·세션 identity와 idle/loading/loaded/failed 상태를 좁은 표시 구성요소로 분리한다. 각 셀에서 거대 orchestration을 반복하지 않는다.
2. 같은 identity의 상태 갱신은 이미지와 task 유지. 다른 identity는 즉시 이전 표시를 제거하고 취소한다. 성공/catch/defer 모두 identity 검사.
3. 실패를 loaded로 마킹하지 않는다. 작은 avatar는 기본 이미지, 기존 같은 이미지가 있으면 유지. 객체 없음/접근 거부 분류를 서비스 결과로 전달한다.
4. 프로필 상세 자동 원본 upgrade를 제거하고 source nil 변경을 처리한다.
5. viewer 진입은 initial 썸네일→무캐시 원본. provider 실패가 기존 캐시/직접 Storage fallback으로 우회하지 않도록 검증한다. 취소된 interactive dismiss와 실제 종료를 구분한다.
6. 원본 실패 버튼과 재시도 후 교체를 유지하고 종료 시 viewer 내부 참조/Task/임시 파일 소유권을 해제한다. 다른 미디어 viewer 동작은 보존한다.

## 완료 기준·검증

동일 사진 반복 apply 추가 fetch0, 다른 사용자 셀에 늦은 성공/실패 적용0, 선택/제거 후 이전 사진 복귀0, 일반 프로필 원본 자동 다운로드0, 확대 종료 이후 캐시0. fake 상태 테스트 실행, viewer 기존 회귀 실행, 간단한 시각/탭/줌은 Phase5 수동 QA.

## 논의 필요·충돌

새 화면/버튼은 확대 실패 재시도 외 추가하지 않는다. source identity 및 원본-only 계약은 Phase0 기준. 화면과 다음 선로딩 phase가 같은 컨트롤러를 수정하므로 순차 진행한다.
