# iOS Cloud Functions Contract Inventory

## 현재 경계

- 진입점: `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`.
- transport: `Functions.functions(region: "asia-northeast3")`.
- public surface: callable wrapper 40개와 `callHelloUser` debug API 1개.
- 공통 처리: callable 실행, dictionary 검증, 날짜/숫자 변환, 기능별 response mapping이 한 concrete type에 섞여 있다.
- `defaultFunctions`와 `callFunction`의 선택적 `functions` 인자는 현재 호출 경로에서 사용되지 않는다.

## 기능별 callable 계약

표의 입력/출력 key는 리팩터링 전후 유지 대상이다. Swift response model의 세부 optional/default mapping도 기존 구현을 기준으로 보존한다.

### 인증

| Swift API / callable | 입력 key | 출력 핵심 key | 현재 소비자 | 목표 capability |
| --- | --- | --- | --- | --- |
| `exchangeKakaoToken` | `accessToken` | `firebaseCustomToken`, `identityKey`, `providerUserID`, `email?` | `DefaultSocialAuthRepository` | `KakaoAuthBridgeCalling` |

### 브랜드 관리자

| Swift API / callable | 입력 key | 출력 핵심 key | 현재 소비자 | 목표 capability |
| --- | --- | --- | --- | --- |
| `getBrandAdminCapabilities` | 없음 | `isTotalAdmin`, `roles`, `ownedBrandIDs`, `adminBrandIDs` | `BrandAdminSessionStore` | `BrandAdminFunctionsCalling` |
| `createBrand` | `name`, `englishName?`, `isFeatured`, `websiteURL?`, `lookbookArchiveURL?` | `brandID` | `CloudFunctionsBrandStore` | 동일 |
| `updateBrand` | `brandID`, `name`, nullable URL/name, `isFeatured?` | `brand` | `CloudFunctionsBrandStore` | 동일 |
| `addBrandManager` | `brandID`, `email`, `role` | manager mutation receipt | `CloudFunctionsBrandStore` | 동일 |
| `removeBrandManager` | `brandID`, `email`, `role` | manager mutation receipt | `CloudFunctionsBrandStore` | 동일 |
| `updateBrandLogoPaths` | `brandID`, `logoThumbPath?`, `logoDetailPath?` | `brandID` | `CloudFunctionsBrandStore` | 동일 |

주의: `updateBrandLogoPaths` 경로는 주입된 manager 대신 `CloudFunctionsManager.shared`를 직접 사용한다. Phase 2에서 동일 capability 주입으로 통일한다.

### 브랜드 요청과 검색

| Swift API / callable | 입력 key | 출력 핵심 key | 현재 소비자 | 목표 capability |
| --- | --- | --- | --- | --- |
| `searchBrands` | `query`, `limit` | `brands` | `CloudFunctionsBrandSearchRepository` | `BrandRequestFunctionsCalling` |
| `submitBrandRequest` | `brandName`, `englishBrandName?` | `requestID`, `groupID`, `status`, `isDuplicate`, `remainingToday` | `CloudFunctionsBrandRequestRepository` | 동일 |
| `listMyBrandRequests` | `scope`, `limit`, cursor keys? | `requests`, `nextCursor`, `scope` | 동일 | 동일 |
| `listBrandRequestGroups` | filters, `limit`, cursor keys? | `groups`, `nextCursor` | 동일 | 동일 |
| `updateBrandRequestGroupStage` | `groupID`, `adminStage`, notes? | `groupID`, `status`, `adminStage`, `updatedRequestCount` | 동일 | 동일 |
| `resolveBrandRequestGroup` | `groupID`, `resolvedBrandID`, `adminNote?` | group mutation receipt | 동일 | 동일 |
| `markBrandRequestGroupBrandCreated` | `groupID`, `createdBrandID` | group mutation receipt | 동일 | 동일 |

서버에는 iOS wrapper가 없는 `listBrandRequests`, `updateBrandRequestStage`, `resolveBrandRequest`도 존재한다. 서버 export는 보존하며 새 iOS API 추가는 이번 리팩터링 범위가 아니다.

### 룩북 상호작용

| Swift API / callable | 입력 key | 출력 핵심 key | 현재 소비자 | 목표 capability |
| --- | --- | --- | --- | --- |
| `setBrandEngagement` | `brandID`, `isLiked` | IDs, `isLiked`, `likeCount` | brand engagement repository | `LookbookEngagementFunctionsCalling` |
| `setPostEngagement` | `brandID`, `seasonID`, `postID`, `kind`, `isEnabled` | IDs, `isLiked`, `isSaved`, `metrics` | post engagement repository | 동일 |
| `setSeasonEngagement` | `brandID`, `seasonID`, `isLiked` | IDs, `isLiked`, `likeCount` | season engagement repository | 동일 |
| `setCommentEngagement` | IDs, `commentID`, `isLiked` | IDs, `parentCommentID`, `isLiked`, `likeCount` | comment engagement repository | 동일 |

### 댓글과 안전

