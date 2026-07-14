# OutPick Screen Spec

## 목적

OutPick의 화면 구성과 화면별 책임을 AI 에이전트가 빠르게 확인하기 위한 문서다.

## 작성 원칙

- 화면에는 사용자가 실제로 필요한 정보와 액션만 둔다.
- 요청하지 않은 부가 화면을 만들지 않는다.
- 화면 이동이 2단계 이상 이어지거나 modal/sheet/push 정책이 섞이면 Coordinator 책임을 먼저 검토한다.
- 화면별 상세 구현은 관련 `View`, `ViewModel`, `Coordinator`, `Container` 진입점을 함께 기록한다.

## 앱/루트 화면

### Boot Loading

- 파일: `OutPick/Features/Login/Presentation/BootLoadingViewController.swift`
- 책임: 앱 시작 후 로그인/프로필/메인 탭 라우팅 전 임시 로딩 화면을 제공한다.
- 진입: `AppCoordinator.start`, `AppCoordinator.routeAfterAuthenticated`

### Login

- 파일: `OutPick/Features/Login/Presentation/LoginViewController.swift`
- ViewModel: `OutPick/Features/Login/Presentation/LoginViewModel.swift`
- 조립: `OutPick/Features/Login/Presentation/LoginCompositionRoot.swift`
- 책임: 소셜 로그인 진입과 로그인 성공 callback 전달.

### Main Tab

- 파일: `OutPick/App/TabBarController/MainTab/CustomTabBarViewController.swift`
- 조립: `OutPick/App/TabBarController/Composition/MainTabCompositionRoot.swift`
- 탭 builder: `OutPick/App/TabBarController/Composition/DefaultMainTabBuilder.swift`
- 현재 탭: 채팅 목록, 참여 채팅방, 룩북, 좋아요, 마이페이지.

## Profile 화면

### First/Second Profile

- 파일: `OutPick/Features/Profile/Views/FirstProfileViewController.swift`
- 파일: `OutPick/Features/Profile/Views/SecondProfileViewController.swift`
- ViewModel: `FirstProfileViewModel`, `SecondProfileViewModel`
- Coordinator: `ProfileCoordinator`
- 책임: 프로필 생성/완성 흐름.

### User Profile Detail

- 파일: `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`
- ViewModel: `UserProfileDetailViewModel`
- Coordinator: `UserProfileDetailCoordinator`
- 책임: 사용자 프로필 상세 표시.

## Chat 화면

### Room Lists

- 파일: `OutPick/Features/Chat/Controllers/RoomListsCollectionViewController.swift`
- ViewModel: `RoomListsViewModel`
- 조립: `ChatCompositionRoot.makeRoomListRoot`
- 책임: 채팅방 목록 표시와 방 진입.

### Joined Rooms

- 파일: `OutPick/Features/Chat/Controllers/JoinedRoomsViewController.swift`
- ViewModel: `JoinedRoomsViewModel`
- 조립: `ChatCompositionRoot.makeJoinedRoomsRoot`
- 책임: 참여 중인 채팅방 목록 표시.

### Chat Room

- 파일: `OutPick/Features/Chat/Controllers/ChatViewController.swift`
- ViewModel: `ChatRoomViewModel`
- Coordinator: `ChatCoordinator`
- 책임: 채팅 메시지, 첨부, 답장, 미디어 흐름.
- 룩북 공유 카드: `messageType = lookbookShare` 메시지는 compact 카드로 표시한다. 카드는 `sharedContent` snapshot만 사용하고 원본 룩북 데이터는 조회하지 않는다.

### Chat Supporting Screens

- 방 생성: `RoomCreateViewController`, `RoomCreateViewModel`
- 방 편집: `RoomEditViewController`, `RoomEditViewModel`
- 방 검색: `RoomSearchViewController`, `RoomSearchViewModel`
- 방 설정: `ChatRoomSettingViewController`, `ChatRoomSettingViewModel`
- 미디어 갤러리: `MediaGalleryViewController`

## Lookbook 화면

### Lookbook Home

- 파일: `OutPick/Features/Lookbook/Views/LookbookHome/LookbookHomeView.swift`
- ViewModel: `LookbookHomeViewModel`
- 조립: `LookbookCompositionRoot.makeRoot`
- Coordinator: `LookbookCoordinator`
- 책임: 룩북 홈과 브랜드 목록 진입.

### Brand Detail

