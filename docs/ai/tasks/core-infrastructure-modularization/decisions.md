# Core Infrastructure Modularization Decisions

## 목적

이번 task의 확정 결정과 구현 전 논의가 필요한 제안을 구분한다.

## 결정 인덱스

| ID | 상태 | 결정 | 상세 |
| --- | --- | --- | --- |
| D1 | 확정 | 현재 배포 단위 안에서 기능별 modular monolith 경계를 만든다. | [모듈 경계](decisions/module-boundaries.md) |
| D2 | 확정 | 기능별 Protocol/Client/Store와 공통 transport/database, 얇은 entrypoint를 사용한다. | [모듈 경계](decisions/module-boundaries.md) |
| D3 | 확정 | iOS 앱, Firebase Functions default codebase, Socket Cloud Run 서비스 배포 경계를 유지한다. | [배포 경계](decisions/deployment-boundaries.md) |
| D4 | 확정 | 기존 wire/data contract를 보존하고 내부 구조만 변경한다. | [호환과 전환](decisions/compatibility-and-transition.md) |
| D5 | 확정 | 계약 inventory 후 iOS Functions → GRDB → Functions → Socket → 통합 순서로 전환한다. | [호환과 전환](decisions/compatibility-and-transition.md) |
| D6 | 확정 | 기존 giant manager façade는 phase 내부에서만 임시 허용하고 phase 종료 전에 제거한다. | [호환과 전환](decisions/compatibility-and-transition.md) |
| D7 | 확정 | Socket에 Node built-in test 기반 최소 계약 테스트를 추가한다. | [검증](decisions/validation.md) |
| D8 | 확정 | RoomListsCollectionViewController의 callHelloUser 직접 호출과 API를 제거한다. | [호환과 전환](decisions/compatibility-and-transition.md) |
| D9 | 확정 | Lookbook 기존 Repository Protocol을 재사용하고 구현체가 feature adapter 역할을 직접 맡는다. | [Phase 2 결정](decisions/phase-2-ios-cloud-functions.md) |
| D10 | 확정 | Protocol은 소비자 기준, mapper/concrete 구현은 기능 응집도 기준으로 나눈다. | [Phase 2 결정](decisions/phase-2-ios-cloud-functions.md) |
| D11 | 확정 | 공통 transport는 Firebase callable와 primitive decoding만 소유한다. | [Phase 2 결정](decisions/phase-2-ios-cloud-functions.md) |
| D12 | 확정 | production DI를 명시화하되 앱 전체 singleton lifecycle 정리는 확장하지 않는다. | [Phase 2 결정](decisions/phase-2-ios-cloud-functions.md) |
| D13 | 확정 | 사용 중인 callable 38개만 이전하고 미사용/서버 전용 iOS surface를 복제하지 않는다. | [Phase 2 결정](decisions/phase-2-ios-cloud-functions.md) |
| D14 | 확정 | callable 38개의 wire 계약과 원본 Firebase 오류 전달을 자동 검증한다. | [Phase 2 결정](decisions/phase-2-ios-cloud-functions.md) |
| D15 | 확정 | 운영 배포 전이므로 GRDB roomImage와 legacy no-op migration을 clean break로 제거한다. | [Phase 3 결정](decisions/phase-3-grdb.md) |
| D16 | 확정 | 소비자 Protocol은 나누고 횡단 transaction은 작업 단위 Store가 소유한다. | [Phase 3 결정](decisions/phase-3-grdb.md) |
| D17 | 확정 | DB 표현이 실제로 다른 타입부터 persistence Record를 선택적으로 분리한다. | [Phase 3 결정](decisions/phase-3-grdb.md) |
| D18 | 확정 | FTS 저장 실패는 message/FTS/media transaction 전체를 rollback한다. | [Phase 3 결정](decisions/phase-3-grdb.md) |
| D19 | 구현·자동 검증 완료 | `AppDatabase.live()` 오류를 throws로 SceneDelegate까지 전달하고 실패 화면·수동 재시도·DEBUG once/always 주입으로 복구 경계를 검증한다. | [Phase 3 결정](decisions/phase-3-grdb.md) |
| D20 | 확정 | Firebase Functions는 기능 하위 도메인과 역할별 module로 분리한다. | [Phase 4 결정](decisions/phase-4-firebase-functions.md) |
| D21 | 확정 | Firebase Admin 초기화와 global runtime option은 core가 각각 한 번 소유한다. | [Phase 4 결정](decisions/phase-4-firebase-functions.md) |
| D22 | 확정 | 얇은 Functions wrapper와 작업 단위 service를 분리하되 모든 함수에 factory/interface를 강제하지 않는다. | [Phase 4 결정](decisions/phase-4-firebase-functions.md) |
| D23 | 확정 | infrastructure `core`와 여러 feature가 공유하는 도메인 정책 `shared`를 구분한다. | [Phase 4 결정](decisions/phase-4-firebase-functions.md) |
| D24 | 확정 | `index.ts`는 기존 49개 이름만 명시적으로 flat export한다. | [Phase 4 결정](decisions/phase-4-firebase-functions.md) |
| D25 | 확정 | clean build, 하위 test 재귀 발견과 export/runtime metadata contract test를 도입한다. | [Phase 4 결정](decisions/phase-4-firebase-functions.md) |
| D26 | 확정 | 위험이 낮은 module부터 순차 이전하고 전체 Functions 배포는 별도 승인한다. | [Phase 4 결정](decisions/phase-4-firebase-functions.md) |
| D27 | 확정 | Socket은 Node 22 JavaScript ESM을 유지한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D28 | 확정 | `index.js`는 bootstrap과 lifecycle 조립만 담당한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D29 | 확정 | `createSocketApplication`을 listen과 분리된 application 조립 경계로 둔다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D30 | 확정 | Firebase Admin 초기화를 명시적인 bootstrap dependency로 만든다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D31 | 확정 | 기능별 `register*Handlers` factory로 event 등록 책임을 나눈다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D32 | 확정 | handler는 좁은 service에 의존하고 service가 db/admin 작업 단위 부작용을 소유한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D33 | 확정 | socket runtime, room registry, rate limiter와 media dedupe state owner를 분리한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D34 | 확정 | clock과 ID generator를 주입 가능하게 한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D35 | 확정 | 기존 event/payload/ACK와 side-effect 순서를 보존한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D36 | 확정 | Phase 5 모듈화에서는 media dedupe 의미 변경을 분리한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D37 | 확정 | startup, health와 graceful shutdown 계약을 보존한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D38 | 확정 | dependency 없는 재귀 `node:test` runner를 사용한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D39 | 확정 | 기존 Docker image와 Socket Cloud Run service 배포 경계를 유지한다. | [Phase 5 결정](decisions/phase-5-socket.md) |
| D40 | 후속 task에서 최종 범위 재확정 | 실시간 발신 메시지 전체를 in-flight Promise와 Firestore transaction winner 기반 단일 emit/push로 강화하고, iOS 수신 ingress에서 방별 최근 message ID 300개를 중복 제거한다. | [Phase 5 결정](decisions/phase-5-socket.md), [후속 결정](../socket-message-dedupe-hardening/decisions.md) |
| D41 | 확정 | Phase 2~5 관련 targeted test와 iOS generic build를 통합 회귀 기준으로 사용한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D42 | 확정 | 새 Firebase emulator를 도입하지 않고 기존 자동 계약 테스트와 통제된 운영 smoke를 결합한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D43 | 확정 | 배포 가능한 commit과 복구 가능한 rollback 기준을 배포 전에 확정한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D44 | 확정 | 전체 자동 회귀 후 Socket을 먼저 배포하고 gate 통과 뒤 Functions를 배포한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D45 | 확정 | Socket은 traffic split 없이 새 revision 100%로 전환하고 이전 revision으로 전체 rollback한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D46 | 확정 | Firebase Functions default codebase 49개 export를 전체 배포한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D47 | 확정 | Socket과 Functions 배포를 독립적인 중단·rollback gate로 운영한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D48 | 확정 | 양쪽 gate 통과 후 iOS 종단 QA를 수행하며 D40은 Phase 6에서 제외한다. | [Phase 6 결정](decisions/phase-6-integration-deployment.md) |
| D49 | 구현·자동/실제 reconnect gate 완료 | iOS Socket listener를 client 생성 시 한 번만 등록하고 active reconnect 중 off/on을 금지하며 raw auth logging을 제거한다. | [Phase 6 iOS Socket 안정화](phases/phase-6-ios-socket-stabilization.md) |

