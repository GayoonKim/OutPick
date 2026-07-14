# Lookbook Entrypoints

## 목적과 탐색 순서

Lookbook 변경 시 필요한 코드만 찾기 위한 인덱스다.

1. 화면/사용자 흐름 변경: 이 문서의 화면 표
2. 데이터/API 변경: `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`
3. 장기 기술 결정: `docs/ai/ADR.md`
4. 완료 상태·QA: 관련 task의 `progress.md`, `qa-checklist.md`

## 공통 조립

| 책임 | 진입점 |
| --- | --- |
| 앱 탭 조립 | `OutPick/Features/Lookbook/LookbookCompositionRoot.swift` |
| Feature DI/factory | `OutPick/Features/Lookbook/LookbookContainer.swift` |
| 화면 전환 | `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift` |
| 댓글 전환 | `OutPick/Features/Lookbook/Coordinators/PostCommentCoordinator.swift` |
| Repository 조립 | `OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift` |
| SwiftUI environment | `OutPick/Features/Lookbook/Environment` |
| 공용 store | `OutPick/Features/Lookbook/Domains/Stores` |
| DTO/mapper | `OutPick/Features/Lookbook/Models` |
| 이미지/미디어 | `OutPick/Features/Lookbook/Services` |

- Lookbook/Liked root는 UIKit navigation stack 위 SwiftUI Hosting 구조다.
- 상세 push/pop은 SwiftUI hidden route가 아니라 `LookbookCoordinator`가 소유한다.
- View는 Repository/Firebase를 직접 만들지 않고 Container가 주입한다.
- SwiftUI 입력 화면 키보드 dismiss는 `KeyboardDismissSupport.outpickDismissKeyboardOnTap()`을 사용한다.
- Firestore 기본 identity는 ADR-020에 따라 문서 경로 ID를 사용한다. read DTO는 `Decodable`, Season write payload는 `SeasonWriteDTO`로 분리한다.

## Firestore 문서 ID 경계

| 확인할 내용 | 코드 진입점 |
| --- | --- |
| read schema와 DTO→Domain mapping | `OutPick/Features/Lookbook/Models/DTOs/`; identity가 필요한 mapper의 `toDomain(documentID:)` |
| snapshot 경로 ID 전달 | `OutPick/Features/Lookbook/Repositories/Implementations/Firestore*Repository.swift` |
| 브랜드·시즌·포스트 기본 identity | `BrandDTO.swift`, `SeasonDTO.swift`, `PostDTO.swift`와 각 Firestore Repository |
| 댓글·replacement 기본 identity | `CommentDTO.swift`, `ReplacementDTO.swift`와 `FirestoreCommentRepository.swift`, `FirestoreReplacementRepository.swift` |
| 태그·alias·concept 기본 identity | `TagDTO.swift`, `TagAliasDTO.swift`, `TagConceptDTO.swift`와 각 Firestore Repository |
| import job·candidate 기본 identity | `SeasonImportJobDTO.swift`, `SeasonCandidateDTO.swift`와 각 Firestore Repository |
| Season 생성 write payload | `SeasonWriteDTO.swift`, `FirestoreSeasonRepository.swift`의 create 경로 |
| 경계 회귀 테스트 | `OutPickTests/FirestoreDocumentIDBoundaryTests.swift` |

Repository가 `DocumentSnapshot.documentID`를 같은 snapshot에서 decode한 DTO와 함께 mapper에 전달한다. 자기 문서 ID는 DTO 필드로 중복 저장하지 않으며, `brandID`, `postID`, `userID`처럼 부모 경로나 별도 query 계약을 나타내는 ID는 해당 데이터 계약대로 유지한다.

## 화면별 진입점

