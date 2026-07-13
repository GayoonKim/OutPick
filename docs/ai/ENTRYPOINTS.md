# OutPick Entrypoints

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 인덱스 문서다.

루트 문서는 공통 진입점과 세부 문서 링크만 유지한다. 기능별 상세 진입점은 필요한 문서만 추가로 읽는다.

## 공통 진입점

- 앱 시작/루트 라우팅: `OutPick/App/AppCoordinator.swift`
- Scene 연결/초기 DI와 bootstrap 실패 복구: `OutPick/App/SceneDelegate.swift`, `OutPick/App/Bootstrap/`
- 탭 조립: `OutPick/App/TabBarController/Composition`
- 기능 코드: `OutPick/Features`
- 공통 인프라: `OutPick/Infra`
- iOS Cloud Functions 공통 transport: `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
- iOS Cloud Functions 기능 adapter: `OutPick/Features/*`의 `CloudFunctions*Repository/Client`와 Lookbook `CloudFunctionsMappers/`
- iOS local database bootstrap/Store: `OutPick/DB/GRDB/Core/AppDatabase.swift`, `OutPick/DB/GRDB/Stores/` (`AppDatabase.live()`는 `throws`)
- Chat persistence 계약/조립: `OutPick/Features/Chat/Persistence/`
- 공통 키보드 dismiss helper: `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`
- 로컬 DB/데이터 schema: `docs/ai/entrypoints/DATA.md`
- Firebase Functions flat export: `functions/src/index.ts`
- Firebase Functions 공통 runtime/callable: `functions/src/core/`
- Firebase Functions 기능 구현: `functions/src/{auth,brand,chat,lookbook}/`
- Socket bootstrap/application: `Socket/index.js`, `Socket/src/app/`
- Socket 기능 경계: `Socket/src/{auth,handlers,rooms,messages,media,lifecycle,runtime}/`
- Socket 자동 검증: `Socket/test/`, `Socket/scripts/run-tests.mjs`
- Phase 6 통합 회귀/배포 gate: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`, `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`
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

| 포인터 | 문서 |
| --- | --- |
| 현재 작업과 최근 완료 상태 | `docs/ai/tasks/active.md` |
| 세션 복원 | `HANDOFF.md` |
| 장기 결정 | `docs/ai/ADR.md` |
| 데이터 계약 | `docs/ai/DATA_SCHEMA.md` |

최근 작업은 `active.md`에서 관련 task의 `decisions.md`와 `progress.md`로 들어간다. phase 전체 이력은 루트 인덱스에 복사하지 않는다.

## 변경 목적별 빠른 경로

| 변경 목적 | 읽기 순서 |
| --- | --- |
| 핵심 인프라 모듈화 | `tasks/core-infrastructure-modularization/design.md` → `contracts/README.md` → `active.md`가 가리키는 현재 phase 결정/계획/테스트 → decisions/plan/progress → ADR-019 → 네 현재 대형 진입점 |
| 삭제 purge queue/장애 | task decisions/progress → ADR-018 → `lookbook/deletion/purgeDrain.ts` → `lookbook/deletion/functions.ts` scheduler/query → `purgeLease.ts` → test |
| 삭제 요청 앱 목록/retry | task progress → `LOOKBOOK.md` 삭제 관리 → `FIREBASE.md` 삭제 lifecycle → iOS/Functions 구현 |
| 룩북 import/진단 | task progress → `architecture/LOOKBOOK_IMPORT_WORKER.md` → `FIREBASE.md` URL import → worker/앱 구현 |
| 브랜드 요청/관리 | `LOOKBOOK.md` 관리자 흐름 → `FIREBASE.md` 권한·요청 → 관련 task progress |
| Chat membership/cache | `CHAT.md` → `DATA_SCHEMA.md` Chat 계약 → 관련 task decisions/progress |

작업 시작 시 이 문서와 `docs/ai/tasks/active.md`만 먼저 읽고, 표가 가리키는 세부 문서만 추가로 확인한다.
