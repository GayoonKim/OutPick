# Active Task Index

## 현재 상태

- 현재 등록된 핵심 task는 없다. `socket-ingress-ordering-hardening`은 Phase 1~6 구현, 자동 회귀와 실제 Firebase/Simulator 핵심 QA를 완료하고 2026-07-17 종료했다.
- `socket-message-dedupe-hardening`은 구현·자동 회귀·candidate closeout을 완료하고 2026-07-16 종료했다.
- `firestore-document-id-boundary-cleanup`은 Phase 1~4 구현·QA, rules 운영 배포, 운영 `Rooms.ID` cleanup과 사후 재감사까지 완료하고 2026-07-14 종료했다.
- `core-infrastructure-modularization`은 Phase 2~5 구현, Phase 6 동일 SHA 회귀, Socket/Functions 운영 배포, D49 안정화와 통합 수동 QA까지 완료하고 2026-07-14 종료했다.
- FCM/APNs 채팅 알림은 Apple Developer 계정 결제와 APNs/Firebase Apple app 설정 후 별도 구현·실기기 QA task로 진행한다. 초기에는 메시지별 알림과 방별 thread grouping을 사용하고 custom 요약은 운영 피드백 이후 검토한다.
- Chat route/ViewModel 중복 생존 가능성은 별도 후속 분석 후보다. 새 Chat push가 기존 route lifecycle만 종료하고 navigation stack에서 제거하지 않는 경로를 동일 방 재진입·알림/deep link·deinit 증거로 확인한 뒤, 결함으로 판정될 때만 수정안을 논의한다.
- `socket-ingress-ordering-hardening`의 선택적 후속 QA는 이미 보이는 target의 card 억제와 실기기 VoiceOver 발화·포커스 확인이다. 핵심 읽음·수렴 정확성 완료를 막지 않으며 필요할 때 별도 QA로 수행한다.
- 최근 완료 구현 작업은 `socket-ingress-ordering-hardening`이다.
- 새 작업을 시작할 때 이 문서에는 현재 task 한 건과 바로 이전 완료 작업만 상세 링크로 유지한다.
- 오래된 완료 이력은 각 task의 `progress.md`, 장기 결정은 `docs/ai/ADR.md`에서 확인한다.

## 현재 핵심 작업

등록된 작업 없음.

## 최근 완료 작업

| 작업 | 상태 | 핵심 결과 | 상세 |
| --- | --- | --- | --- |
| `socket-ingress-ordering-hardening` | 완료·Phase 1~6 자동 회귀와 실제 Firebase/Simulator QA 완료 | 순차 ingress, visible strict recovery, bounded Banner, reconnect/route lifecycle, 대규모 unread catch-up과 visible read frontier | [progress](socket-ingress-ordering-hardening/progress.md), [qa](socket-ingress-ordering-hardening/qa-checklist.md), [Phase 6](socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md) |
| `socket-message-dedupe-hardening` | 완료·candidate closeout 완료·운영 traffic 전환 별도 승인 | 전체 실시간 메시지 winner-only emit/push, 공통 ACK 수렴과 iOS 최근 ID 300개 ingress dedupe | [progress](socket-message-dedupe-hardening/progress.md), [qa](socket-message-dedupe-hardening/qa-checklist.md) |
| `firestore-document-id-boundary-cleanup` | 완료·rules 운영 배포·데이터 cleanup·통합 QA 완료 | 경로 document ID를 canonical source로 통일하고 앱 `@DocumentID`와 운영 Rooms 중복 ID를 제거 | [progress](firestore-document-id-boundary-cleanup/progress.md), [qa](firestore-document-id-boundary-cleanup/qa-checklist.md), [ADR-020](../adr/ADR-020-firestore-문서-identity는-문서-경로-id를-단일-기준으로-사용한다.md) |
| `core-infrastructure-modularization` | 완료·운영 배포·통합 QA 완료, FCM 별도 보류 | iOS Functions/GRDB, Firebase Functions, Socket을 기능별 경계와 공통 runtime, 얇은 entrypoint로 전환 | [progress](core-infrastructure-modularization/progress.md), [qa](core-infrastructure-modularization/qa-checklist.md), [ADR-019](../adr/ADR-019-핵심-인프라는-기능별-모듈러-경계와-현재-배포-단위를-유지한다.md) |
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
