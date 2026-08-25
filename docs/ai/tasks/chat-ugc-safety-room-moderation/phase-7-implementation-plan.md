# Phase 7 미디어 격리·정규화·신고 Evidence 구현 계획

## 상태

- 작성일: 2026-08-18
- 상태: Phase 7.0~7.3 로컬 구현·Development/Production rollout·확장 QA, Phase 7.4A 순수 계약, 7.4B preparation/accepted 확정·삭제 transaction, 2026-08-25 Phase 7.4C-1~C-3 generation-scoped evidence copy/cleanup의 로컬 구현과 Development 전용 bucket/IAM/세 Function/필수 인덱스 3개/경계 용량·접근 거부·무잔여 E2E를 완료했다. Rules·TTL·관리자 query와 Production rollout은 미수행이며 Phase 7.4D 이후 별도 승인 gate다.
- 상위 계약: `decisions.md`, `contracts/chat-moderation-v1.json`, ADR-024
- 범위: 신규 채팅 이미지·동영상의 격리 업로드, 기술 검증·metadata 제거, ready 전달, 메시지 전체 evidence, 관리자 queue 승격, 전역 비노출과 복원
- 비범위: 외부 유해성 의미 판정, 관리자 웹 evidence byte 전달 UI, 댓글·답글 미디어, 기존 미디어 소급 정규화, 자동 계정 제재

### Phase 7.0 feasibility 완료 결과 — 2026-08-18

- `tools/chat-media-processing-worker/`에 Node.js/TypeScript CLI, sharp 이미지 처리, ffprobe/ffmpeg stream-copy remux, 합성 fixture와 runtime/benchmark 진입점을 추가했다.
- sharp는 보안 advisory가 있는 0.34.5 대신 수정 버전 0.35.3으로 고정했으며 설치 audit은 취약점 0건이다.
- JPEG metadata 제거, alpha PNG, animated GIF 2-frame 보존, MIME mismatch, 손상 이미지, GIF resource guard와 video probe 순수 계약은 통과했다.
- 실제 HEVC HEIC fixture는 형식 probe에는 성공하지만 prebuilt sharp/libvips가 HEVC decoder를 포함하지 않아 decode가 실패했다. 사용자 결정으로 iOS가 정적 HEIC/HEIF를 고품질 JPEG로 바꾼 뒤 업로드하고 서버는 raw HEIC/HEIF를 `unsupportedMedia`로 거부한다.
- 번들 Node.js 24.19.0에서 계약 보정 후 12/12가 통과했다. 개발 전용 정적 ffmpeg/ffprobe로 1시간 H.264/AAC stream-copy remux, metadata·subtitle track 제거와 runtime verification을 통과했다.
- 4096x4096 JPEG 30장 순차 처리는 10.537초, 190-frame 1024x512 GIF 99,614,720 decoded pixel은 3.750초였다. 전체 process peak RSS는 402,560 KiB(약 393 MiB)였다. 201-frame GIF는 decode 전에 `resourceLimit`으로 거부했다.
- Development Cloud Build `c57a715a-2948-45ea-b464-21437cf474c7`에서 Linux verification target과 최종 runtime target을 모두 빌드했다. Node.js 24.19.0, sharp 0.35.3, libvips 8.18.3, ffmpeg/ffprobe 5.1.9로 12/12, runtime verification과 최종 runtime image 재검증이 통과했다.
- Linux benchmark는 4096x4096 JPEG 30장 순차 처리 32.992초, 190-frame 1024x512 GIF 99,614,720 decoded pixel 9.538초, process peak RSS 343,756 KiB(약 336 MiB)였다.
- 확정 상한은 static 64M pixel, GIF 200 frame·frame당 16,777,216 pixel·총 100M decoded pixel, 이미지당 60초, video remux 10분이다. Cloud Run Job 사양은 2 vCPU·1 GiB이며 attachment는 task 안에서 순차 처리한다.
- custom libvips와 전용 HEIC decoder는 도입하지 않는다. Cloud Build는 검증용 source upload와 로컬 Docker image build만 수행했으며 registry image push, Cloud Run 배포, traffic 전환과 Firebase 데이터 변경은 하지 않았다.

## 핵심 문제

현재 미디어 흐름은 Socket `chat:mediaFinalize`가 공개 Storage path를 신뢰하고 즉시 message·seq를 생성한다. iOS pending 상태는 `uploading/failed`뿐이고 신고 action은 접수 UI 없이 성공 문구만 표시한다. `Attachment`에는 배열 index만 있고 evidence가 참조할 안정적인 ID가 없다.

Phase 7은 다음 경계를 동시에 바꾼다.

1. 클라이언트가 제출한 MIME·크기·codec·metadata를 신뢰하지 않는다.
2. ready 전에는 공개 객체·message·seq·Socket·FCM·room preview가 없다.
3. 장시간 동영상을 duration으로 거부하지 않으면서 request timeout에 종속되지 않는다.
4. 신고·삭제·취소·worker 완료가 경합해도 한 가지 서버 상태로 수렴한다.
5. evidence 원본과 복원 payload는 일반 클라이언트가 읽을 수 없다.
6. 기존 realtime ordering, read frontier와 outbox 재실행 복원을 깨지 않는다.

## 기술 선택

### 처리 실행 단위

- 전용 runtime은 `tools/chat-media-processing-worker/`의 Node.js 24 + TypeScript container로 만든다.
- 이미지 probe·정규화는 `sharp/libvips`, 동영상 probe·metadata 제거는 `ffprobe/ffmpeg`를 사용한다.
- image worker는 private Cloud Run Service(min instance 0, concurrency 1), video worker는 전용 Cloud Run Job으로 실행한다.
- Firestore trigger Function이 media kind별 Cloud Task를 enqueue하고, dispatcher Function이 `MediaUploads` lease와 kind별 고정 실행 slot을 획득한다. 이미지는 ID token으로 Service의 `POST /process`를 호출하고 영상은 Cloud Run Jobs API로 execution을 시작한다.
- Service/Job platform retry는 0으로 두고 Firestore `attempt`와 watchdog이 최대 3회 자동 실행을 권위 있게 관리한다. 중첩 retry로 실제 시도 횟수가 증가하지 않게 한다.
- 이미지와 영상은 같은 container image를 사용하되 queue, Job timeout과 실행 slot을 분리한다. Development는 이미지 1·영상 1, Production 초기값은 이미지 4·영상 1 slot이다.
- Job은 task count 1·parallelism 1·2 vCPU·1 GiB다. 이미지 전체 task timeout은 40분, 영상은 12분이며 이미지당 60초·영상 remux 10분 내부 timeout을 함께 적용한다.
- Socket runtime identity에는 Cloud Tasks enqueue·Cloud Run 실행 권한을 부여하지 않는다. Socket은 reservation/finalize/cancel mutation만 수행한다.

선택 근거:

- Cloud Tasks HTTP target은 최대 30분이므로 길이 제한 없는 동영상 처리를 요청 수명에 묶지 않는다.
- Cloud Run Job task timeout은 최대 168시간이며 request listener 없이 작업 종료까지 실행할 수 있다.
- 현재 앱이 동영상을 720p MP4로 준비하므로 서버는 허용 codec이면 재인코딩 대신 remux/metadata 제거를 우선해 duration에 비례한 decode 비용을 피한다.

공식 문서 확인일 2026-08-18:

- Cloud Tasks HTTP target timeout: https://docs.cloud.google.com/tasks/docs/creating-http-target-tasks
- Cloud Run Jobs와 task timeout: https://cloud.google.com/run/docs/create-jobs
- sharp animated input·pixel guard: https://sharp.pixelplumbing.com/api-constructor/
- sharp metadata 제거·GIF output: https://sharp.pixelplumbing.com/api-output/
- ffprobe stream·format·metadata 확인: https://ffmpeg.org/ffprobe.html

### 저장 경로와 공개 조건

