# Chat Media Production Rollout Runbook

## 목적과 범위

Phase 7.0~7.3의 격리 업로드, 서버 정규화, ready 전달, iOS pending/outbox를 `outpick-664ae`에 반영한다. App Store/TestFlight 출시는 범위 밖이며, 머지된 정확한 Git SHA의 backend와 Production iOS build/smoke까지만 수행한다.

Production 변경 전 Functions·Socket·Worker·Rules·iOS 자동 검증과 사용자 기기 QA가 모두 완료되어야 한다. 배포 소스는 PR merge SHA와 일치해야 하며 dirty worktree나 PR branch에서 직접 배포하지 않는다.

## Canonical 자원

| 종류 | 이름 |
| --- | --- |
| Project/region | `outpick-664ae` / `asia-northeast3` |
| Quarantine / ready bucket | `outpick-664ae-chat-media-quarantine` / `outpick-664ae-chat-media` |
| Artifact Registry | `outpick-workers` |
| Image Service / video Job | `outpick-chat-media-image` / `outpick-chat-media-video` |
| Cloud Tasks | `chat-media-image-processing` / `chat-media-video-processing` |
| Orchestrator / cleanup SA | `outpick-chat-media-orch` / `outpick-chat-media-cleanup` |
| Worker / task SA | `outpick-chat-media-worker` / `outpick-chat-media-task` |
| Socket runtime SA | 기존 `outpick-socket-runtime-v2` |

버킷은 Standard, `asia-northeast3`, public access prevention enforced, uniform bucket-level access를 사용한다. Quarantine은 soft delete와 versioning을 끄고 `config/chat-media/quarantine-lifecycle.json`의 age 1 delete lifecycle을 적용한다. ready bucket은 클라이언트 직접 write를 허용하지 않는다.

## 배포 순서

1. 머지 SHA, 현재 Socket traffic 100% revision, 기존 Firestore/Storage ruleset과 Function source generation을 기록한다.
2. 위 canonical service account·bucket·queue·Artifact Registry를 생성한다. 이름이 이미 존재하면 설정을 읽어 계약과 정확히 일치하는지 확인하고 임의 덮어쓰기를 중단한다.
3. Worker image를 merge SHA tag로 Cloud Build하고 digest를 기록한다. 같은 digest를 image Service와 video Job에 사용한다. image는 private, concurrency 1, 2 vCPU/1 GiB/min 0이며 video는 task/parallelism 1, retry 0, 2 vCPU/1 GiB다.
4. IAM을 최소 범위로 적용한다. Worker는 두 media bucket object와 Firestore 작업만, orchestrator는 Firestore·Tasks enqueue·image invoke·video execute-with-overrides만, cleanup은 Firestore·두 bucket cleanup만, task는 dispatcher invoke만 가진다. Socket에는 Quarantine bucket `roles/storage.objectUser`와 자기 service account의 `roles/iam.serviceAccountTokenCreator`만 추가한다.
5. `firestore.indexes.json`을 먼저 배포하고 신규 index가 `READY`인지 확인한다. 그 뒤 `firestore.rules`, 기본 `storage.rules`, `firebase.chat-media.json`의 두 exact target을 배포한다. ruleset ID와 로컬 hash를 기록한다.
6. `functions/.env.outpick-664ae`에 canonical URL/audience·queue·service account·Job·bucket을 로컬로만 설정하고 신규 media Function 5개와 변경된 cleanup Function 3개를 exact target으로 배포한다. Gen2 재배포 뒤 trigger Eventarc receiver와 underlying Run invoker binding을 재감사한다.
7. Socket은 merge SHA로 `--no-traffic` candidate를 만든다. candidate readiness, 인증 handshake, 단건 JPEG/MP4 backend smoke, 최근 ERROR 0을 확인한 뒤에만 traffic 100%를 전환한다.
8. Production iOS 스킴을 기기에 설치해 JPEG·PNG·GIF·video 단건, 31장 또는 70장, 앱 종료/재진입 status 복구를 smoke한다. QA 데이터와 임시 IAM/App Check credential은 즉시 회수한다.

## 필수 환경 변수

