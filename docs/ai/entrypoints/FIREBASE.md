# Firebase Entrypoints

## Firebase Functions

- Export entry: `functions/src/index.ts`
- Season candidate discovery: `functions/src/lookbookSeasonCandidateDiscovery.ts`

## 주요 callable/trigger

- Auth: `exchangeKakaoToken`
- Brand: `getBrandAdminCapabilities`, `createBrand`, `updateBrandLogoPaths`, `setBrandEngagement`
- Post: `setPostEngagement`
- Season: `setSeasonEngagement`
- Comment: `setCommentEngagement`, `createComment`, `createReply`, `deleteComment`, `reportComment`
- User safety: `blockUser`, `loadHiddenCommentUserIDs`
- Season import: `requestSeasonImport`, `requestSeasonAssetRetry`, `requestSeasonCandidateImportJobs`
- Firestore triggers: `onSeasonImportQueued`, `onRoomClosed`

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
