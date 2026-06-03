# Firebase Entrypoints

## Firebase Functions

- Export entry: `functions/src/index.ts`
- Lookbook import worker 참고 코드: `functions/src/lookbookImportWorker.ts`
- Lookbook materializer 참고 코드: `functions/src/lookbookImportMaterializer.ts`
- Lookbook asset sync 참고 코드: `functions/src/lookbookAssetSyncWorker.ts`
- Season candidate discovery: `functions/src/lookbookSeasonCandidateDiscovery.ts`

## 주요 callable/trigger

- Auth: `exchangeKakaoToken`
- Brand: `getBrandAdminCapabilities`, `createBrand`, `updateBrandLogoPaths`, `setBrandEngagement`
- Post: `setPostEngagement`
- Season: `setSeasonEngagement`
- Comment: `setCommentEngagement`, `createComment`, `createReply`, `deleteComment`, `reportComment`
- User safety: `blockUser`, `loadHiddenCommentUserIDs`
- Season import: `requestSeasonImport`, `processNextSeasonImportJob`, `processSeasonImportJobs`, `requestSeasonCandidateImportsAndProcess`, `createSeasonContentFromImportJobs`
- Firestore triggers: `onSeasonImportParsed`, `onSeasonImportContentCreated`, `onRoomClosed`

## Lookbook URL Import Worker

Cloud Run worker 전환 기준의 URL 기반 시즌 등록 진입점이다.

- Cloud Functions wake-up trigger/export 후보: `functions/src/index.ts`
- 기존 Functions import 파싱/asset sync 참고 코드: `functions/src/lookbookImportWorker.ts`, `functions/src/lookbookImportMaterializer.ts`, `functions/src/lookbookAssetSyncWorker.ts`
- Cloud Run worker 예정 위치: `tools/lookbook-import-worker/`
- 배포/운영 자동화 후보: `scripts/ai/`

권장 흐름:

```text
앱 브랜드 생성/시즌 선택
→ Firestore seasonCandidates/importJobs 등록
→ Functions Firestore trigger가 Cloud Run worker wake-up
→ Cloud Run worker가 queued importJobs 처리
→ Firestore seasons/posts와 Storage thumb/detail 갱신
→ 앱이 job 상태와 생성 문서를 표시
```

## Firestore

- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
