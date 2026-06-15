# Phase 11/12 Progress

## 상태

- Phase 11은 구현, Cloud Run 배포, smoke QA, 관리자 수동 QA까지 완료됐다.
- Phase 12는 코드 구현, 로컬 검증, 운영 배포, 실제 부분 실패 job smoke QA까지 완료됐다.
- 2026-06-15 사용자 수동 QA 기준으로 실제 브랜드 등록부터 시즌 추가까지 정상 경로 smoke QA도 완료됐다.
- 이전에 실패하던 HATCHINGROOM 브랜드 시즌 등록이 의도한 대로 성공했으므로 시즌 import 개선 작업은 종료 가능 상태다.

## Phase 11: import 이미지 추출 정확도

목표:

- 새 import부터 실제 룩북 본문 이미지로만 post를 생성한다.

완료 작업:

- Phase 11A: worker 파서 수정본 Cloud Run 배포.
- Phase 11A: HATCHINGROOM `product_no=3759`, `3760`, `3761` smoke QA.
- Phase 11B: Cafe24 archive 상세 회귀 테스트 보강.
- 2026-06-15 실제 HATCHINGROOM 브랜드 시즌 등록 회귀 확인.

확정 사항:

- 기존 HATCHINGROOM 관련 Firestore/Storage 데이터는 사용자가 삭제했으므로 별도 데이터 정리 작업은 진행하지 않는다.
- `archive-source-detail` 같은 본문 영역이 있으면 해당 영역을 최우선으로 사용한다.
- zoom/mobile/thumb/detail-info/order/payment/quantity/option 영역은 post 후보로 쓰지 않는다.
- 같은 이미지가 반복되면 canonical URL 기준으로 dedupe한다.

## Phase 12: Season Asset Failure Queue

목표:

- 실패 asset 재시도에서 새 retry import job 문서를 계속 생성하지 않는다.
- 실패 asset만 idempotent하게 재처리한다.

완료 작업:

- Cloud Run worker `lookbook-import-worker-00009-qc9` 배포, 100% traffic.
- Functions `requestSeasonAssetRetry(asia-northeast3)` 배포.
- 통제된 부분 실패 job `phase12-smoke-job-20260610084631`로 실제 앱 버튼 기반 E2E smoke QA 완료.
- smoke QA에서 새 `retrySeasonAssets` job이 생기지 않고 기존 post의 `thumbPath/detailPath`만 복구되는 것을 확인했다.
- smoke Firestore 문서와 Storage prefix `brands/phase12-smoke-brand-20260610084631/` 정리 완료.

확정 사항:

- `failureID`는 `postID_mediaIndex_remoteURLHash`처럼 deterministic하게 만든다.
- 성공하면 failure 문서를 삭제한다.
- 실패하면 같은 문서의 `attemptCount`, `lastErrorMessage`, `lastAttemptAt`을 갱신한다.
- 기존 `retrySeasonAssets` 문서는 앱 미운영 상태이므로 삭제할 필요가 없다.
- 일반 관리자 UI의 1차 정보는 URL/ID가 아니라 시즌명, 이미지 실패 개수, 재시도 상태로 둔다.
- 현재 Cloud Tasks `6 / 3sec` 설정은 유지한다. 더 큰 실제 운영 부하가 확인되면 상향을 재검토한다.
- 재시도 중복 방지는 원본 import job의 `assetRetryStatus`와 `assetRetryRequestID` marker로 처리한다.
- 재시도 버튼은 `assetRetryStatus=queued/processing` 동안 비활성화하고, 성공하면 완료 상태로 전환되며, 재실패하면 다시 활성화한다.

구현 완료:

- Functions `requestSeasonAssetRetry`는 더 이상 `retrySeasonAssets` import job을 만들지 않고, 원본 job에 retry marker를 기록한 뒤 `mode=assetFailureRetry` Cloud Task를 enqueue한다.
- Worker는 `mode=assetFailureRetry` task를 받아 `assetFailures`만 재처리한다.
- 초기 import 또는 재시도 중 post image 실패 시 `assetFailures/{failureID}`를 생성/갱신하고, 성공 시 삭제한다.
- 기존 `partialFailed` job에 failure queue가 없으면 재시도 시 `createdPostIDs`와 post media 누락 경로를 기준으로 lazy 생성한다.
- iOS 가져오기 현황은 원본 `importSeasonFromURL` job만 표시하고, retry job/URL/문서 ID 대신 `seasonTitle/sourceTitle` 기반 제목과 재시도 상태를 표시한다.

로컬 검증:

