# Core Infrastructure Modularization Plan

## 목적

네 개 대형 인프라 진입점을 기능별 계약과 구현으로 분리하기 위한 제안 단계와 승인 상태를 관리한다.

Phase 1 계약 inventory까지 완료했다. Phase 2 이후의 세부 변경 파일과 구현은 각 phase 사용자 승인 전 확정하거나 수정하지 않는다.

## Phase 지도

| Phase | 목표 | 상태 |
| --- | --- | --- |
| Phase 0 | 설계 하네스와 장기 아키텍처 결정 기록 | 완료 |
| Phase 1 | 외부 계약·transaction 경계 inventory와 characterization 기준 확정 | 완료 |
| Phase 2 | iOS Cloud Functions를 기능별 adapter와 공통 transport로 전환 | 구현·자동 검증 완료 |
| Phase 3 | GRDBManager를 기능별 Store와 공통 AppDatabase로 전환 | 구현·자동 검증 완료, 수동 QA 미수행 |
| Phase 4 | functions/src/index.ts를 기능별 모듈과 flat export 진입점으로 전환 | 구현·자동 검증 완료, 운영 배포 승인 대기 |
| Phase 5 | Socket/index.js를 기능별 handler/service와 bootstrap으로 전환 | 구현·자동 검증 완료, 운영 배포·smoke 승인 대기 |
| Phase 6 | 통합 회귀 검증, 운영 배포, 하네스 최종화 | 완료: 동일 SHA 회귀, 운영 배포, D49 안정화, 통합 QA와 fixture cleanup 통과 |

## Phase 0. 설계 하네스

### 목표

작업 가치, 범위, 모듈 경계, 배포 경계, 제약, 완료 기준, 검증 후보를 문서화한다.

### 변경 범위

- docs/ai/tasks/core-infrastructure-modularization/
- docs/ai/ADR.md와 ADR-019
- docs/ai/CODE_ARCHITECTURE.md
- docs/ai/ENTRYPOINTS.md
- docs/ai/tasks/active.md
- HANDOFF.md

### 완료 기준

- 합의된 구조와 미결정 사항이 구분된다.
- 구현 전 사용자 결정 항목이 명시된다.
- 코드는 수정하지 않는다.

### 검증 방법

- 문서 링크/경로 확인.
- git diff --check.

### 논의 필요

- 없음. 사용자가 문서화를 승인했다.

## Phase 1. 계약과 경계 고정

### 목표

리팩터링 전후 반드시 같아야 할 public/wire/data/transaction 계약을 inventory로 고정한다.

### 변경 범위 후보

- CloudFunctionsManager 공개 method와 실제 소비자 mapping
- GRDBManager operation/table/transaction/migration mapping
- functions/src/index.ts export/trigger/runtime option mapping
- Socket/index.js event/payload/ACK/auth/side-effect mapping
- 필요한 characterization test 또는 test fixture
- task decisions/qa/progress

실제 문서: [Phase 1 Contract Inventory](contracts/README.md)와 영역별 상세 문서.

### 완료 기준

- 각 공개 계약의 현재 owner와 새 target owner가 정리된다.
- dead/debug API와 실제 유지 API가 구분된다.
- 함수/이벤트/schema 이름 보존 목록이 작성된다.
- Phase 2~5의 실제 변경 파일과 충돌 지점이 확정된다.

### 검증 방법

- rg 기반 consumer/export/event inventory.
- 기존 test 목록과 coverage gap 확인.
- 필요 시 compile 없이 가능한 정적 contract snapshot.

### 논의 결과

- D4~D8을 확정했다.
- callable/Socket/GRDB 계약 변경은 이번 구조 리팩터링에서 제외한다.
- 새로 발견한 미참조 wrapper와 legacy GRDB API는 해당 구현 phase 전에 N1~N4로 논의한다.

## Phase 2. iOS Cloud Functions boundary

### 목표

CloudFunctionsManager 전체 의존을 기능별 좁은 Protocol/Client로 교체하고 공통 transport만 공유한다.

### 변경 범위 후보

- OutPick/DB/Firebase/CloudFunctions/Core/
- Auth/BrandAdmin의 새 좁은 capability와 client
- 기존 Login/Lookbook Repository 구현 15개
- Lookbook 기능 mapper 7개
- BrandAdminSessionStore와 App/Login/Lookbook DI
- RoomListsCollectionViewController debug call
- OutPickTests/CloudFunctions/ 기능별 adapter test

실제 파일과 순서: [Phase 2 구현 계획](phases/phase-2-ios-cloud-functions.md).

### 완료 기준

- 사용 중인 callable 38개가 새 adapter로 이전된다.
- 승인 대상 소비자가 `CloudFunctionsManager` concrete type 또는 shared를 직접 사용하지 않는다.
- View/ViewController의 직접 Functions 호출이 없다.
- 공통 transport는 SDK 호출과 공통 오류만 담당한다.
- 기능별 response mapping이 해당 adapter 또는 mapper에 위치한다.
- 영구 giant façade를 남기지 않는다.

