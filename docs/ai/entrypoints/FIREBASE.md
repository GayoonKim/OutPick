# Firebase Entrypoints

## Firebase Functions

- Export entry: `functions/src/index.ts`
- Season candidate discovery: `functions/src/lookbookSeasonCandidateDiscovery.ts`

## 주요 callable/trigger

- Auth: `exchangeKakaoToken`
- Brand: `getBrandAdminCapabilities`, `createBrand`, `updateBrand`, `updateBrandLogoPaths`, `addBrandManager`, `removeBrandManager`, `setBrandEngagement`
- Brand request: `searchBrands`, `submitBrandRequest`, `listMyBrandRequests`, `listBrandRequests`, `updateBrandRequestStage`, `resolveBrandRequest`
- Brand request group: `listBrandRequestGroups`, `updateBrandRequestGroupStage`, `resolveBrandRequestGroup`
- Post: `setPostEngagement`
- Season: `setSeasonEngagement`
- Comment: `setCommentEngagement`, `createComment`, `createReply`, `deleteComment`, `reportComment`
- User safety: `blockUser`, `loadHiddenCommentUserIDs`
- Season import: `requestSeasonImport`, `requestSeasonAssetRetry`, `requestSeasonCandidateImportJobs`
- Firestore triggers: `onSeasonImportQueued`, `onRoomClosed`

## Brand Request

- 사용자별 요청 기록: `brandRequests/{requestID}`
- 요청 처리 상태 source: `brandRequestNameIndex/{dedupeKeyHash}`
- 브랜드 검색: callable `searchBrands`가 `brands.normalizedName`과 `brands.normalizedEnglishName` prefix query를 수행한 뒤 중복 브랜드를 제거한다.
- 브랜드명 수요/group 집계: `brandRequestNameIndex/{dedupeKeyHash}`
- `listMyBrandRequests`는 group 상태를 반영해 사용자 노출 상태를 반환한다.
- `listBrandRequestGroups`는 운영자 group 목록 source인 `brandRequestNameIndex`를 조회한다. `adminStage = rejected | completed`일 때 `processedScope = recent | history`를 지원하며, 기본 최근 처리 이력 기준은 14일이다.
- 사용자 일일 제한: `brandRequestDailyCounters/{uid}/brandRequestDays/{yyyyMMdd}`
- 사용자 spam/차단: `brandRequestUserLimits/{uid}`
- 앱/관리자는 Firestore 직접 접근이 아니라 callable을 사용한다.
- Firestore rules는 위 컬렉션들의 client read/write를 차단한다.
- TTL 후보:

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=brandRequestDays \
  --enable-ttl \
  --project=outpick-664ae
