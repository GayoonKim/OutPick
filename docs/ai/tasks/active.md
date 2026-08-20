# Active Task Index

## 현재 상태

- 현재 핵심 task는 `chat-ugc-safety-room-moderation`이다. Phase 0~6 구현·자동 검증·Development QA와 Production backend rollout을 완료했다. Phase 7.0~7.3 attachment별 단일 signed PUT 구현과 Development backend rollout, JPEG·HEIC·PNG·GIF, 31장·70장 FIFO, 영상 앱 종료·방 이탈 후 복구 실기기 QA를 완료했다. 350 MiB 정확 경계·초과와 실제 1시간 영상은 자동 통합 검증을 통과했다. 현재 Phase 7.3 릴리스 후보를 Production에 반영한 뒤 Phase 7.4 evidence backend로 진행한다.
- Phase 6은 자동 의미 필터 미도입, 전송 burst guard, 입력 상한, senderEmail 제거와 로그 최소화를 반영했다. Phase 7은 전용 Cloud Run 기술 검증·metadata 제거, 이미지 30장/GIF, 350 MiB·길이 제한 없는 동영상, 선택 첨부 evidence, 개인/전역 비노출·복원·retention 세부 설계를 확정했다. Phase 7.3 pending UX는 정규화 직후 upload source 기반 1024px 메모리 다운샘플링 로컬 버블, 활성 상태 무표시, 실패·만료에만 시간 위치의 소형 재시도/삭제 아이콘으로 고정했다. GIF badge/viewer, 이미지·영상 실패의 재시도/삭제 전용 표시, 네트워크 재연결, 앱 종료·방 이탈 복원, 70장 30+30+10 FIFO 실기기 QA를 완료했고, 실패 outbox 재실행의 반복 날짜 separator diffable ID 크래시도 occurrence identity와 회귀 테스트로 보정했다. Production backend·Production 구성 빌드 및 smoke가 현재 승인된 배포 gate이며 Sign in with Apple은 별도 후속 작업이다.
- 이전 핵심 task `style-mood-personalization-account-privacy`의 Phase 1~8은 완료 처리했다. Apple Developer Program 가입 후 App Attest 실기기 QA와 운영 백업 설정은 출시 운영 게이트로 분리하고, 개발 데이터 전체 삭제는 마지막 Phase의 별도 승인 전까지 진행하지 않는다.
- `lookbook-discovery-learning-loop`는 사용자 승인으로 task 문서를 생성했다. 동일 active 요청 병합, latest generation publish, 기존 시즌 동일성, 7/30/60일 retention, failure action, watchdog 복구, 관리자 review와 fixture/version gate를 설계 기준으로 확정했다.
- `socket-ingress-ordering-hardening`은 Phase 1~6 구현, 자동 회귀와 실제 Firebase/Simulator 핵심 QA를 완료하고 2026-07-17 종료했다.
- `socket-message-dedupe-hardening`은 구현·자동 회귀·candidate closeout을 완료하고 2026-07-16 종료했으며, 2026-07-22 사용자 승인 후 candidate를 운영 traffic 100%로 전환했다.
- `firestore-document-id-boundary-cleanup`은 Phase 1~4 구현·QA, rules 운영 배포, 운영 `Rooms.ID` cleanup과 사후 재감사까지 완료하고 2026-07-14 종료했다.
- `core-infrastructure-modularization`은 Phase 2~5 구현, Phase 6 동일 SHA 회귀, Socket/Functions 운영 배포, D49 안정화와 통합 수동 QA까지 완료하고 2026-07-14 종료했다.
- FCM/APNs 채팅 알림은 Apple Developer 계정 결제와 APNs/Firebase Apple app 설정 후 별도 구현·실기기 QA task로 진행한다. 초기에는 메시지별 알림과 방별 thread grouping을 사용하고 custom 요약은 운영 피드백 이후 검토한다.
- Chat route/ViewModel 생존 분석에서 LLDB expression retain 오염과 production Back deinit을 분리해 retain leak 가설은 기각했다. 확인된 같은 stack의 종료 route 부분 복귀와 `openRoom` 경쟁은 완료한 `chat-route-lifecycle-hardening`에서 수정·검증했다. 추가 retain 경로 분석은 2026-07-22 사용자 결정으로 후속 목록에서 제외했으며, 디버거 오염 없는 production 지속 생존이 새로 재현될 때만 별도 leak task로 연다.
- `socket-ingress-ordering-hardening`의 이미 보이는 target card 억제는 2026-07-22 사용자 수동 QA로 완료했다. 실기기 VoiceOver 발화·포커스 확인은 같은 날 사용자 결정으로 후속 범위에서 제외했다. 기존 접근성 label/value 구현은 유지한다.
- 최근 완료 구현 작업은 `development-production-environment-separation`이다.
- 새 작업을 시작할 때 이 문서에는 현재 task 한 건과 바로 이전 완료 작업만 상세 링크로 유지한다.
- 오래된 완료 이력은 각 task의 `progress.md`, 장기 결정은 `docs/ai/ADR.md`에서 확인한다.

