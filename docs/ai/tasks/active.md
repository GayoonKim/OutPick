# Active Task Index

## 현재 상태

- 현재 핵심 task는 `core-infrastructure-modularization`이다.
- Phase 2~5 구현을 완료하고 Phase 6 현재 working tree 전체 회귀와 prior rollback 기준 확인까지 완료했다. 배포 candidate commit·동일 SHA 재검증과 Functions/Socket 운영 배포·smoke는 별도 승인 대기다.
- 최근 완료 구현 작업은 `lookbook-deletion-purge-drain`이다.
- 새 작업을 시작할 때 이 문서에는 현재 task 한 건과 바로 이전 완료 작업만 상세 링크로 유지한다.
- 오래된 완료 이력은 각 task의 `progress.md`, 장기 결정은 `docs/ai/ADR.md`에서 확인한다.

## 현재 핵심 작업

| 작업 | 상태 | 핵심 목표 | 상세 |
| --- | --- | --- | --- |
| `core-infrastructure-modularization` | Phase 2~5 구현 완료, Phase 6 working tree 회귀/rollback 기준 완료, commit 승인 대기 | 기능별 Protocol/Client/Store, 공통 transport/database, 얇은 Functions/Socket entrypoint로 전환하되 현재 배포 단위 유지 | [design](core-infrastructure-modularization/design.md), [contracts](core-infrastructure-modularization/contracts/README.md), [Phase 5 결정](core-infrastructure-modularization/decisions/phase-5-socket.md), [Phase 6 결정](core-infrastructure-modularization/decisions/phase-6-integration-deployment.md), [Phase 6 회귀](core-infrastructure-modularization/phases/phase-6-integration-tests.md), [Phase 6 배포](core-infrastructure-modularization/phases/phase-6-deployment.md), [decisions](core-infrastructure-modularization/decisions.md), [plan](core-infrastructure-modularization/plan.md), [progress](core-infrastructure-modularization/progress.md), [qa](core-infrastructure-modularization/qa-checklist.md), [ADR-019](../adr/ADR-019-핵심-인프라는-기능별-모듈러-경계와-현재-배포-단위를-유지한다.md) |

### 현재 코드 진입점