## 현재 상태

- D4~D19는 2026-07-13, D20~D49는 2026-07-14 사용자 승인으로 확정됐다. D40은 후속 `socket-message-dedupe-hardening`에서 완료 캐시 제외, 별도 owner timeout 미도입, text/Lookbook/image/video 상세 transaction winner 계약과 iOS 방별 최근 message ID 300개 ingress dedupe로 최종 범위를 재확정했다.
- Phase 1 계약 inventory는 완료했다.
- Phase 2 설계, 코드 구현과 자동 검증을 완료했다.
- Phase 3와 후속 D19 구현·자동 검증을 완료했다. D19-A~E와 DEBUG once/always 실패·복구 UI가 코드와 테스트에 반영됐다.
- Phase 4 N7~N13은 D20~D26으로 확정했고 구현·자동 검증을 완료했다. 운영 배포는 별도 승인 대기다.
- Phase 5 N14~N26은 D27~D39로 확정했다. D40 media dedupe 강화는 Phase 5 동작 보존 리팩터링과 분리한 후속 작업으로 기록했다.
- Phase 5 변경 파일, Step 5A~5H, rollback·중단 조건과 test file을 문서화하고 코드 구현·자동 검증·ADC 기반 local smoke까지 완료했다. 운영 배포와 Cloud Run/iOS 송수신 smoke는 별도 승인 대기다.
- Phase 6 N27~N34는 D41~D48로 확정했다. 통합 회귀와 Socket → Functions 순차 배포·독립 gate/rollback 계획을 문서화했으며 실행·커밋·운영 배포는 별도 승인 대기다.
- Socket/Functions 배포 후 iOS reconnect crash를 발견해 D49 one-time listener binding과 raw auth logging 제거를 별도 안정화 Step으로 확정했다. 구현, 자동 검증, cold/background 각 5회와 room/text 실제 gate까지 완료했다.

## 장기 결정

여러 feature와 이후 작업에 반복 적용될 D1~D3은 ADR-019에 기록한다. D4~D49는 이 task의 전환·검증 결정으로 유지한다.