```

- TTL policy 적용은 사용자 명시 승인 후 별도 수행한다.

## Brand Management

- 브랜드 생성/수정/관리자 변경은 callable Functions 경계를 사용한다.
- `createBrand`: 총 관리자(`brandAdmins/{uid}.isActive == true`)만 새 브랜드를 생성한다.
- `updateBrand`: 브랜드 owner/admin 또는 총 관리자가 브랜드명, 영문 브랜드명, 공식 홈페이지 URL, 룩북 목록 URL을 수정한다.
- `updateBrand`의 `isFeatured` 변경은 총 관리자만 가능하다.
- 브랜드명/영문명 변경 시 `brandNameIndex/{normalizedName}`과 `brandNameIndex/{normalizedEnglishName}` 중복 검증과 이전 index 삭제를 transaction에서 처리한다.
- `updateBrandLogoPaths`: 브랜드 owner/admin 또는 총 관리자가 Storage 업로드 후 로고 경로를 반영한다.
- `addBrandManager`: normalized email로 `users.email`을 조회해 `brands/{brandID}/admins/{uid}` 문서를 생성/갱신한다.
- `removeBrandManager`: normalized email로 `users.email`을 조회해 `brands/{brandID}/admins/{uid}` 문서를 삭제한다.
- 총 관리자는 owner/admin 모두 추가/삭제할 수 있다.
- 브랜드 owner는 해당 브랜드 admin만 추가/삭제할 수 있고 owner 추가/삭제는 할 수 없다.
- 브랜드 admin은 관리자 추가/삭제 권한을 갖지 않는다.
- 마지막 owner 삭제는 서버에서 차단한다.

## Lookbook Soft Delete Lifecycle

- 삭제 lifecycle API는 callable Functions 경계를 사용한다.
- `requestBrandDeletion`: 총 관리자만 브랜드 삭제 요청을 생성한다. 브랜드 문서에 `deletionStatus = deletionRequested`를 기록하고 `lookbookDeletionRequests/{requestID}` projection과 `lookbookDeletionAuditLogs/{logID}` 감사 로그를 같은 transaction에서 쓴다.
- `cancelBrandDeletion`: 총 관리자만 브랜드 삭제 요청을 취소한다. 브랜드 `deletionStatus`를 `active`로 되돌리고 projection 상태를 `cancelled`로 바꾼다.
- `softDeleteSeason` / `restoreSeason`: 총 관리자 또는 `brands/{brandID}/admins/{uid}.role in ["owner", "admin"]`인 브랜드 관리자가 시즌 삭제 상태를 변경한다. 시즌 삭제는 하위 포스트를 즉시 `deleted`로 바꾸지 않는다.
- `softDeletePost` / `restorePost`: 총 관리자 또는 브랜드 owner/admin이 포스트 삭제 상태를 변경한다. 부모 브랜드가 `deletionRequested`이거나 부모 시즌이 `deleted`이면 개별 포스트 삭제/복구를 막는다.
- `batchSoftDeleteSeasons`: `brandID`와 최대 20개 `seasonIDs`를 받아 시즌 삭제 요청을 항목별 transaction으로 처리한다. 권한과 부모 브랜드 상태 정책은 `softDeleteSeason`과 동일하며, 일부 항목 실패 시 `results`에 항목별 성공/실패를 반환한다.
- `batchSoftDeletePosts`: `brandID`, `seasonID`, 최대 20개 `postIDs`를 받아 같은 시즌 안의 포스트 삭제 요청을 항목별 transaction으로 처리한다. 권한과 부모 브랜드/시즌 상태 정책은 `softDeletePost`와 동일하며, 일부 항목 실패 시 `results`에 항목별 성공/실패를 반환한다.
- `listLookbookDeletionRequests`: 총 관리자는 전역 삭제 요청 목록을 조회할 수 있고, 브랜드 owner/admin은 `brandID`를 지정한 자신 권한 브랜드 목록만 조회할 수 있다. `statusGroup = active`는 `active/failed`, `statusGroup = processed`는 영구 삭제가 끝난 `purged`만 조회한다. 복구된 `restored`와 취소된 `cancelled`는 완료 목록에 포함하지 않는다. processed group은 `processedScope = recent | history`를 지원하며, 기본 최근 처리 이력 기준은 14일이다. 기존/부분 projection에 `targetDisplayName` 또는 `brandName`/`seasonTitle`/`postCaption` 같은 표시 snapshot이 비어 있으면 원본 브랜드/시즌/포스트 문서를 읽어 응답 summary만 보강한다. `targetDisplayName`이 "삭제된 브랜드/시즌/포스트" fallback이더라도 target별 snapshot 이름이 있으면 브랜드명/시즌명/포스트명으로 보강한다. 시즌명은 시즌 문서의 `displayTitle`, legacy `title`, `sourceTitle` 순서로 읽는다. 이 보강은 운영 projection 문서 backfill write를 수행하지 않는다.
- iOS callable wrapper는 `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`, repository 경계는 `CloudFunctionsBrandRequestRepository.swift`와 `CloudFunctionsLookbookDeletionRepository.swift`를 확인한다.
- 다음 핵심 작업인 포스트 삭제 audit thumbnail은 `docs/ai/tasks/post-deletion-audit-thumbnail/design.md`에 설계되어 있다. 아직 구현 전이며, 구현 시 포스트 요청에 한해 별도 Storage prefix와 projection 필드 추가가 필요하다.
- 삭제 요청 projection 컬렉션은 `lookbookDeletionRequests/{requestID}`이며 주요 필드는 `targetType`, `targetID`, `targetPath`, `brandID`, `seasonID`, `postID`, `status`, `requestedBy`, `requestedAt`, `restoreUntil`, `purgeAfter`, `reason`, `updatedAt`이다.
- 신규 projection은 관리자 목록 표시용 snapshot인 `targetDisplayName`, `targetImagePath`, `brandName`, `brandEnglishName`, `brandLogoThumbPath`, `seasonTitle`, `seasonCoverThumbPath`, `postCaption`, `postImageThumbPath`를 함께 저장한다. 기존 projection에는 없을 수 있으므로 클라이언트는 fallback을 유지한다.
- 감사 로그 컬렉션은 `lookbookDeletionAuditLogs/{logID}`이며 일반 클라이언트 직접 read/write는 허용하지 않는다.
- 앱 또는 관리자 callable hard delete는 제공하지 않는다. 영구 삭제는 scheduled function만 수행한다.
- `purgeExpiredLookbookDeletions`: Phase 5 scheduled hard delete function이다.
  - `Asia/Seoul` 기준 매일 04:00 실행.
  - 한 번에 최대 20개 deletion request target 처리.
  - `active` 요청 또는 `status = failed`, `autoRetryEligible = true`, `purgeAfter <= now`, `retryAfter <= now 또는 retryAfter 없음`, `purgeAttemptCount < 3` 대상만 처리.
  - 브랜드 purge는 `brands/{brandID}` 하위 Firestore 문서 전체, `brandNameIndex`, 관련 user state projection, `brands/{brandID}/` Storage prefix를 삭제한다.
  - 시즌 purge는 시즌 하위 posts/comments/replacements, 관련 user state projection, `brands/{brandID}/seasons/{seasonID}/` Storage prefix를 삭제한다.
  - 포스트 purge는 포스트 하위 comments/replacements, 관련 user state projection, `brands/{brandID}/seasons/{seasonID}/posts/{postID}/` Storage prefix를 삭제한다.
  - 문서 필드에 저장된 Storage 파일은 raw Storage path만 삭제 대상으로 인정한다. `://`가 들어간 URL, 외부 `remoteURL`, `sourcePageURL`은 삭제하지 않는다.
  - 부모 target이 purge되면 같은 범위의 하위 active/failed deletion request projection도 `purged`로 닫는다.
  - 실패 시 `failed`, `purgeAttemptCount`, `lastPurgeAttemptAt`, `retryAfter`, `autoRetryEligible`, `purgeErrorMessage`와 감사 로그를 남기고, 3회 실패 후 자동 재시도에서 제외한다.
