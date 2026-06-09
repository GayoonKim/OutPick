# Dark Theme System Completed Progress

## 목적

다크 테마 시스템 작업의 phase별 완료 기록, 변경 파일 인덱스, 검증 상태를 보존한다.

현재 상태 요약은 `../progress.md`, phase 지도는 `../plan.md`, 설계는 `../design.md`, 결정 상세는 `../decisions/theme-system.md`를 본다.

## 완료 작업 인덱스

| 구간 | 요약 | 주요 산출물 |
| --- | --- | --- |
| 초기 하네스 | 기존 문서와 색상 상태를 확인하고 다크 전용 작업 문서를 생성했다. | `design.md`, `decisions.md`, `plan.md`, ADR-010 |
| Phase 2 | 다크 전용 앱 appearance, AccentColor, UIKit/SwiftUI 공통 토큰을 적용했다. | `OutPickTheme.swift`, `AppDelegate.swift`, `Info.plist`, AccentColor |
| Phase 3 | 탭바, UIKit/SwiftUI 공통 navigation/loading/toast/progress 색상을 토큰화했다. | tab/navigation/share/toast 공통 컴포넌트 |
| Phase 4A | 룩북 홈, 좋아요 탭, 공통 이미지 placeholder/failure/loading 색상을 토큰화했다. | LookbookHome, Liked, LookbookAssetImageView |
| Phase 4Nav | 룩북 SwiftUI 화면군에 공통 navigation bar를 적용하고 native toolbar 노출을 줄였다. | LookbookNavigationBar, 홈/좋아요/상세 화면 |
| Phase 4B | 브랜드/시즌/포스트 상세 화면의 본문과 metric/like 색상 체계를 정리했다. | BrandDetail, SeasonDetail, PostDetail |
| Phase 4C | 댓글/sheet/생성/import 플로우를 다크 토큰으로 정리하고 포스트 저장 버튼 UI를 제거했다. | 댓글 sheet, 생성 플로우, import 화면 |
| Phase 4C 후속 | 시즌 import 진행 문구 중복, 차단/삭제 sheet 레이아웃 잘림을 보정했다. | CreateBrandCandidateSelection, confirmation sheets |
| Phase 5A | 채팅 목록/참여방/검색 화면의 라이트 배경, 검정 텍스트, 파란/주황 상태색을 토큰화했다. | RoomLists, JoinedRooms, RoomSearch, RoomListCollectionViewCell |
| Phase 5A 후속 | 채팅 목록 navigation search 버튼을 방 추가 버튼과 같은 accent로 맞췄다. | CustomNavigationBarView |
| Phase 5B | 채팅방 본문, 입력창, 답장/검색/첨부 UI, 메시지 셀, 날짜/읽음 마커, 공지/롱프레스 메뉴를 토큰화했다. | ChatViewController, ChatUIView, ChatMessageCell, ChatReplyView, ChatSearchUIView, AttachmentView, 보조 셀 |
| Phase 5B 후속 | 채팅방 back/search/setting icon과 첨부 `+`/앨범/카메라 버튼을 accent로 맞추고, 채팅방 설정 화면 일부를 다크 토큰으로 선반영했다. | CustomNavigationBarView, ChatUIView, AttachmentView, ChatRoomSettingViewController, setting cells |
| Phase 5C | 방 생성/편집/설정/미디어 갤러리 목록 화면을 토큰화하고, 전체 화면 viewer의 black overlay 예외를 유지했다. | RoomCreateViewController, RoomCreateContentView, RoomEditViewController, ChatRoomEdit cells, MediaGalleryViewController |
| Phase 6 | 로그인/부트, 프로필 생성/상세, 마이페이지 root의 라이트 배경/검정 텍스트/systemBlue hero를 다크 토큰으로 정리했다. | LoginViewController, BootLoadingViewController, Profile views, MyPageViewController |
| Phase 6 후속 | 로그인 로고 표현과 애니메이션, 프로필 2단계 입력/사진 버튼 레이아웃, 프로필 상세 닫기 버튼을 QA 피드백 기준으로 보정했다. | LoginViewController, SecondProfileViewController, UserProfileDetailViewController |
| Phase 7A | 앱 전역 하드코딩 색상 sweep으로 일반 화면의 시스템 라이트 색상을 추가 토큰화했다. | AppCoordinator, ConfirmView, BannerView, BottomActionSheetView, ChatBannerView |
| Phase 7B | 탭별 최종 smoke QA 체크리스트를 기준으로 전체 앱 다크 모드 마감 검수를 완료했다. | 수동 QA 체크리스트 |

