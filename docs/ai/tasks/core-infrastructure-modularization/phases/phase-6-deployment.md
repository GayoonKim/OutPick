# Phase 6 Deployment And Smoke Plan

## 상태와 승인 경계

- D43~D48은 사용자 승인으로 확정됐다.
- 이 문서는 배포 순서, gate, smoke와 rollback 절차를 확정한다.
- 문서 작성은 배포 승인이 아니다.
- 자동 회귀 실행, commit, Socket 배포, 운영 fixture 생성과 Functions 배포는 필요한 시점에 각각 사용자 명시 승인을 받는다.

## Step 6A. 배포 source와 rollback 기준 확정

1. `git status --short`, 변경 파일과 신규 파일을 작업 단위별로 확인한다.
2. iOS app, iOS test, Functions, Socket, docs 커밋 후보를 분리한다.
3. 실제 배포할 Functions/Socket commit SHA를 확정한다.
4. 자동 회귀 결과가 같은 SHA에서 생성됐는지 확인한다.
5. 현재 운영 상태를 읽기 전용으로 다시 조회한다.

Socket 기록 항목:

- service/region.
- latest ready revision.
- traffic 100% revision.
- image URL과 digest.
- min/max instances, timeout, concurrency와 service account.

Functions 기록 항목:

- 현재 49개 함수 이름과 region/type.
- prior source에 대응하는 Git commit 또는 복구 가능한 source archive.
- runtime config/secret/queue/worker 환경 계약.

중단 조건:

- Functions prior source를 복구할 수 없으면 Functions 배포를 중단한다.
- Socket 이전 revision을 조회할 수 없거나 ready 상태가 아니면 Socket 배포를 중단한다.
- secret JSON, 로컬 설정 또는 무관한 변경이 배포 context/commit에 포함되면 중단한다.

### 2026-07-14 확인 결과

- 현재 branch: `main`.
- 현재 HEAD: `ccc141e6060e598f71baa9aff392860f4de2ddad`.
- 운영 Functions: 49개 모두 ACTIVE, 동일 source hash `338c32e93a232b1a16378671cb8b6857dc6406af`.
- 대표 Functions 배포 archive의 모든 `src/*.ts`, package/lock, TypeScript/ESLint 설정이 Git HEAD의 `functions/`와 일치했다.
- 비교용 archive에는 환경 파일이 포함되어 있어 내용을 읽거나 보존하지 않고 비교 직후 `/tmp`에서 삭제했다.
- 따라서 Functions prior source 기본 rollback 기준은 Git HEAD `ccc141e`로 확보했다.
- Socket previous ready/traffic revision: `outpick-socket-00005-jwg`, traffic 100%.
- Socket previous image digest: `sha256:1d90573fd2b746bb3e6014e4a050ae767160989dc2caf41c7c29327e1cde2834`.
- Socket service는 concurrency 80, timeout 3600, maxScale 1과 전용 service account를 사용한다.
- 현재 변경은 아직 commit되지 않았으므로 배포 candidate SHA는 미확정이다. commit 승인·생성 후 Step 6B를 같은 SHA에서 다시 실행해야 한다.

## Step 6B. 전체 자동 회귀

[Phase 6 통합 회귀 계획](phase-6-integration-tests.md)을 같은 배포 commit SHA 기준으로 전부 실행한다.

완료 기준:

- 모든 targeted test/build/check 통과.
- 검증 결과와 SHA 기록.
- 검증 뒤 source 변경 없음.

2026-07-14 현재 working tree 기준 전체 회귀는 통과했다. 배포 commit SHA 기준 재실행은 남아 있다.

## Step 6C. Socket image build와 배포

image tag 원칙:

```text
asia-northeast3-docker.pkg.dev/outpick-664ae/cloud-run-source-deploy/outpick-socket:{commit-sha}
```

후보 명령:

```bash
gcloud builds submit Socket \
  --project=outpick-664ae \
  --tag=asia-northeast3-docker.pkg.dev/outpick-664ae/cloud-run-source-deploy/outpick-socket:{commit-sha}

gcloud run deploy outpick-socket \
  --project=outpick-664ae \
  --region=asia-northeast3 \
  --image=asia-northeast3-docker.pkg.dev/outpick-664ae/cloud-run-source-deploy/outpick-socket:{commit-sha} \
  --service-account=outpick-socket@outpick-664ae.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=1 \
  --timeout=3600 \
  --concurrency=80 \
  --port=8080
```

주의:

- 배포 직전 실제 service 설정과 후보 flag가 동일한지 비교한다.
- traffic split을 사용하지 않는다.
- 새 revision이 ready가 된 뒤 트래픽 100%와 image digest를 기록한다.