| 변경 목적 | View | ViewModel/상태 |
| --- | --- | --- |
| 홈·검색 | `Views/LookbookHome/LookbookHomeView.swift` | `ViewModels/LookbookHomeViewModel.swift` |
| 브랜드 요청 | `Views/BrandRequest` | `BrandRequestViewModel.swift`, `MyBrandRequestsViewModel.swift` |
| 브랜드 상세 | `Views/BrandDetail/BrandDetailView.swift` | `BrandDetailViewModel.swift` |
| 시즌 상세 | `Views/SeasonDetail/SeasonDetailView.swift` | `SeasonDetailViewModel.swift` |
| 포스트·댓글 | `Views/PostDetail` | `PostDetailViewModel.swift`, `PostCommentsViewModel.swift` |
| 좋아요 | `Views/Liked` | `LikedViewModel.swift` |
| 브랜드 생성 | `Views/CreateBrand/brand` | `CreateBrandViewModel.swift`, `CreateBrandFlowView.swift` |
| 시즌 직접 생성 | `Views/CreateBrand/season/CreateSeasonView.swift` | `CreateSeasonViewModel.swift`; production 조립·표시 호출부가 없어 현재 앱 진입 불가 |
| 관리자 홈 | `Views/Admin/LookbookAdminHomeView.swift` | `BrandAdminSessionStore` |
| 브랜드 요청 관리 | `Views/Admin/AdminBrandRequestGroupsView.swift` | `AdminBrandRequestGroupsViewModel.swift` |
| 브랜드 관리 | `Views/Admin/AdminBrandManagementView.swift` | `AdminBrandManagementViewModel.swift` |
| 삭제 관리 | `Views/Admin/AdminLookbookDeletionManagementView.swift` | `AdminLookbookDeletionManagementViewModel.swift` |
| import 현황 | `Views/BrandDetail/SeasonImportManagementView.swift` | `SeasonImportManagementViewModel.swift` |

경로 prefix는 `OutPick/Features/Lookbook/`이다.

## 자주 수정하는 흐름

### 브랜드 상세

읽기 순서:

1. `BrandDetailView.swift`
2. `BrandDetailViewModel.swift`
3. `BrandRepositoryProtocol.swift`, `SeasonRepositoryProtocol.swift`
4. 관련 repository implementation
5. `LookbookContainer.swift`, `LookbookCoordinator.swift`

현재 계약:

- 초기 `Brand` snapshot으로 빠르게 표시한 뒤 단건 브랜드와 시즌 목록을 최신화한다.
- pull-to-refresh는 브랜드, interaction state, 시즌을 함께 갱신한다.
- 삭제 요청 등 사용자 비노출 상태면 상세 상태를 비우고 unavailable을 표시한다.
- 관리자 수정 결과는 `applyUpdatedBrand(_:)`로 상세 상태에 반영한다.
- 이미지 확대는 공용 `LookbookImageViewerView`/Infra UIKit viewer를 사용한다. 선택 이유는 ADR-017.

### 관리자 브랜드 요청

읽기 순서:

1. `AdminBrandRequestGroupsView.swift`
2. `AdminBrandRequestGroupsViewModel.swift`
3. `Domains/Entities/BrandRequest.swift`
4. `ListBrandRequestGroupsUseCase.swift`
5. `BrandRequestRepositoryProtocol.swift`
6. `CloudFunctionsBrandRequestRepository.swift`

현재 계약:

- segment는 `새 요청/처리 중/보류/완료`다.
- `보류/완료`는 최근 14일을 기본 표시하고 이전 기록은 별도 pagination한다.
- 브랜드 생성과 검수 완료는 분리한다.
- 삭제 요청 목록의 `active/failed` 정책과 혼동하지 않는다.

### 관리자 브랜드·시즌 관리

읽기 순서:

1. `AdminBrandManagementView.swift`
2. `AdminBrandManagementViewModel.swift`
3. `Domains/Entities/BrandManagement.swift`
4. 관련 repository/use case
5. `LookbookContainer.swift`

현재 계약:

- 총 관리자와 브랜드 owner/admin 권한을 분리한다.
- 메뉴는 정보, 관리자, 시즌 가져오기, 삭제 흐름으로 구성한다.
- 시즌 가져오기는 후보 discovery와 import job 현황을 분리한다.
- 실제 worker 구조는 `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`를 먼저 본다.

### 삭제 관리 화면

읽기 순서:

