# Phase 3 — 아바타 표시·확대 수명

## 구현

- `AvatarImagePresentationState`가 사용자ID/정규화 경로, idle/loading/loaded/failed, 소비자 Task와 요청 revision을 소유한다. 동일 identity apply는 완료 이미지와 진행 요청을 유지한다. 변경/제거/reset/suspend는 revision을 바꿔 늦은 성공·실패가 현재 이미지/상태/task를 변경하지 못하게 한다. 네트워크/캐시 및 세션 세대는 Phase2 서비스가 계속 소유한다.
- UIKit은 `AvatarImageView`를 사용한다. 마이페이지·프로필 편집·프로필 상세·채팅 메시지·방 목록 메시지·참여자 셀에 연결했다. ViewModel userID는 읽기 전용으로 노출했다. 프로필 편집에서 선택한 이미지/제거는 원격 표시 상태를 reset한 뒤 즉시 반영한다.
- 셀 재사용과 didEndDisplaying은 취소, willDisplay/재등장은 필요한 요청만 재개한다. 각 화면의 viewDidDisappear/viewDidAppear와 이미지뷰 window 수명을 연결했다. 완료 썸네일은 같은 사진으로 돌아오면 유지한다.
- 방 목록은 messageID별 MessagePreviewView를 재사용한다. 동일 목록 갱신에서 avatar 뷰를 모두 제거·재생성하던 흐름을 없앴다.
- 댓글 카드/답글/삭제·신고·차단 sheet는 공통 `CommentSafetyAvatarView`를 쓴다. userID를 전달하고 source가 바뀐 프레임에는 이전 사진을 그리지 않는다. 사라질 때 취소하고 재등장 시 일시 실패를 재시도한다. 요청 전 loadedPath를 기록하던 방식은 제거했다.
- 서비스가 Storage 객체 없음/접근 거부를 `AvatarImageLoadingError.unavailable`로 변환한다. 표시 상태가 Firebase SDK를 직접 해석하지 않는다. 영구 실패는 일반 재등장으로 반복하지 않고 source 변경을 기다린다. 일시 실패는 실패 상태로 남으며 일반 apply만으로 자동 반복하지 않는다.
- 프로필 확대는 `SimpleImageViewerVC(transientImages: true)`를 사용한다. 기존 썸네일 유지·실패 버튼·수동 재시도는 유지한다. 캐시/로드 provider 실패 시 로컬 파일 직접 읽기로 우회하지 않는다. 종료는 page 작업 취소와 원본/초기 이미지 참조 해제, 늦은 결과 차단을 수행한다. 취소된 interactive disappearance로 간주되는 willDisappear→didAppear만으로 닫지 않는다. 다른 미디어 viewer는 기존 기본값(false) 유지.

## 변경 경계

핵심 신규 파일은 Chat/Services/ImageLoading의 AvatarImagePresentationState.swift·AvatarImageView.swift다. 같은 폴더 AvatarImageRequest/Service의 오류 계약, ChatMessageCell(+LookbookShare)/ParticipantListCell/RoomListCollectionViewCell과 각 controller, MyPage/Profile ViewModel·controller, 댓글 avatar views, 공용 SimpleImageViewerVC가 변경됐다. 서버 API/데이터/Firebase 규칙/새 구독은 변경하지 않았다.

## 검증

- 첫 빌드에서 공유 카드 thumbnail closure에 불필요하게 throws가 붙은 컴파일 오류를 발견해 avatar closure에만 throws를 적용하도록 수정했다.
- 최종 앱·전체 테스트 target `build-for-testing` 통과: `/private/tmp/outpick-avatar-phase3-build2.log`.
- 표시 상태·서비스/세션·Repository·프로필 수정·채팅 profile/comment/preview·공용 캐시54개(10 Swift Testing suite)와 ImageViewerStateTests10개(XCTest) 모두 통과: `/private/tmp/outpick-avatar-phase3-tests.log`(`TEST SUCCEEDED`).
- AvatarImagePresentationStateTests: 동일 identity 추가 요청0, 다른 사용자/경로의 늦은 성공·실패, 제거/선택 reset, 일시 실패 재등장, unavailable 반복 억제, 취소된 이전 완료가 새 Task를 지우지 않음, 일시 화면 이탈 후 완료 이미지 유지.
- ImageViewerStateTests 신규3개: transient 종료 이미지 해제·늦은 결과 차단, 유효 로컬 파일도 provider 실패를 우회하지 않음, 완료되지 않은 disappearance 후 요청 유지. 기존7개(썸네일 유지·재시도·저장·페이지·chrome) 회귀 포함.
- Storage 오류 분류 objectNotFound/unauthorized/unknown(3인자 시나리오)을 포함한 서비스6개 테스트 추가 실행 모두 통과: `/private/tmp/outpick-avatar-phase3-errors-tests.log`(`TEST SUCCEEDED`). 최종 소스 컴파일 포함, `git diff --check` 통과.

## 남은 범위

Phase4는 방향 기반 viewport1.5/0.5·고유24·이탈300ms 선로딩 및 새 메시지/참여 상태/수동 갱신 이벤트의 요청·재시도 연결이다. 이번에는 표시 수명 기반 재등장만 연결했으며 viewport 전체 완료로 해석하지 않는다. UIKit 실제 interactive dismiss 제스처·셀 스크롤/깜박임·줌·원본 종료 메모리는 Phase5 실기기 QA다. 기기 설치/서버 변경/커밋/PR 없음.