### 2026-07-14 실행 결과

- 배포 candidate HEAD: `7580a1e`.
- Cloud Build: `c9184096-d482-4388-a5d3-53c82a64b62f`, 성공.
- image tag: `outpick-socket:7580a1e`.
- image digest: `sha256:1cec132dfd183e4bb2125caa22443335b5e5949d4046f1792c886c523b1065a1`.
- 새 revision: `outpick-socket-00006-k8k`, Ready/Active.
- 새 revision traffic: 100%.
- previous rollback revision: `outpick-socket-00005-jwg`.
- build dependency audit에서 기존 moderate 취약점 8건이 보고됐다. package/lockfile은 이번 Phase에서 변경하지 않았으며 별도 dependency 보안 업데이트 후보로 남긴다.

## Step 6D. Socket 배포 gate

비파괴 smoke:

1. `/readyz`, `/healthz` 200.
2. root metadata 응답.
3. token 없음과 잘못된 token이 기존 error code로 거절됨.
4. 새 revision error log 확인.

승인된 fixture smoke:

1. 정상 Firebase test token 연결.
2. 전용 test room join/rejoin.
3. text message ACK와 두 client 수신.
4. 필요 시 lookbook/image/video 각 1회.
5. background/foreground reconnect.
6. room leave/close와 FCM.
7. 생성한 Firestore/Storage fixture 정리.

중단/rollback 조건:

- readiness 실패.
- 정상 token 연결 불가.
- event/ACK/persist/수신 계약 위반.
- 반복되는 5xx, unhandled rejection 또는 Firebase permission error.

rollback 후보:

```bash
gcloud run services update-traffic outpick-socket \
  --project=outpick-664ae \
  --region=asia-northeast3 \
  --to-revisions={previous-ready-revision}=100
```

rollback 후 health와 정상 token 연결을 다시 확인한다. 실패 원인을 기록하기 전 Functions 배포로 넘어가지 않는다.

### 2026-07-14 gate 진행 상태

- root와 `/readyz`: 기존/신규 Cloud Run URL에서 200.
- Cloud Run revision startup/container health: 성공.
- missing/invalid Firebase token: 기존 계약대로 연결 거절.
- 신규 revision의 ERROR severity log: 없음.
- 외부 `/healthz`: Google Frontend 404이며 container request log에 도달하지 않았다. 동일 source의 local `/healthz`는 200이므로 별도 플랫폼 경로 확인 항목으로 기록한다.
- 정상 Firebase ID token: 확인 완료.
  - 저장소 기본 UI test 계정은 Password provider 비활성화로 REST 로그인이 불가능했다.
  - 현재 로컬 계정에는 service-account token signing/impersonation 권한이 없다.
  - anonymous auth는 `ADMIN_ONLY_OPERATION`으로 비활성화되어 있다.
  - 운영 사용자 가장, IAM/provider 변경과 Auth 사용자 생성을 수행하지 않았다.
- 사용자가 개발 앱에서 정상 Kakao 로그인, 기존 채팅방 진입과 text 1건 전송을 수행했다.
- 새 revision 로그에서 Firebase UID 연결, `server:connect:ready`, room join과 text persist/emit(`seq: 1`)을 확인했다.
- 따라서 최소 Socket gate를 통과하고 Step 6E Functions 전체 배포로 진행했다.

## Step 6E. Firebase Functions 전체 배포

사전 gate:

- Step 6B 전체 회귀 통과.
- Step 6D Socket gate 통과.
- Functions prior source rollback 기준 확보.
- 배포 전 49개 export와 계획된 update/create/delete diff 검토.
- 의도하지 않은 function 삭제가 있으면 중단하고 사용자 확인을 받는다.

배포 명령:

```bash
firebase deploy --only functions --project outpick-664ae
```

부분 이름 선택 배포는 사용하지 않는다.

### 2026-07-14 실행 결과

- candidate HEAD: `7580a1e`.
- predeploy lint와 clean TypeScript build: 통과.
- 계획된 기존 49개 function update: 전부 성공. create/delete 없음.
- 배포 후 49개 모두 `ACTIVE`, region `asia-northeast3`, runtime `nodejs24`.
- 배포 source hash: `6ab1e46ab24ec61401c312e92ad4e7e1c5c133d9`.

## Step 6F. Functions 배포 gate

비파괴 확인:

1. 49개 함수의 region/type과 deploy 성공 확인.
2. trigger path, scheduler/timezone과 runtime option 확인.
3. 인증 없는 대표 callable이 기존 `HttpsError` code를 반환하는지 확인.
4. 테스트 계정으로 읽기 중심 `getBrandAdminCapabilities`, `searchBrands`, `listMyBrandRequests` 확인.
5. 신규 error log, initialization 중복과 permission error 확인.

기본 smoke에서 하지 않는 작업:

- 삭제/purge scheduler 강제 실행.
- room close cleanup을 운영 room에서 강제 실행.
- import Cloud Tasks를 실제 브랜드에 생성.
- 권한/데이터를 변경하는 관리자 callable 실행.

중단/rollback 조건:

- 일부 함수 deploy 실패 또는 export 누락.
- region/trigger/schedule/runtime metadata 변경.
- 대표 callable의 error code/response 회귀.
- 새로운 initialization/permission/trigger 오류.

rollback:

- Step 6A에서 확인한 prior source를 전체 Functions로 재배포한다.
- 개별 Gen2 revision traffic 조정은 49개 함수의 일관성을 보장하기 어려우므로 기본 rollback으로 사용하지 않는다.
- rollback deploy 후 같은 비파괴 gate를 반복한다.

### 2026-07-14 gate 진행 상태

- 49개 region/runtime/state와 동일 source hash: 통과.
- trigger count: callable 43, schedule 3, Firestore event 3.
- scheduler: 기존 `0 4 * * *` 2개와 `30 4 * * *` 1개, `Asia/Seoul`, 모두 `ENABLED`.
- 비인증 `getBrandAdminCapabilities`: HTTP 401과 `UNAUTHENTICATED` 확인.
- 로그인된 개발 앱 완전 재실행 후 인증 `getBrandAdminCapabilities`: HTTP 200 확인.
- 배포 후 신규 Functions ERROR log: 없음.
- 로그인 세션 개발 앱에서 `searchBrands`와 `listMyBrandRequests` 인증 read smoke를 완료했다.
  - `listMyBrandRequests`: active/history scope 모두 HTTP 200, 빈 결과 ready UI 확인.
  - `searchBrands`: 빈 결과와 `UNAFFECTED` 결과 1건 모두 HTTP 200 확인.
  - 같은 시간대 두 service의 `severity>=ERROR` 로그는 0건이었다.
- Functions 자체 gate에는 rollback 사유가 발견되지 않았다.

## Step 6G. iOS 종단 QA와 최종화

두 배포 gate가 모두 통과한 뒤 개발 앱으로 확인한다.

- 로그인/브랜드 권한/대표 Lookbook callable.
- 채팅 connect/join/rejoin과 text/lookbook/image/video.
- GRDB 저장, 앱 재실행과 검색/복원.
- reconnect, FCM, leave/close.
- bootstrap DEBUG once/always는 운영 앱이 아닌 test build에서 확인한다.

### 2026-07-14 종단 QA 중단 사유

- 개발 앱 완전 재실행 시 인증 Socket connect/ready 직후 `Index out of range`로 앱이 종료됐다.
- crash stack은 Socket.IO 라이브러리 `SocketIOClient.handleEvent`의 handler 배열 subscript를 가리킨다.
- 동시에 `RealtimeSocketService.handleConnected()`가 message listener의 off/on 재등록을 수행하고 있어 handler collection 경쟁 상태가 원인 후보다.
- `RealtimeSocketService.swift`는 candidate에서 변경되지 않았고, 새 서버의 `server:connect:ready` payload와 `room list` 전송 순서는 previous source와 동일하다.
- client reconnect 안정성을 논의·수정·검증하기 전 전체 수동 QA를 재개하지 않는다.

### 2026-07-14 D49 이후 채팅·GRDB QA 재개 결과

- D49 one-time listener 수정 후 cold launch와 background/foreground reconnect gate가 통과해 QA를 재개했다.
- `OOTD 공유`에서 텍스트, 사진 1장, 8초 동영상 1개와 UNAFFECTED 시즌 공유 1건을 전송해 각각 단일 표시를 확인했다.
- 앱 완전 종료·재실행 후 같은 room에서 text/image/video/lookbook 4종이 모두 복원됐다.
- 재실행 Socket connect/rejoin과 최근 Cloud Run `severity>=ERROR` 0건을 확인했다.
- `OOTD 공유` 검색·결과 이동과 `해칭룸 정보 공유방` 이미지/동영상 모아보기도 통과했다.
- 이전 메시지 pagination은 아래 전용 105-message fixture QA에서 완료했고, FCM은 사용자 Apple 개발자 계정 환경 제약으로 보류했다.
- 실패 메시지 재시도, 일반 구성원 room leave와 방장 room close는 아래 후속 QA에서 완료했다.