1. iOS Functions transport: `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
2. iOS local database: `OutPick/DB/GRDB/Core/AppDatabase.swift`, `OutPick/DB/GRDB/Stores/`, `OutPick/Features/Chat/Persistence/ChatPersistenceProvider.swift`
3. Firebase Functions: `functions/src/index.ts` → `functions/src/{core,shared,auth,brand,chat,lookbook}/`
4. Socket Cloud Run server: `Socket/index.js` → `Socket/src/app/`, `Socket/src/{auth,handlers,rooms,messages,media,lifecycle,runtime}/`

### 구현 전 사용자 결정

- D4~D8은 확정됐다: 계약 보존, 순차 전환, phase 내 임시 façade, Socket 최소 테스트, `callHelloUser` 제거.
- D9~D14도 확정됐다: 기존 Repository Protocol 재사용, transport/domain mapping/DI 범위, callable 38개 이전, 전체 wire test.
- Phase 2는 구현과 자동 검증까지 완료됐다. 실제 운영 상태를 바꾸는 수동 QA만 미수행이다.
- Phase 3 D15~D18은 확정됐다: legacy migration/table/API clean break, operation-owning Store, 선택적 persistence record, FTS strict rollback.
- Phase 3는 구현과 자동 검증까지 완료됐다. fresh DB는 15개 migration을 사용하고 legacy `roomImage`는 없다.
- D19-A~E는 확정됐다: throws를 SceneDelegate까지 전달하고 독립 실패 화면·수동 재시도·알림 route 보존·OSLog와 DEBUG once/always failure injection으로 검증한다.
- D19는 구현과 unit/UI test, generic Simulator build까지 완료됐다.
- Phase 4 D20~D26은 확정됐다: 기능별 module, core 단일 초기화, 얇은 wrapper/service, core/shared 기준, 49개 명시적 export, clean/재귀 test, 순차 이전·전체 배포 승인.
- Phase 4 추가 A안 3개와 Step 4A~4I를 구현했고 49개 export/runtime 계약과 51개 테스트, lint/build가 통과했다.
- Phase 5 D27~D39는 확정됐다: Node 22 JavaScript ESM 유지, application/handler/service/state/lifecycle 경계, 계약 보존, 재귀 `node:test`, 단일 Cloud Run 배포 경계를 사용한다.
- D40 media dedupe는 in-flight Promise, TTL/LRU와 Firestore transaction winner 기반 단일 emit/push 방향을 후속 작업으로 확정했으며 상세 수치는 구현 계획 전에 결정한다.
- Phase 5 Step 5A~5H를 구현해 `index.js`를 41줄로 축소하고 handler/service/state/lifecycle 경계와 재귀 test runner를 추가했다. Socket check, 43개 테스트와 ADC 기반 local health/shutdown smoke가 통과했다.
- Phase 4 Functions와 Phase 5 Socket 운영 배포·실제 Firebase smoke는 별도 사용자 승인 전 진행하지 않는다.
- Phase 6 D41~D48은 확정됐다: 관련 targeted 회귀, 새 emulator 제외, commit/rollback 선확보, Socket → Functions 순차 전체 배포, traffic split 금지, 독립 gate와 최종 iOS QA를 사용한다.
- Phase 6 현재 working tree 전체 자동 회귀는 통과했다. commit, 동일 SHA 재검증, 운영 fixture 생성과 각 운영 배포는 별도 승인 전 진행하지 않는다.

## 최근 완료 작업

| 작업 | 상태 | 핵심 결과 | 상세 |
| --- | --- | --- | --- |
| `lookbook-deletion-purge-drain` | 완료·운영 배포·QA 완료 | 일일 purge의 전체 20개 상한 제거, cursor drain, 브랜드별 lease/최대 3개 병렬, 7분 claim cutoff | [progress](lookbook-deletion-purge-drain/progress.md), [decisions](lookbook-deletion-purge-drain/decisions.md), [ADR-018](../adr/ADR-018-룩북-영구-삭제는-일일-bounded-drain과-브랜드-lease로-처리한다.md) |
| `lookbook-deletion-request-list-simplification` | 완료·운영 배포·수동 QA 완료 | 앱 삭제 요청 목록을 `active/failed`로 단순화하고 총 관리자 manual retry 추가 | [progress](lookbook-deletion-request-list-simplification/progress.md), [decisions](lookbook-deletion-request-list-simplification/decisions.md) |
| `lookbook-admin-soft-delete-lifecycle` | 완료·운영 배포·통합 QA 완료 | 7일 복구 가능 soft delete와 scheduled hard delete lifecycle | [progress](lookbook-admin-soft-delete-lifecycle/progress.md), [decisions](lookbook-admin-soft-delete-lifecycle/decisions.md) |
| `admin-request-list-retention-unification` | 완료, 일부 삭제 목록 정책은 후속 작업으로 대체됨 | 브랜드 요청 처리 이력 14일 정책 | [progress](admin-request-list-retention-unification/progress.md), [decisions](admin-request-list-retention-unification/decisions.md) |
| `admin-web-brand-season-management` | 완료·운영 배포·통합 QA 완료 | 앱 관리자 브랜드/시즌 관리와 import 흐름 | [progress](admin-web-brand-season-management/progress.md), [decisions](admin-web-brand-season-management/decisions.md) |

`admin-request-list-retention-unification`의 삭제 요청 완료/history UI 계약은 후속 `lookbook-deletion-request-list-simplification`에서 제거됐다. 현재 계약은 항상 후속 task를 우선한다.

## 최근 작업 코드 진입점

### 삭제 purge drain

1. 정책: `lookbook-deletion-purge-drain/decisions.md`, ADR-018
2. 순수 orchestration: `functions/src/lookbook/deletion/purgeDrain.ts`
3. query/claim/purge/scheduler: `functions/src/lookbook/deletion/functions.ts`
4. lease: `functions/src/lookbook/deletion/purgeLease.ts`
5. index: `firestore.indexes.json`
6. 검증: `functions/src/lookbook/deletion/purgeDrain.test.ts`, `purgeLease.test.ts`

### 삭제 요청 앱/서버 목록

1. 서버: `functions/src/lookbook/deletion/functions.ts`의 `listLookbookDeletionRequests`, `retryFailedLookbookDeletionPurge`
2. iOS 화면: `AdminLookbookDeletionManagementView.swift`
3. 상태: `AdminLookbookDeletionManagementViewModel.swift`
4. 도메인/API: `LookbookDeletionRequest.swift`, `LookbookDeletionRepositoryProtocol.swift`
5. 구현: `CloudFunctionsLookbookDeletionRepository.swift`, `LookbookDeletionCloudFunctionsMapper.swift`, 공통 transport

## 검증 기준

- Functions: `cd functions && npm test && npm run lint && npm run build`
- iOS: `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- Firestore: 관련 workflow에 따라 rules/index dry-run 후 승인된 범위만 배포
- 데이터 삭제/운영 배포: 사용자 명시 승인 필요

## 다음 작업 등록 규칙

1. 새 task 디렉터리의 `design.md`, `decisions.md`, `plan.md`, `progress.md`, `qa-checklist.md`를 사용자 승인 후 만든다.
2. 이 문서의 `현재 상태`에는 한 건의 현재 task만 둔다.
3. 완료 시 표에 한 줄을 추가하되 상세 phase 이력은 복사하지 않는다.
4. 여러 작업에 반복 적용할 결정만 ADR로 승격한다.
5. 코드 진입점이 바뀌면 `docs/ai/ENTRYPOINTS.md`와 관련 `entrypoints/*.md`를 함께 갱신한다.
