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
| extraction 검토 | `Views/BrandDetail/LookbookExtractionReviewView.swift` | `LookbookExtractionReviewViewModel.swift` |
| 기존 시즌 보수 | `Views/BrandDetail/LookbookSeasonRepairView.swift` | `LookbookSeasonRepairViewModel.swift` |

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
| extraction review | `LookbookExtractionReview.swift` | `LookbookExtractionReviewRepositoryProtocol`, `ManageLookbookExtractionReviewUseCase` |
| existing-season repair | `LookbookSeasonRepair.swift` | `LookbookSeasonRepairRepositoryProtocol`, `ManageLookbookSeasonRepairUseCase` |

- protocol은 `Domains/UseCases`, `Repositories/Protocols`에서 찾는다.
- 외부 구현은 `Repositories/Implementations`, DTO는 `Models/DTOs`, 변환은 `Models/Mapper`에서 찾는다.
- 기본 identity가 필요한 DTO mapper는 `documentID`를 명시적으로 받고, Repository가 `DocumentSnapshot.documentID`를 전달한다.
- `SeasonDTO`는 read-only이며 생성 write는 `Models/DTOs/SeasonWriteDTO.swift`를 사용한다.
- 상호작용 정합성은 `LookbookInteractionStore`와 대상별 store를 먼저 확인한다.

## 이미지·공유·Navigation

### 이미지

- 공용 로딩/캐시: `Services/ImageLoading`.
- extraction review와 existing-season repair의 외부 이미지 preview는 `LookbookRemotePreviewImageLoader` 단일 인스턴스를 Container에서 공유한다. 메모리·디스크 캐시, 동일 요청 in-flight 병합, 중복 제거된 8개 window prefetch와 최대 동시 4개 다운로드를 사용한다.
- 공용 렌더링은 `Views/Shared/LookbookRemotePreviewImageView.swift`다. extraction review는 순번·제외 상태가 있는 가로 단일 행 `LazyHStack`, repair는 keep/add/reorder/remove-candidate 구역별 2열 `LazyVGrid`로 표시한다.
- 확대 viewer: `Navigation/LookbookImageViewerView.swift`와 Infra viewer.
- 같은 Storage path 덮어쓰기 시 `updatedAt` 기반 cache invalidation을 확인한다.

시즌 상세 목록 계약:

- `LoadSeasonDetailUseCase`는 source order 포스트를 첫 24개와 `PageCursor`로 반환하고, ViewModel이 cursor를 보존한다.
- 마지막 12개 카드 영역에서 다음 24개를 요청하며 `PostID` 중복 제거, 동일 cursor 동시 호출 차단, refresh generation 이전 결과 폐기를 적용한다.
- Firestore visibility filter로 빈 page가 반환돼도 `nextCursor`가 있으면 다음 page까지 이어서 조회한다.
- 첫 12개와 현재 위치 앞 32개 이미지를 prefetch하고, 다음 page가 append되면 새 이미지 최대 24개를 카드 노출 전에 즉시 큐에 등록한다.
- prefetch concurrency는 4로 제한해 공용 `ImageCachePipeline`의 네트워크 permit 6개 중 2개를 실제 visible image load에 남긴다. 저장은 `.memoryAndDisk`, 동일 경로 in-flight 병합과 중복 방지는 기존 pipeline과 ViewModel path set이 담당한다.
- load-more 실패는 기존 포스트를 유지하고 화면 하단 재시도를 제공한다.

### Chat 공유

- Lookbook 쪽 payload/bridge: `OutPick/Features/Lookbook/`의 share 관련 View/Navigation.
- Chat 접합부: `docs/ai/entrypoints/CHAT.md`.
- snapshot/상세 최신화 결정: ADR-011~013.
- 공유 완료 확인 UI: `Views/Shared/LookbookShareConfirmationBar.swift`와 `BrandDetailView.swift`, `SeasonDetailView.swift`, `PostDetailView.swift`.
- `채팅방으로 이동` 처리 중에는 로딩을 표시하고 이동·계속 보기 버튼과 interactive sheet dismiss를 모두 잠근다. 성공하면 확인 sheet를 닫고, 최신 유효 요청의 실제 실패만 오류 toast와 재시도를 허용한다.

### URL 기반 시즌 import

- 앱: `CreateBrandCandidateSelectionView.swift`, `AdminBrandManagementView.swift`, `SeasonImportManagementView.swift`.
- repository: `CloudFunctionsSeasonCandidateDiscoveryRepository.swift`와 import repository.
- review: `LookbookExtractionReviewView.swift`, `LookbookExtractionReviewViewModel.swift`, `CloudFunctionsLookbookExtractionReviewRepository.swift`.
- import 현황의 검토 action은 `LookbookCoordinator`가 상세 화면을 push하고 `LookbookContainer`가 Repository/UseCase/ViewModel을 조립한다.
- review 화면은 예상/발견 수량 방향을 기준으로 동작한다. 초과·예상 수 미확인은 불필요 후보 제외와 `승인`, 미달은 승인 없이 `누락된 이미지 알리기`, content hash 미완료는 승인 차단을 제공한다. correctionRequired 재분석은 총 관리자에게만 노출한다.
- review 초기 로딩 화면은 안내 문구 아래에 accent 색상의 큰 진행 표시를 배치한다.
- 두 review 화면의 외부 후보 이미지는 같은 remote preview loader/cache를 공유하며 URL별 중복 네트워크 요청을 병합한다.
- `원본과 다시 비교` 진행 화면은 설명 아래 accent `ProgressView`를 표시한다. diff가 없으면 상세 화면을 자동 종료하고 목록의 `원본과 다시 비교` 상태로 복귀하며, 실제 변경이 있을 때만 `변경 검토`로 전환한다.
- Functions/worker: `docs/ai/entrypoints/FIREBASE.md`, `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`.
- Cafe24 목록의 `collection_detail.html`처럼 section과 detail을 underscore로 연결한 상세 경로도 공통 discovery 후보로 인정한다. 이미지 링크와 제목 링크가 같은 URL로 분리된 목록은 URL 기준 병합으로 한 시즌 후보에 수렴한다.

## 변경 시 함께 갱신할 문서

- 화면·DI·Coordinator 위치: 이 문서와 `docs/ai/ENTRYPOINTS.md`.
- 데이터/API: `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`.
- 장기 선택: 새 ADR 또는 기존 ADR.
- phase 상태와 QA: 관련 task의 `progress.md`, `qa-checklist.md`.
