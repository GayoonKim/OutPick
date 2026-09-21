# Phase 0 조사 — 2026-09-18

## 후속 합의 — 아래 최초 조사보다 우선

- 사용자 재인코딩 방식 확정: 즉시 표시 후 백그라운드 변환·저장, 동일 작업 단일화·공용 제한 유지. 형식은 실제 썸네일 JPEG/PNG 비교로 결정한다.
- 원본-only 처리는 실제 존재 미확인·정상 앱 업로드는 쌍이므로 필수 결정에서 제외했다. 서버 policy가 개별 필드를 허용한다는 사실과 실제 데이터 존재를 구분한다.
- 다음 결정: 썸네일 다운로드 한도 통일. AvatarSetupViewController와 ProfileEditViewController 모두 DefaultMediaProcessingService.makePair 기본 호출 → ImageThumbnailDataMaker.defaultMaxPixel=500 → ProfileAvatarUploader에서 JPEG quality0.8로 업로드. 현 기본 생성 규격은 긴 변500px JPEG이며 업로드 단계의 파일 바이트 상한 보장으로 해석하지 않는다. 실제 기존 이미지 크기 표본은 아직 미측정.

## 승인과 상태

사용자 `세부 구현 계획 따라서 구현 진행해도 문제 없는거지? 문제 없으면 진행하자`로 구현 착수를 승인했다. Phase0 읽기 조사 진행. 제품 정책은 유지하며 아래 기술 선택 대기 때문에 Phase1 코드 변경 전이다. 재승인할 대상은 구현 전체가 아니라 미정 기술 계약이다.

기준 HEAD: `3c162f30686d8d2e5c46d9f76ed39c06977e3814`. 시작 시 문서4개 변경과 docs/portfolio/·firestore-debug.log가 있었고 보존했다. 앱/테스트 코드 변경·빌드·테스트·기기 변경 없음.

## 확인한 소비자 지도

경로는 OutPick/ 기준이다. 최종 구현 때 각 호출의 실제 표시/최신화 이벤트를 함께 연결한다.

| 화면 | 진입점 | 기존 최대 다운로드 | 예정 저장 |
| --- | --- | --- | --- |
| 마이페이지/편집 | Features/MyPage/Controller/MyPageViewController.swift, Views/ProfileEditViewController.swift | 5MiB | 메모리+디스크 |
| 프로필 상세 | Features/Profile/Views/UserProfileDetailViewController.swift | 썸네일3MiB/원본20MiB | 진입 정책/확대 원본 비저장 |
| 채팅 메시지 | Features/Chat/Controllers/ChatViewController.swift → Views/Cell/ChatMessageCell.swift | 3MiB | 참여 여부 |
| 방 목록 메시지 avatar | Features/Chat/Controllers/RoomListsCollectionViewController.swift → Views/Cell/RoomListCollectionViewCell.swift | 2MiB(선로딩도 동일) | 참여 여부 |
| 참여자/설정 | Features/Chat/Views/Cell/ChatRoomSetting/ParticipantListCell.swift, Controllers/ChatRoomSettingViewController.swift, ViewModels/ChatRoomSettingViewModel.swift | 3MiB | 참여 여부 |
| 댓글/답글 | Features/Lookbook/Views/PostDetail/PostCommentCardView.swift, CommentSafetyAvatarView.swift, ViewModels/PostDetailViewModel.swift, PostCommentsViewModel.swift, PostCommentRepliesViewModel.swift | 대표 기본3MiB, 나머지 전달값 구현 전 확인 | 메모리만 |

LookbookHomeView의 AvatarImageManaging 구현은 Preview fake다. RoomSearch/JoinedRooms의 확인된 이미지 호출은 RoomImageService이며 방 대표 이미지를 이번 아바타로 오인하지 않는다.

## 경로·수명 근거

- ChatCoordinator.presentUserProfile → UserProfileDetailCoordinator → UserProfileDetailCompositionRoot.
- 댓글/답글 sheet → CommentUserProfileDetailView → UserProfileDetailCompositionRoot. 출발 저장 정책 전달을 추가해야 한다.
- AvatarImageSource.seedPath는 경로를 thumbnail로 간주하고 merged는 nil을 덮지 않는다. authoritative 제거를 별도로 적용해야 한다.
- ProfileAvatarUploader는 thumbnail JPEG0.8과 originalFileURL을 업로드한다. 정상 등록 흐름에는 두 경로가 있지만 원본-only 기존 데이터 존재 여부는 서버에서 조사하지 않았다.
- ImageCacheMemoryStore는 UIImage만 보관, ImageLoadCoordinator는 완료 시 소비자에게 payload 없는 결과를 반환한다. 다운로드 바이트가 메모리 이미지와 함께 남는다는 가정은 불가능하다.
- ImageCachePersistence는 payload/permit 수명을 소유하고 세대 검사 disk write를 사용한다. 승격도 같은 무효화 경계를 통과해야 한다.
- SimpleImageViewerVC는 원본 cache 조회→썸네일→원본 provider 순서다. 주입 provider 실패 시 추가 원격 fallback은 확인한 loadImageFromPath에 없다. 로컬 파일 직접 로딩은 별도 경로이므로 수명/예산 검증 대상이다.

## 사용자 결정이 필요한 기술 선택 — 아직 미확정

1. 디스크 승격용 바이트: UIImage 재인코딩(추가 CPU, PNG이면 JPEG 손실 재압축 방지·대신 파일 증가), 다운로드 바이트 별도 메모리 보관(추가 메모리/퇴거 정책), 저장 목적 재다운로드(네트워크 증가)를 비교한다. 추천 후보는 썸네일만 공용 준비/I/O 예산 아래 비동기 PNG 재인코딩하고 디스크 크기/비용을 QA하는 방식이다. 구현 전 사용자 결정 필요.
2. 다운로드 한도: 당장 기존2/3/5MiB·원본20MiB를 유지하면 한도 변경 회귀를 피하지만 같은 경로라도 서로 다른 한도 요청은 별도 작업이다. 한도 통일은 추가 결정이다. 추천 후보는 기존 한도 유지·호환 요청만 병합부터 시작하는 것.
3. 원본-only 일반 표시: 새 썸네일 생성/저장 정책을 추가하는 대신 화면 수명 동안만 원본 대체 표시·캐시 미저장 후보. 해당 자료 재방문 시 재다운로드하는 단점이 있다. 자료 존재를 추측으로 단정하지 않는다.

## 검증과 다음 단계

읽기 조사만 수행. Phase0 완료로 처리하지 않는다. 기술 선택 확정 후 정책/한도 지도를 보완하고 Phase1의 공용 비저장·승격 코드와 fake 회귀 작성·실행으로 이어간다. 기존 사용자 합의 정책이나 자동 테스트 실행을 다시 승인받지 않는다.