### 2026-07-14 이전 메시지 pagination QA

- 전용 공개 room `QA-P6-PAGE-0714`와 `seq 1...105` text fixture를 구성했다.
- `lastReadSeq=105`, latest `seq=105`, 로컬 cache 0건에서 재진입해 최초 `latestTail`이 80개(`seq 26...105`)임을 확인했다.
- debugger에서 `loadOlderMessages(before: "qa-p6-page-0714-026")` 실제 호출을 포착했고, 완료 후 GRDB가 105개(`seq 1...105`)로 확장됐다.
- ID/seq distinct count는 각각 105로 중복이 없었고 화면 최상단에서 `QA-P6-PAGE-001`을 확인했다.
- 방장 종료 후 Firestore room/joined projection은 `NOT_FOUND`, members/messages는 0건이었고 GRDB message/FTS/outbox/media/profile/roomImage row도 모두 0건이었다.

### 2026-07-14 실패 메시지 retry QA

- 운영 서버나 호스트 네트워크 중단 없이 Simulator process의 Socket 참조만 일시적으로 해제해 `OOTD 공유` 텍스트 전송 실패를 재현했다.
- 실패 버블과 GRDB `isFailed=1`, text outbox `stage=failed`를 확인했다.
- 접근성 target이 없는 실패 아이콘 좌표 탭 대신 debugger에서 동일 `confirmRetryUpload(for:)` 진입점을 호출했고, 표시된 확인 UI의 `재시도` 버튼부터 실제 UI로 진행했다.
- Socket 복구 후 동일 message ID가 서버에 한 번만 저장되고 sequence가 부여됐으며 GRDB는 `isFailed=0`, outbox 0건으로 정리됐다.
- 앱 완전 재실행 후 정상 메시지 1건 복원과 Socket 오류 로그 0건을 확인했다.

### 2026-07-14 room close·cleanup QA

- 전용 공개 room `QA-P6-CLOSE-0714`를 앱에서 생성하고 방장 종료를 실행했다.
- 종료 확인 UI, 목록 제거와 Socket 생성/join/leave request를 확인했다.
- Firestore room 문서와 members/messages는 모두 제거됐고 GRDB message/FTS/outbox/media/profile 관련 row도 0건이었다.
- Socket `severity>=ERROR` 로그는 0건이었다.
- 이후 별도 Google 로그인 계정과 전용 fixture로 일반 구성원 leave를 검증했다.

### 2026-07-14 일반 구성원 room leave·local cleanup QA

- Kakao 방장 계정으로 전용 공개 room `QA-P6-LEAVE-0714`를 만들고 Google 로그인 사용자가 가입했다.
- Google 사용자가 테스트 메시지 1건을 전송한 뒤 일반 구성원 종료 확인 UI로 leave했고, 해당 room은 Google 사용자의 목록에서 제거됐다.
- Firestore room, 방장 member, `Messages` 1건은 유지됐고 Google member 문서만 제거됐다.
- Simulator 운영 GRDB의 message/FTS/outbox/media/profile 관련 row는 해당 room 기준 모두 0건이었다.
- Socket leave request가 기록됐으며 같은 시간대 `ERROR`/`FATAL` 로그는 없었다.
- Kakao 방장 계정으로 복귀해 방장 종료 경고와 복구 불가 안내를 확인하고 fixture를 닫았다.
- 최종 확인에서 Firestore room은 `NOT_FOUND`, `members`와 `Messages`는 각각 0건이었고 GRDB message/FTS/outbox/media/profile/roomImage 관련 row도 모두 0건이었다.
- Socket 방장 leave request가 기록됐고 같은 조회 범위에 `ERROR` 이상 로그는 없었다. 전용 fixture cleanup까지 완료했다.

최종 기록:

- Functions 배포 시각과 결과.
- Socket image tag/digest와 new/previous revision.
- 자동 회귀 commit SHA와 결과.
- smoke 계정/fixture 범위와 cleanup 여부.
- 실패/rollback 여부와 관찰 로그.
- ENTRYPOINTS/FIREBASE/CHAT/TESTS/progress/qa/HANDOFF 갱신.

## 배포 완료 기준

- 자동 회귀가 배포 SHA에서 통과했다.
- Socket/Functions 각 gate가 통과했다.
- 승인된 iOS 종단 QA가 통과했다.
- 운영 fixture가 정리됐다.
- rollback 지점과 실제 배포 결과가 문서화됐다.
- D40 또는 다른 동작 변경이 포함되지 않았다.