### 검증 방법

- callable 38개의 fake transport 기반 payload/function-name test.
- primitive decoder와 복잡한 response mapper unit test.
- Firebase 원본 오류 전달 test.
- 관련 Repository/Store test.
- iOS generic simulator build.
- 대표 로그인/룩북 관리자/상호작용 수동 QA.

### 논의 결과

- D9~D14를 확정했다.
- 기존 Repository Protocol을 재사용하고 pass-through Client 계층을 중복 추가하지 않는다.
- N1~N2, DI 범위, Domain mapping owner, 테스트 깊이를 확정했다.
- 구현 승인 전까지 Swift 코드는 수정하지 않는다.

## Phase 3. GRDB boundary

### 목표

GRDBManager의 database bootstrap, migration, message, outbox, media, profile cache, cleanup 책임을 분리한다.

### 변경 범위 후보

- OutPick/DB/GRDB/Core/
- OutPick/DB/GRDB/Migrations/
- OutPick/DB/GRDB/Records/
- OutPick/DB/GRDB/Stores/
- ChatContainer와 관련 Manager/Repository/UseCase DI
- GRDBManagerMigrationTests
- Chat profile/outbox/media 관련 tests

구체적인 변경 파일과 순서는 [Phase 3 GRDB 구현 계획](phases/phase-3-grdb.md), 테스트 fixture와 실패 주입 시나리오는 [Phase 3 GRDB 테스트 계획](phases/phase-3-grdb-tests.md)을 따른다.

### 완료 기준

- AppDatabase가 DatabasePool과 migration 실행을 소유한다.
- 소비자는 필요한 persistence Protocol만 받는다.
- D15에서 유지하기로 한 15개 migration identifier/order/schema가 유지된다.
- 메시지/media index 및 room cleanup transaction 경계가 유지된다.
- FTS 실패는 message/FTS/media 전체를 rollback하고, room exit cleanup은 outbox까지 같은 transaction으로 삭제한다.
- GRDBManager giant façade를 제거한다.

### 검증 방법

- GRDB migration targeted test.
- message/outbox/media/profile/cleanup unit or integration test.
- fresh DB 15개 migration과 legacy table 부재 확인.
- iOS generic simulator build.
- 채팅 검색/미디어/나가기 대표 수동 QA.

### 논의 결과

- D15: legacy migration/table/API 제거와 개발 DB 초기화.
- D16: 소비자별 Protocol과 operation-owning Store transaction.
- D17: 복잡한 mapping에만 선택적 persistence record 도입.
- D18: FTS 오류 전파와 엄격한 transaction rollback.
- 상세 근거는 [Phase 3 GRDB 결정](decisions/phase-3-grdb.md)에 기록했다.

## Phase 4. Firebase Functions modules

### 목표

functions/src/index.ts에서 기능 구현을 제거하고 기존 이름의 flat export만 유지한다.

### 변경 범위 후보

- functions/src/core/
- functions/src/auth/
- functions/src/brand/
- functions/src/lookbook/
- functions/src/chat/
- functions/src/index.ts
- 기존 helper/test 위치 이동
- package test glob이 하위 디렉터리 test를 포함하도록 필요한 경우 조정

### 완료 기준

- index.ts는 bootstrap 의존과 flat export 중심이다.
- admin/runtime 초기화 소유권이 한 곳이다.
- handler/service/validator/mapper 책임이 기능별로 나뉜다.
- 기존 Function export 이름과 runtime option이 유지된다.
- circular import가 없다.

### 검증 방법

- npm test.
- npm run lint.
- npm run build.
- build 결과 export inventory 비교.
- emulator 또는 승인된 callable smoke QA.

### 논의 결과

- D20: 기능 하위 도메인과 functions/service/validator/mapper 책임으로 분리한다.
- D21: Firebase Admin과 global runtime option은 core의 단일 owner가 초기화한다.
- D22: 얇은 wrapper와 작업 단위 service를 분리하되 모든 함수의 factory/interface화는 하지 않는다.
- D23: infrastructure `core`, 공유 도메인 정책 `shared`, feature-local helper를 구분한다.
- D24: `index.ts`는 wildcard 없이 기존 49개 이름만 명시적 flat export한다.
- D25: stale `lib` clean, 하위 test 재귀 발견, export/runtime metadata contract test를 적용한다.
- D26: 저위험 module부터 순차 이전하고 전체 Functions 배포는 별도 승인한다.
- 상세 근거는 [Phase 4 Firebase Functions 결정](decisions/phase-4-firebase-functions.md)에 기록했다.
- 변경 파일과 Step 4A~4I는 [Phase 4 구현 계획](phases/phase-4-firebase-functions.md), contract/service/policy 테스트는 [Phase 4 테스트 계획](phases/phase-4-firebase-functions-tests.md)을 따른다.