## 현재 핵심 작업

- `chat-ugc-safety-room-moderation`
  - [결정](chat-ugc-safety-room-moderation/decisions.md)
  - [Phase 계획](chat-ugc-safety-room-moderation/plan.md)
  - [현재 상태](chat-ugc-safety-room-moderation/progress.md)
  - [QA 기준](chat-ugc-safety-room-moderation/qa-checklist.md)
  - 상태: Phase 0~6 구현·자동 검증·Development 사용자 QA와 Production Functions·Rules·exact TTL·Socket rollout 완료. Phase 7.0 worker·Linux fixture, Phase 7.1 격리·job lifecycle, Phase 7.2 ready·delivery·cleanup, Phase 7.3 attachment별 단일 signed PUT과 형식·GIF·31/70장 FIFO·종료/이탈 복구 QA 완료. 현재 승인된 Phase 7.3 Production backend rollout과 Production 구성 빌드·smoke 후 Phase 7.4 evidence backend로 전환한다.

## 이전 핵심 작업

- `lookbook-extraction-issue-operations`
  - [설계](lookbook-extraction-issue-operations/design.md)
  - [현재 상태](lookbook-extraction-issue-operations/progress.md)
  - [QA 기준](lookbook-extraction-issue-operations/qa-checklist.md)
  - 상태: Phase 1~7 구현, Development contract 3 배포와 실제 상세/목록 cover QA 완료. 이벤트 기반 이미지 fix QA와 Production rollout을 후속 경계로 분리하고 2026-08-06 종료.