- 격리: 환경별 전용 Standard bucket의 `{roomID}/{senderUID}/{uploadID}/{attachmentID}/source`. `asia-northeast3`, soft delete·versioning 비활성화, 1일 lifecycle backstop을 사용한다.
- ready: `rooms/{roomID}/messages/{messageID}/attachments/{attachmentID}/{variant}`
- evidence: 환경별 전용 evidence bucket의 `{bundleID}/{attachmentID}/display`
- `uploadID`는 기존 호환과 멱등성을 위해 최초 구현에서 `messageID`와 같게 사용한다.
- `attachmentID`는 `SHA-256(uploadID + ":" + immutableSlotID + ":" + mediaKind)` 기반 결정적 ID다. 화면 배열 index는 정렬용일 뿐 evidence identity로 사용하지 않는다.
- worker가 ready path에 객체를 먼저 materialize해도 Storage Rules는 reservation `ready`와 message 존재를 함께 확인하기 전까지 다른 사용자 read를 거부한다.
- 격리 `source`는 공개 경로로 이동하지 않는다. worker가 새 `display`와 `thumbnail`을 만들고 ready commit 뒤 source를 영구 삭제한다. evidence는 raw source가 아니라 실제 노출된 정규화 `display`만 복사한다.
- iOS는 큰 바이너리를 Socket/Functions에 전달하지 않고 예약된 exact path로 quarantine Storage에 직접 업로드한다. 다만 Photos/카메라 원본 byte가 아니라 업로드 전용 transport source를 준비한다. 정적 이미지는 orientation bake·4096px·sRGB·metadata 제거 후 HEIC/HEIF·JPEG를 JPEG quality 0.92로 인코딩하고 PNG는 초기 투명/비투명 모두 보존한다. GIF는 animation을 보존한다.

### 동영상 처리

- iOS는 720p H.264/AAC MP4 transport source 하나만 quarantine에 직접 올린다. pending UI용 local thumbnail은 업로드하지 않는다.
- 입력 상한은 source와 서버 결과 모두 350 MiB, 메시지당 1개다. duration 상한은 두지 않는다.
- `ffprobe`로 실제 container, video/audio codec, duration, dimensions, rotation, track와 format/stream metadata를 확인한다.
- 허용 MP4/H.264/AAC 입력은 stream copy remux와 metadata/불필요 track 제거를 우선한다.
- worker가 `min(1초, duration/2)` 시점에서 긴 변 512px metadata-free JPEG thumbnail을 생성한다. thumbnail 추출 실패는 `failed/nonRetryable/invalidMedia`다.
- 손상 파일, 실행 불가능 stream, 허용하지 않은 codec/container는 `failed/nonRetryable/invalidMedia`로 끝내며 duration 때문에 실패시키지 않는다.
- app 준비 결과와 서버 probe 결과가 다르면 서버 값을 권위 값으로 사용한다.

### GIF 처리

- `animated: true`로 모든 frame을 읽고 GIF animation을 보존한다. 첫 frame JPEG로 평탄화하지 않는다.
- `unlimited` 옵션은 사용하지 않는다. frame 수, frame당 pixel, 총 decoded pixel, input channel, memory, CPU와 timeout guard를 모두 적용한다.
- 상한은 200 frame, frame당 16,777,216 pixel, 총 100,000,000 decoded pixel과 이미지당 60초로 contract constant와 worker 설정에 고정한다. 상한 초과는 앱 crash나 OOM이 아니라 `failed/nonRetryable/resourceLimit`로 수렴한다.

## 서버 데이터 계약

### `Rooms/{roomID}/MediaUploads/{uploadID}`

- 핵심 필드: `senderUID`, `moderationPrincipalID`, `kind`, `clientMutationID`, `attachmentCount`, `quarantinePaths`, `processingStatus`, `processingAttempt`, `retryable`, `leaseToken`, `leaseExpiresAt`, `executionName`, `processingSlotID`, `nextAttemptAt`, `normalizedManifest`, `failureCode`, `cleanupStatus`, `expiresAt`.
- 상태: `uploading → queued → processing → ready`.
- 종료 상태: `canceled | failed | expired`.
- `ready`, `canceled`는 terminal이다. `failed/retryable=true`만 명시적 retry로 `queued`에 돌아갈 수 있다.
- 별도 `chatMediaProcessingJobs` 문서는 만들지 않는다. reservation과 processing이 항상 1:1이므로 `MediaUploads`가 예약·lease·retry·execution 상태를 함께 소유한다.
- upload reservation과 V4 signed PUT URL은 생성 후 24시간, processing deadline은 finalize의 source 검증 완료 후 `queued` 전환 시점부터 6시간이다.
- ready/canceled/final failed/expired가 확정되면 quarantine source, execution lease와 principal slot을 즉시 정리한다. terminal `MediaUploads`에는 `clientMutationID`와 최소 결과만 남겨 outbox 멱등 재실행을 7일 지원한 뒤 TTL 삭제한다. 이는 media byte 보존이 아니다.

### `chatMediaProcessingSlots/{slotID}`

- 초기 slot은 Production `image-0...image-3`, `video-0`, Development `image-0`, `video-0`이다.
- 핵심 필드: `kind`, `leaseToken`, `leaseOwnerUploadPath`, `leaseExpiresAt`, `updatedAt`.
- dispatcher는 `MediaUploads` claim과 빈 slot 획득을 transaction으로 묶고 slot을 얻은 경우에만 execution을 시작한다.
- Cloud Tasks concurrency는 dispatcher 호출 속도만 제어하며 실행 중 Job 수의 최종 권위가 아니다. worker 완료와 watchdog이 slot lease를 반환·회수한다.
- 사용자별 active 상태는 이미지 메시지 최대 2개, 영상 최대 1개다. 24시간 byte hard cap은 초기 도입하지 않고 실제 사용량·abuse metric으로 별도 확정한다.
- 이 상한은 canonical principal별 server-only 고정 slot 문서를 preflight transaction에서 점유하고 terminal cleanup/watchdog에서 반환한다. `uploading|queued|processing` 동시 작업만 계산하며 같은 `clientMutationID` 재시도는 새 slot을 소비하지 않는다. image 2개는 메시지당 30장 기준 동시 최대 60장일 뿐 누적 전송 제한이 아니고, iOS local queue가 terminal slot 반환 뒤 다음 메시지를 순차 시작한다.

### `chatMediaDeliveryJobs/{roomID_messageID}`

- ready transaction과 함께 생성한다.
- 핵심 필드: `messageID`, `roomID`, `seq`, `eventKind`, `status`, `attempt`, `nextAttemptAt`, `createdAt`, `expiresAt`.
- Socket watcher가 동일 messageID/seq를 emit하고 FCM을 fan-out한 뒤 완료 처리한다.
- 전달은 at-least-once로 보고 watcher 재시작·ACK 유실의 중복 event는 Socket session과 iOS가 messageID/seq first-wins로 제거한다. 사용자에게 중복 메시지·unread가 나타나지 않는 것이 완료 기준이다.

### 신고·evidence

- `moderationMessageIncidents/{incidentID}`와 revision별 reporter 문서가 메시지 신고의 canonical 원장이다. 작성자 aggregate에는 `reportedMessages/{incidentID}`와 `messageReporters/{reporterID}` marker를 함께 기록한다.
- 일반 단일은 `holding`, 같은 메시지 고유 신고자 2명은 `reviewRequired`, 긴급 사유 첫 신고는 `urgent`다. 기한 경과 holding은 `reviewDueAt <= serverNow` 관리자 조회에 포함할 뿐 scheduler로 상태를 바꾸지 않는다.
- 작성자 패턴은 최근 7일 `reportedMessages` 최대 3개와 `messageReporters` 최대 2개를 각각 조회해 둘 다 충족할 때만 성립한다.
- global threshold transaction은 최근 24시간 reporter marker를 읽고 새 submission을 포함해 긴급 고유 2명 또는 전체 사유 고유 3명인지 계산한다.
- `moderationMessageEvidence/{bundleID}`는 제한된 text snapshot과 신고된 메시지의 전체 attachment manifest를 기록한다. `bundleID`와 object path는 message/revision/attachment 기준 결정적 ID다.
- `moderationEvidenceCopyJobs/{bundleID}`와 `moderationEvidenceCleanupJobs/{bundleID}`가 복사·삭제를 멱등 처리한다.
- `moderationMessageGuards/{incidentID}`는 신고/삭제 transaction의 server-only first-commit-wins 원장이다.
- `moderationHiddenMessagePayloads/{roomID_messageID}`는 전역 숨김 전 복원 가능한 공개 payload만 서버 전용으로 보관한다.
- 신고 성공은 개인 숨김을 자동 생성하지 않는다. 명시적 `이 메시지 숨기기`를 후속 구현할 경우 신고와 분리된 owner-only 전체 메시지 hide relation으로 설계한다.