1. `Views/Admin/AdminLookbookDeletionManagementView.swift`
2. `ViewModels/AdminLookbookDeletionManagementViewModel.swift`
3. `Domains/Entities/LookbookDeletionRequest.swift`
4. `Repositories/Protocols/LookbookDeletionRepositoryProtocol.swift`
5. `Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
6. `Repositories/Implementations/CloudFunctionsMappers/LookbookDeletionCloudFunctionsMapper.swift`
7. `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
8. `docs/ai/entrypoints/FIREBASE.md`의 삭제 lifecycle

현재 계약:

- 앱 목록은 `active/failed`만 표시한다. 완료/history picker는 없다.
- 총 관리자 전역 목록은 브랜드별로 묶고, 브랜드 관리 내부는 해당 브랜드로 scope한다.
- 총 관리자만 브랜드 삭제 요청/복구와 failed manual retry를 수행한다.
- 브랜드 owner/admin은 해당 브랜드의 시즌·포스트 삭제/복구만 수행한다.
- owner/admin failed 문구는 실행 중/자동 재시도와 최종 실패를 구분한다.
- 다음 page는 목록 전체 하단 sentinel이 요청하며 `requestID`로 중복 제거한다.
- 상세 정책과 검증: `docs/ai/tasks/lookbook-deletion-request-list-simplification/`.

## Domain·Repository 지도

| 영역 | Entity/Store | Repository/UseCase |
| --- | --- | --- |
| 브랜드 | `Brand.swift`, `BrandUserState.swift`, `BrandInteractionStore` | `BrandRepositoryProtocol`, brand use cases |
| 시즌 | `Season.swift`, `SeasonUserState.swift`, `SeasonInteractionStore` | `SeasonRepositoryProtocol`, season use cases |
| 포스트 | `LookbookPost.swift`, `PostUserState.swift`, `PostInteractionStore` | `PostRepositoryProtocol`, post use cases |
| 댓글 | `Comment.swift`, `CommentUserState.swift`, `CommentInteractionStore` | comment repository/use cases |
| 관리자 | `BrandManagement.swift`, `BrandRequest.swift` | brand admin/request repository/use cases |
| 삭제 | `LookbookDeletionRequest.swift` | `LookbookDeletionRepositoryProtocol` |
| import | `SeasonImportJob.swift`, `SeasonCandidate.swift`, `LookbookExtractionDiagnostic.swift` | import/discovery repositories |

- protocol은 `Domains/UseCases`, `Repositories/Protocols`에서 찾는다.
- 외부 구현은 `Repositories/Implementations`, DTO는 `Models/DTOs`, 변환은 `Models/Mapper`에서 찾는다.
- 기본 identity가 필요한 DTO mapper는 `documentID`를 명시적으로 받고, Repository가 `DocumentSnapshot.documentID`를 전달한다.
- `SeasonDTO`는 read-only이며 생성 write는 `Models/DTOs/SeasonWriteDTO.swift`를 사용한다.
- 상호작용 정합성은 `LookbookInteractionStore`와 대상별 store를 먼저 확인한다.

## 이미지·공유·Navigation

### 이미지

- 공용 로딩/캐시: `Services/ImageLoading`.
- 확대 viewer: `Navigation/LookbookImageViewerView.swift`와 Infra viewer.
- 같은 Storage path 덮어쓰기 시 `updatedAt` 기반 cache invalidation을 확인한다.

### Chat 공유

- Lookbook 쪽 payload/bridge: `OutPick/Features/Lookbook/`의 share 관련 View/Navigation.
- Chat 접합부: `docs/ai/entrypoints/CHAT.md`.
- snapshot/상세 최신화 결정: ADR-011~013.

### URL 기반 시즌 import

- 앱: `CreateBrandCandidateSelectionView.swift`, `AdminBrandManagementView.swift`, `SeasonImportManagementView.swift`.
- repository: `CloudFunctionsSeasonCandidateDiscoveryRepository.swift`와 import repository.
- Functions/worker: `docs/ai/entrypoints/FIREBASE.md`, `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`.

## 변경 시 함께 갱신할 문서

- 화면·DI·Coordinator 위치: 이 문서와 `docs/ai/ENTRYPOINTS.md`.
- 데이터/API: `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`.
- 장기 선택: 새 ADR 또는 기존 ADR.
- phase 상태와 QA: 관련 task의 `progress.md`, `qa-checklist.md`.