- Firestore rules는 `lookbookDeletionRequests`, `lookbookDeletionAuditLogs` 직접 접근을 막고, `brands/{brandID}/seasons/{seasonID}`와 `posts/{postID}` 직접 `delete`를 막는다. 기존 create/update 권한은 유지한다.
- 인덱스는 `firestore.indexes.json`의 `lookbookDeletionRequests` 목록/정리용 composite index와 `brandStates`, `seasonStates`, `postStates`, `commentStates` collection group field override를 사용한다.
- 운영 배포와 OUTSTANDING 통합 QA 결과는 `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`와 `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/qa-checklist.md`를 확인한다.

## Lookbook URL Import Worker

Cloud Run worker 전환 기준의 URL 기반 시즌 등록 진입점이다.

- Cloud Functions wake-up trigger/export 후보: `functions/src/index.ts`
- Season candidate discovery: `functions/src/lookbookSeasonCandidateDiscovery.ts`
- Cloud Run worker package: `tools/lookbook-import-worker/`
- Cloud Run worker server: `tools/lookbook-import-worker/src/server.ts`
- Cloud Run worker processor: `tools/lookbook-import-worker/src/processor.ts`
- Cloud Run worker lifecycle/retry 분류: `tools/lookbook-import-worker/src/job-lifecycle.ts`, `tools/lookbook-import-worker/src/import-error.ts`
- 공개 URL/SSRF 방어 HTTP boundary: `tools/lookbook-import-worker/src/public-http.ts`
- Cloud Run worker Firebase boundary: `tools/lookbook-import-worker/src/firebase.ts`
- Cloud Run worker config/env boundary: `tools/lookbook-import-worker/src/config.ts`
- 배포/운영 자동화 후보: `scripts/ai/`