### 전역 visibility

- `Messages/{messageID}.moderationVisibilityState`는 누락 또는 `visible`, `hiddenPendingReview`, `deleted`를 사용한다.
- 전역 숨김 transaction은 server-only 복원 payload를 저장하고 공개 message를 같은 seq의 `검토 중인 메시지입니다` tombstone으로 바꾼다.
- 기각 복원은 같은 messageID/seq와 기존 sentAt을 복원하고 delivery event를 `restore`로 생성한다. room latestSeq, lastReadSeq와 unread는 변경하지 않는다.
- 위반 확정은 같은 seq의 삭제 tombstone으로 전환한다.
- 기각 시 `reviewRevision`을 증가시키고 이전 reporter marker가 새 threshold에 포함되지 않게 한다.

## API·이벤트 계약

### Socket 발신 API

- `chat:mediaPreflight`: exact quarantine path와 reservation expiry 반환.
- `chat:mediaFinalize`: 공개 메시지를 만들지 않고 전체 object manifest 검증 후 같은 `MediaUploads`를 `uploading → queued`로 commit.
- `chat:mediaProcessingStatus`: reservation owner에게 현재 상태, retryable, messageID/seq를 반환.
- `chat:mediaCancel`: ready 전 cancel transaction. worker ready와 먼저 commit된 transaction이 승리.
- 수동 재시도는 실패한 server job을 되살리지 않는다. 새 `uploadID`와 새 `clientMutationID`로 새 reservation을 만들고, 새 outbox가 저장된 뒤 이전 local pending/outbox를 정리한다.
- 기존 `chat:mediaFinalize` 성공 ACK의 의미는 “메시지 전송 완료”에서 “서버 처리 접수”로 바뀌므로 iOS와 Socket을 호환 배포 단위로 다룬다.

### Socket 수신 이벤트

- `chat:mediaProcessingStatusChanged`: 발신자의 pending UI 갱신.
- 기존 `receiveImages`/`receiveVideo`: ready delivery job 이후에만 발행.
- `chat:messageModerationVisibility`: `hiddenPendingReview | restored | deleted`, messageID, seq, reviewRevision을 전달.

### 신고 API

- 메시지 long press는 attachment 선택이나 동영상 시점 입력 없이 전용 `submitMessageReport`로 `이 메시지 신고`를 제출한다. 서버는 message의 stable attachment ID·media kind·sender와 전체 attachment manifest를 다시 검증한다. `submitUserReport`는 프로필/참여자 사용자 신고로 유지한다.
- 메시지 신고는 canonical message incident로 기록하고 같은 작성자 aggregate의 message/reporter marker에도 반영한다. 프로필 사용자 신고와 방 신고는 메시지 evidence를 만들지 않는다.
- 삭제가 먼저 commit됐으면 `messageAlreadyDeleted`를 반환하고 신고 원장·evidence·moderation count는 만들지 않는다. 이전에 보지 못한 `clientRequestID`의 최상위 transport receipt와 공유 limiter slot 1개는 만든다.
- 신고 preparation이 먼저 commit되면 server-only guard에 evidence hold를 반영해 삭제 cleanup과 transaction conflict를 만들고, evidence available 뒤에만 accepted 신고를 확정한다.
- 관리자 report detail은 evidence 상태와 object ID만 반환하며 byte URL은 반환하지 않는다.

## 구현 단계

### Phase 7.0 — Feasibility·계약·fixture

목표:

- 구현 전에 worker binary와 resource guard가 JPEG·PNG·animated GIF·장시간 MP4를 처리하고 raw HEIC/HEIF를 명시적으로 거부할 수 있는지 증명한다.

변경 파일 후보:

- `tools/chat-media-processing-worker/package.json`
- `tools/chat-media-processing-worker/Dockerfile`
- `tools/chat-media-processing-worker/src/{contracts,imageProcessor,videoProcessor}.ts`
- `tools/chat-media-processing-worker/fixtures/`
- `contracts/chat-moderation-v1.json`
- `docs/ai/ADR.md`, ADR-024, `DATA_SCHEMA.md`

구현:

1. synthetic/redistributable fixture로 static image, metadata 포함 image, animation GIF, 과도한 frame/pixel GIF, 짧은/장시간 MP4, 손상·위장 MIME를 준비한다.
2. sharp/libvips의 JPEG/PNG/GIF output과 raw HEIC/HEIF `unsupportedMedia` 거부를 container 안에서 확인한다. iOS HEIC/HEIF→JPEG 출력은 Phase 7.3에서 검증한다.
3. GIF peak RSS·CPU·elapsed와 decoded pixel을 측정해 frame/decode/memory/timeout 상한을 고정한다.
4. ffprobe JSON parsing과 MP4 stream-copy metadata 제거를 확인한다.
5. output에 제거 대상 EXIF/XMP/IPTC/QuickTime metadata와 보조 track이 남지 않는 assertion을 만든다.

완료 기준:

- 지원 format과 제거 metadata matrix가 fixture test로 고정된다.
- GIF resource 상한이 숫자로 contract에 기록된다.
- duration이 긴 MP4를 decode 재인코딩 없이 remux할 수 있음을 확인한다.
- container resource/timeout과 non-retryable 오류 코드가 확정된다.

중단 조건:

- 애니메이션 보존 또는 350 MiB 장시간 동영상 처리가 선택 stack으로 안전하게 불가능하면 Phase 7.1로 넘어가지 않고 대체 library/runtime만 재논의한다.

### Phase 7.1 — Quarantine·Job orchestration·IAM

목표:

- ready 생성 없이 reservation → upload → queued → processing/terminal 상태가 멱등 수렴한다.

변경 파일 후보:

- `Socket/src/config.js`
- `Socket/src/media/mediaUploadService.js`
- `Socket/src/handlers/mediaHandlers.js`
- `Socket/src/app/productionDependencies.js` 또는 현재 media dependency 조립부
- `functions/src/chat/media/{contracts,functions,dispatcher,processingSlots,watchdog}.ts`
- `functions/src/index.ts`, `functions/src/index.contract.test.ts`
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json`
- `tools/chat-media-processing-worker/`
- 환경별 deploy/audit script 후보

구현:

1. preflight가 공개 prefix 대신 exact quarantine paths를 반환한다.
2. Storage Rules가 active capability, room membership, owner reservation, exact path, expiry와 declared content length를 검증한다.
3. finalize는 예약된 전체 object manifest·개수·경로·generation·byte 합계를 검증하고 같은 `MediaUploads`를 queued로 전환한다.
4. 이미지/영상별 Firestore trigger → Cloud Task → dispatcher → 고정 slot → Cloud Run Job execution 흐름을 추가한다.
5. `MediaUploads` worker claim lease, stale lease/slot watchdog, 최대 3회 retry와 terminal cleanup을 구현한다.
6. 전용 identity를 dispatcher, worker, cleanup으로 분리한다. worker는 quarantine read, ready write와 자신이 lease한 `MediaUploads` update만 허용한다.
7. 환경별 quarantine·media·evidence bucket 경계와 quarantine soft delete off·1일 lifecycle을 배포 계약으로 고정한다.
8. v2는 attachment당 quarantine source 하나만 예약한다. 기존 public original+thumbnail 직접 업로드 v1은 Phase 7.3 iOS cutover QA까지 병행하고 v2 전환 뒤 제거한다.

완료 기준:

- 임의 사용자가 타인의 quarantine path에 쓰거나 읽을 수 없다.
- duplicate finalize/task/worker execution이 한 job lease만 처리한다.
- Production 이미지 4·영상 1, Development 이미지 1·영상 1보다 많은 execution이 동시에 시작되지 않는다.
- cancel/expired/invalid/resource-limit/technical failure가 seq 없이 terminal 상태로 끝난다.
- ready/canceled/final failed/expired에서 source와 principal slot은 즉시 정리되고, cleanup 실패로 남은 source만 bucket 1일 lifecycle이 제거한다.
- IAM audit에서 Socket identity에 Tasks/Run Admin 권한이 없다.

### Phase 7.2 — Ready transaction·delivery·cleanup

목표:

- 정규화된 객체만 한 번 message/seq로 materialize하고 기존 realtime ordering과 push를 유지한다.

변경 파일 후보:

- `functions/src/chat/media/{readyService,deliveryJobs,cleanup}.ts`
- `Socket/src/messages/sequenceStore.js`
- `Socket/src/media/mediaDeliveryWatcher.js` 신규
- `Socket/src/push/chatPushService.js`
- `Socket/src/index.js`, `Socket/src/app/`
- `functions/src/chat/cleanup/`
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`