- `development-production-environment-separation`
  - [앱 환경 진입점](../entrypoints/APP.md)
  - [Firebase·worker 환경 진입점](../entrypoints/FIREBASE.md)
  - [PR #3](https://github.com/GayoonKim/OutPick/pull/3)
  - 상태: Phase 1~4, Production 인증 Function identity 전환, Development/Production import smoke, PR #3 병합과 Production Worker traffic 전환 완료. 실기기 App Attest만 Apple Developer Program 가입 후 외부 의존 후속 작업으로 유지.

## 다음 핵심 작업

- `lookbook-discovery-learning-loop`
  - [설계](lookbook-discovery-learning-loop/design.md)
  - [결정](lookbook-discovery-learning-loop/decisions.md)
  - [Phase 계획](lookbook-discovery-learning-loop/plan.md)
  - [현재 상태](lookbook-discovery-learning-loop/progress.md)
  - [QA 기준](lookbook-discovery-learning-loop/qa-checklist.md)
  - 상태: Phase 1·3 완료, Phase 2 핵심 구현 완료·통합 배포 대기, Phase 4 backend review 완료·learning UI 일부 대기.

## 논의 완료·착수 대기 핵심 작업

- `customer-support-https-page`
  - 상태: App Store 제출·외부 사용자 배포 전에 HTTPS 고객지원 페이지를 제공하는 후속 작업. 문의 수단, 계정 제한 이의제기, 신고 처리 문의, 개인정보 처리방침과 계정 삭제 안내가 범위 후보이며 요구사항·호스팅·URL·구현 계획은 미확정·미승인.
- `sign-in-with-apple-account-lifecycle`
  - 상태: Sign in with Apple 로그인·재인증·계정 삭제·동일 provider 재가입 moderation principal 복원을 별도 후속 작업으로 기록했다. 정책·콘솔·제품 흐름·아키텍처 요구사항 미논의, 계획 미작성, 구현 미승인.
- `chat-room-moderator-delegation`
  - [현재 경계](chat-room-moderator-delegation/decisions.md)
  - 상태: 방 생성자가 다른 참여자에게 관리자 권한을 임명·회수하는 기능을 별도 작업으로 분리. 채팅 안전 작업의 공통 room moderation authorization을 선행 조건으로 하며 세부 제품·권한 설계 미확정·구현 미승인.
- `admin-web-operations-migration`
  - [확정 결정](admin-web-operations-migration/decisions.md)
  - 상태: 총관리자 전용 관리자 웹의 운영 범위와 브랜드 권리 확인 흐름 기록 완료. 웹 기술 스택·구현 계획 미작성·구현 미승인.
- `ios-admin-console-removal`
  - [확정 결정](ios-admin-console-removal/decisions.md)
  - 상태: 모든 iOS 환경·구성에서 관리자 콘솔을 제거하는 범위 기록 완료. 관리자 웹 운영 기능 동등성 검증 뒤 착수하며 구현 계획 미작성·구현 미승인.

### 권장 진행 순서

1. `chat-ugc-safety-room-moderation`: 서버 권위의 room moderation authorization, 메시지 삭제, 신고·차단, 기술적 전송 남용 방어, 내보내기·재입장 차단을 먼저 확립한다.
2. `customer-support-https-page`: 외부 배포 전에 공개 문의·제한 이의제기·신고 처리·개인정보·계정 삭제 경로를 준비한다. 내부 QA 중에는 병렬 후속 준비가 가능하다.
3. `chat-room-moderator-delegation`: 앞 작업의 공통 권한 판정에 관리자 membership을 추가해 다른 채팅·웹 범위에 영향을 퍼뜨리지 않는다.
4. `admin-web-operations-migration`: 준비된 채팅 신고·제재 API와 기존 룩북 운영 API를 소비하는 총관리자 웹을 구축하고 운영 동등성을 검증한다.
5. `ios-admin-console-removal`: 관리자 웹 운영 전환이 끝난 뒤 모든 iOS 구성에서 내부 관리자 콘솔을 제거한다.

- 필수 의존성은 `chat-ugc-safety-room-moderation → chat-room-moderator-delegation`, `chat-ugc-safety-room-moderation의 신고·제재 API → admin-web-operations-migration의 채팅 운영 화면`, `admin-web-operations-migration 동등성 검증 → ios-admin-console-removal`이다.
- `chat-room-moderator-delegation`은 관리자 웹과 iOS 관리자 콘솔 제거의 필수 선행 조건은 아니지만, 채팅 권한 도메인을 연속해서 안정화하고 회귀 범위를 닫기 위해 두 번째 순서를 권장한다.

## 다음 핵심 작업 상세

- `lookbook-discovery-learning-loop`
  - 범위: 브랜드 생성 직후 시즌 후보를 자동 추출하고, 관리자 확인 후 선택한 시즌의 이미지만 추출하는 흐름을 유지한다. season discovery의 구조 evidence, issue cluster, 관리자 정상/누락/오탐 피드백, 최소 fixture 승격, extractor version gate를 포함한다.
  - 비동기 경계: `CreateBrandDiscoveryViewModel`이 Firestore 관찰을 소유하고 화면 종료 시 관찰만 끝낸다. 서버 job은 계속되며 최초 job ID 또는 브랜드 published pointer로 상태와 결과를 복원한다.
  - 시즌 동일성: URL 일치 여부를 우선 사용하되, URL이 달라도 동일 브랜드 안에서 정규화한 시즌 이름이 기존 시즌 하나와 유일하게 일치하면 새 시즌을 만들지 않고 기존 시즌으로 연결해 최신 source URL만 갱신한다. 대소문자·공백과 `F/W`/`FW`, `S/S`/`SS` 표기를 정규화하고, `LOOKBOOK`·`COLLECTION`·`CAMPAIGN`처럼 구체적이지 않은 이름이나 복수 일치는 자동 연결하지 않고 관리자 검토 대상으로 둔다. URL 갱신만으로 이미지 재추출을 자동 시작하지 않는다.
  - 회귀·배포 게이트: Generic/Platform/Domain 추출 규칙 변경은 영향 범위가 다르지만 항상 전체 fixture corpus를 실행한다. Domain은 정확한 host·platform·실제 fixture 연결과 비대상 host 격리를, Platform은 여러 브랜드 fixture와 타 플랫폼 오탐 방지를, Generic은 모든 platform/domain/incident differential과 대표 실제 URL smoke를 추가로 요구한다. 기존 성공 결과의 후보 수·집합·순서·제목·strategy·adapter·quality가 예상하지 않게 바뀌면 candidate 배포를 중단한다. 의도된 개선은 관리자 ground truth 확인, golden expected 명시 갱신, extractor/adapter version bump, Development smoke와 사용자 승인 후에만 Production으로 전환한다. 장기적으로 CI required check와 검증되지 않은 직접 배포·traffic 전환 차단을 포함한 강한 게이트를 설계한다.
  - Fixture·재발 관리: fixture는 브랜드 수와 1:1로 늘리지 않고 platform, template signature, strategy, failure/quality reason, 구조 token을 기준으로 같은 원인은 기존 issue cluster와 대표 fixture에 통합한다. 새 fixture는 기존 fixture가 표현하지 못하는 의미 있는 구조·동작 분기에만 추가한다. `fixedInExtractorVersion`보다 낮은 Worker에서 생긴 occurrence는 배포 drift로 분리하고, 수정 버전 이상에서 같은 fingerprint가 재발하면 cluster를 `open`으로 되돌려 `recurrenceCount`를 증가시키며 새 실패보다 우선 조사한다. 이때 기존 fixture도 실패하면 코드 회귀로 배포 중단·rollback, fixture는 통과하지만 실제 URL만 실패하면 fixture 불충분·새 구조 변형·adapter 미선택·잘못된 계층 배치·네트워크/차단 원인을 구분한다. 같은 cluster로 묶는 것은 중복 fixture 생성을 막는 것이며 재발을 무시하거나 자동 승인하는 의미가 아니다.
  - 실패·복구: 최초 job은 `createBrand` transaction에서 함께 만들고, active job은 watchdog이 누락 task·만료 lease·stale generation·retry 소진을 감시해 복구 또는 종료 상태로 수렴시킨다. `awaitingReview/correctionRequired`는 실행 중이 아닌 action-required 상태이며 관리자 판단, 로직 보강 후 재분석, 취소로 닫는다. 시즌 목록은 새 discovery generation, 시즌 이미지는 기존 import job의 새 review/dispatch generation으로 재분석한다.
  - 상태: durable Functions/Worker, rules/index/TTL 설정, iOS 생성 플로우 접합부 구현과 자동 검증 완료. 관리자 review/re-entry UI, extractor 재분석/issue cluster UI, Development/Production 배포는 미수행.

## 최근 완료 작업

| 작업 | 상태 | 핵심 결과 | 상세 |
| --- | --- | --- | --- |
| `lookbook-extraction-issue-operations` | 완료·Development contract 3 배포·실데이터 QA | IAM issue operations, runtime verifier, 안전 retry 상태, AMOMENTO 15개 상세 fallback과 OUTSTANDING 44개 목록 cover 회귀 | [progress](lookbook-extraction-issue-operations/progress.md), [qa](lookbook-extraction-issue-operations/qa-checklist.md) |
| `development-production-environment-separation` | 완료·PR #3 병합·Production Worker traffic 100% | 두 scheme/네 configuration, Firebase·Socket·Worker fail-fast, 환경별 auth/OIDC identity, Development/Production import smoke | [APP](../entrypoints/APP.md), [FIREBASE](../entrypoints/FIREBASE.md), [PR #3](https://github.com/GayoonKim/OutPick/pull/3) |
| `lookbook-extraction-learning-loop` | 완료·Phase 1~8·운영 worker 배포와 실제 URL smoke·YOUTH 데이터 정리 완료 | silent under-extraction 차단, review/trust/evidence/repair, Generic→Cafe24 adapter와 fixture differential | [progress](lookbook-extraction-learning-loop/progress.md), [qa](lookbook-extraction-learning-loop/qa-checklist.md) |
| `chat-route-lifecycle-hardening` | 완료·Phase 6~9 자동 회귀와 Simulator/실기기 QA 완료 | 탭별 Chat stack, same-stack 교체, stack별 request 경쟁, terminal/transient lifecycle, UIKit edge-pop과 Chat gesture 책임 정리 | [progress](chat-route-lifecycle-hardening/progress.md), [qa](chat-route-lifecycle-hardening/qa-checklist.md) |
| `socket-ingress-ordering-hardening` | 완료·Phase 1~6 자동 회귀와 실제 Firebase/Simulator QA 완료 | 순차 ingress, visible strict recovery, bounded Banner, reconnect/route lifecycle, 대규모 unread catch-up과 visible read frontier | [progress](socket-ingress-ordering-hardening/progress.md), [qa](socket-ingress-ordering-hardening/qa-checklist.md), [Phase 6](socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md) |
| `socket-message-dedupe-hardening` | 완료·candidate closeout·운영 traffic 100% 전환 완료 | 전체 실시간 메시지 winner-only emit/push, 공통 ACK 수렴과 iOS 최근 ID 300개 ingress dedupe | [progress](socket-message-dedupe-hardening/progress.md), [qa](socket-message-dedupe-hardening/qa-checklist.md) |
| `firestore-document-id-boundary-cleanup` | 완료·rules 운영 배포·데이터 cleanup·통합 QA 완료 | 경로 document ID를 canonical source로 통일하고 앱 `@DocumentID`와 운영 Rooms 중복 ID를 제거 | [progress](firestore-document-id-boundary-cleanup/progress.md), [qa](firestore-document-id-boundary-cleanup/qa-checklist.md), [ADR-020](../adr/ADR-020-firestore-문서-identity는-문서-경로-id를-단일-기준으로-사용한다.md) |
| `core-infrastructure-modularization` | 완료·운영 배포·통합 QA 완료, FCM 별도 보류 | iOS Functions/GRDB, Firebase Functions, Socket을 기능별 경계와 공통 runtime, 얇은 entrypoint로 전환 | [progress](core-infrastructure-modularization/progress.md), [qa](core-infrastructure-modularization/qa-checklist.md), [ADR-019](../adr/ADR-019-핵심-인프라는-기능별-모듈러-경계와-현재-배포-단위를-유지한다.md) |
| `lookbook-deletion-purge-drain` | 완료·운영 배포·QA 완료 | 일일 purge의 전체 20개 상한 제거, cursor drain, 브랜드별 lease/최대 3개 병렬, 7분 claim cutoff | [progress](lookbook-deletion-purge-drain/progress.md), [decisions](lookbook-deletion-purge-drain/decisions.md), [ADR-018](../adr/ADR-018-룩북-영구-삭제는-일일-bounded-drain과-브랜드-lease로-처리한다.md) |
| `lookbook-deletion-request-list-simplification` | 완료·운영 배포·수동 QA 완료 | 앱 삭제 요청 목록을 `active/failed`로 단순화하고 총 관리자 manual retry 추가 | [progress](lookbook-deletion-request-list-simplification/progress.md), [decisions](lookbook-deletion-request-list-simplification/decisions.md) |
| `lookbook-admin-soft-delete-lifecycle` | 완료·운영 배포·통합 QA 완료 | 7일 복구 가능 soft delete와 scheduled hard delete lifecycle | [progress](lookbook-admin-soft-delete-lifecycle/progress.md), [decisions](lookbook-admin-soft-delete-lifecycle/decisions.md) |
| `admin-request-list-retention-unification` | 완료, 일부 삭제 목록 정책은 후속 작업으로 대체됨 | 브랜드 요청 처리 이력 14일 정책 | [progress](admin-request-list-retention-unification/progress.md), [decisions](admin-request-list-retention-unification/decisions.md) |
| `admin-web-brand-season-management` | 완료·운영 배포·통합 QA 완료 | 앱 관리자 브랜드/시즌 관리와 import 흐름 | [progress](admin-web-brand-season-management/progress.md), [decisions](admin-web-brand-season-management/decisions.md) |

`admin-request-list-retention-unification`의 삭제 요청 완료/history UI 계약은 후속 `lookbook-deletion-request-list-simplification`에서 제거됐다. 현재 계약은 항상 후속 task를 우선한다.

## 최근 작업 코드 진입점

### Chat route lifecycle hardening

1. 제품·기술 결정: `chat-route-lifecycle-hardening/decisions.md`
2. 구현 계획과 변경 파일 후보: `chat-route-lifecycle-hardening/plan.md`
3. route owner: `OutPick/Features/Chat/ChatCoordinator.swift`
4. lifecycle state: `OutPick/Features/Chat/ChatRoomRouteLifecycleState.swift`
5. stack 배치 정책: `OutPick/Features/Chat/ChatNavigationStackPolicy.swift`
6. request state/Task owner: `OutPick/Features/Chat/ChatOpenRoomRequestState.swift`, `ChatOpenRoomRequestRegistry.swift`
7. 화면 transient 복귀: `OutPick/Features/Chat/Controllers/ChatViewController.swift`
8. cross-feature route: `OutPick/App/Routing/DefaultAppContentRouter.swift`
9. 룩북 이동 UI: `OutPick/Features/Lookbook/Views/Shared/LookbookShareConfirmationBar.swift`, Brand/Season/Post detail views
10. 자동 검증: `OutPickTests/ChatNavigationControllerTests.swift`, `ChatNavigationStackPolicyTests.swift`, `ChatOpenRoomRequestStateTests.swift`, `ChatOpenRoomRequestRegistryTests.swift`, `ChatRoomRouteLifecycleStateTests.swift`
11. 검증 설계: `chat-route-lifecycle-hardening/qa-checklist.md`
12. 완료한 Phase 6~9: UIKit pop A/B와 최소 수정 → 미사용 interactive transition 제거 → Chat tap/long-press 범위 축소 → 핵심 24개·영향 범위 86개 회귀와 실기기 QA

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
- iOS: `OutPick-Development` 또는 `OutPick-Production` scheme과 대응 configuration을 명시해 build
- Firestore: 관련 workflow에 따라 rules/index dry-run 후 승인된 범위만 배포
- 데이터 삭제/운영 배포: 사용자 명시 승인 필요

## 다음 작업 등록 규칙

1. 새 task 디렉터리의 `design.md`, `decisions.md`, `plan.md`, `progress.md`, `qa-checklist.md`를 사용자 승인 후 만든다.
2. 이 문서의 `현재 상태`에는 한 건의 현재 task만 둔다.
3. 완료 시 표에 한 줄을 추가하되 상세 phase 이력은 복사하지 않는다.
4. 여러 작업에 반복 적용할 결정만 ADR로 승격한다.
5. 코드 진입점이 바뀌면 `docs/ai/ENTRYPOINTS.md`와 관련 `entrypoints/*.md`를 함께 갱신한다.