- 파일: `OutPick/Features/Lookbook/Views/BrandDetail/BrandDetailView.swift`
- ViewModel: `BrandDetailViewModel`
- factory: `LookbookContainer.makeBrandDetailView`
- 책임: 브랜드 상세, 시즌 목록, 브랜드 좋아요 상태 표시/변경.
- 공유: `공식 사이트 방문` 옆에 공유 버튼을 둔다. 버튼 탭 시 내부 채팅방 공유 sheet를 연다.

### Season Detail

- 파일: `OutPick/Features/Lookbook/Views/SeasonDetail/SeasonDetailView.swift`
- ViewModel: `SeasonDetailViewModel`
- factory: `LookbookContainer.makeSeasonDetailView`
- 책임: 시즌 상세, 시즌 좋아요 상태 표시/변경, 시즌 내 포스트 탐색.
- 공유: 좋아요 수/액션 영역 옆에 공유 버튼을 둔다. 버튼 탭 시 내부 채팅방 공유 sheet를 연다.

### Post Detail and Comments

- 파일: `OutPick/Features/Lookbook/Views/PostDetail/PostDetailView.swift`
- ViewModel: `PostDetailViewModel`
- 댓글 ViewModel: `PostCommentsViewModel`, `PostCommentRepliesViewModel`
- Coordinator: `LookbookCoordinator`, `PostCommentCoordinator`
- 책임: 포스트 상세, 댓글/대댓글, 신고, 삭제, 차단, 상호작용.
- 공유: 좋아요, 댓글 버튼 옆에 공유 버튼을 둔다. 포스트에는 독립 title이 없으므로 공유 snapshot title은 `포스트`, subtitle은 `브랜드명 · 시즌명`을 우선 사용한다.

### Lookbook Share Sheet

- 후보 파일: `OutPick/Features/Lookbook/Views/Share/LookbookShareSheetView.swift`
- 후보 ViewModel: `LookbookChatShareViewModel`
- 책임: 공유 대상 preview, 참여 중인 채팅방 단일 선택, 전송 상태, 빈/실패 상태, 전송 성공 완료 bar 연결.
- 상단 preview:
  - 브랜드: 썸네일, 브랜드명, `브랜드`
  - 시즌: 썸네일, 시즌명, 브랜드명
  - 포스트: 썸네일, `포스트`, `브랜드명 · 시즌명`
- 방 row: 대표 사진 + 방 이름만 표시한다.
- 전송 성공 UI: 현재 룩북 화면 위 하단 confirmation bar. 문구 `채팅방에 공유했어요`, 액션 `이동`, 보조 액션 `닫기`. 자동 사라짐은 사용하지 않는다.
- 빈 상태: `아직 참여 중인 채팅방이 없어요. 관심 가는 방에 참여한 뒤 공유해보세요.`
- 실패 상태: 방 목록 실패는 `채팅방을 불러오지 못했어요`, 전송 실패는 `공유하지 못했어요`.

### Create Brand/Season

- 폴더: `OutPick/Features/Lookbook/Views/CreateBrand`
- ViewModels: `CreateBrandViewModel`, `CreateSeasonViewModel`, `CreateSeasonFromURLViewModel`
- 책임: 브랜드 생성과 URL 기반 시즌 생성/가져오기. `CreateSeasonView`/`CreateSeasonViewModel` 구현은 남아 있지만 production 조립·표시 진입점은 없으며, 직접 시즌 생성 복원 또는 미사용 코드 제거는 별도 후속 후보다.

### Liked

- 파일: `OutPick/Features/Lookbook/Views/Liked/LikedView.swift`
- ViewModel: `LikedViewModel`
- 조립: `LookbookCompositionRoot.makeLikedRoot`
- factory: `LookbookContainer.makeLikedView`
- 책임: 좋아요 브랜드/시즌/포스트 섹션 표시.
- 현재 목표: 섹션별 독립 상태와 부분 실패 처리를 지원한다.

## MyPage 화면

- 파일: `OutPick/Features/MyPage/MyPageController/MyPageViewController.swift`
- 진입: `DefaultMainTabBuilder` index 4
- 확실하지 않음: 상세 화면 책임과 하위 흐름은 아직 이 문서에 정리되지 않았다.

## 새 화면 추가 기준

새 화면을 추가하기 전에 아래를 확인한다.

- 기존 탭/Coordinator/Container factory에 붙일 수 있는가?
- View가 직접 Repository, UseCase, Firebase, Cloud Functions, Firestore SDK를 생성하지 않는가?
- 화면 이동 책임이 Coordinator에 있는가?
- 요청 범위 밖 화면이 추가되지 않았는가?
- 완료 기준과 수동 QA 기준이 명확한가?
