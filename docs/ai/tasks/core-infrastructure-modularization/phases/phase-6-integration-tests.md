# Phase 6 Integration Regression Plan

## 상태와 목표

- D41~D48은 사용자 승인으로 확정됐다.
- Phase 2~5의 API/data/wire 계약과 앱 조립을 한 번의 release candidate 기준으로 재검증한다.
- 2026-07-14 사용자 승인으로 현재 working tree의 전체 자동 회귀를 실행해 통과했다.
- 아직 배포 commit이 없으므로 commit SHA 고정 후 동일 검증을 다시 실행하는 배포 gate는 남아 있다.

## 2026-07-14 실행 결과

- iOS Phase 2/3/D19 관련 unit 21개 test type: 통과.
- `AppBootstrapFailureUITests`: 통과.
- iOS generic Simulator `CODE_SIGNING_ALLOWED=NO` build: 통과.
- Functions: 51개 test, ESLint, clean TypeScript build 통과.
- Socket: syntax check, 43개 `node:test`, ADC check 통과.
- Socket local smoke: Firestore room preload, root/readyz/healthz 200, SIGINT graceful shutdown 통과.
- 구조 검색: 제거된 `CloudFunctionsManager`/`GRDBManager` 참조, Functions/Socket root 구현, D40 media 구현 유입 없음.
- `git diff --check`: 통과.

남은 warning:

- iOS build/test에 기존 `UIButton.contentEdgeInsets` deprecated warning 1건과 불필요한 `await` warning 2건이 있다. 실패는 아니며 이번 구조 리팩터링 범위 밖이다.
- Socket local start에 Node `punycode` deprecation warning이 있다. 서버 start/health/shutdown에는 영향이 없었으며 dependency 후속 정리 후보로 남긴다.

## 위험도

- 고위험: callable wire/error, GRDB transaction/cleanup, DB bootstrap 복구, Firebase export/runtime metadata, Socket auth/event/ACK/side-effect 순서.
- 통합 위험: 서로 다른 phase의 DI 조립이 같은 앱 binary에서 링크되지 않거나 production endpoint와 계약이 어긋나는 경우.
- 운영 위험: 검증한 source와 실제 배포 commit이 달라지는 경우.

## 자동 검증 범위

### 1. iOS Cloud Functions

대상:

- `OutPickTests/CloudFunctions/`

검증:

- 공통 response decoder.
- function name과 payload.
- Auth/BrandAdmin capability.
- Lookbook adapter 15개와 사용 callable 38개.
- Firebase 원본 오류 전달.

### 2. GRDB와 Chat persistence

대상:

- `OutPickTests/GRDB/` 7개 suite.
- `ChatOutgoingOutboxUseCaseTests`.
- `ChatProfileSyncManagerTests`.
- `ChatRoomExitUseCaseTests`.

검증:

- fresh 15개 migration.
- message/FTS/media strict rollback.
- outbox/profile/media Store.
- transient/exit cleanup transaction.
- 실제 Chat consumer와 persistence Protocol 연결.

### 3. App bootstrap

대상:

- `AppBootstrapFailureInjectorTests`.
- `AppCompositionRootTests`.
- `AppBootstrapFailureUITests`.

검증:

- database factory 오류 mapping.
- DEBUG once 실패 후 재시도 성공.
- DEBUG always 반복 실패와 앱 생존.
- 정상 bootstrap 경로.

### 4. iOS build

```bash
xcodebuild -scheme OutPick \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

목적:

- Phase 2 Functions DI, Phase 3 database provider, D19 Scene bootstrap과 Chat/Lookbook consumer를 하나의 app target으로 조립한다.

### 5. Firebase Functions

```bash
cd functions
npm test
npm run lint
npm run build
```

검증:

- 총 49개 flat export.
- callable 43개, Firestore trigger 3개, scheduler 3개.
- region/runtime option/trigger path/schedule.
- Firebase 초기화와 global option 단일 owner.
- root implementation 부재와 feature import 방향.
- clean build와 compiled test 재귀 발견.

### 6. Socket

```bash
npm --prefix Socket run check
npm --prefix Socket test
```

검증:

- HTTP route 3개.
- middleware 2개 순서.
- client event 11개와 disconnect.
- auth/room/message/media ACK.
- persist→emit→push→ACK.
- readiness/shutdown과 explicit Firebase bootstrap.
- D40 동작 유입 부재.

### 7. 구조와 repository 상태

```bash
git diff --check
rg -n "CloudFunctionsManager|GRDBManager" OutPick OutPickTests
rg -n "socket\.on|io\.use|runTransaction|\.collection\(" Socket/index.js
rg -n "onCall|onSchedule|onDocument|runTransaction|\.batch\(" functions/src/index.ts
```

추가 확인:

- `CloudFunctionsManager.swift`, `GRDBManager.swift` 제거 상태.
- `functions/src/index.ts`와 `Socket/index.js`가 얇은 진입점인지 확인.
- giant concrete dependency나 phase 임시 façade가 production consumer에 남지 않았는지 확인.
- 신규 source/test가 배포 commit 범위에 모두 포함됐는지 확인.

## 로컬 통합 smoke

### Socket

- `npm --prefix Socket run check:adc`.
- 임의 port local start.
- Firestore room preload 성공.
- `/readyz`, `/healthz` 200.
- SIGINT graceful shutdown.

### Functions

- 새 emulator infrastructure는 추가하지 않는다.
- import/export metadata와 service fake test를 자동 gate로 사용한다.
- 실제 callable/IAM은 배포 후 통제된 smoke에서 확인한다.

## 수동 QA 범위

배포 전 로컬/Simulator:

- 정상 앱 bootstrap.
- DEBUG once/always bootstrap 실패 복구.
- 채팅 진입, pagination, 검색과 로컬 복원.

양쪽 서버 배포 후:

- 로그인과 대표 Lookbook callable.
- Socket connect/join/rejoin.
- text/lookbook/image/video 송수신.
- background/foreground reconnect.
- room leave/close.
- FCM fanout.

## 추가하지 않는 테스트와 이유

- 전체 iOS test suite 강제 실행: 이번 변경과 무관한 기존 test를 release gate에 포함하지 않고 관련 targeted test와 generic build로 경계를 고정한다.
- SwiftUI snapshot: 화면 시각 구조 변경이 핵심이 아니다.
- 새 Firebase emulator fixture: 별도 infrastructure 설계가 필요하다.
- 성능 benchmark: 기능/성능 변경이 아니라 동작 보존형 구조 리팩터링이다.
- D40 concurrency test: 후속 동작 변경 task 범위다.

## 실행 순서와 중단 조건

1. 배포 후보 commit과 working tree 범위를 확정한다.
2. iOS targeted test와 generic build.
3. Functions test/lint/build.
4. Socket check/test와 ADC local smoke.
5. 구조 검색과 `git diff --check`.
6. 모든 결과를 같은 commit SHA 기준으로 기록한다.

다음 조건이면 배포 계획으로 넘어가지 않는다.

- test/build/check 하나라도 실패한다.
- 계약 count나 metadata가 기준선과 다르다.
- local Socket start/health/shutdown이 실패한다.
- 검증 후 배포 대상 source가 변경됐다.
- rollback 기준이 확보되지 않았다.