## Phase 5. Socket modules

### 목표

Socket/index.js를 server bootstrap으로 축소하고 auth/connection/room/message/media/lifecycle handler와 service를 분리한다.

### 변경 범위 후보

- Socket/index.js
- Socket/src/app/
- Socket/src/auth/
- Socket/src/handlers/
- Socket/src/media/
- Socket/src/lifecycle/
- Socket/package.json
- Socket/src/**/*.test.js 후보

### 완료 기준

- index.js는 dependency 생성, handler 등록, start/shutdown 조립만 담당한다.
- event 이름, payload, ACK, 인증과 persist/fanout 순서가 유지된다.
- process-local mutable state가 한 runtime owner에서 생성되고 주입된다.
- handler가 fake dependency로 검증 가능하다.

### 검증 방법

- npm --prefix Socket run check.
- 승인 시 npm --prefix Socket test.
- 로컬 server readyz/healthz.
- 실제 또는 로컬 인증 연결, room, message, media smoke QA.
- Docker build 또는 Cloud Build 전 syntax/test 확인.

### 논의 필요

- D27~D39 구조·계약 결정은 확정됐다.
- 변경 파일, Step 5A~5H, rollback·중단 조건은 [Phase 5 구현 계획](phases/phase-5-socket.md), test file과 fake/spy·수동 QA는 [Phase 5 테스트 계획](phases/phase-5-socket-tests.md)에 구체화했다.
- D40 media dedupe 강화는 Phase 5 동작 보존 리팩터링과 분리한다. 후속 구현 전에 TTL·용량·timeout과 follower ACK fixture를 확정한다.
- Phase 5 코드 구현과 자동 검증을 완료했다.
- 운영 Cloud Run 배포 시점은 구현·자동 검증 완료 후 별도 승인받는다.

## Phase 6. 통합 검증과 문서 최종화

### 목표

네 영역이 기존 사용자/운영 계약을 유지하는지 통합 확인하고 새 코드 진입점을 하네스에 반영한다.

### 변경 범위 후보

- docs/ai/ENTRYPOINTS.md
- docs/ai/CODE_ARCHITECTURE.md
- docs/ai/entrypoints/DATA.md
- docs/ai/entrypoints/FIREBASE.md
- docs/ai/entrypoints/CHAT.md
- 관련 TESTS 문서
- task progress/qa/decisions
- 필요 시 HANDOFF.md

### 완료 기준

- 다음 작업자가 기능별 구현, DI, API/data contract, 검증 위치를 문서만으로 찾을 수 있다.
- 코드 검색에서 giant manager 직접 의존과 대형 entrypoint 구현이 남지 않는다.
- 모든 자동 검증과 수동 QA 결과가 기록된다.
- 배포가 필요한 영역은 사용자 승인 후 배포 결과와 rollback 지점을 기록한다.

### 검증 방법

- iOS build 및 targeted tests.
- Functions test/lint/build.
- Socket check/test.
- git diff --check.
- 대표 통합 QA.

### 논의 필요

- D41~D48 통합 회귀·배포 순서는 확정됐다.
- 상세 검증은 [Phase 6 통합 회귀 계획](phases/phase-6-integration-tests.md), 배포 gate와 rollback은 [Phase 6 배포 계획](phases/phase-6-deployment.md)을 따른다.
- 동일 SHA 자동 회귀, Socket/Functions 운영 배포, D49 안정화와 승인된 운영 fixture QA까지 완료했다.

## 구현 승인 상태

- Phase 0 문서화: 승인·완료.
- Phase 1 계약 inventory: 승인·완료.
- Phase 2 설계와 구현 계획: 승인·완료.
- Phase 2 코드 수정: 승인·완료.
- Phase 3 설계·구현·테스트 계획 문서화: 승인·완료.
- Phase 3 코드 수정: 승인·완료.
- Phase 3 자동 테스트와 generic Simulator build: 완료.
- Phase 3 수동 QA: Phase 6 채팅·GRDB 통합 QA에서 완료.
- Phase 3 후속 D19 throws 전환: 구현·targeted unit/UI test·generic Simulator build 완료.
- Phase 4 설계·구현·테스트 계획 문서화: 승인·완료.
- Phase 4 코드 수정: 승인·완료.
- Phase 5 설계·구현·테스트 계획 문서화: 승인·완료.
- Phase 5 코드 수정과 자동 검증: 승인·완료.
- Phase 6 결정·통합 회귀·배포 계획 문서화: 승인·완료.
- Phase 6 현재 working tree 자동 회귀 실행: 승인·완료.
- Phase 6 배포 candidate commit과 동일 SHA 재검증: 승인·완료.
- 운영 배포: 승인·완료.
- Phase 6 통합 수동 QA와 fixture cleanup: 완료.
- 작업 종료: 2026-07-14 승인·완료. FCM은 Apple 개발자 계정 결제 후 별도 QA로 이관.
