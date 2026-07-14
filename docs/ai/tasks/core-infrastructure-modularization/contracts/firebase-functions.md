# Firebase Functions Contract Inventory

## 현재 경계

- 진입점: `functions/src/index.ts`.
- bootstrap: `admin.initializeApp()`, `getFirestore()`, `setGlobalOptions({maxInstances: 10})`.
- 공통 region: `asia-northeast3`.
- export: callable 43개, Firestore trigger 3개, scheduler 3개, 총 49개.
- 배포 단위: Firebase default codebase를 유지한다.

## callable export 기준선

모든 callable은 기존 export 이름, payload/response와 `HttpsError` code 의미를 유지한다.

| target module | export 이름 |
| --- | --- |
| `auth/` | `exchangeKakaoToken` |
| `brand/admin/` | `getBrandAdminCapabilities`, `createBrand`, `updateBrand`, `addBrandManager`, `removeBrandManager`, `updateBrandLogoPaths` |
| `brand/requests/` | `submitBrandRequest`, `listMyBrandRequests`, `listBrandRequests`, `listBrandRequestGroups`, `updateBrandRequestStage`, `updateBrandRequestGroupStage`, `resolveBrandRequestGroup`, `markBrandRequestGroupBrandCreated`, `resolveBrandRequest`, `searchBrands` |
| `lookbook/deletion/` | `requestBrandDeletion`, `cancelBrandDeletion`, `softDeleteSeason`, `batchSoftDeleteSeasons`, `restoreSeason`, `softDeletePost`, `batchSoftDeletePosts`, `restorePost`, `listLookbookDeletionRequests`, `retryFailedLookbookDeletionPurge` |
| `lookbook/engagement/` | `setBrandEngagement`, `setPostEngagement`, `setSeasonEngagement`, `setCommentEngagement` |
| `lookbook/comments/` | `createComment`, `createReply`, `deleteComment` |
| `lookbook/safety/` | `reportComment`, `blockUser`, `loadHiddenCommentUserIDs` |
| `lookbook/import/` | `requestSeasonImport`, `requestSeasonAssetRetry`, `requestSeasonCandidateImportJobs`, `runLookbookExtractionDiagnostic`, `getLatestLookbookExtractionDiagnostic`, `discoverSeasonCandidates` |

## trigger와 scheduler 기준선

| export | type / source | runtime option | target module |
| --- | --- | --- | --- |
| `onLookbookDeletionManualRetryQueued` | Firestore update `lookbookDeletionRequests/{requestID}` | region, 540s, 1GiB | `lookbook/deletion/` |
| `purgeExpiredLookbookDeletions` | schedule `0 4 * * *` | Asia/Seoul, 540s, 1GiB | `lookbook/deletion/` |
| `onSeasonImportQueued` | Firestore write `brands/{brandID}/importJobs/{jobID}` | region, 60s, 256MiB | `lookbook/import/` |
| `onRoomClosed` | Firestore update `Rooms/{roomId}` | region | `chat/cleanup/` |
| `cleanupExpiredChatMediaUploads` | schedule `0 4 * * *` | Asia/Seoul | `chat/cleanup/` |
| `cleanupExpiredLookbookExtractionDiagnostics` | schedule `30 4 * * *` | Asia/Seoul | `lookbook/import/` |

## callable별 예외 runtime option

- 기본: `{region: FUNCTIONS_REGION}`.
- `requestSeasonCandidateImportJobs`: timeout 120s, memory 512MiB.
- `runLookbookExtractionDiagnostic`: timeout 120s, memory 512MiB.
- `discoverSeasonCandidates`: timeout 60s, memory 512MiB.
- 나머지 runtime option은 현재 `index.ts` 선언을 그대로 비교한다.

## Cloud Tasks와 worker HTTP 계약

- 기본 location: `asia-northeast3`; 환경 변수 `OUTPICK_LOOKBOOK_IMPORT_TASKS_LOCATION`으로 override 가능.
- 기본 queue: `lookbook-import-jobs`; 환경 변수 `OUTPICK_LOOKBOOK_IMPORT_TASKS_QUEUE`로 override 가능.
- import/asset retry endpoint: worker base URL + `/tasks/import-job`.
- discovery diagnostic endpoint: worker base URL + `/tasks/discover-seasons-diagnostic`.
- OIDC service account와 audience는 현재 runtime 환경 변수 계약을 유지한다.
- task ID는 brand/job 또는 asset retry 식별자에서 deterministic하게 생성해 중복 요청을 `ALREADY_EXISTS`로 처리한다.
- import payload의 `brandID`, `jobID`, `maxAttempts`, `requestedAt`과 asset retry payload의 mode/season/source/request key를 유지한다.

## 기존 분리 module과 재사용 기준

- `lookbookDeletionPurgeDrain.ts`와 test: deletion orchestration을 유지하며 새 feature 폴더로 이동 가능하다.
- `lookbookDeletionPurgeLease.ts`와 test: deletion lease 정책을 유지한다.
- `lookbookSeasonCandidateDiscovery.ts`, `lookbookSeasonCandidateParser.ts`: import module 내부 service 후보다.
- 이동 시 import path만 바꾸고 정책, query, retry/idempotency 의미는 함께 변경하지 않는다.

## 목표 source 구조

- `core/`: Firebase Admin/Firestore bootstrap, runtime constants, 여러 feature가 공유하는 검증된 primitive.
- `auth/`, `brand/`, `lookbook/`, `chat/`: handler, service, validator, mapper를 기능별로 소유한다.
- `index.ts`: bootstrap 의존을 한 번 초기화하고 기존 이름으로 handler를 flat export한다.
- feature 간 직접 import를 피하고 정말 공유되는 의존성만 `core/`로 올린다.

Phase 4 D20~D26에서 `core`는 infrastructure, 여러 feature가 공유하는 도메인 정책은 `shared`, 나머지는 feature-local로 구분했다. `index.ts`는 wildcard 없이 이 문서의 49개 이름만 명시적으로 flat export한다. 상세는 `../decisions/phase-4-firebase-functions.md`를 따른다.

## 초기화와 부작용 계약

- Admin SDK 초기화와 global option 설정은 process당 한 소유자에서 한 번 수행한다.
- module import 자체가 중복 trigger 등록이나 추가 초기화를 만들지 않아야 한다.
- Firestore transaction/batch, Cloud Tasks, Storage 삭제, notification 등 현재 handler의 부작용 순서를 보존한다.
- trigger path와 schedule/timezone은 파일 이동과 무관한 운영 계약이다.

## test 발견 규칙 위험

현재 `functions/package.json`의 test 명령은 build 후 `lib/*.test.js`만 실행한다. test를 하위 feature 폴더로 옮길 경우 glob이 누락되므로 Phase 4에서 하위 디렉터리 test가 실제 실행되도록 명령을 조정하고 검증한다.

## Phase 4 회귀 기준

- build 산출물의 49개 export 이름을 변경 전 snapshot과 비교한다.
- runtime option, trigger path, schedule/timezone을 표와 비교한다.
- `npm test`, `npm run lint`, `npm run build`를 통과한다.
- circular import와 Admin SDK 중복 초기화가 없어야 한다.
- 운영 배포는 별도 사용자 승인 전 수행하지 않는다.