구현:

1. worker 완료 trigger가 reservation/lease/cancel 상태와 normalized manifest를 다시 확인한다.
2. room seq transaction에서 ready reservation, message, media index, room summary와 delivery job을 함께 기록한다.
3. Socket watcher가 delivery job을 lease로 claim해 emit/FCM하고 완료한다.
4. message write 이후 ACK 유실·watcher 재시작·중복 snapshot의 at-least-once event를 messageID/seq로 dedupe한다.
5. canceled/failed/expired quarantine, orphan ready objects와 완료 job을 scheduler로 정리한다.

완료 기준:

- ready 전 read/broadcast/push/preview가 모두 0이다.
- text Socket transaction과 media Function transaction이 같은 room seq에서 경합해도 중복·gap이 없다.
- room preview는 ready 또는 restore 시점에만 바뀐다.
- public message가 없는 ready object는 Rules로 읽히지 않고 cleanup된다.

### Phase 7.3 — iOS upload·pending·outbox

상태: 2026-08-20 완료. attachment별 단일 signed PUT foreground 구조의 로컬 구현·자동 검증과 Development worker image·image Service·video Job·Socket·Functions rollout을 완료했다. iPhone 14에서 JPEG·실제 HEIC→JPEG·PNG·animated GIF, 31장 30+1, 70장 30+30+10 FIFO, 네트워크 실패·재시도, 영상 앱 종료·재실행과 채팅방 화면 이탈·재진입을 확인했다. 앱 재실행은 silent pending 선복원과 status-only 2·4·8초 reconciliation을 사용하며 일반 실패는 팝업 없이 재시도·삭제로 수렴한다. 정확한 350 MiB/장시간 영상 실파일과 실패 확인창 시각 점검은 Production 전 확장 QA로 분리하며 Phase 7.3 완료를 막지 않는다.

목표:

- 사용자가 업로드/대기/처리/실패를 구분하고 앱 재실행 뒤 복원·취소·수동 재시도할 수 있다.

변경 파일 후보:

- `OutPick/Infra/Media/DefaultMediaProcessingService.swift`
- `OutPick/Infra/Media/AVAssetExportVideoCompressor.swift`
- `OutPick/Features/Chat/Domain/Models/{Attachment,ChatOutgoingOutbox}.swift`
- `OutPick/Features/Chat/Repositories/ChatMediaMessageSendingRepository.swift`
- `OutPick/Features/Chat/Domain/UseCases/{ChatMediaUploadUseCase,ChatOutgoingOutboxUseCase}.swift`
- `OutPick/Features/Chat/Stores/ChatPendingMediaUploadStore.swift`
- `OutPick/Infra/Realtime/RealtimeSocketService.swift`
- `OutPick/Features/Chat/Controllers/{ChatViewController,ChatViewControllerExtension}.swift`
- `OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift`
- `OutPick/DB/GRDB/{Migrations/GRDBMigrationRegistry,Stores/GRDBChatOutgoingOutboxStore}.swift`
- `OutPick/Features/Chat/ChatContainer.swift`

구현:

1. `Attachment`에 stable `attachmentID`와 animation/media format metadata를 추가하고 mapper/GRDB/Socket payload를 맞춘다.
2. picker는 계속 unlimited selection이고 image 결과를 순서대로 30장씩 chunk한다. image와 video 혼합 선택은 현재 동작과 일치하게 타입별 message로 분리한다.
3. 정적 image transport source는 orientation bake·4096px·sRGB·metadata 제거, HEIC/HEIF·JPEG quality 0.92와 PNG 보존 계약으로 만든다. GIF는 animation을 보존하고 video는 720p H.264/AAC MP4 하나를 만든다. 이 source만 preflight 응답의 quarantine path로 직접 upload하고 finalize ACK를 `queued`로 해석한다.
4. pending state를 `uploading(progress) | queued | processing | failed(retryable) | expired`로 확장한다.
5. outbox에 server upload ID/status checkedAt와 terminal 시각을 저장하고 relaunch 시 status API로 reconcile한다.
6. ready 전 사용자가 취소하면 local task 취소와 server cancel을 함께 요청한다. server 결과가 ready면 confirmed message로 수렴한다.
7. failed/expired outbox와 local media는 deterministic clock 기준 7일 뒤 삭제한다.
8. GIF picker 결과를 첫 frame JPEG로 변환하지 않고 animation 원본을 outbox/quarantine에 유지한다.
9. video local thumbnail은 pending UI에만 사용하고 server에는 업로드하지 않는다. ready 이후에는 worker가 만든 512px JPEG thumbnail을 사용한다.
10. 이미지와 동영상 quarantine source는 attachment당 V4 signed PUT 하나로 foreground `URLSession`이 직접 전송한다. URL은 24시간 bearer credential로 취급해 로그에 남기지 않는다. PUT 응답 유실 때 서버가 고정 path의 generation·크기·체크섬을 한 번 확인해 정상 객체를 성공으로 복구한다.
11. 서버는 단일 source의 size/SHA-256/MIME 검증 뒤 `queued`로 전환한다. 전송 실패·앱 종료·방 이탈은 로컬 실패로 수렴하며 보호된 source에서 사용자 재시도/삭제를 제공한다. 성공·취소·최종 실패에는 source를 즉시 삭제하며 bucket lifecycle은 실패 cleanup 안전망이다.
11. 수동 재시도는 새 upload/message identity로 시작한다. 새 outbox 저장 전에는 이전 bubble/outbox를 제거하지 않으며, 이전 server terminal record를 재활성화하지 않는다.
12. `ChatMediaUploadUseCase`의 공유 actor가 image/video kind별 FIFO turn을 관리한다. 각 lane은 reservation부터 server terminal까지 한 메시지만 실행하고, turn 대기 중인 메시지는 outbox `needsUpload`와 silent pending 버블을 유지한다.
13. Socket ACK의 machine-readable `active_upload_limit`을 iOS transport error에 보존한다. FIFO head만 같은 upload identity로 2·4·8·15·30초, 이후 30초 backoff 재시도하며 다른 server 오류는 대기로 오분류하지 않는다.
14. reservation 이후 PUT/reconciliation/finalize 실패는 best-effort cancel로 server source·principal slot을 정리한다. cancel/ready first-commit-wins에서 ready면 확정 흐름으로 수렴하고, terminal 또는 task 취소에서 반드시 local turn을 반환한다.
15. 앱 재실행은 outbox local media를 status 조회 전에 silent pending으로 먼저 stage한다. `uploading` server session은 finalize in-flight 가능성을 고려해 2·4·8초 status reconciliation만 수행하고, `queued|processing|ready`면 monitoring을 재개한다. 끝까지 `uploading`이거나 조회 오류가 지속되면 server cancel 후 수동 재시도·삭제로 전환하며 파일 PUT은 자동 재개하지 않는다.

완료 기준:

- 31장 선택은 30장+1장 두 메시지로 순서를 보존한다.
- 60장·70장과 연속 picker batch는 FIFO 순서로 `30+30`, `30+30+10`에 수렴하고 slot 포화만으로 실패하지 않는다.
- preflight `active_upload_limit`은 동일 identity backoff 재시도 후 빈 slot을 사용하며 permission/room access/invalid contract 오류는 즉시 실패한다.
- FIFO waiter 취소는 뒤 waiter를 막지 않고, terminal·cancel/ready 경합·reservation 이후 실패에서 turn과 server slot을 누수하지 않는다.
- 앱 종료/재실행 뒤 uploading/queued/processing/failed 상태가 signed target/object generation reconciliation으로 중복 upload 없이 복원된다.
- 앱 재실행 직후 영속화용 `isFailed`가 왼쪽 실패 표시로 노출되지 않고, 종료 직전 finalize가 commit된 경우 silent pending에서 server success로 수렴한다.
- cancel/ready race 결과가 서버와 UI에서 일치한다.
- 7일 전 실패 원본은 유지되고 7일 경계 이후 record/file이 함께 삭제된다.

테스트 계획:

- `ChatMediaUploadTurnQueueTests`: kind별 FIFO, image/video lane 독립, head 완료 뒤 다음 시작, waiter 취소 뒤 다음 진행을 deterministic continuation으로 검증한다.
- `ChatMediaUploadUseCaseTests`: `active_upload_limit → backoff → 동일 identity 예약 성공`, 비용량 오류 즉시 실패, 예약 이후 실패 cancel, cancel/ready 경합 ready 우선을 fake repository와 injected sleeper로 검증한다.
- `ChatMediaUploadUseCaseTests`: relaunch reconciliation이 `uploading → queued|ready`를 status-only polling으로 성공 복원하고, 계속 `uploading`·반복 조회 오류는 cancel/manual retry로 닫으며 foreground uploader를 호출하지 않는다.
- Socket/iOS transport test: ACK `active_upload_limit` machine code가 일반 localized message 파싱 없이 typed reservation error로 매핑되는지 검증한다.
- 기존 `ChatMediaSelectionChunkerTests`: 31·60·70장 chunk count와 각 message reindex·원본 순서 보존을 검증한다.
- 수동 QA: slot이 하나만 가용한 Development에서 70장 선택과 연속 picker batch가 silent pending을 유지한 뒤 전부 ready·cleanup되고, 방 이탈 시 waiting 메시지가 실패·재시도/삭제로 전환되는지 확인한다.
- 수동 QA: 영상 PUT 중 앱 종료·재실행 시 왼쪽 실패 표시가 깜빡이지 않고, 종료 전 finalize가 commit됐으면 조용히 성공하며 미완료 `uploading`이면 재확인 뒤 재시도·삭제 상태로 수렴하는지 확인한다.
- 수동 QA: 일반 이미지·동영상 전송 실패는 전역 팝업 없이 실패 버블의 재시도·삭제만 표시하고, room access 재확인 결과 ban인 경우에만 참여 제한 중단 안내를 표시하는지 확인한다.
- 시각 snapshot/UI 자동화는 추가하지 않는다. 활성 waiting/uploading/queued/processing이 모두 기존 silent presentation을 공유하므로 실제 버블 순서와 실패 아이콘 유무를 실기기에서 확인한다.

### Phase 7.4 — 신고 evidence·삭제 경합·retention

#### 목표와 권위 원장

- 신고된 메시지 전체를 review revision당 한 번만 보존하고 신고/삭제 순서와 관리자 처리 결과에 따라 evidence가 정확히 생성·삭제되게 한다.
- 별도 `moderationReviewQueue` projection과 72시간 승격 scheduler는 만들지 않는다. 관리자 API는 canonical `moderationMessageIncidents`, `moderationUserReports`, `moderationRoomReports`를 직접 조회한다.
- evidence 준비 중에는 server-only guard/bundle/job만 존재하고 canonical 신고 집계에는 포함하지 않는다. evidence가 `available`이 된 뒤 `moderationMessageIncidents/{incidentID}`가 현재 revision의 queue/review/visibility/evidence projection, `revisions/{reviewRevisionID}`이 revision audit, `revisions/{reviewRevisionID}/reporters/{reporterID}`가 revision당 reporter 한 건을 소유한다.
- `moderationUserReports/{senderPrincipalID}/reportedMessages/{incidentID}`와 `messageReporters/{reporterID}`를 분리하고 최근 7일 query를 각각 limit 3/2로 실행해 `3 messages + 2 reporters` 패턴을 정확히 판정한다.
- `moderationMessageGuards/{incidentID}`는 client deny인 신고/삭제 경합 권위다. 신고 여부를 client-readable message document의 필드로 노출하지 않는다.
- `moderationMessageEvidence/{bundleID}`는 text snapshot과 전체 attachment manifest를 공통 소유하고, `moderationEvidenceCopyJobs`와 `moderationEvidenceCleanupJobs`가 Storage 상태를 멱등 처리한다.

#### API 계약

- `submitMessageReport(roomID, messageID, reason, detail?, clientRequestID)`는 active/restricted reporter, App Check, active room read context와 self-report 금지를 검증한다.
- 최초 evidence 준비는 `status=processing`이며 신고 count·queue·visibility에 반영하지 않는다. text snapshot 또는 전체 media evidence가 `available`이 된 뒤에만 `status=accepted`를 반환한다.
- 같은 `clientRequestID` replay는 revision과 무관한 최상위 `moderationMessageReportRequests/{requestID}`를 현재 revision 선택보다 먼저 조회한다. 앱은 최초 UUID를 terminal 결과까지 유지한다. 준비 중이면 동일 `processing`, 완료됐으면 최초 terminal receipt를 반환해 관리자 종결 뒤 지연 retry도 새 revision을 만들지 않으며 transport quota도 다시 소비하지 않는다. 같은 reporter/message/reviewRevision의 새 `clientRequestID`는 새 transport receipt slot 1개를 소비하되, 준비 중이면 결정적 bundle 작업을 재사용하고 접수 완료 뒤에는 `status=alreadyReported`, `alreadyReported=true`, `originalReceivedAt`을 반환한다. 이때 moderation count·evidence는 중복 변경하지 않는다.
- 삭제가 먼저 확정된 message는 `status=messageAlreadyDeleted`, `messageID`, `seq`를 반환하고 신고 원장·evidence·moderation count는 만들지 않는다. 새 `clientRequestID`이면 최상위 transport receipt를 만들고 공유 limiter slot 1개를 소비한다.
- 신규 접수 성공은 `status=accepted`, incidentID/reviewRevision/submissionID, `queueClass=holding|reviewRequired|urgent`, `visibilityState`, `receivedAt`을 반환한다.
- 기존 `listModerationReports`를 `targetType=message`일 때 `messageQueueView=urgent | reviewRequired | overdueHolding | inReview | resolved | dismissed`를 받도록 확장한다. `overdueHolding`은 `queueClass=holding && reviewDueAt<=serverNow`를 직접 조회하며 문서를 변경하지 않는다.
- 기존 `getModerationReportDetail(targetType=message, targetID=incidentID)`은 현재 revision reporter submission, 작성자 최근 90일 확정 위반 참고값, evidence 상태와 object ID만 반환한다. byte URL은 반환하지 않는다.

#### Phase 7.4A — 순수 계약·단위 테스트

1. domain/version을 포함한 canonical tuple SHA-256으로 message incident/revision/reporter/submission/bundle/guard/job의 결정적 ID와 상태 enum을 추가한다. 최초 revision은 0이며 terminal review 뒤 새 유효 신고만 revision을 증가시킨다.
2. queue 판정은 긴급 첫 신고 `urgent`, 일반 첫 신고 `holding`, 전체 고유 reporter 2명 `reviewRequired`다. `urgent`는 이후 일반 신고로 낮아지지 않는다.
3. global hide는 같은 revision 최근 24시간 긴급 고유 2명 또는 전체 사유 고유 3명이다. 긴급 reporter도 전체 count에 포함한다.
4. same-author pattern은 최근 7일 서로 다른 incident 3개와 고유 reporter 2명 이상을 함께 요구한다. 한 reporter의 3개 메시지 연속 신고와 한 메시지 다중 신고는 불충족이다. 충족 시 `messagePatternReviewUntil = min(세 번째 최신 메시지 시각, 두 번째 최신 신고자 시각) + 7일`로 계산해 scheduler 없이 만료시킨다.
5. retention은 review open/inReview 보류, 기각·삭제만·경고만 즉시 cleanup, restriction/suspension 30일, appeal/legal hold 보류로 계산한다.
6. 신고 결과는 `processing | accepted | alreadyReported | failed | messageAlreadyDeleted`다. `processing`은 evidence 준비 상태이며 `available` 뒤에만 신규 accepted 집계 효과를 가진다.
7. 24시간·7일은 시작 경계를 포함하고 미래 시각을 제외한다. overdue는 `reviewDueAt <= serverNow`, 작성자 패턴은 `messagePatternReviewUntil > serverNow`만 활성이다.
8. 이전 선택 attachment/video timestamp WIP는 제거했고, 2026-08-21 사용자 승인 뒤 위 최신 계약만 `functions/src/moderation/messageEvidence/{contracts,contracts.test}.ts`에 구현했다.

