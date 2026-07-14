# Phase 6 Integration And Deployment Decisions

## 상태

2026-07-14 사용자 승인으로 N27~N34를 D41~D48로 확정했다. Phase 6는 Phase 2~5의 동작 보존 여부를 통합 검증하고 Functions/Socket을 서로 독립적인 gate로 배포하는 단계다. 이 문서는 결정만 기록하며 자동 검증 실행, 커밋, 운영 배포와 운영 fixture 생성은 각각 별도 승인 후 수행한다.

## D41. 관련 phase targeted test와 iOS generic build를 통합 회귀 기준으로 사용한다

- Phase 2 Cloud Functions adapter, Phase 3 GRDB/Chat, D19 bootstrap unit/UI test를 묶어 실행한다.
- 전체 프로젝트의 모든 iOS test를 무조건 실행하지 않고 이번 리팩터링의 변경 경계와 직접 소비자를 검증한다.
- generic iOS Simulator build로 조립·링크 회귀를 보완한다.

이유:

- 모든 전역 test의 비용과 무관한 기존 실패를 Phase 6 gate에 섞지 않으면서 변경된 transport/database/bootstrap/DI 경계를 모두 포함한다.
- 단순 UI happy path보다 서버 실패, transaction, bootstrap 복구와 wire 계약을 우선한다.

## D42. 새 Firebase emulator 체계를 Phase 6에 도입하지 않는다

- Functions는 기존 contract/policy/service test, lint와 build를 자동 gate로 사용한다.
- Socket은 fake 기반 event/ACK/service test와 ADC local start smoke를 사용한다.
- 실제 IAM, callable transport와 Socket.IO transport는 통제된 운영 smoke로 보완한다.

이유:

- 현재 격리된 emulator fixture와 cleanup 기준선이 없다.
- emulator 구축을 이번 구조 리팩터링에 섞으면 검증 대상보다 test infrastructure 변경이 더 커진다.

재검토 조건:

- Functions/Firestore/Storage를 함께 재현해야 하는 회귀가 반복되거나 운영 smoke fixture 관리 비용이 커질 때 별도 task로 설계한다.

## D43. 배포 가능한 commit과 rollback 기준을 배포 전에 먼저 확정한다

- iOS app, iOS test, Functions, Socket과 문서는 프로젝트 커밋 원칙에 따라 작업 단위별 commit 후보로 분리한다.
- dirty worktree 자체를 운영 배포 기준으로 사용하지 않는다.
- Socket image tag는 `manual` 재사용 대신 배포 commit SHA를 포함한다.
- Functions는 현재 운영 배포 소스와 Git commit 또는 복구 가능한 source archive의 대응 관계를 확인해야 한다.

중단 조건:

- 현재 운영 Functions source를 되돌릴 기준을 확인하지 못하면 Functions 배포를 시작하지 않는다.
- 배포할 commit과 자동 검증 결과가 다르면 배포하지 않고 검증을 다시 수행한다.

현재 확인 상태:

- 2026-07-14 읽기 전용 확인 시 Socket 운영 트래픽 100%는 `outpick-socket-00005-jwg`를 사용했다.
- 이 revision은 시간에 따라 바뀔 수 있으므로 배포 직전에 다시 조회한다.
- 2026-07-14 대표 배포 archive 전체 source/config와 49개 동일 source hash를 확인해 운영 Functions prior source가 Git HEAD `ccc141e`와 일치함을 확인했다.

## D44. Socket을 먼저 배포하고 gate 통과 후 Functions를 배포한다

순서:

1. 전체 자동 회귀.
2. Socket 단독 배포와 smoke.
3. Socket gate 통과.
4. Functions 전체 배포와 smoke.
5. 두 서버를 사용하는 iOS 종단 QA.

이유:

- Functions와 Socket은 서로를 직접 호출하지 않고 Firestore/Storage 계약을 공유하는 독립 배포 단위다.
- Socket은 Cloud Run revision traffic을 이전 revision으로 되돌리는 rollback이 Functions 전체 재배포보다 빠르다.
- 각 gate를 분리하면 장애 원인을 Socket과 Functions 중 하나로 격리할 수 있다.

## D45. Socket은 traffic split 없이 새 revision 100%로 전환한다

