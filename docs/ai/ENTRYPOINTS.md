# OutPick Entrypoints

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 인덱스 문서다.

루트 문서는 공통 진입점과 세부 문서 링크만 유지한다. 기능별 상세 진입점은 필요한 문서만 추가로 읽는다.

## 공통 진입점

- 앱 시작/루트 라우팅: `OutPick/App/AppCoordinator.swift`
- Scene 연결/초기 DI: `OutPick/App/SceneDelegate.swift`
- 탭 조립: `OutPick/App/TabBarController/Composition`
- 기능 코드: `OutPick/Features`
- 공통 인프라: `OutPick/Infra`
- 공통 키보드 dismiss helper: `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`
- 로컬 DB/데이터 schema: `docs/ai/entrypoints/DATA.md`
- Firebase Functions: `functions/src/index.ts`
- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- Firebase/Storage 운영 권한 확인: `docs/ai/entrypoints/FIREBASE.md`
- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`

## 세부 진입점

- 앱 조립, 탭, 주요 Feature: `docs/ai/entrypoints/APP.md`
- Chat 앱 화면/검색/채팅방 흐름: `docs/ai/entrypoints/CHAT.md`
- Lookbook 앱 화면/도메인: `docs/ai/entrypoints/LOOKBOOK.md`
- Profile 생성/수정/상세: `docs/ai/entrypoints/PROFILE.md`
- Data/GRDB/Repository boundary: `docs/ai/entrypoints/DATA.md`
- Firebase Functions/Firestore: `docs/ai/entrypoints/FIREBASE.md`
- 테스트: `docs/ai/entrypoints/TESTS.md`

## 작업별 진입점

- 현재 작업 포인터: `docs/ai/tasks/active.md`
- 루트 포인터: `HANDOFF.md`
- 포스트 삭제 audit thumbnail 작업: `docs/ai/tasks/post-deletion-audit-thumbnail/design.md`, `docs/ai/tasks/post-deletion-audit-thumbnail/plan.md`, `docs/ai/tasks/post-deletion-audit-thumbnail/qa-checklist.md`
- 포스트 삭제 audit thumbnail 서버/iOS 경계: `functions/src/index.ts`, `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`, `OutPick/Features/Lookbook/ViewModels/AdminLookbookDeletionManagementViewModel.swift`, `OutPick/Features/Lookbook/Domains/Entities/LookbookDeletionRequest.swift`
- 룩북 import 진단 작업: `docs/ai/tasks/lookbook-import-diagnostics/design.md`, `docs/ai/tasks/lookbook-import-diagnostics/phase-1-data-api-contract.md`, `docs/ai/tasks/lookbook-import-diagnostics/phase-2a-worker-diagnostic-endpoint-design.md`, `docs/ai/tasks/lookbook-import-diagnostics/plan.md`, `docs/ai/tasks/lookbook-import-diagnostics/qa-checklist.md`
- 룩북 import 진단 서버/iOS 경계: `functions/src/index.ts`, `functions/src/lookbookSeasonCandidateDiscovery.ts`, `functions/src/lookbookSeasonCandidateParser.ts`, `tools/lookbook-import-worker/src/server.ts`, `tools/lookbook-import-worker/src/season-discovery.ts`, `tools/lookbook-import-worker/src/processor.ts`, `tools/lookbook-import-worker/src/season-discovery.test.ts`, `tools/lookbook-import-worker/src/processor.test.ts`, `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`, `OutPick/Features/Lookbook/Domains/Entities/LookbookExtractionDiagnostic.swift`, `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsSeasonCandidateDiscoveryRepository.swift`, `OutPick/Features/Lookbook/Views/Admin/AdminBrandManagementView.swift`, `OutPick/Features/Lookbook/Views/CreateBrand/brand/CreateBrandCandidateSelectionView.swift`, `OutPick/Features/Lookbook/Views/BrandDetail/SeasonImportManagementView.swift`, `OutPick/Features/Lookbook/ViewModels/SeasonImportManagementViewModel.swift`
- 관리자 요청 목록 14일 표시 정책 통일 작업: `docs/ai/tasks/admin-request-list-retention-unification/design.md`, `docs/ai/tasks/admin-request-list-retention-unification/plan.md`, `docs/ai/tasks/admin-request-list-retention-unification/qa-checklist.md`
- 관리자 요청 목록 서버/iOS 경계: `functions/src/index.ts`, `OutPick/Features/Lookbook/Views/Admin/AdminBrandRequestGroupsView.swift`, `OutPick/Features/Lookbook/ViewModels/AdminBrandRequestGroupsViewModel.swift`, `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`, `OutPick/Features/Lookbook/ViewModels/AdminLookbookDeletionManagementViewModel.swift`
- 룩북 삭제 lifecycle 완료 작업: `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/progress.md`, `docs/ai/tasks/lookbook-admin-soft-delete-lifecycle/qa-checklist.md`
- 룩북 삭제 lifecycle 서버 경계: `functions/src/index.ts`, `firestore.rules`, `firestore.indexes.json`, `docs/ai/entrypoints/FIREBASE.md`
- 룩북 삭제 lifecycle iOS 경계: `docs/ai/entrypoints/LOOKBOOK.md`

작업 시작 시에는 이 문서와 `docs/ai/tasks/active.md`를 먼저 보고, 필요한 세부 진입점 문서만 추가로 확인한다.