## Lookbook Import Worker 문서 지도

처음 구조를 이해할 때:

- 전체 책임 경계와 기술 선택 요약: `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`
- Firebase/worker 코드 진입점: 이 문서의 `Lookbook URL Import Worker` 섹션

현재 작업 상태를 볼 때:

- 현재 task 포인터: `docs/ai/tasks/active.md`
- 진행상황과 검증 상태: `docs/ai/tasks/lookbook-import-worker/progress.md`
- phase별 목표와 완료 기준: `docs/ai/tasks/lookbook-import-worker/plan.md`

기술 결정 이유를 볼 때:

- 작업 중 결정 상세: `docs/ai/tasks/lookbook-import-worker/decisions.md`
- 여러 작업에 반복 적용될 아키텍처 요약: `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`

Phase 4.5 이후 운영 설계를 볼 때:

- Cloud Tasks target architecture, job lifecycle, fallback, observability: `docs/ai/tasks/lookbook-import-worker/phase-4-5-design.md`

커밋 포함 여부를 판단할 때:

- 하네스 커밋 기준: `docs/ai/workflows/implementation/commits.md`

권장 흐름:

```text
앱 브랜드 생성/시즌 선택
→ Firestore seasonCandidates/importJobs 등록
→ Functions Firestore trigger가 Cloud Tasks enqueue
→ Cloud Tasks가 Cloud Run worker task endpoint 호출
→ Cloud Run worker가 importJob 처리
→ Firestore seasons/posts와 Storage thumb/detail 갱신
→ 앱이 job 상태와 생성 문서를 표시
```

## Firestore

- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`

## Firebase Storage Rules

- Storage rules source: `storage.rules`
- Deploy config: root `firebase.json`의 `"storage": { "rules": "storage.rules" }`
- `OutPick/firebase.json`은 Functions 설정만 갖고 있어 Firebase source of truth로 쓰지 않는다.
- 운영 bucket 확인:

```bash
gcloud storage buckets list --project outpick-664ae --format='value(name,location,uniformBucketLevelAccess)'
```

- 운영 Rules release 확인:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-goog-user-project: outpick-664ae" \
  "https://firebaserules.googleapis.com/v1/projects/outpick-664ae/releases"
```

- 2026-07-03 최소 권한 rules 배포 전 확인된 운영 Storage release:
  - release: `projects/outpick-664ae/releases/firebase.storage/outpick-664ae.appspot.com`
  - ruleset: `projects/outpick-664ae/rulesets/a9ad4934-efaf-40d4-bdba-7e088743c817`
  - updateTime: `2024-10-03T10:51:50.370558Z`
- ruleset 본문 확인:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-goog-user-project: outpick-664ae" \
  "https://firebaserules.googleapis.com/v1/projects/outpick-664ae/rulesets/a9ad4934-efaf-40d4-bdba-7e088743c817"