## 변경 파일 인덱스

하네스/결정 문서:

- `docs/ai/tasks/dark-theme-system/design.md`
- `docs/ai/tasks/dark-theme-system/decisions.md`
- `docs/ai/tasks/dark-theme-system/plan.md`
- `docs/ai/tasks/dark-theme-system/progress.md`
- `docs/ai/tasks/active.md`
- `HANDOFF.md`
- `docs/ai/ADR.md`

전역 테마/앱 appearance:

- `OutPick/DesignSystem/OutPickTheme.swift`
- `OutPick/Assets.xcassets/AccentColor.colorset/Contents.json`
- `OutPick/App/AppDelegate.swift`
- `OutPick/Info.plist`

공통 chrome/share 컴포넌트:

- `OutPick/App/TabBarController/MainTab`
- `OutPick/UINavigationControllerManager`
- `OutPick/Infra/ShareView`
- `OutPick/Infra/Toast/AppToastView.swift`

룩북 화면군:

- `OutPick/Features/Lookbook/Views/Shared`
- `OutPick/Features/Lookbook/Views/LookbookHome`
- `OutPick/Features/Lookbook/Views/Liked`
- `OutPick/Features/Lookbook/Views/BrandDetail`
- `OutPick/Features/Lookbook/Views/SeasonDetail`
- `OutPick/Features/Lookbook/Views/PostDetail`
- `OutPick/Features/Lookbook/Views/CreateBrand`

채팅 화면군:

- `OutPick/Features/Chat/Controllers/RoomListsCollectionViewController.swift`
- `OutPick/Features/Chat/Controllers/JoinedRoomsViewController.swift`
- `OutPick/Features/Chat/Controllers/RoomSearchViewController.swift`
- `OutPick/Features/Chat/Views/Cell/RoomListCollectionViewCell.swift`
- `OutPick/Infra/ShareView/CustomNavigationBar/CustomNavigationBarView.swift`
- `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- `OutPick/Features/Chat/Views/ChatUIView.swift`
- `OutPick/Features/Chat/Views/AttachmentView.swift`
- `OutPick/Features/Chat/Views/ChatReplyView.swift`
- `OutPick/Features/Chat/Views/ChatSearchUIView.swift`
- `OutPick/Features/Chat/Views/ChatMessageCollectionView.swift`
- `OutPick/Features/Chat/Views/ChatNotiView.swift`
- `OutPick/Features/Chat/Views/ChatCustomPopUpMenu.swift`
- `OutPick/Features/Chat/Views/AnnouncementBannerView.swift`
- `OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift`
- `OutPick/Features/Chat/Views/Cell/ChatImagePreviewCell.swift`
- `OutPick/Features/Chat/Views/Cell/DateSeperatorCell.swift`
- `OutPick/Features/Chat/Views/Cell/readMarkCollectionViewCell.swift`
- `OutPick/Features/Chat/Controllers/ChatRoomSettingViewController.swift`
- `OutPick/Features/Chat/Views/Cell/ChatRoomSetting`
- `OutPick/Features/Chat/Controllers/RoomCreateViewController.swift`
- `OutPick/Features/Chat/Views/RoomCreateContentView.swift`
- `OutPick/Features/Chat/Controllers/RoomEditViewController.swift`
- `OutPick/Features/Chat/Views/Cell/ChatRoomEdit`
- `OutPick/Features/Chat/Views/MediaGalleryViewController.swift`

## 검증 상태

통과:

- `jq empty OutPick/Assets.xcassets/AccentColor.colorset/Contents.json`
- `plutil -lint OutPick/Info.plist`
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- `git diff --check`

색상 검색:

- Phase 3 대상 경로에서 직접 색상 검색을 수행했고, 남은 결과는 문자열/변수명 false positive로 확인했다.
- Phase 4A 대상 경로에서 직접 색상 검색을 수행했고, 남은 결과는 테마 토큰 사용 또는 변수명 false positive로 확인했다.
- Phase 4B 대상 경로에서 라이트 배경/검정 텍스트 직접 지정 누수를 정리했다. 남은 `Color.black`, `.white`, `Color.clear`는 이미지 overlay, media viewer, 투명 placeholder 예외로 확인했다.
- Phase 4C 대상 경로에서 라이트 배경/검정 텍스트 직접 지정 누수를 정리했다. 남은 `Color.black`, `.white`는 `PostImagePreviewView` media viewer 예외로 확인했다.
- Phase 5A 대상 경로에서 직접 색상 검색을 수행했고, 남은 결과는 `OutPickTheme` 토큰 사용으로 확인했다.
- Phase 5B 대상 경로에서 직접 색상 검색을 수행했고, 남은 `.black`, `.white`, `UIColor.black` 계열은 이미지/비디오 badge, 업로드 overlay, AVPlayer 저장 버튼 등 media overlay 예외로 확인했다.
- Phase 5C 설정 화면 일부 대상 경로에서 직접 색상 검색을 수행했고, 남은 `.black`, `.white`, `UIColor.black` 계열은 미디어 preview play badge overlay 예외로 확인했다.
- Phase 5C 생성/편집/미디어 갤러리 대상 경로에서 직접 색상 검색을 수행했고, 남은 `.black`, `.white`, `UIColor.black` 계열은 전체 화면 image/video viewer, save/close overlay, play badge 예외로 확인했다.
- Phase 6 대상 경로에서 직접 색상 검색을 수행했고, 남은 `.black`/`.white` 계열은 font weight 또는 문자열 trim false positive로 확인했다.
- Phase 7A 전역 검색에서 일반 화면의 `systemBackground`, `secondarySystemBackground`, `systemBlue`, `secondaryLabel`, `label` 잔여를 추가 정리했다. 남은 `.black`/`.white` 계열은 media viewer, 이미지/비디오 badge, dim scrim, shadow, 이미지 gradient overlay 예외로 확인했다.

사용자 수동 QA:

- Phase 3 탭바, 네비게이션, 공통 컴포넌트 수동 QA 완료.
- Phase 4A 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트 수동 QA 완료.
- Phase 4Nav 룩북 SwiftUI 공통 네비게이션 바 수동 QA 완료.
- Phase 4B 브랜드 상세, 시즌 상세, 포스트 상세 수동 QA 완료.
- Phase 4C 댓글, sheet, 생성/import 플로우 수동 QA 완료.
- Phase 5A 채팅 탭 root/list/search 화면 수동 QA 완료.
- Phase 5B 채팅방 핵심 화면 수동 QA 완료.
- Phase 5C 방 생성/편집/설정/미디어 화면 수동 QA 완료.
- Phase 6 프로필, 마이페이지, 로그인/부트 화면 수동 QA 완료.
- Phase 7 최종 앱 smoke QA 완료.

기존 빌드 경고:

- `LoadChatRoomParticipantsUseCase` Swift 6 actor-isolation 경고.
- 일부 `contentEdgeInsets`/`windows` deprecation 경고.
- `functions/node_modules/@unrs/resolver-binding-darwin-arm64` search path 누락 경고.
- 위 경고들은 이번 다크 모드 변경으로 새로 만든 오류는 아니며, 빌드는 성공했다.