- Functions `npm run lint`, `npm run build` 통과.
- Worker `npm run lint`, `npm run build`, `npm test` 통과. 최신 테스트 15개.
- iOS `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.

운영 smoke QA:

- smoke brand: `phase12-smoke-brand-20260610084631`
- smoke season: `phase12-smoke-season-20260610084631`
- smoke post: `phase12-smoke-post-000`
- smoke job: `phase12-smoke-job-20260610084631`
- fixture 상태:
  - 원본 job `status=partialFailed`, `assetFailedCount=1`
  - post media `thumbPath/detailPath=null`
  - `assetFailures` 문서 0개로 시작해 lazy 생성 경로를 검증
- 실제 앱의 가져오기 현황에서 재시도 버튼을 눌러 callable 경로를 탔다.
- 결과:
  - 원본 job `status=succeeded`, `assetSyncStatus=ready`, `assetCompletedCount=1`, `assetFailedCount=0`
  - 원본 job `assetRetryStatus=succeeded`, `assetRetryErrorMessage=null`
  - `assetFailures` 남은 문서 0개
  - post `assetSyncStatus=ready`, `assetSyncErrorMessage=null`
  - post media `thumbPath/detailPath` 생성
  - `importJobs`에는 원본 `importSeasonFromURL` job 1개만 존재하고 `retrySeasonAssets` job은 생성되지 않음
  - Cloud Tasks queue 잔여 task 0개

최종 앱 정상 경로 QA:

- 2026-06-15 사용자 수동 QA 기준으로 브랜드 등록 → 시즌 후보 확인 → 시즌 선택 → import job 생성 → worker 처리 → 앱 가져오기 현황 표시 → 시즌/이미지 생성까지 확인 완료.
- 실패 관련 분기를 제외한 정상 경로 포인트는 모두 의도한 대로 동작했다.
- 이전에 실패하던 HATCHINGROOM 브랜드 시즌 등록도 깔끔하게 성공했다.
- 이 확인으로 앱에서 시즌 후보 import job 생성 smoke QA는 완료로 본다.

### 구현 계획 상세

#### Phase 12A: Failure Queue 기록

변경 범위:

- `tools/lookbook-import-worker/src/processor.ts`
- worker 단위 테스트.

구현:

- `syncAssets`에서 post image 실패 시 `assetFailures/{failureID}` 문서를 생성/갱신한다.
- failure 문서 필드:
  - `brandID`, `seasonID`, `postID`, `mediaIndex`, `remoteURL`, `sourcePageURL`
  - `sourceImportJobID`
  - `kind: "postImage"`
  - `status: "failed"`
  - `attemptCount`
  - `lastErrorMessage`, `lastAttemptAt`
  - `createdAt`, `updatedAt`
- post image 성공 시 같은 `failureID` 문서를 삭제한다.
- season cover 실패는 이번 Phase 12의 핵심 대상에서 제외하고 기존 season/job summary로 유지한다. 이유: 사용자 재시도 UX의 핵심은 grid post 이미지 복구이며, cover 실패는 post별 failure queue와 식별 축이 다르다. cover 실패가 운영에서 반복되면 별도 `seasonCover` failure kind를 후속 확장한다.

완료 기준:

- import 중 일부 post 이미지 실패 시 failure 문서가 deterministic ID로 1개만 생긴다.
- 같은 실패를 반복해도 새 failure 문서가 늘지 않고 attempt 정보만 갱신된다.
- 성공한 post image는 failure 문서가 남지 않는다.

#### Phase 12B: Retry Cloud Task 전환

변경 범위:

- `functions/src/index.ts`
- Cloud Run worker task endpoint/processor.
- 앱 retry receipt mapping.

구현:

- `requestSeasonAssetRetry`는 더 이상 `retrySeasonAssets` import job 문서를 만들지 않는다.
- `sourceJobID`로 원본 `importSeasonFromURL` job을 검증하고 `targetSeasonID`를 확인한다.
- 기존 `partialFailed` job에 `assetFailures`가 없으면 `createdPostIDs`와 post media의 누락 `thumbPath/detailPath`를 기준으로 lazy failure queue를 생성한다.
- Functions는 `brandID`, `seasonID`, `sourceJobID`, `mode: "assetFailureRetry"` payload로 Cloud Task를 enqueue한다.
- 중복 방지는 원본 import job의 retry marker와 task request ID를 함께 사용한다.
  - 원본 job에 `assetRetryStatus`, `assetRetryRequestID`, `assetRetryRequestedAt`을 기록한다.
  - `assetRetryStatus`가 `queued` 또는 `processing`이면 duplicate receipt를 반환한다.
  - 새 요청을 받을 때마다 새 `assetRetryRequestID`를 발급하고 task name은 이 request ID를 포함한다.
  - 이렇게 하면 동시에 누르는 중복 요청은 막고, 실패 후 즉시 다시 누르는 재시도는 가능하다.
- retry receipt는 retry job ID가 아니라 `sourceJobID`, `seasonID`, `status`, `duplicate` 중심으로 반환한다.

완료 기준:

- 재시도를 여러 번 눌러도 `importJobs` 하위에 새 `retrySeasonAssets` 문서가 생기지 않는다.
- Cloud Task 중복 enqueue가 서버에서 막힌다.
- 기존 앱 Repository/UseCase 경계는 유지한다.

#### Phase 12C: Worker Failure Retry 처리

변경 범위:

- `tools/lookbook-import-worker/src/server.ts`
- `tools/lookbook-import-worker/src/processor.ts`
- worker 단위 테스트.

구현:

- task endpoint가 기존 `jobID` payload와 새 `mode: "assetFailureRetry"` payload를 모두 처리한다.
- asset failure retry path는 URL parsing/materializing을 하지 않는다.
- worker는 `seasons/{seasonID}/assetFailures` 중 retry 대상 문서를 읽고 해당 post media를 다시 fetch/압축/upload한다.
- 이미 post media에 `thumbPath`와 `detailPath`가 있으면 성공으로 간주하고 failure 문서를 삭제한다.
- 실패하면 같은 failure 문서의 attempt/error/timestamp만 갱신한다.
- 원본 import job summary를 남은 failure 수 기준으로 갱신한다.
  - 남은 failure 0개: `status=succeeded`, `assetSyncStatus=ready`, `assetFailedCount=0`
  - 남은 failure n개: `status=partialFailed`, `assetSyncStatus=partial`, `assetFailedCount=n`

완료 기준:

- retry가 기존 post 문서를 재사용하고 새 post/import job을 만들지 않는다.
- 성공/실패가 원본 job, season, post, failure queue에 일관되게 반영된다.

#### Phase 12D: 가져오기 현황 UI 정리

변경 범위:

- `SeasonImportJob` domain/DTO.
- `FirestoreSeasonImportJobRepository`.
- `ManageSeasonImportJobsUseCase`.
- `SeasonImportManagementViewModel`.
- `SeasonImportManagementView`.

구현:

- 가져오기 현황 목록은 원본 `importSeasonFromURL` job만 표시한다.
- `retrySeasonAssets` job은 기존 데이터가 남아 있어도 UI에서 숨긴다.
- 제목 우선순위:
  1. season 문서 `displayTitle`
  2. import job `seasonTitle`
  3. import job `sourceTitle`
  4. `"시즌 가져오기"`
- `targetSeasonID`, import job ID, URL은 기본 UI에 표시하지 않는다.
- 남은 `assetFailures` 개수 기준으로 “이미지 일부 실패 n개”와 재시도 가능/진행 중 상태를 표시한다.

완료 기준:

- 가져오기 현황에서 개발자용 ID 대신 시즌 이름 또는 import source title이 보인다.
- 실패 이미지 재시도 버튼은 원본 import job 행에만 보인다.
- 재시도 중에도 별도 retry job 행이 늘어나지 않는다.

#### Phase 12E: 검증

테스트 설계:

- 테스트 대상:
  - Functions retry 요청 검증과 duplicate task 처리.
  - worker failure queue 생성/삭제/재시도 로직.
  - iOS 가져오기 현황 표시/재시도 상태 로직.
- 필요한 테스트:
  - worker unit test: 실패 시 deterministic failure 문서 생성, 성공 시 삭제, retry path에서 기존 post media 재처리.
  - Functions lint/build. Cloud Tasks enqueue는 emulator 구성이 없으면 단위 테스트보다 smoke QA 중심으로 확인한다.
  - iOS build. ViewModel 단위 테스트 인프라가 충분하지 않으면 이번 변경은 수동 QA 중심으로 둔다.
- 수동 QA 항목:
  - 통제된 실패 asset을 만든 뒤 가져오기 현황에 시즌명과 실패 개수가 표시되는지 확인.
  - 재시도 후 새 `retrySeasonAssets` job 문서가 생기지 않는지 확인.
  - 실패 asset만 `thumbPath/detailPath`가 복구되는지 확인.
- 보류할 테스트와 이유:
  - 실제 Cloud Tasks/Cloud Run 통합은 로컬 단위 테스트로 안정 제어하기 어렵기 때문에 운영 smoke QA로 검증한다.
- 테스트 실행 여부:
  - 구현 후 Functions `npm run lint`, `npm run build`, worker `npm run lint`, `npm test`, iOS `xcodebuild`를 실행한다.

### 모호점 점검

- 추가 사용자 결정이 필요한 모호점은 없다.
- season cover 실패를 failure queue에 포함할지는 후속 확장으로 둔다. 이번 Phase 12는 post image 실패 복구에 집중한다.
- 기존 `retrySeasonAssets` 문서는 새 UI에서 숨기고 새로 만들지 않는다. 운영 데이터 삭제는 별도 승인 없이는 진행하지 않는다.