```

- 배포 전 운영 Storage rules 본문은 `match /{allPaths=**} { allow read, write; }` 전역 허용 상태였다.
- 따라서 당시 비참여 preview 이미지/비디오 read는 운영 권한상 허용됐지만, write까지 열려 있어 출시/외부 테스트 전 최소 권한 rules 적용이 필요했다.
- 2026-07-03 사용자 승인 후 repo source of truth와 운영 배포를 완료했다.

2026-07-03 로컬 초안:

- root `firebase.json`에 `"storage": { "rules": "storage.rules" }`를 추가했다.
- `storage.rules` 초안은 기본 deny 후 path별 최소 권한을 허용한다.
- Chat `rooms/{roomID}/...`
  - `get`: 로그인 사용자 허용. Firestore `Rooms/{roomID}/Messages` read가 `signedIn()`이라 비참여 preview 요구사항과 맞춘다.
  - `create/update`: room member 또는 creator로 제한한다.
  - `delete`: room member 또는 creator로 제한한다.
- Profile `profileImage/{userID}/...`
  - `get`: 로그인 사용자 허용.
  - `create/update/delete`: 본인만 허용.
- Lookbook `brands/{brandID}/...`
  - `get`: 로그인 사용자 허용.
  - `create/update/delete`: 총 관리자 또는 Firestore `brands/{brandID}/admins/{uid}.role in ["owner", "admin"]` 기반 write 권한 사용자만 허용.
- legacy prefix는 기본 deny한다.
- 로컬 검증:

```bash
firebase deploy --only storage --project outpick-664ae --dry-run --non-interactive
git diff --check -- firebase.json storage.rules
```

- dry-run compile은 통과했다.
- 2026-07-03 운영 배포:

```bash
firebase deploy --only storage --project outpick-664ae --non-interactive
```

- 배포 완료 후 release:
  - release: `projects/outpick-664ae/releases/firebase.storage/outpick-664ae.appspot.com`
  - ruleset: `projects/outpick-664ae/rulesets/148e8921-6195-42df-b575-09b17bbc88c4`
  - updateTime: `2026-07-03T10:04:35.211531Z`
- 배포 후 ruleset 본문이 로컬 `storage.rules`와 같은 최소 권한 rules임을 REST API로 확인했다.
- 배포 직후 앱 수동 QA에서 chat media upload와 room cover upload가 실패했다.
- 원인: Storage rules의 `firestore.get()`/`firestore.exists()` cross-service lookup을 위해 Firebase Storage service agent에 Firestore read 권한이 필요했지만 IAM binding이 없었다.
- 2026-07-03 추가한 IAM binding:

```bash
gcloud projects add-iam-policy-binding outpick-664ae \
  --member="serviceAccount:service-715386497547@gcp-sa-firebasestorage.iam.gserviceaccount.com" \
  --role="roles/firebaserules.firestoreServiceAgent"
```

- 확인 명령:

```bash
gcloud projects get-iam-policy outpick-664ae \
  --flatten='bindings[].members' \
  --filter='bindings.role:roles/firebaserules.firestoreServiceAgent OR bindings.members:service-715386497547@gcp-sa-firebasestorage.iam.gserviceaccount.com' \
  --format='table(bindings.role,bindings.members)'
```

- 확인 결과 `roles/firebaserules.firestoreServiceAgent`와 `roles/firebasestorage.serviceAgent`가 Firebase Storage service agent에 부여되어 있다.
- IAM 반영 후 앱 수동 QA:
  - 참여자가 `채팅 참여하기`로 `Rooms/{roomID}/members/{uid}`를 만든 뒤 이미지 메시지 전송 성공.
  - 참여자가 `채팅 참여하기`로 `Rooms/{roomID}/members/{uid}`를 만든 뒤 비디오 메시지 전송 성공.
  - 방장이 채팅방 cover 생성/수정/삭제 성공.
- 2026-07-04 남은 앱 수동 QA를 완료했다.
  - 비참여 사용자가 preview에서 이미지/비디오 thumbnail을 볼 수 있음을 확인했다.
  - 본인이 profile avatar를 업로드할 수 있음을 확인했다.
  - 브랜드 owner/admin이 brand logo 또는 season cover를 업로드할 수 있음을 확인했다.
  - legacy prefix가 필요한 화면은 확인되지 않았다.