#### Phase 7.4B — 신고/삭제 transaction

구현·활성화 경계:

- parser·service·transaction과 테스트만 구현하고 root callable export·Development/Production 배포는 하지 않는다. Phase 7.4C/D와 Phase 7.5 iOS 준비 뒤 활성화한다.
- legacy media fallback은 만들지 않는다. 신규 ready attachment에 display generation/contentType을 추가하고 테스트 데이터 cleanup 뒤 신규 schema 메시지만 신고한다.
- 신고 대상은 user-authored text/image/video/lookbookShare다. reply/sharedContent는 target message에 이미 포함된 bounded 표시 snapshot만 보존하고 참조 원문을 따라가지 않는다.

신규 신고 transaction read set:

- reporter `moderationAccounts/{uid}`와 room/member
- `Rooms/{roomID}/Messages/{messageID}`
- sender `moderationAccounts/{senderUID}`
- `moderationMessageGuards/{incidentID}`
- incident root와 current revision reporter doc
- current revision 최근 24시간 reporter query: 전체 limit 3, 긴급 limit 2
- user aggregate, `reportedMessages/{incidentID}`, `messageReporters/{reporterID}`와 최근 7일 marker query limit 3/2
- reporter minute rate bucket

신규 신고 transaction write set:

- guard `reportFirst|deleteFirst`와 evidence `copyPending|copying|available|failed`, preparation `attemptGeneration`
- evidence가 available인 신규 accepted 확정에서만 incident root, revision audit와 reporter doc
- evidence가 available인 신규 accepted 확정에서만 user aggregate와 reported-message/reporter marker
- text/manifest evidence bundle과 media가 있으면 copy job
- user/room accepted 요청과 이전에 보지 못한 message `clientRequestID` transport receipt는 principal당 UTC 1분 10회 기술 limiter를 공유한다. 정확히 같은 UUID replay만 무료다. 새 UUID는 preparation 재사용·alreadyReported·messageAlreadyDeleted여도 receipt slot 1개를 소비하지만 moderation 신고 count/queue/evidence에는 포함하지 않는다. 신규 semantic preparation은 별도 관측 count만 증가시키며 같은 요청을 이중 과금하지 않는다.
- global threshold 충족 시 message `moderationVisibilityState=hiddenPendingReview`와 server-only 복원 payload
- `requestedAt`과 `acceptedAt`을 분리하고 canonical received/window/SLO 시각은 requestedAt을 사용한다.
- 최초 bundle available 뒤 processing preparation을 최대 30건씩 accepted로 확정하는 동안 incident는 `draining`, 모두 끝난 뒤 `reviewable`이다. 각 preparation의 `initialRequestID` receipt만 drain에서 함께 확정하고 추가 alias receipt는 같은 UUID 재조회 시 terminal generation 결과로 개별 수렴한다. 관리자 종결은 reviewable에서만 허용한다.

삭제 transaction:

- 기존 room/message/job/audit과 guard를 함께 읽는다.
- guard가 없거나 `contentState=deleted`면 delete가 guard `deleted`를 먼저 쓰고 기존 tombstone/cleanup을 진행한다. 뒤 신고는 `messageAlreadyDeleted`로 종료한다.
- guard가 report-first hold면 message tombstone은 즉시 적용하고 public ready media용 `chatMessageCleanupJobs`를 `awaitingEvidence`로 만든다. cleanup worker는 이 상태를 claim하지 않으며 evidence copy 성공 또는 terminal failure 뒤 `pending`으로 전환한다.
- 두 transaction이 같은 guard를 읽고 쓰므로 동시 실행은 Firestore 재시도로 한 순서에 수렴한다.
- 이전에 보지 못한 새 `clientRequestID`의 delete-first와 semantic duplicate는 최상위 transport receipt를 만들고 공유 limiter slot 1개를 소비한다. 정확히 같은 UUID replay만 quota를 다시 소비하지 않는다.
- 관리자 confirmed delete는 client-safe `deletionPresentation=moderationRemoved`를 tombstone에 남기고 처리 중 preparation을 messageAlreadyDeleted로 종료한다. dismiss 뒤 새 유효 신고는 reviewRevision을 증가시켜 새 bundle로 시작한다.

멱등성·재시도:

- 같은 reporter/message/revision은 reason/detail과 무관하게 최초 preparation 한 건을 권위로 사용한다. processing은 기존 작업, accepted는 alreadyReported이며 사유 수정 API는 두지 않는다.
- 실패 request receipt는 원래 generation 결과를 유지한다. partial destination cleanup과 빈 `objectPaths`까지 완료된 bundle `failed`, preparation `failed`, copy job `failed`의 동일 generation을 확인한 뒤 새 clientRequestID만 같은 deterministic ID의 세 문서를 모두 증가한 attemptGeneration으로 원자 재시작하고 stale generation worker는 쓰기를 거부한다.

#### Phase 7.4C — evidence copy·cleanup

1. text-only bundle은 신고 transaction에서 snapshot이 완성되므로 media copy 없이 `available`이다.
2. media bundle은 server-derived attachment 1...30개의 ready bucket/path/generation/bytes/contentType을 copy job에 고정한다. worker는 환경별 exact ready bucket, message/attachment display path, image 1...30 JPEG/PNG/GIF 또는 video MP4 1개를 다시 검증하고 client 값·일반 URL·thumbnail·quarantine source를 신뢰하지 않는다.
3. evidence object는 `{bundleID}/g{attemptGeneration}/{attachmentID}/display`다. source generation, destination create-if-absent와 delete generation precondition, Firestore `attemptGeneration + leaseToken`을 함께 사용해 동일 attempt replay는 dedupe하고 이전 generation worker는 새 attempt를 오염·삭제하지 못한다.
4. 이미지 묶음은 모든 normalized display, 동영상은 normalized MP4 전체 1개만 복사한다. thumbnail과 quarantine source는 evidence가 아니다.
5. 별도 evidence byte cap으로 정상 ready message의 신고를 거부하지 않는다. bundle에 `totalDisplayBytes`를 기록하고 Development에서 30장/350 MiB 복사 시간·비용을 측정한다.
6. copy는 최초 포함 최대 3회, 실패 뒤 1분/2분 backoff다. retry 중 partial destination은 같은 generation에서 재사용하고 public cleanup은 기다린다. 3회째 실패하면 partial destination 삭제와 preparation/최초 receipt failure drain을 끝낸 뒤 bundle 최소 failed tombstone·guard failed·public cleanup pending으로 수렴한다. partial 상태를 accepted로 확정하지 않는다.
7. job phase는 `copying | acceptanceDrain | cleaningPartial | failureDrain | completed`다. Storage metadata 검증은 `copying` 안에서 수행하고, bytes available 뒤 preparation을 최대 30건씩 모두 accepted로 drain한 후에만 copy job을 succeeded로 만든다. onCreate + 5분 scheduler, timeout 9분, lease 12분, scheduler limit 10, Development/Production maxInstances 1/2를 초기값으로 사용한다. 마지막 시도의 만료 lease는 같은 시도 번호로 회수해 copy 또는 cleanup 횟수 상한을 넘기지 않고 terminal 상태로 수렴시킨다.
8. retention cleanup은 저장된 destination generation과 일치하는 object를 먼저 모두 삭제하고 evidence bundle 문서를 완전 삭제한다. cleanup job은 민감 field를 scrub한 최소 완료 영수증만 7일 유지한다. copy job도 완료 뒤 source/evidence와 room/message 연결을 scrub해 7일 유지하고 request receipt는 30일 유지한다.
9. C-1은 로컬 구현·fake Storage·Firestore emulator, C-2는 Development bucket/IAM/root export/세 Function, C-3는 필수 인덱스 3개와 30장/350MiB·접근 거부·soft delete/cleanup 실측까지 완료했다. Production rollout은 별도 승인 gate다.