- Socket: `CHAT_MEDIA_QUARANTINE_BUCKET=outpick-664ae-chat-media-quarantine`.
- Functions: `CHAT_MEDIA_DISPATCHER_URL`, `CHAT_MEDIA_DISPATCHER_AUDIENCE`, `CHAT_MEDIA_IMAGE_TASKS_QUEUE`, `CHAT_MEDIA_VIDEO_TASKS_QUEUE`, `CHAT_MEDIA_TASKS_SERVICE_ACCOUNT_EMAIL`, `CHAT_MEDIA_IMAGE_SERVICE_URL`, `CHAT_MEDIA_IMAGE_SERVICE_AUDIENCE`, `CHAT_MEDIA_VIDEO_JOB_NAME`, `CHAT_MEDIA_QUARANTINE_BUCKET`, `CHAT_MEDIA_READY_BUCKET`.
- Worker: `CHAT_MEDIA_READY_BUCKET=outpick-664ae-chat-media` 고정. upload path·lease token·kind는 dispatcher가 실행별로 주입한다.

`.env.outpick-664ae`와 signed URL, OIDC token, App Check debug token은 Git·로그·문서에 기록하지 않는다.

## 배포 후 게이트

- 신규/변경 Function이 모두 `ACTIVE`, scheduler가 enabled이고 최근 ERROR가 0이다.
- 두 queue는 `RUNNING`, image Service와 video Job은 같은 image digest·canonical worker identity다.
- 두 bucket은 public IAM 0, quarantine lifecycle age 1, soft delete/versioning off다.
- Socket candidate와 live `/readyz`가 200이고 live traffic은 단일 검증 revision 100%다.
- Firestore delivery job이 `completed`, `MediaUploads`가 `ready`, source가 quarantine에서 삭제되고 ready 두 variant만 남는다.
- signed URL·required headers가 앱 GRDB와 서버 로그에 남지 않는다.

## Rollback

- Socket 문제는 기록한 이전 revision으로 즉시 traffic 100%를 되돌린다.
- Functions 문제는 배포 전 source generation으로 exact Function만 재배포하고 신규 client rollout을 중단한다.
- Rules 문제는 기록한 이전 ruleset을 release에 다시 연결한다. 보안 규칙을 완화해 우회하지 않는다.
- Worker 문제는 Service/Job을 직전 digest로 되돌린다. queued upload는 watchdog과 Cloud Tasks retry가 수렴하므로 원장을 직접 수정하지 않는다.
- 버킷·service account·queue는 rollback 중 삭제하지 않는다. 신규 자원 삭제는 잔존 object/job과 참조 0을 별도 감사하고 다시 승인받는다.

## 2026-08-20 실제 배포 기록

- 코드 기준: PR #15, PR #16 병합 완료. 최종 merge SHA `e5100643f67500cc79dd9f7a7df03a69f0ff8078`.
- Worker: Cloud Build `ab30f3de-c85f-467a-b081-6a315d6afb14`, digest `sha256:8663f9d93c85b6a06f1658c289fc21450d44c5b077d12932e02c8256e3958501`. image Service와 video Job이 같은 digest·worker identity를 사용한다.
- Backend: 신규 media Function 5개와 변경 cleanup Function 3개 `ACTIVE`, scheduler 자동 실행 HTTP 200, queue 2개 `RUNNING`, composite index 7개 `READY`, TTL 2개 `ACTIVE`. 신규 media 계층의 배포 후 ERROR는 0건이었다.
- Socket: image `sha256:55dddf2265c93f67ace2cb2be6b3b87df5daaad3c84f2251fc9218bb8df9b5a9`의 revision `outpick-socket-p73-prod-0820`을 traffic 100%로 전환했다. candidate/live `/readyz` 200, Production 앱 인증 handshake 101, 전환 이후 ERROR 0건을 확인했다. rollback revision은 `outpick-socket-p6-log-min-0818`이다.
- iOS: 정확한 SHA의 `Production-Release` iPhone arm64 build는 성공했다. 개인 개발팀의 Production App Attest entitlement 제한 때문에 Release 설치는 불가했고, 같은 Production 스킴의 `Production-Debug`를 개인 개발 서명으로 iPhone 14에 설치·실행해 스모크했다.
- E2E: 사용자 단건 JPEG와 영상이 앱에서 최종 전송 완료됐다. 운영 로그에서 JPEG image Service HTTP 200, video Job `exit(0)`, dispatcher·worker-completion 2xx와 전체 관련 ERROR 0건을 확인했다. QA Firestore/Storage 식별자는 서비스 계정의 broad 조회를 사용하지 않고 사용자 완료 UI와 식별자 비노출 로그로 판정했다.