| Swift API / callable | 입력 key | 출력 계약 | 현재 소비자 | 목표 capability |
| --- | --- | --- | --- | --- |
| `createComment` | `brandID`, `seasonID`, `postID`, `message` | 기존 comment mutation response | comment writing repository | `LookbookCommentFunctionsCalling` |
| `createReply` | 위 key + `parentCommentID` | 기존 reply mutation response | 동일 | 동일 |
| `deleteComment` | IDs, `commentID`, `reason?` | 기존 delete response | 동일 | 동일 |
| `reportComment` | reporter/target IDs와 snapshot, `reason`, `detail?` | 기존 report response | comment safety repository | `LookbookSafetyFunctionsCalling` |
| `blockUser` | `blockerUserID`, `blockedUserID`, nickname?, `source` | 기존 block response | user block repository | 동일 |
| `loadHiddenCommentUserIDs` | `currentUserID` | `hiddenUserIDs` | user block repository | 동일 |

### 시즌 import와 진단

| Swift API / callable | 입력 key | 출력 핵심 key | 현재 소비자 | 목표 capability |
| --- | --- | --- | --- | --- |
| `requestSeasonImport` | `brandID`, `seasonURL`, `sourceCandidateID?` | `jobID`, `status`, `seasonURL`, `sourceCandidateID`, `duplicate` | season import repository | `LookbookImportFunctionsCalling` |
| `requestSeasonAssetRetry` | `brandID`, `sourceJobID` | `sourceImportJobID`, `seasonID`, `status`, `duplicate` | asset retry repository | 동일 |
| `discoverSeasonCandidates` | `brandID` | `brandID`, `sourceURL`, `candidateCount` | 현재 참조 없음 | Phase 2에서 제거 |
| `requestSeasonCandidateImportJobs` | `brandID`, `candidateIDs` | IDs, job IDs, counts, failures | job requesting repository | 동일 |
| `runLookbookExtractionDiagnostic` | `brandID`, `type`, source IDs? | diagnostic | candidate discovery/diagnostic 경로 | 동일 |
| `getLatestLookbookExtractionDiagnostic` | `brandID`, `type`, `sourceImportJobID?` | optional diagnostic | 현재 참조 없음 | Phase 2에서 제거 |

### 룩북 삭제 lifecycle

| Swift API / callable | 입력 핵심 key | 출력 계약 | 현재 소비자 | 목표 capability |
| --- | --- | --- | --- | --- |
| `requestBrandDeletion`, `cancelBrandDeletion` | `brandID`와 기존 reason/request key | 기존 mutation receipt | deletion repository | `LookbookDeletionFunctionsCalling` |
| `softDeleteSeason`, `restoreSeason` | `brandID`, `seasonID`와 기존 reason key | 기존 mutation receipt | 동일 | 동일 |
| `batchSoftDeleteSeasons` | `brandID`, season ID 목록과 기존 reason key | 기존 batch receipt | 동일 | 동일 |
| `softDeletePost`, `restorePost` | `brandID`, `seasonID`, `postID`와 기존 reason key | 기존 mutation receipt | 동일 | 동일 |
| `batchSoftDeletePosts` | parent IDs, post ID 목록과 기존 reason key | 기존 batch receipt | 동일 | 동일 |
| `listLookbookDeletionRequests` | scope/filter/limit/cursor key | requests와 next cursor | 동일 | 동일 |
| `retryFailedLookbookDeletionPurge` | request 식별 key | 기존 retry receipt | 동일 | 동일 |

세부 key와 response decoding의 최종 비교 원본은 Phase 2 변경 직전의 `CloudFunctionsManager.swift`다. 리팩터링에서 의미를 바꾸지 않고 그대로 옮긴다.

## 직접 의존 현황과 전환 규칙

- `AppCompositionRoot`가 `BrandAdminSessionStore()`를 만들며 내부 기본값이 concrete singleton에 연결된다.
- `LookbookRepositoryProvider`의 여러 기본 repository가 manager 전체에 의존한다.
- 일부 repository는 생성자 주입을 사용하지만 일부 method는 `.shared`를 다시 참조한다.
- `RoomListsCollectionViewController.viewDidLoad`의 `callHelloUser`는 제거가 확정됐다.
- 목표 공통 경계는 SDK 호출과 공통 오류 변환만 맡는 `CloudFunctionsTransporting`이다.
- 기능 Client가 function name, payload, response mapping을 소유하고 Repository/Store는 필요한 capability Protocol만 받는다.

## 제거·보류 구분

- 제거 확정: `callHelloUser` public API와 화면 직접 호출.
- 제거 확정: `discoverSeasonCandidates`, `getLatestLookbookExtractionDiagnostic` iOS wrapper.
- 추가하지 않음 확정: 현재 iOS wrapper가 없는 서버 전용 callable 3개.

## Phase 2 회귀 기준

- region은 `asia-northeast3`로 유지한다.
- function name, payload nullability, response optional/default mapping을 fake transport로 검증한다.
- View/ViewController의 Functions 직접 호출과 승인 대상 `.shared` 참조가 0이어야 한다.
- phase 종료 시 `CloudFunctionsManager` giant public façade를 제거한다.