- 새 revision과 이전 revision을 동시에 serving하는 canary traffic split을 사용하지 않는다.
- 배포 전 이전 ready revision과 image digest를 기록한다.
- 실패 시 이전 revision으로 트래픽 100%를 되돌린다.

이유:

- room registry, reconnect/rate state와 media delivered state는 process-local이다.
- 두 revision을 동시에 사용하면 같은 room/request가 서로 다른 process state에 배치될 수 있어 canary 결과와 사용자 동작을 해석하기 어렵다.

재검토 조건:

- 공유 state 또는 revision 간 일관성을 보장하는 구조를 도입한 뒤 canary 전략을 다시 설계한다.

## D46. Firebase Functions default codebase 49개 export를 전체 배포한다

- 기본 명령은 `firebase deploy --only functions --project outpick-664ae`다.
- 일부 함수 이름만 선택 배포하지 않는다.
- export 이름, runtime metadata, trigger path와 schedule 계약을 배포 전 test로 고정한다.

이유:

- 49개 export가 같은 `index.ts`, core Firebase 초기화와 global runtime option을 공유한다.
- 부분 배포는 구·신 source revision 혼합 상태를 만들어 이번 모듈화의 실제 배포 결과를 불명확하게 한다.

## D47. 각 배포를 독립적인 중단·rollback gate로 운영한다

Socket gate:

- readiness/health 200.
- 누락·잘못된 token 거절과 정상 Firebase token 연결.
- 전용 test room join/rejoin, 대표 message ACK/수신.
- 신규 error log 없음.

Functions gate:

- 49개 함수와 region/trigger/schedule 확인.
- 인증 실패 callable의 기존 error code.
- 읽기 중심 대표 callable과 신규 error log 확인.
- destructive trigger/scheduler를 smoke 목적으로 강제 실행하지 않는다.

중단 조건:

- 배포 일부 실패, export 누락, health/auth/ACK 계약 위반, 지속적인 신규 error가 있으면 다음 배포로 넘어가지 않는다.
- Socket은 이전 revision traffic 100% 복귀, Functions는 확인한 prior source 전체 재배포를 기본 rollback으로 한다.

## D48. 양쪽 gate 통과 후 iOS 종단 QA를 수행하고 D40은 제외한다

- 로그인과 대표 callable, 채팅 connect/join/reconnect, text/lookbook/image/video, GRDB 복원, room leave/close와 FCM을 확인한다.
- 운영 변경이 필요한 QA는 전용 test account/room/media fixture와 cleanup 절차를 먼저 확정한다.
- D40 in-flight Promise, TTL/LRU와 transaction winner는 Phase 6에 포함하지 않는다.
- 최종 revision, image digest, Functions 배포 결과, smoke/QA와 rollback 지점을 하네스에 기록한다.

## 보류한 대안

- Functions 먼저 배포: 기술적으로 가능하지만 rollback이 빠른 Socket을 먼저 격리 검증하는 이점이 작아진다.
- Socket traffic split canary: process-local state가 revision 사이에 분리되어 현재 구조에는 적합하지 않다.
- Functions 부분 배포: shared core/index 변경과 49개 export의 일관된 검증이 어려워진다.
- Phase 6에서 emulator와 D40까지 구현: 검증·배포와 새 동작 변경을 분리할 수 없다.

## D49. 배포 후 iOS Socket reconnect 안정화

Socket/Functions 배포 후 개발 앱 완전 재실행에서 Socket.IO handler 배열 `Index out of range` crash가 발견됐다. 사용자 승인으로 다음을 별도 안정화 Step으로 확정했다.

- listener는 새 `SocketIOClient` 생성 직후 연결 전에 한 번만 등록한다.
- active connection과 reconnect 중 handler collection을 `off/on`으로 변경하지 않는다.
- listener lifetime은 Socket client lifetime과 동일하게 유지하고 consumer 부재는 actor state에서 처리한다.
- Socket.IO raw logging을 비활성화해 handshake credential이 console에 남지 않게 한다.
- server event/payload/ACK와 배포 revision은 변경하지 않는다.
- narrow listener binder fake test와 cold launch/background 반복 reconnect QA를 통과한 뒤 전체 QA를 재개한다.

변경 파일과 구현·테스트 순서는 [Phase 6 iOS Socket 안정화 계획](../phases/phase-6-ios-socket-stabilization.md)을 따른다.