#### Phase 7.4D — Rules·index·관리자 query·문서

- Firestore Rules는 incident/revision/reporter/user marker/guard/evidence/job/confirmed violation을 모든 client read/write에서 deny한다.
- Storage Rules는 evidence bucket/prefix를 모든 Firebase client SDK read/write에서 deny한다.
- message incident index는 queue view별로 고정한다: `queueClass + reviewState + slaDueAt + lastReportedAt + __name__`, overdue는 `queueClass + reviewState + reviewDueAt + lastReportedAt + __name__`.
- user pattern marker의 `lastReportedAt`은 parent-scoped query로 `reportedMessages` 최근 3개와 `messageReporters` 최근 2개만 읽고 무제한 배열을 aggregate에 저장하지 않는다.
- user 관리자 요약은 `messagePatternReviewUntil > serverNow`일 때만 반복 메시지 신고 신호를 활성 표시한다. 만료 시 문서를 재작성하는 scheduler는 두지 않는다.
- 관리자 API는 source collection별 cursor를 사용하고 message/user/room을 한 cursor에 임의 병합하지 않는다. 관리자 웹은 별도 section/tab으로 표시한다.

#### 변경 파일 후보

- `functions/src/moderation/reports/{contracts,service,functions}.ts`
- `functions/src/moderation/messageEvidence/{contracts,service,evidenceCopy,evidenceCleanup}.ts` 신규
- `functions/src/moderation/admin/{contracts,service,functions}.ts`
- `functions/src/chat/moderation/service.ts`, `functions/src/chat/cleanup/`
- `functions/src/index.ts`, `functions/src/index.contract.test.ts`
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`
- `contracts/chat-moderation-v1.json`, `DATA_SCHEMA.md`, entrypoint/QA 문서

#### 완료 기준

- 30장 이미지 메시지 신고는 30장 전체가 한 evidence bundle에 존재하고 동일 revision 후속 신고가 object를 늘리지 않는다.
- 같은 request replay는 일반 성공, 같은 reporter의 새 request는 already-reported, delete-first는 already-deleted로 구분된다.
- 3 messages + 2 reporters/7일, urgent/general queue와 24시간 global threshold가 경계 시각±1 ms에서 일치한다.
- delete/report 동시 transaction 두 순서가 guard에 의해 각각 계약대로 수렴한다.
- 72시간 holding은 scheduler/write 없이 server-now query에서만 overdue 목록에 포함된다.
- cleanup 실패는 retryPending/failed로 남고 evidence를 조용히 유실하지 않는다.
- 일반 사용자·비활성 admin·권한 없는 server identity가 evidence를 읽지 못한다.

### Phase 7.5 — 신고 UX·관리자 queue·전역 숨김/복원

목표:

- 실제 사용자 신고 흐름을 서버 계약에 연결하고 관리자 queue 승격과 동일 seq 전역 복원을 앱 전체에 적용한다.

변경 파일 후보:

- `OutPick/Features/Chat/Domain/Models/ChatModerationReport.swift`
- `OutPick/Features/Chat/Repositories/ChatModerationReportingRepository.swift`
- `OutPick/Features/Chat/Domain/UseCases/SubmitChatModerationReportUseCase.swift`
- `OutPick/Features/Chat/Domain/Policies/ChatMessageActionPolicy.swift`
- `OutPick/Features/Chat/Moderation/` 신규 ViewModel·ViewController
- `OutPick/Features/Chat/Controllers/{ChatViewController,ChatViewControllerExtension}.swift`
- `OutPick/Infra/Media/ImageViewer/SimpleImageViewerVC.swift`
- `OutPick/Features/Chat/Services/MediaPreview/`
- `OutPick/DB/GRDB/` message/media index store·migration
- `OutPick/Features/Chat/{ChatCoordinator,ChatContainer,ChatCompositionRoot}.swift`

구현:

1. 현재 stub `handleReport`를 attachment 선택 없는 메시지 신고 reason/detail 화면으로 연결한다.
2. image viewer 진입도 현재 image 한 장이 아니라 해당 메시지 전체 신고임을 명시한다.
3. report 성공은 접수 안내만 표시하고 메시지를 자동 숨기지 않는다. 명시적 개인 메시지 숨김은 후속 범위로 분리한다.
4. 관리자 API는 canonical incident를 직접 조회해 일반 단일 holding, 같은 메시지 고유 2명 reviewRequired, 긴급 단일 urgent와 `holding && reviewDueAt<=serverNow` overdue 목록을 제공한다. 작성자 반복 패턴은 서로 다른 메시지 3개와 고유 신고자 2명/7일을 모두 요구한다.
5. global hide event는 GRDB public payload/media index와 앱 내부 media cache를 정리하고 동일 seq 검토 tombstone으로 바꾼다.
6. restore event는 authoritative message를 다시 받아 같은 seq에 복원하며 unread/banner/push를 만들지 않는다.
7. 일반 사용자 신고 화면은 Phase 7에서 message/image-viewer 경로만 구현한다. 프로필·참여자 목록·방 설정 신고와 제한/정지/지원 통합은 Phase 8에 남긴다.

완료 기준:

- 신고 전송 실패 시 사유·detail과 clientRequestID가 유지된다.
- 신고 성공 직후 메시지는 자동으로 사라지지 않는다.
- 같은 request replay는 일반 접수 성공, semantic duplicate는 `이미 신고한 메시지예요`, delete-first는 `이미 삭제된 메시지예요`를 표시하고 즉시 같은 seq tombstone으로 수렴한다.
- 관리자 기각 뒤 모든 사용자는 같은 seq 내용을 복원한다.
- hidden/restore가 visible unread, read frontier, room latestSeq를 변동시키지 않는다.
- Dynamic Type·VoiceOver에서 이유, 메시지 전체 신고 안내, 제출/취소와 결과 문구를 탐색할 수 있다.

### Phase 7.6 — 통합·정책·Development rollout 준비

목표:

- 코드 완료와 외부 출시 가능 조건을 분리하고 Development에서 안전하게 검증할 배포 단위를 만든다.

변경 파일 후보:

- `docs/ai/ENTRYPOINTS.md`
- `docs/ai/entrypoints/{CHAT,FIREBASE,TESTS}.md`
- task `progress.md`, `qa-checklist.md`, `HANDOFF.md`
- 환경별 IAM/deploy/audit script
- App Review Notes 초안과 개인정보 처리방침/App Privacy 갱신 후보 문서

구현:

1. container digest, Functions/Socket source revision, Rules/index manifest와 iOS contract version을 하나의 호환 matrix로 기록한다.
2. Development deploy는 worker/dispatcher/Functions/Rules/index/Socket/iOS 순서를 고정하고 각 mutation 전 별도 사용자 승인을 받는다.
3. 기존 공개 path pending upload가 있으면 읽기 전용 감사하고 0건이면 migration 없이 cutover한다. 존재하면 별도 migration/cleanup 승인을 받는다.
4. App Review demo 계정에서 신고·차단·고객지원·임시 숨김·복원 흐름을 재현할 fixture를 준비한다.
5. 개인정보 처리방침에 evidence 목적·메시지 전체 수집 범위·접근권한·처리 결과별 보존을 반영할 문구를 준비한다.

완료 기준:

- 모든 targeted 자동 검증과 Development 수동 QA가 통과한다.
- 권한 없는 client/evidence 접근과 ready 전 공개가 실제 Development에서 실패한다.
- App Review Notes, support URL/운영 담당, 24h/72h queue가 준비되기 전 외부 출시를 진행하지 않는다.
- 관리자 evidence byte 전달 방식은 `admin-web-operations-migration` 미구현 상태로 남고 Phase 7 클라이언트에 임시 URL을 추가하지 않는다.

## 테스트 계획

### Worker unit/fixture

- 실제 MIME과 확장자 불일치, 손상 파일, oversized input/output.
- JPEG/PNG orientation bake, sRGB, metadata 제거와 4096px/15 MiB 상한, raw HEIC/HEIF 거부. iOS HEIC/HEIF→JPEG는 Phase 7.3 대상이다.
- animated GIF frame/order/delay/loop 보존, resource-limit 경계±1.
- MP4/H.264/AAC probe, 장시간 duration, rotation/color 보존, metadata/aux track 제거, 350 MiB 경계.
- retryable I/O와 non-retryable invalid/resource-limit 분류.

### Functions unit/transaction

- finalize/job/lease/watchdog idempotency와 최대 3회.
- cancel-before-ready, ready-before-cancel, stale lease와 duplicate execution.
- text/media 동시 seq allocation, ready transaction 재시도와 delivery 단일 생성.
- report attachment validation, reporter dedupe, 24시간 threshold, reviewRevision reset.
- report-first/delete-later, delete-first/report-later, evidence copy dedupe.
- dismissal/sanction/appeal retention과 cleanup retry.
- hidden/restore의 동일 seq·latestSeq·read frontier 불변성.

### Socket unit

- preflight/finalize/status/retry/cancel capability·room ban·rate limit.
- finalize가 직접 message/seq/emit/push를 만들지 않는 회귀.
- delivery watcher reconnect/duplicate snapshot의 at-least-once event와 client first-wins dedupe.
- global visibility event의 room fan-out과 원문 로그 비노출.

### Firestore·Storage emulator

- reservation owner exact quarantine write만 허용.
- ready 전 quarantine/ready path read deny.
- ready message 이후 public read와 canceled/failed path deny.
- report/evidence/signal/restore payload client direct read/write deny.
- owner-only personal hide relation read와 client write deny.
- moderation state client mutation deny.

### iOS unit

- picker 결과 30장 chunk 순서와 stable attachment ID mapping.
- pending state, relaunch status reconciliation, cancel/ready race와 manual retry.
- deterministic clock 기반 failed outbox 7일 retention 경계.
- report command validation, 선택 유지, 동일 UUID retry.
- attachment visibility reindex, representative/reply preview 선택.
- global hidden/restore가 unread를 만들지 않고 개인 hide를 유지.
- Coordinator report/image-viewer route spy와 Repository fake failure.

### 수동 QA

- 실제 JPEG·HEIC·PNG·animated GIF 선택, iOS HEIC/HEIF→JPEG 전송, animation 재생, 저장과 서버 raw HEIC/HEIF 거부.
- 31장 선택의 30+1 message 분할과 대기 overlay.
- 장시간 동영상 background/foreground·앱 재실행·취소·재시도.
- message/image viewer의 전체 메시지 신고, attachment 선택 UI 부재, 신고 뒤 자동 숨김 부재.
- global 검토 tombstone·기각 복원·room preview와 unread.
- 작은 화면, 최대 Dynamic Type, VoiceOver, 네트워크 단절.

단순 레이아웃 pixel 배치와 happy path navigation은 UI 자동 테스트를 추가하지 않고 수동 QA를 우선한다. 서버 race, Rules, retention, cache/outbox와 상태 전이는 자동 테스트를 필수로 한다.

## 정책 리스크와 출시 gate

| 우선순위 | 리스크 | 구현 요구사항 | 출시 조건 |
| --- | --- | --- | --- |
| P0 | Apple Guideline 1.2의 게시 전 필터 요구를 자동 의미 검사 없이 충족하는지 **확실하지 않음** | 신고·차단·임시 숨김·신속 처리·연락처를 실제 앱/서버 경로로 제공 | App Review Notes와 심사 피드백 확인 전 외부 출시 금지 |
| P0 | evidence에 민감 이미지·영상과 개인정보가 포함될 수 있음 | 메시지/attachment·byte 상한, client deny, active admin server authorization, audit, 처리 결과별 삭제 | 개인정보 처리방침·법률 검토와 Development bundle 용량 측정 완료 |
| P0 | 아동 성착취물·즉각적 불법 위험 처리 의무가 **확실하지 않음** | 일반 evidence와 분리 가능한 restricted escalation hook만 두고 임의 legal hold 금지 | 별도 법률·운영 runbook 승인 |
| P1 | 신고 처리 지연 | 긴급 24시간·일반 72시간 SLO 경고와 담당 운영 경로 | 실제 담당자·support URL 준비 |
| P1 | 심사자가 backend 흐름을 재현하지 못함 | demo 계정·신고·차단·숨김·복원 fixture와 App Review Notes | 제출 전 end-to-end smoke |
| P2 | Photos 권한과 로컬 원본 오해 | picker 사용 시점 권한, 로컬 원본은 변경하지 않는 UX, 실패 outbox 7일 삭제 | 권한 거부·설정 복구 QA |

Apple App Review Guidelines 1.2 확인일: 2026-08-18

- https://developer.apple.com/app-store/review/guidelines/
- UGC 앱에는 부적절 콘텐츠 필터링 방법, 신고와 신속 대응, 악성 사용자 차단, 공개 연락처가 요구된다.
- OutPick의 신고 기반 모델이 첫 요구를 충족하는지는 공식 문서만으로 보장할 수 없어 **확실하지 않음**으로 유지한다.

## 배포·rollback 순서

구현 완료는 배포 승인이 아니다. 각 환경 배포는 별도 사용자 승인을 받는다.

1. Development 신규 server-only collections의 deny Rules와 index를 배포한다.
2. worker image와 Cloud Run Job을 생성하되 dispatcher traffic/trigger는 비활성으로 둔다.
3. Functions dispatcher/worker callback/watchdog/evidence API를 배포한다.
4. Socket candidate를 0% 또는 tagged revision으로 배포하고 신규 event contract를 smoke한다.
5. iOS Development 빌드를 설치한 뒤 신규 upload만 quarantine으로 보낸다.
6. 실제 fixture QA와 cleanup audit 후 Development를 완료한다.
7. Production은 원격 index/IAM/data를 다시 읽기 전용 감사하고 exact target별 승인을 받는다.

Rollback:

- 신규 iOS cutover 전에는 기존 Socket media finalize를 유지한다.
- cutover 뒤 구버전이 공개 path finalize를 호출하지 못하도록 최소 호환 버전 또는 server contract version을 확인한다.
- worker/dispatcher 장애 시 신규 media preflight만 fail closed하고 text/lookbook message는 유지한다.
- message가 ready된 뒤에는 worker rollback으로 해당 message seq를 되돌리지 않는다.

## 커밋 후보

1. 계약·ADR·fixture scaffold
2. worker image/video processor와 fixture tests
3. Functions job orchestration·ready transaction·cleanup
4. Firestore/Storage Rules·indexes와 emulator tests
5. Socket reservation/finalize/delivery watcher와 tests
6. iOS attachment/outbox/upload state와 tests
7. evidence/visibility backend와 transaction tests
8. iOS 신고/visibility UX와 tests
9. 하네스·QA·runbook 문서

같은 service/protocol 경계와 DI 조립부를 건드리므로 Phase 7.1~7.5 구현은 순차 진행한다. Worker fixture 준비와 iOS 화면 wireframe 수준 검토만 병렬 후보이며, 코드 통합은 각 선행 계약이 고정된 뒤 진행한다.

## 다음 승인 단위

1. Phase 7.0 fixture·worker container·Linux 검증과 contract 수치 반영은 완료했다.
2. Phase 7.1·7.2 서버 로컬 구현과 Development bucket/IAM/queue/Job/Functions/Rules/index/TTL 반영은 완료했다. Production은 변경하지 않았다.
3. Phase 7.3 signed PUT·영상 조각 upload·pending·outbox 로컬 구현, Development signer IAM·backend 배포와 image/video backend core E2E는 완료했다. 다음은 실제 iOS background·cancel race·형식/상한 확장 QA이며 Production은 별도 승인 전 변경하지 않는다.
4. Production 배포와 traffic·Firebase mutation은 환경별 exact target 승인 없이는 수행하지 않는다.
