# Chat UGC Safety And Room Moderation Progress

## 현재 상태

- Phase 0 exact contract 고정 완료.
- Phase 1 moderation principal과 account capability 구현·자동 검증·Development rollout 완료.
- Phase 2 신고·관리자 처리 서버 API, Firestore deny/index/TTL, thin iOS 신고 contract 구현, Production backend rollout과 인증된 관리자/비관리자 callable smoke 완료.
- Phase 3 서버 권위 메시지 삭제·방 종료 lifecycle, 활성 Rooms query, 계정 capability v2와 Storage reservation 보정의 Production rollout·실제 앱 QA 완료.
- Phase 4 전역 차단 단방향 visibility·push·로컬 admission 구현, 자동 검증, Production Functions·Socket rollout과 Production 두 계정 핵심·앱 종료 혼합 unread QA를 완료해 종료 처리했다. 실제 기기 background FCM/APNs는 Apple Developer Program 가입 후 출시 전 외부 gate로 분리했다.
- Phase 5는 2026-08-12 로컬 구현·자동 검증과 Production rollout을 완료했다. room ban은 active room read를 유지하고 membership·write만 차단하며, 영구 정지는 전체 room membership을 제거한다. owner 승계는 일반 채팅을 잠그지 않는 durable account sweep + 방별 transaction으로 수렴한다. 운영 감사 결과 별도 데이터 migration은 필요하지 않았다.
- Phase 6은 2026-08-18 완료 처리했다. 로컬 구현·자동 검증, Development rollout·사용자 QA, Production backend rollout과 최종 리뷰를 마쳤고 PR #14 merge commit `4d69f4c85646b5db1977020842a2efbdbfba7169`가 `main`에 반영됐다. 자동 텍스트 필터는 제외하고 신고·차단·방 운영·관리자 사후 제재를 유지한다. Socket 단일 인스턴스 메모리 limiter, 댓글·답글 Firestore 공유 minute bucket·멱등 UUID, 신규 메시지 `senderEmail` 전면 제거, 원문 로그 최소화와 입력 상한 차단을 구현했다. 길이 counter·제한 임박 경고는 사용자 결정으로 제거했다. TestFlight/App Store 업로드는 별도 출시 단계다.
- Phase 7.3은 이미지·영상 모두 attachment당 단일 V4 signed PUT을 쓰는 foreground 전송으로 다시 단순화했다. 네트워크 단절·앱 종료·방 이탈은 로컬 실패로 처리하고 보호된 source에서 재시도/삭제를 제공하며 전송 중 취소 UI·background session·영상 parts/Compose를 제거했다. iOS/Socket/Functions/worker 구현·자동 검증, Development E2E와 이후 승인된 Production backend rollout을 완료했다. 실기기 JPEG ready·렌더링 E2E와 warm 처리 2.56초를 확인했다. 아래 조각/resumable E2E 절은 교체 전 이력이며 최신 Production 세부 상태는 `HANDOFF.md`를 따른다.
- Phase 7.4A는 2026-08-21 최신 evidence-first 계약의 로컬 순수 구현과 자동 검증을 완료했다. 텍스트·이미지 묶음 전체·동영상 전체 evidence가 `available`이 된 뒤에만 `accepted` 신고와 canonical incident/reporter/aggregate·queue·visibility를 확정하고, 준비 중 `processing`과 확정 `failed`는 신고 집계에 포함하지 않는다. versioned canonical tuple ID, 최초 revision 0과 terminal reopen, 일반 단일 `holding`·같은 메시지 고유 2명 `reviewRequired`·긴급 단일 `urgent`, 긴급 2명 또는 전체 3명/24시간 전역 비노출, 작성자 `메시지 3개 + 신고자 2명/7일`, retention·appeal/legal hold를 순수 함수로 고정했다. Functions 전체 226/226, build, lint 오류 0과 계약 JSON/diff 검증을 통과했으며 기존 non-null assertion 경고 17개만 남았다. 다음은 Phase 7.4B이며 외부 리소스·배포는 수행하지 않았다.
- Phase 7.4B는 2026-08-24 로컬 구현을 완료했다. `moderationMessageReportRequests/{requestID}`를 revision-independent transport receipt로 분리해 관리자 종결 뒤 같은 UUID의 지연 retry가 새 revision을 만들지 않으며, 새 UUID만 새 심사 회차를 연다. 동일 UUID replay는 무료이고 이전에 보지 못한 새 UUID receipt는 preparation 재사용·alreadyReported·messageAlreadyDeleted 결과여도 user/room 요청과 공유하는 1분 10회 transport limiter를 소비한다. text/lookbook 즉시 accepted, ready media processing preparation/bundle/copy job, available bundle 30건 단위 draining, reporter dedupe·작성자 aggregate·24시간 visibility, report/delete guard와 public cleanup `awaitingEvidence`를 transaction으로 연결했다. 최종 리뷰에서 추가 UUID receipt 전체를 무제한 drain하던 transaction 크기 위험을 최초 receipt+조회 시 개별 수렴으로 제한했고, partial cleanup 전 실패 재시작과 preparation/bundle/copy job generation 불일치를 동일 terminal generation 검증·원자 `+1` 재시작으로 보정했다. Functions 228/228, lint 오류 0, Rules 45/45와 transaction 35/35를 통과했으며 media drain·generation fence와 신고/삭제 양쪽 순서도 에뮬레이터로 확인했다. root callable export·Rules/index·Storage copy worker·iOS·Development/Production 배포는 하지 않았다.
- Development `outpick-test`에 Secret v1, Google 계정 backfill, Functions·Rules·Storage·Socket을 반영했다.
- Production `outpick-664ae`에는 Phase 1~5 승인 범위의 Secret·moderation 데이터·Functions·Firestore/Storage Rules·indexes·Socket을 반영했다.
- Development Google·Kakao 재로그인·탈퇴·재가입과 제한 안내 root의 수동 QA를 완료했다.
- Phase 2 전에 Phase 1-P Production readiness를 진행하기로 방향을 정했고, 내부 active smoke 한정 HMAC 정책과 Kakao Admin API 검증 migration 방식은 사용자 승인을 받았다.
- Phase 1-P migration helper와 CLI Production gate 구현·자동 검증, Production Auth dry-run, HMAC Secret 생성, bootstrap·backfill·영향 Function 15개와 Firestore·Storage Rules 배포를 완료했다. Socket high 취약점 패치와 단일 최소 권한 runtime role/identity 검증 후 r3 revision을 Production 100%로 전환했다. Sign in with Apple은 별도 후속 작업으로 기록했다.

## Phase 6 현재 규모 최종 설계 — 2026-08-18

- 욕설·혐오·위협·금칙어·광고·링크·동일 문장과 공백/기호/Unicode 우회를 모든 메시지·댓글·답글에서 자동 판정하지 않는다. 문맥 없는 차단의 오탐과 표현 제한을 피하고 사용자의 신고·차단, 방 생성자의 내보내기/재입장 제한과 플랫폼 관리자의 사후 검토·제재를 사용한다.
- 콘텐츠 의미와 무관한 타입·빈 값·권한·최대 길이를 유지한다. 채팅/룩북 공유는 UTF-8 4,000 bytes, 댓글·답글은 1,000자이며 앱은 counter 없이 상한을 넘는 입력을 막고 서버 거부 뒤 입력을 보존한다.
- Socket는 `max-instances=1`과 process memory limiter를 유지한다. text 12/2초, lookbook 6/2초, image/video preflight·finalize 각 4/2초를 `moderationPrincipalID + roomID + messageKind`로 적용하며 principal 누락은 UID fallback 없이 fail closed한다.
- 같은 messageID retry는 짧은 bucket에서 quota를 다시 소비하지 않고 기존 Firestore transaction이 최종 멱등성을 보장한다. bucket lifecycle은 60초 idle TTL·30초 sweep·50,000 cap으로 고정했고 deploy/restart 초기화는 현재 규모에서 수용한다.
- 댓글·답글은 Functions 다중 인스턴스 가능성을 고려해 principal 전역 합산 20/분의 server-only Firestore bucket을 사용한다. 동일 clientRequestID는 quota와 UGC를 중복 생성하지 않고 counter는 내용 없이 2일 TTL로 정리한다.
- 신규 text/lookbook/media 메시지부터 Firestore·Socket·FCM·iOS model·GRDB의 `senderEmail` 저장·전송을 모두 중단한다. 구현 전 active principal과 message 데이터를 읽기 전용 감사하고 사실상 비어 있으면 migration을 만들지 않는다.
- Socket success/invalid/exception log의 메시지·답장 원문, email, nickname/avatar와 전체 payload를 제거하고 최소 structured metadata만 남긴다. 과거 내부 QA 로그는 삭제하지 않고 기존 retention으로 자연 만료시킨다.
- Redis/Memorystore는 도입하지 않는다. 다중 Socket 인스턴스, 단일 인스턴스 연결/CPU/메모리/latency 한계 또는 실제 프로세스 간 우회가 관측되면 Socket.IO adapter/PubSub와 공유 limiter를 설계한다.
- Phase 7.4 최신 관리자 조회는 일반 단일 `holding`, 같은 메시지 고유 2명 `reviewRequired`, 기한 경과 holding 직접 조회, 같은 작성자 서로 다른 메시지 3개 + 전체 고유 신고자 2명/7일, 긴급 단일 `urgent`로 설계했다. 별도 queue projection과 기한 승격 scheduler는 만들지 않는다. 최근 90일 관리자 확정 경고는 참고값이며 신고 횟수만으로 자동 제재하지 않는다.
- 2026-08-18 추가 확정으로 텍스트·이미지·동영상 모두 외부 의미 판정 provider로 보내지 않고 신고·차단·관리자 사후 검수 모델을 사용한다. Phase 7 전용 Cloud Run은 quarantine 미디어의 기술 검증·metadata 제거·정규화만 담당한다.
- 댓글·답글 길이는 기존 Functions 동작과 맞춘 trim 이후 UTF-16 code unit 1,000으로 고정하고 iOS도 `utf16.count`를 사용한다. 길이 counter나 제한 임박 경고는 표시하지 않는다.
- 댓글·답글 `clientRequestID`는 전송 탭에서 생성해 네트워크 retry 동안 유지하고 입력 수정·취소·성공 후 새 작성 때 교체한다. rate limit은 입력을 보존하고 자동 재전송 없이 `retryAt` 이후 사용자 직접 재전송으로 처리한다.
- Apple App Review Guidelines 1.2는 UGC 필터 방법을 요구하므로 자동 텍스트 필터가 없는 모델의 승인 여부는 **확실하지 않음**이다. 신고·차단·방 운영·관리자 적시 대응·고객지원 연락처를 App Review Notes에 선제 설명하고 심사 피드백이 있으면 필터 도입을 다시 논의한다.
- 관리자 웹은 후속 task지만 외부 출시 전에는 Phase 2 관리자 API 또는 제한된 운영 도구로 실제 신고를 확인·처리할 담당자와 긴급 24시간/일반 72시간 내부 경고 경로가 필요하다.
- 읽기 전용 감사 결과 Development active account 0명·message 0건, Production active account 2명·유효하지 않은 principal 0명·message 0건이었다. 기존 `senderEmail` message도 양 환경 0건이므로 별도 데이터 migration은 만들지 않았다.
- Cloud Run 읽기 전용 감사에서 Development `outpick-socket-development`와 Production `outpick-socket` 모두 `maxScale=1`, concurrency 80, timeout 3,600초를 유지해 process-memory limiter 전제가 충족됐다.
- 로컬 검증은 Socket check·85/85, Functions 197/197와 lint/build, Firestore·Storage Rules 41/41, transaction 29/29, iOS 관련 6개 suite의 고유 테스트 26개와 Development build-for-testing, JSON parse·diff whitespace 검증을 통과했다. 기존 Swift actor isolation과 linker search path 경고는 남아 있으나 Phase 6 컴파일·테스트 실패는 없다.
- Phase 6 Development QA와 Production backend rollout은 아래 기록대로 완료했다. 운영 UGC 데이터 migration은 필요하지 않았고 Production iOS binary/TestFlight/App Store 배포는 수행하지 않았다.

## Phase 6 Development rollout — 2026-08-18

- `createComment`, `createReply` 두 callable만 `outpick-test`에 exact target으로 배포했다. 둘 다 asia-northeast3 Node.js 24 `ACTIVE`이며 올바른 무인증 callable envelope를 HTTP 401 `UNAUTHENTICATED`로 거부했다.
- Firestore 원격 감사에서 로컬 manifest 대비 Development 누락 composite 10개·field override 12개와 원격 전용 composite 2개를 확인했다. Phase 6 외 변경과 원격 index 삭제를 피하기 위해 전체 indexes 배포를 중단하고 `moderationCommentWriteRateLimitBuckets.expiresAt` TTL만 exact command로 활성화했다. operation은 `SUCCESSFUL`, TTL은 `ACTIVE`다.
- Firestore Rules는 compile 후 Development에 release했다. rate bucket client read/write deny가 포함되며 전체 emulator Rules 41/41·transaction 29/29를 배포 근거로 사용한다.
- Socket Cloud Build `4a21d0c8-1bcf-4e30-98b7-2ba7a66319fc`, digest `sha256:4e2c78775ad7d066e29bf0a87abbc463e49074941e3dc8982f281a06d96870d2`로 revision `outpick-socket-development-00004-rud`를 0% candidate 배포했다. Ready/Active/ContainerHealthy, tagged readiness 200, runtime identity·Development bucket·maxScale 1·concurrency 80·timeout 3,600초와 ERROR 0건을 확인한 뒤 traffic 100%로 전환했다. 이전 `00002-hal`은 0% rollback revision으로 보존한다.
- 전환 후 canonical `/readyz`가 200을 반환했고 Socket ERROR는 0건이다. Functions lint는 기존 non-null assertion warning 17개·오류 0, Functions 197/197과 Socket check·85/85가 재통과했다.
- 첫 사용자 QA에서 방 생성이 Firestore `PERMISSION_DENIED`로 실패했다. Development `getMyModerationState`가 2026-08-07 구버전이라 새 Kakao 계정의 `moderationAccounts/{uid}`에 Rules가 요구하는 `accountStatus` projection을 쓰지 않은 것이 직접 원인이었다. 최신 소스는 이미 해당 projection을 쓰므로 코드 변경 없이 `getMyModerationState`만 exact target으로 Development에 재배포했다. Node.js 24 `ACTIVE`, updateTime `2026-08-18T08:02:08Z`, 배포 후 ERROR 0이며 앱 재실행 bootstrap으로 기존 누락 문서를 자동 보정한다.
- 방 생성 재QA는 성공했으나 오픈채팅 목록이 비어 있었다. 방·member·joinedRooms 문서는 모두 정상이고, 앱의 `Rooms where isClosed == false, lifecycleStatus == active orderBy lastMessageAt desc` 쿼리를 원격에서 재현해 복합 인덱스 누락 `FAILED_PRECONDITION`을 확인했다. 전체 manifest는 계속 배포하지 않고 해당 composite `CICAgOi3z5wK` 하나만 Development에 생성했으며 operation은 `SUCCESSFUL`, index는 `READY`다. 동일 쿼리 재검증에서 생성 방 `TR-1` 1건을 정상 반환했다.
- 사용자 수동 QA의 나머지 항목과 Codex의 Simulator 경계값 QA를 합쳐 Phase 6 Development QA를 완료했다. 당시 채팅 3,200/4,000 bytes와 4,001번째 차단, 댓글·답글 각 800/1,000 UTF-16과 1,001번째 차단을 실제 UI에서 확인했다. 실패·재시도는 iOS 관련 14/14, Functions 계약 5/5, Firestore Rules 41/41·transaction 29/29의 동일 UUID 동시 3회 단건 수렴으로 검증했고 긴 QA 댓글·답글 원격 잔존은 0건이다. 이후 사용자 결정으로 80% counter만 제거하고 상한 차단은 유지했으며 관련 iOS 14/14와 Development·Production 빌드를 재통과했다.

## Phase 6 Production rollout — 2026-08-18

- 사전 감사에서 Production active account 2명은 모두 유효한 moderation principal을 가졌고 message·`senderEmail` 필드·기존 댓글 rate bucket은 0건이었다. 따라서 데이터 migration이나 기존 UGC 수정은 수행하지 않았다.
- `createComment`, `createReply`만 exact target으로 배포했으며 둘 다 asia-northeast3 Node.js 24 `ACTIVE`다. 배포 이후 두 service의 ERROR 로그는 0건이다.
- `moderationCommentWriteRateLimitBuckets.expiresAt` TTL 하나만 exact command로 활성화해 `ACTIVE`를 확인했다. Production composite index 44개는 로컬과 이미 일치해 index 배포는 수행하지 않았다.
- Firestore Rules는 전체 emulator Rules 41/41·transaction 29/29 통과를 근거로 compile 후 Production에 release했다. rate bucket client read/write deny를 포함하며 Storage Rules는 변경하지 않았다.
- 최초 Socket Cloud Build `a356d803-263b-4820-8e48-2f9b1b9c092e`로 rate-limit 후보를 검증했다. 최종 리뷰에서 성공 로그의 `senderUID`와 stale 80% 경고 계약을 제거한 뒤 Cloud Build `de071fbc-21f9-4f9f-81d4-87e8d94ca292`, digest `sha256:c558c3b383185a00d395c660344d33ea29d37de23a243fd401e4e0531405022c`로 revision `outpick-socket-p6-log-min-0818`을 다시 0% 후보 배포했다. maxScale 1·concurrency 80·timeout 3,600초·기존 runtime identity를 보존했고 Ready/ContainerHealthy, tagged readiness 200, ERROR 0을 확인한 뒤 traffic 100%로 전환했다. 직전 `outpick-socket-p6-text-rate-0818`은 0% rollback revision으로 보존한다.
- 전환 후 canonical `/readyz` 200, 새 Socket revision과 댓글 Functions ERROR 0을 확인했다. 최종 리뷰에서 실패 뒤 초안을 수정했다가 원문으로 되돌릴 때 이전 UUID를 재사용할 수 있는 경계와 요청 중 수정한 새 초안이 성공 응답으로 지워질 수 있는 경계를 보정했다. 길이 counter 제거와 이 보정 후 iOS 관련 14/14와 `OutPick-Production` Production-Release generic Simulator build도 성공했다. 기존 Swift actor isolation·deprecated API 경고는 남아 있으나 Phase 6 오류는 없다.
- Phase 6 backend와 앱 소스 작업은 완료했다. 외부 출시 전 App Review Notes와 실제 신고 대응 운영 경로 준비는 별도 출시 gate로 유지한다.

## Phase 7 세부 설계 확정 — 2026-08-18

- `reservation → quarantine upload → technical validation/metadata removal → ready`와 전용 Cloud Run worker를 확정했다. ready 전 message/seq/read/broadcast/push/preview는 없으며 외부 유해성 의미 판정 API는 사용하지 않는다.
- 이미지 선택은 무제한, 메시지당 최대 30장으로 분할한다. 정규화 후 이미지당 15 MiB, 메시지 합산 150 MiB, 긴 변 4096px이다. 사용자는 JPEG·HEIC·PNG·애니메이션 GIF를 선택할 수 있으며 iOS가 정적 HEIC/HEIF만 JPEG로 바꿔 업로드하고 서버 raw HEIC/HEIF는 거부한다. 동영상은 메시지당 1개·350 MiB이고 길이 제한은 두지 않는다.
- 2026-08-20 최신 결정으로 attachment 선택과 동영상 timestamp를 폐기하고 이미지 묶음 전체 또는 동영상 전체를 메시지 단위 evidence로 복사한다. Evidence 원본은 클라이언트에 공개하지 않으며 활성 플랫폼 관리자가 서버 인증 뒤 특정 객체만 제한적으로 조회한다. 실제 전달 방식은 관리자 웹 구현 시 재검토한다.
- 신고 직후 자동 개인 숨김은 폐기했다. 일반 단일 `holding`·같은 메시지 고유 2명 `reviewRequired`·기한 경과 holding 직접 조회·작성자 서로 다른 메시지 3개 + 전체 고유 신고자 2명/7일, 긴급 단일 `urgent`, 긴급 2명 또는 전체 3명의 24시간 전역 threshold, 같은 seq 검토 tombstone과 기각 복원/no-unread, 위반 삭제 tombstone을 최신 계약으로 확정했다.
- 신고/삭제는 first transaction commit wins다. evidence는 기각·삭제만·경고만이면 즉시 비동기 삭제하고 계정 제재 근거면 30일 이의제기 기간을 적용한다. 실패한 로컬 outbox는 7일 뒤 삭제한다.
- 이 갱신은 문서 설계만 수행했다. Phase 7 코드·rules·indexes·배포·테스트는 사용자 구현 승인 전 변경하지 않는다. GIF의 정확한 frame/decode/memory/CPU 상한은 지원 철회 없이 구현 가능성 검증에서 고정한다.

## Phase 7 구현 계획 작성 — 2026-08-18

- `phase-7-implementation-plan.md`에 Phase 7.0~7.6의 목표, 의존성, 변경 파일 후보, API·데이터·IAM, 완료 기준, 자동 테스트·수동 QA와 rollback 순서를 작성했다.
- 길이 제한 없는 동영상은 Cloud Tasks HTTP target의 30분 상한에 직접 묶지 않고 짧은 dispatcher가 전용 Cloud Run Job execution을 시작하는 구조로 계획했다. worker job retry는 0, Firestore attempt/watchdog을 권위 retry로 두어 최대 3회를 중복 계산하지 않는다.
- image/GIF는 sharp/libvips, video probe·metadata 제거는 ffprobe/ffmpeg stack으로 확정했다. GIF resource 수치는 Phase 7.0 container fixture에서 측정해 contract에 고정했다.
- 현재 Socket finalize가 즉시 message/seq를 만들고, iOS 신고 action이 stub이며, `Attachment`에 stable ID가 없는 실제 코드 경계를 계획에 반영했다.
- 구현 첫 단계는 Phase 7.0 fixture/worker scaffold이며 사용자 승인으로 완료했다. Phase 7.1 이후와 배포는 아직 승인되지 않았다.

## Phase 7.0 feasibility 구현 완료 — 2026-08-18

- 사용자 승인으로 `tools/chat-media-processing-worker/` 독립 Node.js/TypeScript worker scaffold, Dockerfile, 이미지·영상 processor, 합성 fixture, runtime verification과 resource benchmark 진입점을 추가했다. Firebase·Socket·iOS·Rules·운영 환경은 변경하지 않았다.
- sharp 0.34.5의 high advisory를 확인해 Node.js 24 호환 수정 버전 0.35.3으로 고정했고 production dependency audit은 취약점 0건이다.
- build는 성공했다. JPEG metadata 제거, alpha PNG, animated GIF frame 보존, MIME mismatch, 손상 이미지, GIF resource guard와 video probe를 포함한 자동 테스트 12/12가 통과했다.
- 실제 HEVC HEIC 합성 fixture는 prebuilt sharp/libvips에 HEVC decoder가 없어 실패했다. 사용자 결정으로 iOS가 정적 HEIC/HEIF를 고품질 JPEG로 정규화한 뒤 업로드하고 서버 raw HEIC/HEIF는 `unsupportedMedia`로 거부하도록 계약과 테스트를 변경했다. custom libvips/HEVC decoder는 도입하지 않는다.
- HEIC 계약 보정 후 번들 Node.js 24.19.0에서 build와 12/12가 통과했다. 실제 201-frame GIF 선제 거부, 1시간 H.264/AAC MP4 stream-copy, 위치·제목 metadata와 subtitle track 제거를 포함한다. 개발 전용 정적 ffmpeg/ffprobe를 사용했고 production dependency audit은 취약점 0건이다.
- runtime verification은 JPEG·PNG·2-frame GIF 정규화, raw HEIC transport 거부와 1시간 영상 metadata 제거를 통과했다.
- 로컬 benchmark는 4096x4096 JPEG 30장 10.537초, 190-frame 1024x512 GIF 99,614,720 decoded pixel 3.750초, process peak RSS 402,560 KiB(약 393 MiB)였다.
- 사용자 승인으로 Development Cloud Build `f79af4cd-7167-475d-882d-16815244247c`에서 최초 Linux 검증을 통과했다. 이어 `c57a715a-2948-45ea-b464-21437cf474c7`에서 verification target과 최종 runtime target을 모두 빌드하고 최종 image 내부 runtime verification까지 통과했다. registry push, Cloud Run 배포와 traffic/Firebase mutation은 수행하지 않았다.
- 최종 Linux runtime은 Node.js 24.19.0, sharp 0.35.3, libvips 8.18.3, ffmpeg/ffprobe 5.1.9다. 12/12와 JPEG·PNG·GIF, raw HEIC 거부, 1시간 video remux·metadata/부가 track 제거가 통과했다.
- Linux benchmark는 JPEG 30장 32.992초, 약 100M decoded-pixel GIF 9.538초, peak RSS 343,756 KiB(약 336 MiB)였다. static 64M pixel, GIF 200 frame·frame당 16,777,216 pixel·총 100M pixel, 이미지당 60초, video remux 10분과 Cloud Run 2 vCPU·1 GiB·task 내 순차 처리를 최종 계약으로 확정했다.

## Phase 7.1 저장·처리량 구조 추가 확정 — 2026-08-19

- 환경별 quarantine·일반 media·moderation evidence의 3개 bucket 경계를 확정했다. quarantine은 `asia-northeast3` Standard, soft delete/versioning off, 1일 lifecycle backstop이며 ready/canceled/final failed/expired 확정 즉시 source를 영구 삭제한다. 일반 media에는 `display/thumbnail`, evidence에는 신고된 메시지의 정규화 `display` 전체를 저장한다.
- reservation과 processing이 1:1이므로 별도 `chatMediaProcessingJobs`를 제거하고 `MediaUploads`가 attempt·lease·execution·retry·normalized manifest를 함께 소유한다. terminal 문서는 outbox 멱등 재실행을 위해 7일 후 TTL 삭제한다.
- image/video queue·Firestore 고정 slot을 분리한다. Development 각 1, Production 초기 image 4/video 1이다. 이미지는 private Cloud Run Service(min 0, concurrency 1), 영상은 task count/parallelism 1의 Cloud Run Job이며 둘 다 2 vCPU·1 GiB, retry 0을 사용한다.
- principal별 active 업로드는 이미지 메시지 2개·영상 1개로 확정했다. 24시간 byte hard cap은 초기 설정하지 않고 실제 사용량·abuse·비용 지표로 별도 결정한다.
- 추가 논의에서 iOS가 Photos/카메라 원본 byte 대신 업로드 전용 source를 만들어 quarantine Storage에 직접 올리기로 확정했다. 정적 이미지는 orientation bake·4096px·sRGB·metadata 제거 후 HEIC/HEIF·JPEG는 JPEG quality 0.92, PNG는 초기 투명/비투명 모두 PNG를 유지한다. GIF animation도 보존한다. 서버 worker의 재검증과 최종 display/thumbnail 생성은 유지한다.
- 동영상은 iOS가 720p H.264/AAC MP4 source 하나를 올리고 local pending thumbnail은 업로드하지 않는다. worker가 `min(1초, duration/2)`에서 512px JPEG thumbnail을 만들며 추출 실패는 `invalidMedia`로 수렴한다.
- 현재 계약은 upload reservation/signed target 24시간·finalize 뒤 processing deadline 6시간이다. ready/canceled/final failed/expired에는 quarantine source·part와 lease/slot을 즉시 정리하고, 1일 bucket lifecycle은 crash·IAM/네트워크·cleanup 버그로 남은 객체의 안전망으로만 사용한다. terminal `MediaUploads`는 byte가 아니라 동일 `clientMutationID` 재시도 결과를 위해 최소 상태를 7일 보존한다.
- principal image 2/video 1은 `uploading|queued|processing` 동시 작업 상한이다. image는 동시에 최대 60장을 점유할 수 있지만 terminal마다 slot을 반환해 local queue의 다음 묶음을 시작하므로 누적 전송량은 제한하지 않는다. 목적은 한 사용자의 queue 독점, 앱 버그와 악의적 업로드에 따른 처리·비용 폭주 방지다.
- 이번 확정 턴은 문서·계약 변경만 수행했다. Phase 7.1 로컬 코드 구현 승인은 유효하지만 bucket/IAM/queue/Job 생성과 Development·Production mutation은 별도 승인 전 수행하지 않는다.

## Phase 7.1 로컬 구현 완료 — 2026-08-19

- 기존 v1 public original/thumbnail 경로는 Phase 7.3 iOS cutover 전까지 보존하고 `contractVersion: 2`에만 attachment당 Quarantine source 하나를 예약하는 preflight/finalize/status/cancel API를 추가했다. v2 `clientMutationID`는 UUID이며 finalize는 실제 Storage generation·size·MIME·전체 manifest를 대조한 뒤 같은 `MediaUploads`를 `queued`로 전환할 뿐 message·seq·emit·push를 만들지 않는다.
- canonical principal별 server-only 고정 slot transaction으로 image message 2개·video 1개의 active backpressure와 같은 UUID replay 멱등성을 구현했다. cancel은 terminal을 먼저 기록하고 principal/execution lease와 Quarantine source를 정리하며 cleanup 실패를 문서에 남긴다.
- queued Firestore trigger → 종류별 결정적 Cloud Task → private dispatcher → 환경별 고정 Firestore execution slot → Cloud Run Job execution 흐름과 5분 watchdog을 추가했다. upload reservation 24시간, processing deadline 6시간, execution lease, 최대 자동 시도 3회, terminal 7일 TTL과 Quarantine cleanup이 한 원장에 수렴한다.
- worker는 로컬 CLI를 유지하면서 Cloud Job env mode를 추가했다. 전용 서비스 계정 ADC로 Quarantine source를 내려받아 attachment를 순차 처리하고 deterministic ready `display/thumbnail`을 업로드한 뒤 같은 processing lease에 technical result와 normalized manifest를 기록한다. 성공 message/seq transaction·source cleanup·slot 반환은 Phase 7.2 trigger가 담당하므로 현재 staging 객체는 공개되지 않는다.
- 전용 `storage.chat-media-quarantine.rules`는 active 예약 owner의 exact attachment source 최초 create만 허용하고 read/list/update/delete, 타인·미예약·MIME/size 위반·terminal/expired 업로드를 거부한다. Firestore Rules는 원장과 두 slot collection의 client access를 명시적으로 거부하고 indexes는 watchdog collection-group query와 `MediaUploads.expiresAt` TTL을 포함한다.
- 로컬 검증은 Functions 204/204, Socket 90/90, worker 15/15, Firestore·Storage Rules 44/44와 transaction 29/29를 통과했다. Functions lint/build와 Socket check도 통과했고 Functions lint에는 기존 moderation non-null assertion warning 17개만 남았다. worker의 `firebase-admin` 하위 UUID advisory는 `uuid 11.1.1` override로 제거해 production dependency audit 0건을 확인했다.
- bucket, lifecycle, Firebase Storage target, service account/IAM, Cloud Tasks queue, Cloud Run Job/Functions/Socket 배포와 실제 클라우드 smoke는 수행하지 않았다. 이 외부 변경은 별도 사용자 승인 대상이다.

## Phase 7.2 ready transaction·delivery·성공 cleanup 로컬 구현 — 2026-08-19

- worker normalized manifest 최초 기록 trigger가 현재 processing lease, exact ready path/generation/size/MIME, attachment IDs, active room membership/ban과 message/delivery 충돌을 다시 확인한다. 성공 시 기존 Socket text와 같은 `Rooms.seq` 문서에서 message, media index, room preview, delivery job, upload ready, execution/principal slot 반환을 한 transaction으로 커밋한다.
- v2 message 표시 snapshot은 ready 시점 `userPublicProfiles`에서 가져오고 미디어 본문은 빈 문자열, sentAt은 ready 시각으로 고정했다. 클라이언트 제출 nickname/avatar를 권위 값으로 저장하지 않는다.
- Socket delivery watcher는 server-only job을 60초 lease로 claim해 기존 media event와 FCM을 순서대로 수행하고 completed로 전환한다. 실패·watcher 재시작은 retryPending/만료 lease 재claim으로 수렴하며 전달은 messageID/seq 기반 at-least-once다. ready 상태는 발신자의 연결 socket에도 `chat:mediaProcessingStatusChanged`로 전달한다.
- 일반 media Storage Rules는 대응 visible v2 message와 exact `readyAttachmentIDs`가 존재할 때만 새 ready 경로를 읽게 했다. cancel/failed/expired 또는 충돌 결과의 orphan ready 객체와 모든 terminal Quarantine source는 즉시 삭제하며, 15분 cleanup scheduler와 bucket lifecycle이 실패 잔존을 재정리한다.
- 로컬 검증은 Functions 207/207, Socket 93/93, Firestore·Storage Rules 45/45와 transaction 29/29를 통과했다. Functions build/lint와 Socket check도 통과했고 Functions lint에는 기존 moderation non-null assertion warning 17개만 남았다.
- Functions/Socket/Rules/index의 로컬 구현과 테스트만 변경했다. bucket/IAM/queue/Job 생성, Development·Production 배포와 실제 realtime/FCM smoke는 수행하지 않았다.

## Phase 7.3 Development 실제 media E2E — 2026-08-19

> 이 절은 resumable upload 기반 이전 구현의 이력이다. 새 signed PUT·16 MiB 조각 Development backend E2E는 아래 별도 절에서 완료했다.

- `OutPick-Development`의 실제 로그인 세션과 Photos picker로 이미지 1장과 29초 동영상 1개를 전송했다. 두 건 모두 iOS preflight·resumable direct upload·finalize, Firestore trigger, Cloud Task, private dispatcher, 전용 image/video Cloud Run Job, ready transaction과 Socket delivery job을 거쳐 각각 `seq=1`, `seq=2`의 visible 메시지로 수렴했다.
- 이미지·동영상 모두 `processingAttempt=1`, `processingStatus=ready`, `cleanupStatus=completed`, failureCode 없음이었다. 일반 media bucket의 `display/thumbnail` 두 객체와 `mediaIndex`가 존재하고 delivery job은 `completed`, Quarantine source는 즉시 삭제된 것을 확인했다. image/video Job은 각각 약 10초에 성공 종료했고 성공 구간의 Cloud Run ERROR는 0건이었다.
- 최초 E2E에서 세 가지 Development IAM/endpoint 누락을 발견해 최소 범위로 보정했다. Socket identity에는 Quarantine bucket 한정 `roles/storage.objectUser`, 두 Eventarc delivery identity에는 각 trigger 서비스 한정 `roles/run.invoker`, task identity에는 dispatcher 서비스 한정 `roles/run.invoker`를 부여했다. Cloud Tasks OIDC target/audience는 Gen2 Functions alias가 아니라 실제 dispatcher `run.app` URI로 수정하고 enqueue Function 2개만 재배포했다.
- IAM 실패로 session 생성 전 남은 QA reservation·principal slot 1건은 Quarantine 객체와 session이 없음을 확인한 뒤 삭제·반환했다. 성공한 QA 방과 이미지·동영상 메시지는 Development에서 결과 확인용으로 유지한다. Production에는 어떤 bucket/IAM/Function/Socket/iOS 변경도 반영하지 않았다.
- 실제 background 종료·relaunch/resume, cancel/ready first-commit-wins, JPEG/HEIC/PNG/GIF·31장/상한·장시간 동영상 시나리오는 이번 core E2E 범위에 포함하지 않았다. 자동 테스트 계약은 통과했지만 Production 전 확장 QA 항목으로 남긴다.

## Phase 7.3 signed PUT·video parts 로컬 구현 — 2026-08-19

- 이미지 source는 attachment당 24시간 V4 signed PUT 하나, 영상 source는 16 MiB 이하 최대 22개 조각으로 분리해 각 signed PUT으로 전송한다. 영상 source/result 상한은 350 MiB이고 duration 상한은 없다.
- Socket는 `chat:mediaRefreshUploadTargets`에서 generation·크기·MIME·signed metadata를 대조해 완료/미완료 조각을 서버 권위로 판정한다. `ifGenerationMatch=0`으로 동일 path overwrite를 막고, finalize는 검증된 generation을 고정한 단일 GCS Compose 후 `queued`로 전환한다.
- iOS background `URLSession`은 일반 PUT의 최종 2xx만 처리한다. PUT 응답 유실·412·transport 실패 뒤 서버 reconciliation을 호출해 이미 존재하는 유효 객체는 성공으로 복구하고 미완료 조각만 다시 전송한다. signed URL은 task description에 넣지 않는다.
- worker는 quarantine source를 내려받은 뒤 실제 bytes의 SHA-256을 streaming 계산해 예약 hash와 다르면 정규화 전에 거부한다. Functions terminal/watchdog cleanup은 final source와 모든 part path를 함께 정리한다.
- 로컬 검증은 Socket check·96/96, Functions build·213/213, worker 16/16, Development generic Simulator build를 통과했다. iOS splitter·Outbox·응답 유실 reconciliation 관련 테스트도 통과했다.

## Phase 7.3 signed PUT Development backend E2E — 2026-08-19

- Socket 자기 서비스 계정에 자기 자신 대상 `roles/iam.serviceAccountTokenCreator`를 부여해 24시간 V4 URL 서명을 활성화했다. task identity의 dispatcher 서비스 한정 `roles/run.invoker`도 Functions 재배포 뒤 복원했다. Production IAM은 변경하지 않았다.
- Cloud Build `eb5d6244-ea9c-4dc9-a320-9f086dbfa06f`가 container 내부 16/16, runtime verification과 benchmark를 통과했고 worker digest `sha256:4741213f15d40de2ba8d916203df6f57523c2133fcbd4da6a4d34de687d56a4f`를 Development image/video Job 모두에 고정했다.
- 첫 실제 image signed PUT에서 GCS custom metadata가 `attachmentID`가 아니라 `attachment-id`로 반환되어 reconciliation이 fail closed하는 문제를 발견했다. 서버 metadata reader가 camelCase와 GCS kebab-case를 canonical 비교하도록 보정하고 실제 반환 형태 회귀 테스트를 추가했다.
- 격리형 backend E2E에서 JPEG 276 bytes 단건과 H.264/AAC MP4 31,364,213 bytes 두 조각을 각각 V4 PUT했다. 두 흐름 모두 완료 조각 reconciliation, video generation 고정 단일 Compose, finalize, Cloud Task, dispatcher, Job, ready transaction과 cleanup을 `processingAttempt=1`로 통과했다. message와 display/thumbnail이 생성되고 Quarantine source·모든 part가 삭제됐다.
- image Job은 8.49초, video Job은 10.49초에 `succeededCount=1`로 완료됐다. E2E 전용 Auth·방·문서·Storage 객체와 임시 영상은 검증 직후 제거했다.
- Socket revision `outpick-socket-development-00013-muw`(tag `p73-350m-0819`)는 candidate/canonical readiness 200과 ERROR 0건 확인 후 Development traffic 100%로 전환했다. Production은 변경하지 않았다.
- 이번 E2E는 서버 계약을 격리된 Node client로 검증했다. 실제 iOS background `URLSession` 강제 종료·재실행, 350 MiB 실파일, 장시간 영상, cancel/ready race와 JPEG/HEIC/PNG/GIF·31장 실기기 QA는 Production 전 확장 gate로 남는다.

## Phase 7.3 실기기 JPEG 렌더링·warm latency 보정 — 2026-08-20

- 실제 TR-1 JPEG는 server ready까지 정상 수렴했지만 iOS v2 mapper가 `bucketThumb`/`bucketOriginal`과 `attachmentID`를 누락해 기본 bucket을 조회했고, 전용 ready bucket Rules는 deploy target이 `firebase.json`에 연결되지 않아 403을 반환했다.
- `ChatMessage` mapper가 v2 bucket·attachment·format·animation metadata를 보존하도록 수정하고 `ChatMessageMediaAttachmentMappingTests`로 회귀를 고정했다. 기본 Firebase/Emulator 설정은 유지하고 전용 bucket deploy만 `firebase.chat-media.json`으로 분리했다.
- ready media Rules는 Storage Rules의 Firestore 교차 조회 2문서 한도를 지키기 위해 account capability + visible message만 조회한다. room 종료는 기존 message/content 즉시 cleanup과 재시도 안전망으로 수렴한다. 삭제·신고 비노출·정지 계정 차단은 유지한다.
- 전체 Emulator 검증은 Rules 45/45와 transaction 29/29를 통과했고 `outpick-test-chat-media`에만 새 Rules를 배포했다. Production은 변경하지 않았다.
- 실기기에서 기존 seq 3~6과 신규 seq 7~8 조회의 403이 사라졌다. 첫 요청은 23분 idle 뒤 cold 상태에서 예약 생성→ready 8.85초였고, 연속 warm JPEG는 worker 완료 2.43초·message ready 2.56초·cleanup 2.83초였다. 전송 직후 앱이 background로 이동해도 seq 8 server ready는 정상 완료됐다.

## Phase 7.3 pending UX 무표시 성공·명확한 실패 — 2026-08-20

- client 정규화가 끝나면 로컬 미디어 버블을 즉시 표시하고 `uploading/queued/processing` 동안 진행률 ring·loading·전송 중 문구·취소 액션을 모두 노출하지 않는다. ready 수렴도 같은 버블을 유지하며 성공 UI를 추가하지 않는다.
- `failed/expired`에서만 시간 라벨을 숨기고 같은 위치에 `arrow.clockwise.circle.fill` 재시도와 `trash.circle.fill` 삭제 아이콘을 노출한다. 아이콘은 17pt, 실제 터치 영역은 각각 44×44pt이며 미디어를 가리는 dim/overlay는 제거했다. 재시도는 기존 outbox 계약대로 새 message/upload/client mutation identity를 사용하고, 삭제는 로컬 pending store·outbox·버블을 함께 정리한다.
- 서버 확정 전 활성 `seq <= 0` 로컬 메시지는 일반 long-press 서버 액션을 차단했다. 공용 실패 아이콘은 텍스트 실패에만 유지하고 미디어 실패에서는 숨긴다. 상태 정책·액션 정책 14/14와 `OutPick-Development` Simulator build가 시간 위치 아이콘 리팩토링 뒤 통과했다. 실제 아이콘 위치와 두 액션의 44pt 탭 영역은 실기기 재검증에 남긴다.
- 첫 실기기 재검증에서 즉시 버블이 500px/JPEG quality 0.5 별도 thumbnail을 사용해 서버 512px/quality 75 thumbnail보다 현저히 흐린 문제를 확인했다. pending과 outbox 복원 attachment가 동일한 4096px/quality 0.92 upload source를 가리키도록 바꾸고 `ChatAttachmentImageService`가 렌더링 시 최대 1024px로 ImageIO 다운샘플링하게 했다. 추가 재압축·전체 4096px decode 없이 선명도와 메모리 상한을 함께 확보한다.
- 보정 Development 빌드를 iPhone 14에 설치해 TR-1에서 다시 전송했고, 사용자가 즉시 로컬 버블이 충분히 선명함을 확인했다. 이어 네트워크 단절에서만 실패 액션이 나타나고 재연결·재시도 뒤 액션이 조용히 사라지며 단일 버블로 확정되는 것까지 확인했다. 당시 overlay 액션 배치는 이후 시간 위치 아이콘 구조로 교체했다.
- 실패 메시지를 보존한 앱 재실행에서 같은 날짜 separator가 server window와 복원 outbox 사이에 비연속으로 반복되며 diffable snapshot duplicate identifier `SIGABRT`가 발생했다. 실기기 crash log 3건의 공통 stack이 `ChatViewController.applyInitialWindowSnapshotAndWait` → `appendItemsWithIdentifiers`임을 확인했다. 날짜 separator identity를 `(day, occurrence)`로 바꾸고 기존 window occurrence를 이어받게 해 충돌을 제거했다.
- 과거 날짜 실패 메시지 복원 회귀를 추가했고 관련 window/pending/action 26/26, Development 실기기 build·설치·재실행을 통과했다. 설치 후 프로세스가 유지되고 신규 crash log가 생기지 않음을 확인했으며 TR-1 재진입 최종 육안 확인은 사용자 QA 대상이다.
- 크래시 보정 빌드에서 메시지는 복원되지만 재시도·삭제 아이콘이 사라지는 후속 결함을 확인했다. terminal 실패가 signed URL session을 정상 삭제하는 반면 복원 코드가 session 존재를 선행 `guard`로 요구해 pending failure state 주입을 건너뛴 것이 원인이었다. terminal `.needsUpload/.uploaded/.failed`는 session 없이 local/uploaded retry payload를 실패 상태로 복원하고, 서버 `queued/processing/ready`만 status monitoring을 재개하도록 분리했다.
- outbox/window/pending/action 관련 34/34와 Development 실기기 build를 통과했고 iPhone 14에 설치·실행했다. TR-1 시간 위치 재시도·삭제 아이콘의 최종 육안 확인은 사용자 응답 대기다.
- 사용자가 TR-1에서 재실행 후 아이콘 복원과 기존 점검 항목을 모두 확인했다. 이어 재시도·삭제 모두 오조작 방지 확인창을 추가했다. 재시도는 prominent `이 메시지를 다시 전송할까요?`, 삭제는 destructive `이 실패 메시지를 삭제할까요? 삭제하면 다시 복구할 수 없어요.`를 사용하며 확인 이후에만 기존 동작을 실행한다. 관련 34/34와 Development 실기기 build·설치·실행을 완료했다.

## Phase 7.3 잔여 QA 진행 순서 최신화 — 2026-08-20

- iPhone 14 JPEG 단일 source의 ready·렌더링과 네트워크 단절→로컬 실패→재연결·재시도 성공은 완료 근거로 유지한다.
- 잔여 작업은 `이미지 형식·31장 QA → 영상 및 앱 종료·방 이탈 QA → Phase 7.3 완료 판정 → Phase 7.4 evidence backend 구현 착수` 순서로 진행한다.
- 현재 단계는 이미지 형식·31장 QA다. JPEG·실제 HEIC→JPEG·PNG·animated GIF는 통과했고 실제 31장 30+1 분할은 아직 통과로 판정하지 않는다.
- Phase 7.4는 Phase 7.3 완료 판정 전에는 구현하지 않는다. Production 변경은 exact target별 별도 승인 전 수행하지 않는다.

## Phase 7.3 JPEG·HEIC·PNG 실기기 QA — 2026-08-20

- iPhone 14 Photos picker에서 JPEG·실제 HEIC·PNG를 각각 전송했다. TR-1 `seq 16~18`은 모두 processing attempt 1, `ready`, cleanup `completed`, failure code 없음으로 수렴했다.
- source MIME은 순서대로 `image/jpeg`, `image/jpeg`, `image/png`였다. 실제 HEIC는 계약대로 iOS에서 JPEG source로 변환됐고, PNG는 PNG source와 display를 유지했다. 세 display와 thumbnail은 전용 `outpick-test-chat-media` bucket에 존재한다.
- 세 upload의 Quarantine prefix 잔존은 각각 0건이고 2026-08-20T04:20:00Z 이후 Development chat-media Cloud Run ERROR는 0건이다.
- 31장 30+1 분할 재QA가 남아 있으므로 이미지 형식·31장 QA 전체는 아직 완료 처리하지 않는다.

## Phase 7.3 animated GIF 실기기 실패 진단 — 2026-08-20

- iPhone 14가 QA GIF를 `image/gif`, 4,925 bytes source로 정상 준비했고 reservation·signed PUT·image worker 호출까지 진행했다. upload은 seq 없이 `processingFailed`, cleanup `completed`로 안전하게 종료됐다.
- Development image service 로그의 직접 오류는 `GIF 애니메이션 프레임이 보존되지 않았습니다.`였다. 같은 source를 로컬 worker로 재현한 결과 원본은 빨강 25프레임 + 파랑 25프레임의 총 50프레임·각 40ms·loop 0인데, sharp 기본 GIF 최적화가 동일 연속 프레임을 빨강 1초 + 파랑 1초의 2프레임으로 합쳤다. 시각적 timeline은 같지만 worker의 exact frame-count 검증이 이를 실패로 판정했다.
- sharp 0.35.3 GIF 출력에 `keepDuplicateFrames: true`를 적용하고, 빨강 25 + 파랑 25의 연속 중복 50프레임 fixture에서 frame 수·delay 배열·loop가 입력과 동일한지 검증하는 integration test를 추가했다. 로컬 worker 17/17과 번들 ffmpeg/ffprobe runtime verification이 통과했다.
- Linux Cloud Build `89daa082-3e7b-4e0e-b7b2-b5717b5e19a0` 검증과 runtime image build `d1d238d9-1f96-41ae-bc71-7cf099b20069`가 통과했다. 새 digest `sha256:056d5106036845e4b129ede29307860e6a59f29ed6857681cbf1caa372eeafa2`는 Development image Service revision `outpick-chat-media-image-service-development-00002-ggv`에만 배포해 traffic 100%, Ready, 인증 proxy root 200, 배포 후 ERROR 0건을 확인했다. CPU 2·1 GiB·concurrency 1·timeout 3600초·bucket·service account·orchestrator invoker는 유지됐고 video Job과 Production은 변경하지 않았다.
- 인증 proxy에서 `/healthz`는 Google Frontend 404였지만 같은 상태 handler의 `/`는 `200 {"ok":true}`였다. GIF 실기기 재QA와 31장 QA가 남아 있어 Phase 7.3 완료 판정 및 Phase 7.4 착수는 보류한다.

## Phase 7.3 animated GIF 재전송·표시 진단 — 2026-08-20

- 보정 배포 뒤 iPhone 14 재전송 upload `BEB3FFC5-D0C2-4376-B78C-A5AFBA959E04`는 processing attempt 1, seq 19, `ready`, cleanup `completed`, failure 없음으로 수렴했다. normalized display는 `image/gif` 3,959 bytes, thumbnail은 `image/jpeg` 1,093 bytes다.
- ready display 객체를 직접 검사해 800×800, 50프레임, 전체 delay 40ms, loop 0이 입력과 동일함을 확인했다. GIF transport·worker frame 보존은 통과다.
- 앱 채팅 버블은 `ChatAttachmentImageService`가 `thumbResourcePath`를 우선 로드하고 `ChatImagePreviewCell`이 정적 `UIImage`를 표시하므로 JPEG thumbnail 첫 frame처럼 보인다. 이미지 뷰어도 현재 animated GIF decoder가 없다.
- `readyService.ts`가 확정 message attachment에 `mediaFormat`과 `animated`를 기록하지 않아, iOS `Attachment` 모델에 필드가 있어도 서버 delivery 이후 GIF badge 조건을 판별할 수 없다. 표시 정책은 `정적 thumbnail + GIF badge + 탭한 viewer에서 animation` 또는 `채팅 버블 inline animation` 중 사용자 결정이 필요하다. 성능·메모리 관점 추천은 전자다.
- 따라서 GIF backend QA만 통과했고 앱 animation·GIF 표시가 남아 있다. 이미지 형식·31장 QA 전체, Phase 7.3 완료 판정과 Phase 7.4 착수는 계속 보류한다.

## Phase 7.3 GIF badge·viewer animation 로컬 구현 — 2026-08-20

- 사용자 결정으로 채팅 목록은 정적 JPEG thumbnail을 유지하고 우하단 `GIF` badge를 표시하며, 탭한 viewer에서만 원본 animation을 재생하는 정책을 확정했다. inline 채팅 animation은 스크롤·메모리·배터리 비용 때문에 도입하지 않았다.
- Functions `readyService.ts`가 worker의 검증된 `displayContentType`, `frameCount`, `animated`를 확정 message와 `mediaIndex`의 `mediaFormat`·`animated`에 기록한다. iOS는 `image + gif + animated == true`를 모두 만족할 때만 확정 GIF로 취급한다.
- `ChatImagePreviewCell`은 정적 thumbnail 우하단 `GIF` badge를 표시하고 reuse 때 초기화한다. `SimpleImageViewerVC`는 Kingfisher `AnimatedImageView`의 lazy frame source, frame preload 3, 현재 page 단독 재생을 사용한다. `ChatAttachmentImageService`는 viewer 원본 data를 최대 byte 제한과 45 MiB compressed-data memory cache로 공급한다.
- Functions 전체 test·lint(오류 0, 기존 warning 17)·build, Development generic Simulator build, iOS GIF metadata·viewer 대상 7개 시나리오가 통과했다. worker는 이미 필요한 technical metadata를 기록하므로 추가 변경·재배포가 필요 없다.
- 사용자 승인으로 `onChatMediaWorkerCompleted`만 `outpick-test` Development에 exact 배포했다. Gen2 Function은 `ACTIVE`, 배포 후 severity ERROR는 0건이며 worker/video Job과 Production은 변경하지 않았다. 같은 source로 iPhone 14용 `OutPick-Development`를 빌드해 `GayoonKim.OutPick.dev`로 설치·실행했다. 기존 seq 19 메시지는 배포 전 metadata라 badge 대상이 아니므로 새 GIF 전송 뒤 badge·viewer 수동 QA가 남아 있고, 이 gate 전에는 GIF 표시 항목과 이미지 형식·31장 QA 전체를 완료 처리하지 않는다.
- 새 GIF upload `0B635AEC-8AB9-4C4D-95CE-F5A4D17D6780`은 attempt 1, seq 20, `ready`, cleanup `completed`, failure 없음으로 수렴했다. 확정 message와 `mediaIndex` 모두 `mediaFormat: gif`, `animated: true`를 저장했고 처리 구간 Function·image Service severity ERROR는 0건이었다. 사용자가 iPhone 14에서 정적 thumbnail 우하단 `GIF` badge, 탭한 viewer의 빨강·파랑 animation, 닫은 뒤 정적 thumbnail 복귀를 모두 확인했다. 이로써 GIF transport·frame 보존·metadata·앱 표시 QA는 통과했으며 다음 항목은 실제 31장 30+1 분할 QA다.

## Phase 7.3 31장 첫 실기기 QA·분할 전송 보정 — 2026-08-20

- 첫 31장 전송에서 제거하기로 한 `여러 메시지로 나눠 전송합니다` 안내가 남아 있었고 마지막 1장 버블은 실패했다. backend에는 30장 upload `F64D731A-D5E9-4181-95A1-82BA7FF97A38`만 생성되어 attempt 1, seq 21, `ready`, cleanup `completed`로 수렴했으며 두 번째 1장 reservation은 생성되지 않았다.
- 안내는 `chunks.count > 1` 조건의 잔존 alert가 원인이므로 분할만으로는 아무 문구도 표시하지 않고, 지원 불가·제한 초과 이미지가 실제 제외됐을 때만 제외 안내를 유지하도록 수정했다.
- 첫 보정은 모든 pending 버블·outbox를 먼저 저장하고 reservation·PUT·finalize만 순차 실행했으나 ready monitoring을 병렬 유지해 두 번째 QA에서도 30장 seq 22만 성공하고 마지막 1장은 reservation 전에 실패했다. principal slot 감사 결과 과거 GIF 실패 upload `ED347B6B-63B1-4BFB-8F9B-6F52572117D4`가 `uploading`으로 image slot 0을 점유한 상태에서 30장 묶음이 slot 1을 사용했고, finalize 직후 아직 terminal이 아닌 동안 1장 preflight가 시작되어 가용 slot이 없었다.
- 최종 보정은 모든 pending 버블·outbox 선행 저장 후 앞 chunk가 `ready|failed|canceled|expired` terminal로 slot을 반환할 때까지 다음 chunk를 시작하지 않는다. 또한 server reservation 이후 PUT/reconciliation/finalize가 실패하면 best-effort cancel로 source와 slot을 즉시 정리하고, cancel/ready 경합에서 ready가 이기면 로컬 실패로 바꾸지 않는다.
- slot cleanup·cancel/ready 자동 테스트 2개를 추가했고 `ChatMediaUploadUseCaseTests` 11개, `ChatMediaSelectionChunkerTests` 2개와 Development Simulator test build, iPhone 14 Development build·설치·실행이 통과했다. 새 31장 선택에서 안내 없음, 30장+1장 두 버블 ready·cleanup·순서 보존을 재QA하기 전까지 항목은 미완료다.

## Phase 5 local 구현 — 2026-08-12

- 방 생성자 전용 `removeRoomMember`, `unbanRoomMember`, `listRoomBans` callable을 추가했다. 내보내기는 canonical principal ban, member/joinedRooms 제거와 정확한 memberCount 갱신을 한 transaction에서 처리하고, 목록 API는 room-scoped opaque token과 ban 시점 최소 snapshot만 반환한다.
- Firestore Rules와 Socket admission이 활성 principal ban의 membership 생성·참여자 join·message/media write를 거부하되 활성 방과 메시지 읽기는 유지한다. Socket ban watcher는 대상 principal 연결만 강제 퇴장시키고 `room:membership-removed`를 발행한다.
- 계정 삭제 최종 확정과 영구 정지는 공용 durable membership sweep을 사용한다. owner 방은 joinedAt 오름차순·UID tie-break의 적격 active member에게 transaction으로 승계하고, 후보가 없으면 각각 `closedByOwner`, `closedByModeration` cleanup job으로 수렴한다. 일반 membership도 전부 제거하며 해제 시 자동 복원하지 않는다.
- iOS는 내보내기 이벤트를 받으면 joined state를 제거하고 현재 방을 읽기 전용 non-member로 전환한다. 해당 방 pending outbox·미완료 upload만 취소하며 기존 메시지·FTS·완료 media cache는 유지한다. 방 설정에는 owner 전용 내보내기와 opaque token 기반 ban 목록·해제를 연결했다.
- Functions 190/190과 lint/build, Socket 76/76, Firestore·Storage Rules 41/41, transaction 24/24, Phase 5 관련 iOS 6개 suite와 Development Simulator build가 통과했다. Production 인덱스 원격 감사는 Firebase CLI 인증 만료로 실행하지 못했으며 로컬 JSON·emulator 계약 검증만 완료했다.
- Production Functions·Socket·Rules·indexes 배포, 운영 데이터 migration과 실제 계정/방 mutation은 수행하지 않았다.
- Production rollout 사전 감사에서 `bans.expiresAt` TTL override가 개인정보 보존 기간 승인 전 자동 삭제를 활성화하지 않는 기존 결정과 충돌함을 확인해 배포 대상에서 제외했다. inactive ban의 `expiresAt` 계약은 유지하지만 법률·개인정보 승인 전 Production TTL policy는 만들지 않는다.

## Phase 5 Production rollout — 2026-08-12

- Firebase CLI 재인증 뒤 Production 원격 index를 감사했다. 기존 composite 41개·field override 29개는 로컬 manifest에 모두 보존됐고 삭제 후보는 0개였다. Phase 5 순증분 composite 3개와 `roomOwnershipSuccessionJobs.expiresAt` TTL 1개만 배포했다.
- 신규 index는 bans 목록 `CICAgOi3z5wK`, succession due-job `CICAgLiTsZgK`, owner active-room `CICAgLiKtpMK`이며 모두 `READY`다. succession job TTL은 `ACTIVE`, 개인정보 보존 승인 전 제외한 bans TTL은 Production에 존재하지 않는다.
- Firestore Rules를 compile dry-run 뒤 Production에 release했다. 활성 방·message read는 유지하고 ban 원장 client read/write, banned membership 생성과 참여자 write 우회를 차단한다.
- `removeRoomMember`, `unbanRoomMember`, `listRoomBans`, `onRoomOwnershipSuccessionQueued`, `drainRoomOwnershipSuccessionJobs`, `mutateAccountModeration`, `finalizeExpiredAccountDeletions` 7개만 exact target으로 배포했다. 전부 asia-northeast3 Node.js 24 `ACTIVE`, succession scheduler는 5분·Asia/Seoul `ENABLED`, 배포 직후 ERROR 0이며 신규 callable 3개는 올바른 무인증 envelope를 HTTP 401로 거부했다.
- Socket Cloud Build `21bc669c-10e5-4f5e-85fd-b44e34b11bf6`, digest `sha256:3ed111783e176674719d11f17e0aec0298e41b562208099b46b0bb4512f49868`로 revision `outpick-socket-p5-ban-0812`를 0% candidate 배포했다. Ready/Active/ContainerHealthy, tagged readiness 200, ERROR 0을 확인한 뒤 traffic 100%로 전환했다. 직전 `outpick-socket-p4-block-0811`은 0% rollback revision으로 유지한다.
- Production 사전 데이터 감사는 Rooms 11개가 모두 closed이고 `isClosed`·lifecycle 필드를 보유했으며 active room 0, 기존 bans 0, succession jobs 0이었다. 따라서 schema backfill이나 운영 데이터 migration은 필요하지 않았고 불필요한 QA ban/audit 원장도 생성하지 않았다.
- `OutPick-Production` Production-Release generic Simulator build가 성공했다. 기존 storyboard·Swift concurrency/deprecation 경고와 linker search path 경고는 남아 있으나 Phase 5 compile 오류는 없다.
- 보충 QA에서 확인한 재실행 active-ban 오표시를 보정했다. `getMyRoomAccess`가 인증 UID의 member/canonical principal ban/room lifecycle을 서버에서 판정하고, iOS는 채팅 진입·foreground에서 조회 완료 전 참여를 막는다. ban은 제한 문구, 조회 실패는 명시적 재확인 버튼으로 표시하며 실패한 참여 시 읽던 메시지를 제거하지 않는다.
- 메시지 long press에 방장 전용 `채팅방에서 내보내기`를 추가했고, 설정 참여자 행 탭은 항상 프로필을 열며 별도 `…`만 내보내기를 연다. 미디어 실패 알림은 ACK/timeout 원문 대신 ban 중단 또는 일반 재시도 문구를 사용한다.
- 보정 후 Functions lint/build 및 191/191, iOS Production-Debug Simulator build와 관련 단위 suite가 통과했다. 이후 OpenJDK 21 환경에서 Firestore·Storage emulator 전체를 재실행해 Rules 41/41과 transaction 26/26을 통과했으며, `member → banned → joinable` self-access 상태, 유효 lease 재점유 금지와 최대 시도 stale lease의 `failed` 종결 검증도 성공했다.
- Phase 5 완료 후 lease 리뷰에서 `processing` job의 과거 `nextAttemptAt`이 유효 lease보다 우선해 중복 claim될 수 있는 경계를 발견했다. 상태별 claim을 `pending/retryPending = due`, `processing = stale lease`로 분리하고 PR #13 merge commit `4fbdb5cc257878f0734f261507de1346c4d5892b`로 `main`에 반영했다. `onRoomOwnershipSuccessionQueued`와 `drainRoomOwnershipSuccessionJobs`만 Production exact-target 재배포했으며 둘 다 Node.js 24 `ACTIVE`, scheduler는 5분·Asia/Seoul `ENABLED`다. 배포 전후 queue 0, 빈 queue 수동 smoke 성공, 관련 ERROR 0이며 Rules·indexes·Storage·Socket·iOS와 운영 데이터는 변경하지 않았다.
- `getMyRoomAccess`만 exact target으로 Production `outpick-664ae`에 추가 배포했고 asia-northeast3 Node.js 24 Gen 2 `ACTIVE` 생성을 확인했다. Firestore Rules·indexes·Storage Rules와 운영 데이터는 이 보정 배포에서 변경하지 않았다.
- 최초 callable smoke에서 잘못된 envelope `{}`를 보낸 3건은 Firebase callable adapter가 HTTP 400과 `Invalid request` ERROR로 기록했다. 이를 보안 판정에서 제외하고 올바른 `{"data":{}}`로 재검증해 3개 모두 HTTP 401을 확인했으며, 해당 시각 이후 Functions·Socket·Scheduler ERROR는 0건이다.
- succession scheduler를 빈 queue에서 수동 1회 실행해 성공 상태를 확인했다. 실행 뒤 bans와 succession jobs는 계속 0건이며 Production QA fixture나 audit 원장을 남기지 않았다.
- 다음 단계인 실제 Production 두 계정 앱 QA는 `qa-checklist.md`의 실행 체크리스트로 고정했다. A=creator/B=participant 방 생성·baseline → 대용량 동영상 pending → 내보내기/읽기 유지·쓰기 차단 → 같은 provider 재로그인 → unban 후 명시적 재가입 → 방·Storage·projection 정리 순서다. remove/unban 감사 로그는 append-only라 삭제하지 않는다.

## Phase 2 local 구현 — 2026-08-10

- 사용자 결정으로 신고 제한은 일/대상별 hard cap 없이 principal당 UTC 1분 10건의 짧은 burst 보호만 둔다. 동일 `clientRequestID`는 submission을 먼저 확인해 원래 접수 결과를 반환하고 quota를 소비하지 않는다.
- `submitUserReport`, `submitRoomReport`는 active target·self report·room membership·trigger message 문맥을 검증하고 aggregate/submission/reporter/rate bucket을 한 transaction으로 기록한다.
- 기존 Phase 2 구현은 신고 본문 snapshot을 UTF-8 4000 bytes로 제한하고 미디어 kind만 기록한다. 메시지 전체 evidence object와 attachment 계약은 Phase 7 구현에서 확장한다.
- 관리자 목록·상세·review mutation·계정 제재 callable은 active platform admin, App Check, capability를 요구한다. 계정 제재는 5분 이내 recent auth, self/protected admin 방어, `stateVersion`을 적용한다.
- 관리자 mutation은 deterministic audit ID, append-only audit과 `caseVersion`/`stateVersion` optimistic concurrency를 사용한다.
- `firestore.rules`는 신고/rate/audit 내부 collection을 client deny하고, `firestore.indexes.json`은 관리자 queue composite index와 rate bucket 2일 TTL을 정의한다.
- iOS는 모델·Repository·UseCase의 thin callable contract만 추가했다. 신고 화면·Coordinator/Container 조립은 Phase 8로 유지한다.
- 공통 `CloudFunctionResponseDecoder`가 서버의 소수점 포함 ISO-8601을 읽지 못하는 경계를 발견해 fractional formatter와 회귀 테스트를 추가했다.
- Functions lint/build와 전체 177/177, Firestore·Storage Rules 35/35, transaction 17/17, iOS 신고/decoder 대상 6개, generic Simulator build, JSON parse와 diff whitespace 검증을 통과했다.
- 이 시점에는 운영 Functions·Rules·index 배포, IAM 변경, 실제 데이터 mutation을 수행하지 않았고, 이후 별도 Production 승인으로 아래 rollout을 진행했다.

## Phase 2 Production rollout 준비 — 2026-08-10

- Production 원격 index/field override를 읽기 전용으로 감사했다. 로컬에 누락돼 있던 기존 `accountDeletion*` 4종과 `brandRequestDays.expiresAt` TTL을 `firestore.indexes.json`에 보존해, 유효 원격 삭제 후보를 0건으로 만들었다.
- 최종 유효 차이는 신규 `moderationUserReports`, `moderationRoomReports` composite index 2개와 `moderationReportRateLimitBuckets`, `moderationAdminRateLimitBuckets` TTL 2개뿐이다.
- `firebase deploy --only firestore:indexes --dry-run`은 rules compile과 함께 통과했다. 실제 index 배포는 별도 명시 승인 전 중단한 뒤 사용자 Production 승인으로 진행했다.
- audited `manage-platform-admin.mjs`를 추가하고 Functions lint/build·177/177을 통과했다.
- Production Auth 2명은 Google 1/Kakao 1, 모두 active account/moderation이다. 기존 active `brandAdmins`인 Kakao 계정 1명을 exact expected-count/confirmation gate로 `platformAdmins`에 등록했다. UID·email·provider subject는 출력하거나 문서화하지 않았다.
- 사용자 Production 승인 후 `firestore:indexes`를 배포했다. 기존 원격 composite index와 TTL field override는 유지됐고, 신규 `moderationUserReports` index `CICAgJiUzYsK`, `moderationRoomReports` index `CICAgLiK-J0K`는 모두 `READY`다. 신규 rate-limit bucket TTL 2개도 원격에 반영됐다.
- `firestore:rules` exact target을 배포하고, `submitUserReport`, `submitRoomReport`, `listModerationReports`, `getModerationReportDetail`, `mutateModerationReview`, `mutateAccountModeration` 6개 Function만 exact target으로 배포했다. Firebase predeploy lint/build가 통과했고 6개 모두 `asia-northeast3`, Node.js 24, `ACTIVE`다.
- 무인증 direct POST는 일반 신고와 관리자 목록 모두 HTTP 401 `UNAUTHENTICATED`로 거부됐으며 데이터 mutation은 없었다. 배포 직후 6개 Cloud Run service의 ERROR 로그는 0건이다.
- 사용자 승인으로 기존 활성 Kakao `platformAdmins` 계정과 Google 비관리자 계정의 Production ID token을 메모리에서만 발급하고 임시 App Check debug token으로 `listModerationReports`를 호출했다. 관리자는 HTTP 성공과 빈 목록을 반환했고 비관리자는 `PERMISSION_DENIED`로 거부됐다. UID·email·provider subject와 token 원문은 출력·저장하지 않았다.
- 관리자 성공 호출이 만든 1분 단위 `moderationAdminRateLimitBuckets` read 문서는 사전 상태로 즉시 복원했다. 신고·계정·검토 데이터 mutation은 없었다. 사후 별도 읽기 감사에서 최근 관리자 read bucket 0건, `codex-p2-*` App Check debug token 0건, exact signer의 임시 Token Creator binding 0건을 확인했고 Phase 2 Function 6개의 ERROR 로그도 0건이다.

## Phase 1-P local 구현 — 2026-08-07

- `functions/src/moderation/backfill.ts`에서 Google·Apple 단일 providerData와 Kakao `kakao:{숫자 ID}` 후보를 분리하고, Kakao 후보는 Admin Key 방식 `/v2/user/me` 응답 ID와 정확히 일치할 때만 resolve한다.
- Kakao persistent custom claims를 새로 저장하지 않으며 Admin Key, HMAC Secret, provider subject, UID와 API 응답 본문은 summary·오류에 포함하지 않는다.
- backfill CLI는 Development/Production project만 허용한다. Production apply는 exact 확인 문자열, canonical Secret 이름과 expected total/Google/Kakao 건수를 모두 요구하며 provider 합계·실제 건수 불일치 또는 unresolved가 있으면 HMAC Secret 조회·Firestore write 전에 중단한다.
- Production dry-run은 HMAC Secret 없이 provider resolution까지만 가능하다. Kakao 후보가 있으면 기존 `KAKAO_ADMIN_KEY`를 프로세스 메모리에서만 읽는다.
- 신규 migration 테스트 10개를 포함한 Functions 전체 `npm test` 164/164, `npm run lint`, `npm run build`가 통과했다.
- Production dry-run 결과 Auth total 2, resolved 2, unresolved 0, Google 1, Kakao 1, Apple 0으로 실행 전 감사 기대값과 정확히 일치했다.
- dry-run은 `--apply` 없이 종료했으며 Production Auth·Firestore·Functions·Rules·Storage·Socket을 변경하지 않았다.
- 사용자 별도 승인 후 Production `MODERATION_PRINCIPAL_HMAC_KEY_V1`을 로컬 저장·원문 출력 없이 256-bit 난수로 생성했다. Secret version 1은 enabled다.
- 사용자 별도 승인 후 Production `getMyModerationState`만 exact target으로 배포했다. Node.js 24 Gen 2 `ACTIVE`, HMAC Secret version 1 binding과 compute service account의 해당 Secret accessor를 확인했다.
- 무인증·App Check 없는 POST는 HTTP 401 `UNAUTHENTICATED`로 거부됐고, 배포 시점 이후 해당 service ERROR 로그는 0건이다. 인증 callable 호출은 아직 수행하지 않았다.
- backfill apply 직전 dry-run은 total 2/Google 1/Kakao 1/unresolved 0으로 다시 일치했고, exact Production 확인 문자열·예상 건수 gate로 2명을 처리했다.
- 사후 검증은 `moderationAccounts`, `moderationPrincipals`, `moderationPrincipalAliases` 각각 2개, Google/Kakao alias 각 1개, 전부 active, account/alias→principal 참조 무결성 정상이다. 금지된 민감 필드 키와 Auth UID·email·provider subject 원문 값은 각각 0개다.
- 사용자 별도 승인으로 profile 4, engagement 4, comment 3, safety 3, account deletion finalizer 1의 exact Function 15개만 Production에 배포했다. Firebase predeploy lint/build가 통과했고 15/15 Node.js 24 Gen 2 ACTIVE, 배포 후 ERROR 0건이다.
- `finalizeExpiredAccountDeletions` scheduler는 `0 * * * *`, `Asia/Seoul`, ENABLED다. 배포 전 source bucket `gcf-v2-sources-715386497547-asia-northeast3`의 아래 generation 15개가 모두 남아 있음을 확인했다.
  - profile: `checkNicknameAvailability` 1785332937172748, `completeOnboarding` 1785332980319450, `updatePublicProfile` 1785332979914786, `updateStylePreferences` 1785332944899846
  - engagement: `setBrandEngagement` 1785332918111916, `setPostEngagement` 1785332918101639, `setSeasonEngagement` 1785332918077834, `setCommentEngagement` 1785332918364457
  - comment: `createComment` 1785332918840132, `createReply` 1785332918556882, `deleteComment` 1785332919363608
  - safety: `reportComment` 1785332927258237, `blockUser` 1785332926983942, `loadHiddenCommentUserIDs` 1785332927154374
  - account deletion: `finalizeExpiredAccountDeletions` 1785332944188282
- Production Firestore 현재 release는 `cloud.firestore`, rollback ruleset은 `bce94c07-bb86-4f9c-a74e-e14dc954085c`이며 remote SHA-256은 `d1978d27b63a73ae5bc230c3fed4bf9c3b0484b6fd44f7305fd8372ffb59cc74`다. 로컬 SHA-256 `88c17d3cb1ab2e32e651c4fce24b7a896caf98218ba2c70e23296580af56f311`과 다름을 확인했다.
- `firebase deploy --only firestore:rules --project outpick-664ae --dry-run --non-interactive`는 compile 성공으로 종료했다. 실제 Firestore Rules release는 아직 변경하지 않았다.
- 배포 직전 Firestore·Storage Emulator 회귀는 Rules 35/35와 transaction 11/11로 통과했다. Production `firestore:rules` exact target만 배포했다.
- 새 Firestore ruleset은 `82942b4b-d110-4ab0-8f09-ab0b4e5aad62`이며 운영 SHA-256 `88c17d3cb1ab2e32e651c4fce24b7a896caf98218ba2c70e23296580af56f311`가 로컬과 일치한다. 이전 `bce94c07-bb86-4f9c-a74e-e14dc954085c`도 계속 읽을 수 있어 rollback 가능하다.
- Production Storage 현재 rollback ruleset은 `e0e75181-a23b-4dcf-a13c-df95bb9a70c6`, remote SHA-256은 `9da3b4d6abe8396ad96a50dc45556d3e7ecffe7351085a4ce0e2af8ecda63bb2`다. 로컬 SHA-256 `78ebf3d161284be1ac3aa4ff4c3a5a86ad4d325287ebefaa79fa36c0e32b94d1`과 다르며 Production Storage dry-run compile은 통과했다. 실제 Storage release는 미변경이다.
- Production `storage` exact target만 배포했다. 새 Storage ruleset은 `599b1ae1-21b0-4be1-a2f6-aa576369221a`이며 운영 SHA-256 `78ebf3d161284be1ac3aa4ff4c3a5a86ad4d325287ebefaa79fa36c0e32b94d1`가 로컬과 일치한다. 이전 `e0e75181-a23b-4dcf-a13c-df95bb9a70c6`도 계속 읽을 수 있어 rollback 가능하다.
- Production Socket candidate 전 preflight에서 `npm run check`, `npm test` 69/69가 통과했다. 현재 service `outpick-socket`은 revision `outpick-socket-00008-4wl` traffic 100%, image digest `sha256:1d3b1e76b8d55b36bade7117d510c6aea5750f03bf565e283729d59e0fcef320`, max instance 1, timeout 3600초, concurrency 80을 유지한다.
- Socket runtime identity는 `outpick-socket@outpick-664ae.iam.gserviceaccount.com`, canonical URL은 `https://outpick-socket-2w7zhxurhq-du.a.run.app`이다.
- Cloud Build `2719bc50-1c06-45d6-923a-1549ad2d7ffe`로 image digest `sha256:403ecf364fbfa0ff3d040fed7d888b000a63539f485ea9c88387f3e949fe8ccd`를 만들고 revision `outpick-socket-moderation-p1p`, tag `moderation-p1p-qa`를 `--no-traffic`으로 배포했다. candidate Ready, tagged `/readyz` 200, ERROR 0이며 live `outpick-socket-00008-4wl`은 계속 100%다.
- build의 `npm audit`에서 high 1·moderate 8이 확인됐다. high는 `socket.io-parser 4.2.6`의 비인증 원격 메모리 고갈 GHSA-2m8v-j782-fhvr이고 패치 `4.2.7`은 현재 `socket.io@4.8.3` 의존 범위 `~4.2.4` 안에 있다. lockfile patch·회귀·새 candidate 전까지 traffic 전환을 금지한다.
- moderate 8은 `firebase-admin@13.10.0`의 Google Cloud 전이 의존성 경로이며 npm이 제시한 자동 수정은 `firebase-admin@10.3.0` major downgrade다. 이 경로의 실제 영향과 안전한 상위 패치는 별도 확인하되 high 패치와 traffic gate를 분리하지 않는다.
- 사용자 승인으로 `Socket/package-lock.json`의 `socket.io-parser`만 4.2.6→4.2.7로 갱신했다. 직접 의존성과 `package.json`은 변경하지 않았다.
- 패치 후 `npm ci`, `npm run check`, 69/69, 설치 버전 4.2.7을 확인했다. production audit은 high 0/critical 0/moderate 8이며 기존 `outpick-socket-moderation-p1p` image는 4.2.6이므로 traffic 대상으로 사용하지 않는다.
- 사용자 승인으로 Cloud Build `3c6db117-22f6-46a9-93fb-112f6a0f64ae`를 실행했다. build `npm ci`도 high/critical 없이 moderate 8만 보고했고 image digest는 `sha256:a7c0a095c64adf0b83459f16a0caf3f68378ce3fffdaea0e919555a1da3b7dc5`다.
- 패치 revision `outpick-socket-moderation-p1p-r2`, tag `moderation-p1p-r2-qa`를 `--no-traffic`으로 배포했다. Ready, tagged `/readyz` 200, ERROR 0, max instance 1/timeout 3600/concurrency 80이며 live `outpick-socket-00008-4wl`은 계속 traffic 100%다.
- 패치 candidate 인증 smoke를 위해 기존 Production Google QA 계정의 Firebase Custom Token을 메모리에서만 서명하는 방식을 사용자 승인으로 시도했다. `firebase-adminsdk-s16bx@outpick-664ae.iam.gserviceaccount.com`에 현재 사용자만 `roles/iam.serviceAccountTokenCreator`를 임시 부여했고 IAM 정책 반영 및 ADC principal 일치를 확인했다. 초기에는 IAM 전파 지연으로 `iam.serviceAccounts.signBlob`이 거부됐으나, 사용자 승인 5분 제한 재시도에서 약 90초 뒤 Custom Token 서명과 Firebase ID Token 교환이 성공했다.
- ID Token의 signed `sub`, `aud`, `iss`를 메모리에서 기존 UID·Production project와 대조한 뒤 candidate WebSocket에 연결했다. HTTP 101 upgrade는 성공했지만 Socket.IO 인증은 `invalid_id_token`으로 거절됐다. candidate 로그의 실제 원인은 runtime ADC의 `auth/insufficient-permission`이었다.
- live와 candidate는 모두 `outpick-socket@outpick-664ae.iam.gserviceaccount.com`을 사용하며, 현재 project IAM은 `roles/datastore.user`, `roles/firebasecloudmessaging.admin`, `roles/storage.objectAdmin`뿐이다. 공통 코드의 `verifyIdToken(idToken, true)`는 revoked/disabled 확인을 위해 Firebase Auth 사용자 조회가 필요하지만 `firebaseauth.users.get` 권한이 없다.
- smoke 중 신규 Auth 사용자·credential 파일·token 출력/저장·Firestore write는 없었다. 임시 Token Creator binding은 결과 확인 즉시 회수했고 잔존 binding 0건이다. live `outpick-socket-00008-4wl` traffic 100%, 패치 candidate traffic 0%는 유지한다.
- 사용자 승인으로 project custom role `projects/outpick-664ae/roles/outpickSocketFirebaseAuthVerifier`를 생성했다. 포함 permission은 `firebaseauth.users.get` 하나, stage는 GA이며 `outpick-socket@outpick-664ae.iam.gserviceaccount.com`에 영구 부여했다.
- 테스트 Token Creator를 다시 임시 부여하고 약 90초 IAM 전파 후 기존 Production Google QA 계정으로 candidate 인증 smoke를 재실행했다. Custom Token 서명, Firebase ID Token 교환·signed claims 대조, WebSocket/Socket.IO 인증 handshake가 모두 성공했다. 신규 Auth 사용자·credential 파일·token 출력/저장·Firestore write는 없으며 임시 binding은 즉시 회수해 잔존 0건이다. candidate 최근 15분 ERROR 로그도 0건이다.
- 기존 IAM 감사에서 Socket은 Firestore document query/listener/transaction/create·update·delete, 방 폐쇄 시 `rooms/{roomID}/` Storage prefix list·delete, chat push의 FCM message send를 실제 사용한다. 현재 predefined `roles/datastore.user`, `roles/storage.objectAdmin`, `roles/firebasecloudmessaging.admin`에는 이보다 넓은 console/statistics, object create/update/IAM/retention, topic subscription/FCM delivery-data 권한이 포함된다. 축소 시 live와 candidate가 같은 service account를 공유하므로 기존 역할은 즉시 제거하지 않고 별도 최소 권한 candidate identity 검증 설계를 먼저 확정한다.
- 패치 candidate 인증 handshake는 완료됐지만 traffic 전환은 아직 수행하지 않았다.
- 사용자 승인으로 서비스 단위 통합 custom role `projects/outpick-664ae/roles/outpickSocketRuntime`을 생성했다. 포함 permission은 Auth user get 1개, Firestore database get/entity allocate·create·delete·get·list·update 7개, Storage object list·delete 2개, FCM message create 1개로 총 11개다.
- 새 전용 identity `outpick-socket-runtime-v2@outpick-664ae.iam.gserviceaccount.com`에는 이 통합 role 하나만 부여했다. 검증된 digest `sha256:a7c0a095c64adf0b83459f16a0caf3f68378ce3fffdaea0e919555a1da3b7dc5`를 revision `outpick-socket-moderation-p1p-r3-lp`, tag `moderation-p1p-r3-lp-qa`로 0% 배포했다. Ready, `/readyz` 200, max 1/timeout 3600/concurrency 80이며 기존 live는 100%를 유지한다.
- 기존 Production Google QA 계정의 메모리 내 ID Token으로 새 candidate 인증 handshake가 성공했다. 이어 unique `qa_socket_lp_*` room, message, fake recipient/device, Storage marker만 생성해 Socket 경유 Firestore read/write/delete, Storage list/delete, FCM fanout을 실제 검증했다. FCM fanout 완료 로그 1건, candidate ERROR 0건이다.
- smoke room·subcollection·unique roomID의 기존 QA 사용자 joinedRooms/roomStates projection·fake recipient/device·Storage prefix는 finally cleanup과 사후 조회에서 잔존 0건이다. 기존 user root·기존 room/content/device 문서는 변경하지 않았고 신규 Auth 사용자·credential/token 저장도 없었다. 테스트 Token Creator는 즉시 회수해 잔존 0건이다.
- 사용자 승인으로 `outpick-socket-moderation-p1p-r3-lp`에 Production traffic 100%를 전환했다. canonical `/readyz` 200, 기존 Google QA 계정 canonical Socket.IO 인증 handshake 성공, 전환 후 ERROR 0건이다. 이전 `outpick-socket-00008-4wl`과 다른 tagged revision은 0%로 보존한다.
- rollback revision이 계속 동작하도록 기존 identity `outpick-socket@...`에도 검증된 `outpickSocketRuntime` role을 먼저 부여한 뒤 `roles/datastore.user`, `roles/storage.objectAdmin`, `roles/firebasecloudmessaging.admin`, 구 Auth verifier binding을 제거했다. 새/기존 Socket identity는 이제 통합 role 하나만 사용한다.
- 바인딩 0건인 구 `outpickSocketFirebaseAuthVerifier` custom role은 soft-delete했다. 테스트 Token Creator 잔존 0건, 최종 canonical readiness 정상, r3 ERROR 0건을 재확인했다.

## Phase 1 완료 내용

- `getMyModerationState`가 Google/Apple Firebase identity 또는 Kakao 서버 검증 custom claim에서 stable subject를 얻고, raw subject를 저장하지 않는 versioned HMAC alias를 계산한다.
- alias lookup, canonical principal 생성·복원, current UID projection을 Firestore transaction으로 수렴시킨다.
- current/previous HMAC key dual lookup과 current alias 추가 경계를 두어 key 회전 시 기존 principal을 유지한다.
- `moderationAccounts/{uid}` 누락·불명확 provider identity는 active fallback 없이 fail closed한다.
- 계정 삭제 최종 private-state 정리는 UID projection을 제거하되 principal·HMAC alias 제재 원장은 보존해 재가입 시 다시 복원한다.
- Functions의 기존 Lookbook 댓글/반응/신고/차단/프로필 mutation에 account capability를 연결하고, 신규 온보딩은 users 문서가 없어도 moderation projection의 create capability를 먼저 검증한다.
- Socket handshake는 restricted read-only 연결을 허용하고 suspended·projection 누락을 거부한다. message/media/공유/room create를 capability로 차단하며 기존 room 실시간 구독은 read capability로 유지한다.
- moderation status 또는 stateVersion 변경을 감시해 기존 Socket을 disconnect하고 재평가한다. restricted owner의 room close도 거부한다.
- Firestore·Storage Rules는 projection 누락을 fail closed하고 restricted read와 active write를 분리하며 moderation 내부 collection direct read/write를 거부한다.
- iOS bootstrap은 사용자 문서 조회 전에 `getMyModerationState`를 호출한다. suspended는 일반 앱 진입 전 안내·계정 삭제·로그아웃 경로로 보내고, restricted 기존 계정은 읽기 흐름과 제한 안내를 제공한다.
- 고객지원 URL은 운영 값이 아직 없으므로 API에서 nullable로 유지하며 값이 주입되면 안내 화면이 동일 URL을 연다.

## Phase 1 검증

- Functions `npm run lint`, `npm test`: Phase 1-P 갱신 후 통과, 164/164.
- Socket `npm run check`, `npm test`: 통과, 69/69.
- Firestore·Storage Emulator: Rules 35/35, transaction 11/11 통과. concurrent same-provider binding, suspended 재가입 복원, old/new HMAC key 회전과 missing account bootstrap get을 포함한다.
- iOS `LoadCurrentUserBootstrapUseCaseTests`: 6개 시나리오 통과. suspended의 account/profile 선행 read 금지와 restricted routing을 포함한다.
- iOS test build에서 기존 Chat test의 unused-result 및 actor isolation warning은 남아 있으나 Phase 1 컴파일·테스트 실패는 없다.
- `jq empty contracts/chat-moderation-v1.json`, `git diff --check`: 최종 검증 대상이다.

## Phase 1 Development rollout

- 2026-08-07 `outpick-test` Auth dry-run 결과 5명 중 Google 1명만 resolved였고, 사용자가 불필요하다고 확정한 password 기반 `uitest-*` Auth 계정 4개를 삭제했다. 연관 Firestore 콘텐츠는 범위를 확대해 삭제하지 않았다.
- `test-admin-server` 룩북 seed는 앞으로 `uitest-*` Auth 계정을 재생성하지 않고 표시용 Firestore fixture만 만든다. 실제 Development 인증은 Google 계정을 사용한다.
- 재실행한 dry-run은 Auth 1명, Google resolved 1, unresolved 0이었다.
- Development `MODERATION_PRINCIPAL_HMAC_KEY_V1` Secret version 1을 원문 출력·로컬 저장 없이 생성했다.
- Google 계정 backfill 결과 `moderationAccounts`, `moderationPrincipals`, `moderationPrincipalAliases`가 각각 1개이고 상태는 active다. raw subject·email·token 필드는 0개다.
- capability 영향을 받는 Functions 16개, Firestore·Storage Rules를 `outpick-test`에 배포했다. `getMyModerationState`는 ACTIVE이며 Development Secret v1만 참조한다.
- Socket image digest `sha256:9e2bcf60b4f262e6f305e757a4d981203b9a0f70d7fb166cd16f39f39a28f400`을 0% candidate로 검증한 뒤 revision `outpick-socket-development-00002-hal`에 traffic 100%를 전환했다. canonical `/readyz` 정상, ERROR 로그 0건이다.

## Phase 1 밖 후속 QA·Production 보류

- Apple 실제 Development 재로그인·탈퇴·재가입 QA는 수행하지 않았다. 현재 iOS 로그인 UI·Repository 계약에 Sign in with Apple 진입점이 없어 QA 전에 별도 기능 설계·구현 승인이 필요하다.
- Production 앱은 현재 개발자·내부 QA 전용이다. 고객지원 URL은 별도 `customer-support-https-page` 작업으로 분리했으며, 준비 전까지 `supportURL: null` 내부 smoke만 허용하고 restricted/suspended 실제 운영과 외부 배포는 금지한다.
- 현재 로그인한 Kakao Developers 계정에서는 Production Native App Key의 `OutPick`만 확인돼 Development 앱의 콘솔 소유 계정·팀은 확인하지 못했다. 다만 Development 실제 연결 해제·재연결에서 기존 HMAC alias와 canonical principal이 그대로 복원돼 구성된 Development 앱의 동일 service user ID 동작은 검증했다.
- Production Kakao User ID Fixed 설정, 고객지원 URL, 개인정보 보존 승인은 Production gate에 남아 있다.
- Phase 1 Development 종료 시점에는 Production Secret·backfill·배포를 수행하지 않았다. 이후 Phase 1-P 별도 승인으로 Secret·bootstrap Function·backfill까지만 반영했다.
- Phase 1-P 착수 전 감사에서는 Production moderation Secret과 `getMyModerationState`가 없었다. 이후 별도 승인으로 두 항목만 생성·배포했으며 Production Socket은 기존 revision `outpick-socket-00008-4wl` traffic 100%를 유지한다.

## Phase 1 Development 재가입 QA — 2026-08-07

- Google 계정을 restricted로 전환한 뒤 기존 콘텐츠·채팅 read, 제한 안내, 메시지·댓글·좋아요·방 생성 차단을 실제 앱에서 확인했다.
- 계정 삭제 grace를 QA용으로 만료시켜 finalizer를 실행했고 request completed, 기존 Auth/users/moderationAccounts 삭제, canonical principal·alias와 restricted 상태 보존을 확인했다.
- 같은 Google 계정 재가입으로 신규 UID가 기존 principal과 restricted projection에 연결되는 서버 복원은 확인됐다.
- 첫 재가입 화면은 `users/{newUID}` missing get을 `isReadableAccount`가 거부해 generic bootstrap failure를 표시했다. Rules를 본인 단일 get 허용으로 수정하되 list·다른 UID·suspended 접근은 계속 거부했고 Emulator 35/35 통과 후 Development에 재배포했다.
- 수정 Rules 적용 후 같은 Google 계정으로 다시 실행했을 때 generic bootstrap failure가 아니라 제한 안내 root로 진입함을 확인했다.
- 제한 안내 root를 기존 패션 매거진 시각 언어에 맞춘 에디토리얼 경고 화면으로 교정했다. warning hairline, serif 제목, monospaced 상태, 제한 정보 카드와 account action row를 사용한다. 첫 QA 피드백으로 좌상단 원형 느낌표는 제거했다.
- Development처럼 `supportURL`이 없는 환경에서는 고객지원 확인 문구와 CTA를 함께 숨기고, URL이 있을 때만 동일 카드에서 고객지원 CTA를 표시한다.
- iPhone 17 Pro Max iOS 26.2 Simulator에서 제한 문구·계정 삭제·로그아웃 action 노출과 계정 삭제 확인 화면 push·복귀를 확인했다. 접근성 최대 글자 크기에서도 scroll로 두 action에 접근할 수 있음을 확인한 뒤 Simulator 설정은 기존 `large`로 복원했다. 로그아웃 실제 실행은 제한 QA 세션 보존을 위해 수행하지 않았다.
- Build iOS Apps의 격리 DerivedData 빌드는 기존 package module을 찾지 못해 실패했으나, 프로젝트 기본 `xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'generic/platform=iOS Simulator' build`는 통과했다.
- Kakao 신규 로그인 뒤 Auth 1개와 active moderation projection/principal 생성을 확인하고, principal과 projection을 24시간 restricted·stateVersion 2로 같은 transaction에서 전환했다.
- 앱에서 실제 Kakao 재인증으로 삭제를 예약한 뒤 사용자의 별도 즉시 삭제 승인에 따라 해당 Development 요청 한 건만 grace 만료 처리했다. finalizer는 1회 시도에서 오류 없이 completed됐고 Auth·users·moderationAccounts는 제거됐으며 Kakao 앱 연결 해제 단계도 통과했다.
- 삭제 직후 Kakao HMAC alias 1개와 canonical restricted principal 1개만 보존되고 raw email·subject·token·providerUserID 필드는 0개임을 확인했다.
- 같은 Kakao 계정 재연결 뒤 Auth와 moderationAccounts가 다시 생성됐고, 기존 alias와 같은 principal에 `restricted`, stateVersion 2로 연결됐다. `users` 문서가 없는 재가입 상태에서도 온보딩이나 generic failure가 아니라 제한 안내 root로 진입했다.

## Phase 1-P Production active smoke — 2026-08-08

- `OutPick-Production` / `Production-Debug`를 iPhone 17 Pro Max iOS 26.2 Simulator에서 빌드·실행했다.
- 첫 Google 로그인 뒤 Firebase Auth는 `VALID`였지만 App Check가 `INVALID`여서 `getMyModerationState`가 401로 거부되고 bootstrap failure가 표시됐다. 현재 Simulator debug token을 Production iOS App Check에 원문 출력·Git/하네스 저장 없이 임시 등록한 뒤 `다시 시도`로 메인 탭 진입에 성공했다.
- Google active 계정은 오픈채팅·채팅·룩북·좋아요·내 정보 기본 read와 로그아웃을 통과했다.
- Kakao active 계정은 로그인 callback 뒤 메인 탭, 채팅·룩북·내 정보 기본 read를 통과했다.
- Kakao 세션의 HATCHINGROOM 브랜드 상세에서 좋아요를 `0→1`로 저장하고 `1→0`으로 즉시 원복해 기본 write를 검증했다. 최종 좋아요 값은 0이며 Production 테스트 변경은 남기지 않았다.
- Kakao 로그아웃 뒤 이번 QA용 App Check debug token을 삭제했다. 삭제 후 기존 debug token 1개만 남았고 이번 등록 resource의 잔존은 false다. debug token 원문은 문서나 저장소에 기록하지 않았다.
- 제한·정지·계정 삭제는 수행하지 않았다. `supportURL: null` 내부 active smoke 경계를 지켰다.
- 이 결과로 Phase 1-P step 10과 Phase 1-P Production 반영 범위를 완료 처리한다.

## Phase 0 완료 내용

- `contracts/chat-moderation-v1.json`을 authoritative v1 contract로 추가했다.
- UID 기반 콘텐츠 identity와 canonical moderation principal을 분리했다.
- versioned HMAC alias, current UID capability projection, 제재·신고·ban·audit collection을 고정했다.
- active/restricted/suspended capability matrix와 restrictedUntil server-clock 판정을 고정했다.
- 사용자·방 신고 aggregate/submission/reporter, review revision과 caseVersion 계약을 고정했다.
- 일반 사용자·room creator·platform admin API, idempotency와 안정된 오류 코드를 고정했다.
- room ban list가 global moderationPrincipalID 대신 room-scoped opaque token만 노출하도록 고정했다.
- 메시지 삭제 tombstone/cleanup, closedByModeration, owner succession 경계를 고정했다.
- transaction 밖 cleanup을 `chatMessageCleanupJobs`와 `moderationRoomCleanupJobs`의 deterministic retry로 고정했다.
- 기존 global block의 단방향 visibility와 hidden payload local redaction을 고정했다.
- ADR-016 media reservation을 격리·기술 검증 상태 머신으로 확장하고 ready transaction 전 message·seq 미생성을 고정할 설계를 확정했다.
- Production TTL과 개인정보·운영·App Review 확인을 코드 완료와 분리된 출시 조건으로 기록했다.

## 변경 문서

- `contracts/README.md`
- `contracts/chat-moderation-v1.json`
- `docs/ai/ADR.md`
- `docs/ai/adr/ADR-024-ugc-안전은-canonical-moderation-principal과-서버-capability로-통합한다.md`
- `docs/ai/DATA_SCHEMA.md`
- `docs/ai/ENTRYPOINTS.md`
- `docs/ai/entrypoints/CHAT.md`
- `docs/ai/entrypoints/FIREBASE.md`
- `docs/ai/entrypoints/TESTS.md`
- `docs/ai/tasks/chat-ugc-safety-room-moderation/decisions.md`
- `docs/ai/tasks/chat-ugc-safety-room-moderation/plan.md`
- `docs/ai/tasks/chat-ugc-safety-room-moderation/qa-checklist.md`
- `docs/ai/tasks/chat-ugc-safety-room-moderation/progress.md`

## 검증

- `jq empty contracts/chat-moderation-v1.json`: 통과.
- 기존 Phase 0 enum 중복·필수 capability/API/document assertion은 통과했다. Phase 7 선택 evidence 계약은 이번 문서 갱신으로 대체했으며 구현 검증은 아직 수행하지 않았다.
- Phase 0~9 heading, 필수 파일, 용어 잔여와 trailing whitespace 점검: 통과.
- tracked 문서와 contract 대상 `git diff --check`: 통과.
- 코드·rules·indexes를 변경하지 않았으므로 Functions/Socket/iOS/rules 테스트와 build는 실행하지 않는다.

## 남은 위험과 중단 조건

- Apple 계정에서 검증된 provider subject를 서버가 안전하게 확보하는 실제 QA는 Sign in with Apple 구현 전까지 확인할 수 없다.
- Kakao token exchange의 providerUserID 검증과 Development 연결 해제·재연결 시 동일 principal 복원은 확인했다. Production 콘솔의 User ID Fixed 확인은 출시 gate로 남는다.
- moderation principal·room ban의 계정 삭제 후 보존은 법률·개인정보 검토 전 Production TTL과 운영 처리를 활성화하지 않는다.
- animated GIF의 정확한 frame/decode/memory/CPU 제한은 Phase 7 구현 가능성 검증 뒤 고정한다. 아동 성착취물·즉각적 불법 위험의 법적 보존·신고 절차는 **확실하지 않음**이며 외부 출시 전에 별도 법률·운영 runbook이 필요하다.

## Phase 3 구현 완료 — 2026-08-10

- `deleteChatMessage`, `closeOwnedChatRoom`, `closeRoomByModeration` callable과 deterministic message/room cleanup trigger·5분 drain scheduler를 추가했다.
- 메시지는 server transaction에서 seq tombstone을 유지하면서 공개 payload·last summary·announcement를 정리하고, reply preview·media index·Storage는 retry job으로 수렴한다.
- 방장 삭제와 관리자 폐쇄를 각각 `closedByOwner`, `closedByModeration`으로 구분하고 lifecycle을 즉시 닫는다. cleanup은 당시 member/creator별 폐쇄 안내를 먼저 생성한 뒤 room subcollection·Storage·room 문서를 즉시 삭제한다.
- 폐쇄 안내는 사용자 확인 delete와 미확인 30일 TTL을 함께 적용한다. 완료 cleanup job은 7일 TTL, 20회 실패 job은 TTL 없이 남는다.
- Firestore·Storage Rules는 폐쇄 방 read/join/write와 message/lifecycle client direct mutation·message media client delete를 거부한다. due job composite index 2개와 TTL override 3개를 추가했다.
- Socket 단일 room cleanup job listener가 pending/completed closure를 모두 받아 `room:closed` emit, registry 제거와 socket leave를 수행한다.
- iOS는 `ChatModerationLifecycleRepository`를 통해 message delete와 owner close를 callable로 보내고 서버 성공 뒤 local GRDB deletion을 적용한다. 참여방 화면은 사용자별 closure notice를 표시하고 확인 성공 시 즉시 삭제한다.

### Phase 3 자동 검증

- Functions lint/build와 전체 181/181 통과. lint error는 0이며 non-null assertion warning 9개가 남아 있다.
- Socket syntax check와 전체 71/71 통과. pending/completed closure listener 경합 테스트를 포함한다.
- Firestore·Storage Rules 37/37, transaction 19/19 통과. 실제 tombstone/reply/media/Storage cleanup, room delete, 사용자별 30일 notice와 삭제 후 idempotent replay를 포함한다.
- iOS Development Simulator build 통과. `CloudFunctionsChatModerationLifecycleRepositoryTests`, `ChatRoomExitUseCaseTests`, `ChatRoomMessageUseCaseTests`, `ChatRoomFirestoreMapperTests` 대상 테스트가 모두 통과했다.
- `jq empty firestore.indexes.json contracts/chat-moderation-v1.json` 통과.

### Phase 3 Production rollout — 2026-08-10

- 사용자 승인 뒤 Production 원격 Firestore 전체 구성과 로컬을 정규화 비교했다. 운영에만 있는 index/field override는 0개였고, Phase 3 신규 composite index 2개와 TTL 3개만 추가 대상임을 확인한 뒤 배포했다.
- `chatMessageCleanupJobs(status,nextAttemptAt)`, `moderationRoomCleanupJobs(status,nextAttemptAt)` index는 모두 `READY`다. 두 cleanup job과 `roomClosureNotices.expiresAt` TTL은 모두 `ACTIVE`다.
- `deleteChatMessage`, `closeOwnedChatRoom`, `closeRoomByModeration`, `onChatMessageCleanupQueued`, `onModerationRoomCleanupQueued`, `drainChatModerationCleanupJobs` 6개만 exact target으로 배포했다. 모두 asia-northeast3 Node.js 24 Gen 2 `ACTIVE`이며 5분 drain scheduler는 `ENABLED`다.
- Firestore Rules와 Storage Rules를 exact target으로 배포했다. Firestore ruleset `e3882745-acf3-409f-b39d-b20790712081`, Storage ruleset `7a003ba0-f72f-4287-901d-b8c67ada91a8`은 각각 로컬 source hash와 일치한다. 배포 직전 Functions 181/181, Socket 71/71, Rules 37/37, transaction 19/19, Firebase dry-run과 `OutPick-Production` generic Simulator build가 통과했다.
- Socket Cloud Build `1816fdca-a98d-4a28-81d3-ead29ff253b3`, image digest `sha256:af0af243b482c01a0a76ecace1364337bea595f5c64961e57951a5522db6083a`를 revision `outpick-socket-moderation-p3-0810` 0% candidate로 배포했다. readiness와 ERROR 0을 확인한 뒤 Production traffic 100%로 전환했다. 이전 `outpick-socket-moderation-p1p-r3-lp`는 0% rollback revision으로 보존한다.
- 기존 active Kakao `platformAdmins` 계정과 Google active 계정을 사용해 격리 `qa_phase3_admin_close_*` 방을 만들고 실제 `closeRoomByModeration` callable을 호출했다. 관리자 폐쇄 성공, cleanup completed, room·Storage 즉시 삭제, 두 사용자 notice 생성, 정확한 30일 TTL, 사용자 권한 notice delete, 동일 request replay 멱등 성공을 확인했다.
- QA가 만든 room/job/notice/audit/Storage object는 모두 0건으로 정리했다. 임시 App Check debug token과 exact signer Token Creator binding도 0건이며 Phase 3 Functions·Socket 배포 시작 이후 ERROR 로그는 0건이다.
- 앱은 아직 TestFlight/App Store/사내 배포 전이라는 ADR-009 조건을 재확인했다. 이번 iOS Production 반영은 `OutPick-Production` 빌드 검증까지이며 외부 앱 배포 artifact 업로드는 수행하지 않았다.

### Phase 3 Production QA 전 활성 Rooms query 보정 — 2026-08-10

- Production 로그인 뒤 방 생성 preflight가 실패한 직접 원인은 방 이름 중복 조회가 폐쇄 방을 제외하지 않아 `roomDataIsActive` Firestore read Rules가 query 전체를 거부한 것이다. 같은 계약 누락이 전체 목록, 참여방 ID 일괄 조회와 검색에도 있어 이름 중복 조회 한 곳만이 아니라 네 경로를 함께 수정했다.
- `FirebaseChatRoomRepository.activeRoomsQuery()`가 `isClosed == false`, `lifecycleStatus == active`를 소유하고 전체 목록·ID 일괄 조회·검색·이름 중복 조회가 공통 사용한다. 폐쇄 문서는 목록/검색/참여방 복원/새 방 이름 점유 대상에서 모두 제외된다.
- `firestore.indexes.json`에는 활성 목록 1개와 활성 검색 2개를 추가했다. 운영 중인 기존 검색 index 2개는 신규 index READY와 앱 QA 전까지 rollback 호환용으로 보존해 이번 배포에서 삭제가 발생하지 않게 했다.
- 배포 전 정규화 전체 감사 결과 index는 로컬 41/원격 38, `onlyLocal`은 신규 Rooms 3개, `onlyRemote`는 0개였다. field override/TTL은 로컬·원격 29개가 완전히 같았다. Firestore index dry-run과 실제 `outpick-664ae` 배포가 성공했다.
- 운영 `Rooms`를 문서 ID·내용 비노출 집계로 읽기 감사한 결과 현재 문서는 0개라 legacy 활성 방 필드 누락에 따른 조회 제외 대상도 0개다. 앞으로 앱이 생성하는 방은 `isClosed: false`, `lifecycleStatus: active`를 함께 기록한다.
- Functions lint/build와 182/182, Rules 37/37, transaction 19/19, `ChatRoomActiveQueryContractTests`, `OutPick-Production` generic Simulator build가 통과했다. 기존 Functions lint warning 9개와 기존 iOS warning은 남아 있으나 오류는 0개다.
- 신규 index 3개는 모두 `READY`다. 변경된 ad-hoc 서명 Production 앱을 Kakao QA Simulator에 설치해 기존 로그인 세션 복원, 오픈채팅 목록 정상 진입과 Rooms 권한·index 오류 0건을 확인했다. Google·Kakao 검색/참여방 조회와 실제 방 생성은 사용자 수동 QA에서 재확인한다.

### Phase 3 앱 수동 QA 후속 보정 — 2026-08-10

- 현재 보고 있는 방에서 배너가 노출된 원인은 화면 진입·이탈 때 visible room 변경까지 추적되지 않은 비동기 Task에 넣어 호출 순서가 역전될 수 있었기 때문이다. visible room 갱신은 화면 수명주기에서 동기 처리하고 Presence 원격 갱신만 비동기로 분리했다.
- 방장 삭제 안내는 삭제를 수행한 creator에게 생성하지 않고 당시 참여자에게만 생성한다. 관리자 종료는 creator를 포함한 당시 참여자 모두에게 생성한다. 안내 schema v2에 `roomName`을 추가하고 사용자 문구에서 `폐쇄`를 제거했다.
- `JoinedRoomsViewModel`은 진행 중인 안내 fetch를 세대 번호와 cancellation로 관리하고, 현재 앱 세션에서 확인 완료한 room ID를 재조회 결과에서 제외해 동일 안내의 중복 표시를 막는다.

### Phase 3 Production QA 후 account capability·Storage 보정 — 2026-08-10

- 이미지 메시지 403의 직접 원인은 Storage Rules가 requester `users`, requester `moderationAccounts`, room의 세 문서를 조회해 플랫폼 한도 2개를 초과한 것이다. `moderationAccounts` schema v2에 `accountStatus`를 포함해 권한 판정을 단일 projection으로 통합했다.
- 계정 삭제 요청·취소와 provider binding은 `users.accountStatus` 원본과 projection을 transaction으로 함께 갱신한다. Functions·Firestore/Storage Rules·Socket auth/listener 모두 capability hot path에서 `moderationAccounts` 한 문서만 사용한다.
- 채팅 미디어 read는 account projection + active room을 확인한다. upload는 Socket capability/room access 검증으로 발급된 짧은 TTL의 pending `MediaUploads/{messageID}` reservation + active room에서 sender/kind/path/expiry를 확인한다. reservation 누락·만료·불일치와 deletionPending 계정의 read는 거부한다.
- privacy-safe schema v2 backfill과 원격 Rules source hash·Firestore index/TTL 전체 감사 script를 추가했다. Production 사전 감사는 사용자 2명/projection 2명, unresolved·missing 0이었고 apply 뒤 모두 schema v2 active, 재실행 update 0이었다.
- 전체 원격 index 41개와 field override 29개는 로컬과 완전히 일치해 index 배포는 수행하지 않았다. Firestore Rules `943f0af9-d161-4f2c-ac01-cf376a4631b6`, Storage Rules `808a41e6-88f7-459a-b2fe-67fe6d351c04`를 exact target으로 배포했고 로컬·운영 source hash가 일치한다. 직전 ruleset은 각각 `e3882745-acf3-409f-b39d-b20790712081`, `7a003ba0-f72f-4287-901d-b8c67ada91a8`로 rollback 가능하다.
- capability 영향 Function 27개는 모두 Node.js 24 Gen 2 `ACTIVE`다. Socket Cloud Build `0f7842a6-c16a-4ae7-9436-bcc4d5f244a5`, image digest `sha256:4b1042cfa340b4e5be43b7d570177893eae62ee14258726a2f3405fd360f3610`의 revision `outpick-socket-account-cap-v2-0810`을 readiness·ERROR 0 확인 뒤 traffic 100%로 전환했다. 이전 `outpick-socket-moderation-p3-0810`은 0% rollback으로 보존한다.
- 최종 자동 검증은 Functions lint/build·185/185, Socket check·70/70, Firestore·Storage Rules 40/40, transaction 20/20, JSON parse와 Production Rules dry-run을 통과했다. 170명 추가 참여자 방 종료 회귀도 batch 한도 안에서 완료됐다. Functions lint error는 0이고 기존 non-null assertion warning 9개만 남았다.
- PR 전 리뷰에서 closure notice batch가 최대 900 writes가 될 수 있던 문제를 참여자 150명 단위(최대 450 writes)로 교정했다. 표시용 방 이름이 없거나 유효하지 않아도 방 물리 삭제는 계속되게 했고, exact contract의 message cleanup/notice schema version도 실제 문서와 맞췄다.
- 실제 Production 앱에서 기존 placeholder였던 이미지 메시지가 정상 표시됐다. 참여자 앱을 종료한 동안 관리자 종료 lifecycle을 실행한 뒤 재실행해 `“{방 이름}” 채팅방이 종료됐어요` 안내가 정확히 한 번 표시되고, 확인 후 해당 notice가 즉시 삭제되며 재진입 때 중복되지 않음을 확인했다.
- QA room·cleanup job·audit·Storage와 남은 creator notice를 정리했고 participant 확인 삭제도 확인했다. 임시 Phase 3 App Check debug token은 0개이며, 배포 후 최근 1시간 Production Cloud Run severity ERROR 로그도 0건이다.

## Phase 3.1 방 종료 lifecycle 개편 구현 — 2026-08-10

- 신규 사용자별 `roomClosureNotices` 생성을 제거하고, 방 콘텐츠 즉시 정리 뒤 하나의 공용 `Rooms/{roomID}` tombstone을 최대 14일 유지하도록 `moderationRoomCleanupJobs`를 schema v2 `content → retention` 단계로 개편했다.
- `acknowledgeRoomClosure` callable이 확인 사용자의 member/joinedRooms/roomStates와 남아 있는 legacy notice를 멱등 정리한다. 방장 삭제 creator는 서버·앱에서 즉시 정리하며 안내 대상에서 제외한다.
- 14일 만료 cleanup은 member 150명씩 최대 450 writes로 나눠 잔여 membership을 제거한 뒤 room tombstone을 삭제한다. tombstone `expiresAt`은 Firestore TTL이 아닌 scheduler due time이다.
- Firestore Rules는 활성 계정이 자신의 joinedRooms projection을 가진 경우에만 종료 tombstone 단건 read를 허용한다. 종료 방 Messages/media read와 모든 client lifecycle write는 계속 차단한다.
- iOS 참여중 목록은 활성 일괄 조회에서 빠진 room ID의 tombstone을 단건 복원한다. 종료 방을 별도 배지·색·subtitle·마지막 메시지 문구로 꾸미지 않고, 행 선택 시 안내 후 callable과 공통 local exit cleaner로 정리한다.
- 접속 중 화면은 Socket의 종료 유형/코드 payload를 Repository→UseCase→ViewModel→Coordinator로 전달해 확인 뒤 정리한다. 자기 방 삭제 creator는 알림 없이 기존 즉시 종료 흐름을 사용한다.
- 기존 Production `roomClosureNotices` read와 30일 TTL은 자연 만료 호환으로 유지한다. Phase 3.1 Production 배포는 수행하지 않았으며 별도 승인 게이트다.
- 자동 검증은 Functions lint/build·185/185, Socket check·70/70, Firestore·Storage Rules 40/40과 transaction 21/21, iOS targeted 10개와 `OutPick-Production` generic Simulator build, JSON parse·`git diff --check`를 통과했다. Functions의 기존 non-null assertion warning 9개만 남았다.

### Phase 3.1 Production rollout — 2026-08-10

- 배포 전 전체 원격 구성 감사에서 Firestore index는 로컬/원격 41개, field override·TTL은 29개로 양방향 차이 0건이었다. Storage Rules는 로컬과 일치했고 Firestore Rules 원격 hash는 배포 전 `HEAD`와 정확히 일치해 이번 Phase 3.1 변경만 차이였다.
- Functions lint/build를 재검증한 뒤 `acknowledgeRoomClosure`를 신규 생성하고 `closeOwnedChatRoom`, `closeRoomByModeration`, `onModerationRoomCleanupQueued`, `drainChatModerationCleanupJobs`를 exact target으로 업데이트했다. 5개 모두 asia-northeast3 Node.js 24 Gen 2, hash `793eb4c2cbdaee4f6c57751deb9e3834537b83f4`, `ACTIVE`다.
- Firestore Rules dry-run compile 뒤 rules만 배포했다. 새 ruleset은 `d1a9ab22-d85b-4794-964c-8a9b9bc1197c`, SHA-256 `5a298ab24098dc44179c805cde4720f4de5d807ee5f4f2222789fa551e9e8865`이며 로컬 source와 일치한다. 이전 ruleset `943f0af9-d161-4f2c-ac01-cf376a4631b6`은 rollback 기준이다.
- Firestore index/TTL과 Storage Rules, Socket, iOS 앱 artifact는 배포하지 않았다. 사후 감사에서도 index 41개·field override 29개는 양방향 차이 0건이고 Storage Rules ruleset은 그대로다.
- cleanup scheduler `firebase-schedule-drainChatModerationCleanupJobs-asia-northeast3`는 `ENABLED`, `every 5 minutes`, `Asia/Seoul`이다. 배포 대상 5개 Cloud Run service의 최근 30분 severity ERROR 로그는 0건이다.
- 실제 방장/관리자 종료와 앱 확인을 포함한 Production 데이터 QA는 아직 수행하지 않았다.

### Phase 3.1 Production 방장 종료 QA 보정 — 2026-08-11

- 오프라인 방장 삭제는 일반 목록 행, 선택 시 방 이름 안내, 확인 후 제거와 재실행 중복 없음까지 통과했다.
- 접속 중 방장 삭제는 실시간 안내와 확인 cleanup은 동작했지만, 확인 뒤 현재 채팅 route가 남는 navigation 결함을 발견했다. `ChatCoordinator`가 원래 목록 이전의 non-chat stack만 남기도록 route 정리를 소유하게 수정했다.
- 기존 Socket `room:leave-or-close`의 즉시 `room:closed` payload에 종료 유형이 없어 제목과 fallback 본문이 중복됐다. 방장 종료 payload에 `closedByOwner`/`ownerDeleted`를 포함하고, 유형을 알 수 없는 fallback은 본문 없이 제목만 표시하도록 수정했다.
- Socket check·70/70, iOS navigation/종료 문구 대상 10/10과 Production-Debug generic Simulator build가 통과했다.
- 사용자 승인으로 Socket Cloud Build `a97273b4-46b5-4134-a82f-39a95e9b8eb0`, image digest `sha256:29ddb169d993b5623fe3f7a9b8cf5bf2ac3ac2d508275a35604e7b47598ae379`를 생성했다. revision `outpick-socket-p31-owner-close-0811`, tag `p31-owner-close-qa`를 0% candidate로 배포해 `/readyz` 성공과 Ready/Active/ContainerHealthy, ERROR 0을 확인했다.
- 검증 뒤 `outpick-socket-p31-owner-close-0811`을 Production traffic 100%로 전환했다. canonical `/readyz`는 정상이며 직전 `outpick-socket-account-cap-v2-0810`은 0% rollback revision으로 보존한다. 이번 배포에서 Functions·Firestore Rules/Indexes·Storage Rules는 변경하지 않았다.
- 접속 중 방장 삭제의 목록 복귀는 변경된 iOS 앱을 재빌드해 재확인해야 한다. 접속 중·오프라인 관리자 종료 QA도 아직 남아 있다.

### Phase 3.1 Production 방장 종료 중복 안내 재보정 — 2026-08-11

- 재QA에서 이전 형식으로 보이는 첫 안내가 자동으로 사라진 뒤 최종 안내가 다시 뜨고, 확인 후에도 채팅 화면이 남는 현상을 확인했다. 원인은 방장 종료 Socket handler와 cleanup watcher가 모두 `room:closed` side effect를 소유하고 iOS가 동일 방 종료를 다시 publish·present할 수 있었던 구조다.
- Socket handler는 방장 종료 ACK만 반환하고, cleanup job의 유형·코드·lifecycle version을 가진 `roomClosureWatcher`만 emit·registry 제거·socket leave를 수행하도록 단일화했다.
- iOS `RealtimeAuthoritativeRoomClosureState`와 `ChatRoomClosurePresentationState`가 같은 방 종료의 최초 한 건만 전달·표시한다. 확인 탭은 로컬 방 제거와 Coordinator route 정리를 즉시 실행하고 `acknowledgeRoomClosure`는 백그라운드에서 멱등 처리한다.
- Socket check·70/70, iPhone 17 Pro의 `RealtimeSocketListenerBinderTests`·`ChatNavigationStackPolicyTests`, `OutPick-Production` generic Simulator build와 `git diff --check`를 통과했다. 실제 안내 1회·즉시 목록 복귀 수동 QA는 새 Socket 배포와 앱 재빌드 뒤 수행한다.
- 사용자 승인으로 Cloud Build `74f8b018-1b4c-46ea-97de-9a226518d257`, image digest `sha256:7cb2082aea3755a9f7bb395551bfe499cf0dfbb787e590a530a15e7103738fda`를 생성했다. revision `outpick-socket-p31-close-dedupe-0811`, tag `p31-close-dedupe-qa`를 0% candidate로 배포해 readiness와 Ready/Active/ContainerHealthy, ERROR 0을 확인했다.
- 검증 뒤 새 revision을 Production traffic 100%로 전환했다. canonical `/readyz`는 정상이고 전환 후 ERROR 0이며, 직전 `outpick-socket-p31-owner-close-0811`은 0% rollback으로 보존한다. Functions·Firestore Rules/Indexes·Storage Rules는 변경하지 않았다.
- 사용자 재QA에서 접속 중 방장 삭제 안내가 정확히 한 번 표시되고, 확인 즉시 기존 오픈채팅/참여중 목록으로 복귀함을 확인해 해당 항목을 통과 처리했다.

### Phase 3.1 Production 관리자 실시간 종료 목록 즉시 제거 보정 — 2026-08-11

- `QA 관리자 실시간 0811` 관리자 종료에서 Google/Kakao 모두 안내 1회와 문구·목록 복귀는 통과했지만, Google 참여중 목록은 확인 직후 종료 방을 유지하고 pull-to-refresh 뒤에만 제거되는 타이밍 결함을 확인했다.
- 원인은 Coordinator가 route를 먼저 복귀한 동안 background acknowledgement보다 `JoinedRoomsViewModel.start()`의 stale fetch가 먼저 끝나 종료 tombstone을 메모리 목록에 복원하고, 오프라인 tombstone 보존을 위한 일반 session-store prune이 종료 방을 의도적으로 제외한 구조였다.
- `ChatRoomClosureListUpdating`을 retained 오픈채팅/참여중 목록 컨트롤러에 연결해 전환 전에 room을 즉시 제거한다. 참여중 목록은 `realtimeRemovedRoomIDs`로 같은 세션의 stale fetch 재삽입도 막되, 미확인 오프라인 tombstone 표시 계약은 변경하지 않았다.
- `JoinedRoomsClosureNoticeTests` 3개와 `OutPick-Production` Production-Debug generic Simulator build, `git diff --check`를 통과했다.
- 변경 앱 재QA에서 Google/Kakao 모두 안내 1회, 정확한 문구, 확인 즉시 목록 복귀, pull-to-refresh 없는 종료 방 제거를 통과했다. 사후 Production 감사에서도 대상 room `RkIbYgW7eAHUkhYKxbsF`는 `closedByModeration`/lifecycle version 2 tombstone, cleanup job은 `awaitingExpiry`/`retention`, member·roomState 문서는 각각 0건으로 수렴했고 관련 Function·Socket ERROR는 0건이었다.

### Phase 3.1 Production 관리자 오프라인 종료 확인 즉시 제거 보정 — 2026-08-11

- `QA 관리자 오프라인 0811`에서 Google 계정이 종료 안내를 확인한 뒤 행이 서버 acknowledgement 왕복을 마친 다음 사라지는 지연을 확인했다. 원인은 `JoinedRoomsViewModel.acknowledgeClosedRoom`이 서버 우선으로 처리한 뒤 local 목록을 제거한 구조였다.
- 확인 탭 즉시 행을 optimistic 제거하고 같은 세션 stale fetch를 차단하도록 실시간·오프라인 local confirmation 집합을 통합했다. 서버 실패 시 제거 전 목록·unread·notice를 복원해 재시도 가능하게 한다.
- `JoinedRoomsClosureNoticeTests` 5개가 iPhone 17 Pro Simulator에서 통과했다. Google은 기존 QA 방 acknowledgement가 이미 완료됐으므로 변경 앱 재빌드 뒤 새 방으로 오프라인 관리자 종료를 먼저 재확인해야 한다.
- 변경 앱을 iPhone 17 Pro/Pro Max에 설치하고 새 Production 방 `QA 관리자 오프라인 재확인 0811`(`nmWv0fnBbRkheIkocPcR`)을 종료했다. 종료 전 active lifecycle v1·member 2·eligible platform admin 1을 확인했고, 종료 뒤 `closedByModeration` lifecycle v2와 콘텐츠 정리·membership 보존을 확인했다.
- Google과 Kakao를 순서대로 실행해 양쪽 모두 일반 행 표시, 방 이름 포함 안내 1회, 확인 즉시 행 제거, 재실행 시 행·안내 미복원을 통과했다. Google 확인 뒤 member/joinedRooms가 정확히 1건씩 남았고 Kakao 확인 뒤 Production Auth 2개 전체 기준 member/joinedRooms/roomStates가 0건으로 수렴했다.
- cleanup job은 `awaitingExpiry`/`retention`, `nextAttemptAt`은 `closedAt` 정확히 14일 뒤이며, QA 시간대 `closeRoomByModeration`·`acknowledgeRoomClosure`·cleanup 관련 Production ERROR는 0건이다. 이로써 Phase 3.1 Production 수동 QA를 완료했다.
## Phase 4 전역 사용자 차단 로컬 구현 — 2026-08-11

- 확정 정책을 `decisions.md`, `plan.md`, `qa-checklist.md`, exact JSON 계약, ADR-024와 공용 entrypoint/data 문서에 반영했다. 채팅 current-window 세션 유지, blockedAt 없는 admission 시점 UID Set 판정, 룩북 즉시 숨김, 참여자·프로필 유지, 차단자에게만 해제 안내, 최신 계약 단일 cutover로 통일했다.
- Functions `blockUser`를 exact contract·자기 차단 거부·최초 createdAt 보존으로 보강하고 멱등 `unblockUser`를 추가했다. Lookbook hidden author 조회에서 blocking-me 역방향 relation을 제거했다.
- 앱 공용 `UserBlockVisibilityStore`/계정별 snapshot/`UserBlockSessionController`를 App bootstrap과 DI에 연결했다. cache → 서버 교체, cache 없는 서버 실패 fail-closed, mutation 성공 뒤 메모리·snapshot 갱신, 로그아웃 clear를 구현했다.
- Chat은 Socket ordering 뒤 live admission, 초기/이전/이후 pagination, 검색, 주변 window, reply, 사용자 공지, room preview/unread, banner, media gallery에서 같은 Store를 적용한다. current window와 GRDB/FTS/media 원문은 소급 정리하지 않고 hidden seq와 raw cursor는 소비한다. 긴 hidden 구간은 UI 요청당 원본 3 page로 제한한다.
- 프로필/메시지 메뉴 차단과 MyPage 차단 해제 목록을 연결했다. 차단 해제는 열린 방을 강제 reload하지 않는다. 룩북은 단방향 relation으로 현재 댓글·답글을 즉시 숨긴다.
- 현재 Chat에는 멘션·사용자 초대 기능 진입점이 없어 실제 존재하는 직접 상호작용인 답장에 해제 가드를 적용했다. 후속 멘션·초대는 같은 `UserBlockVisibilityStore` 가드를 재사용해야 한다.
- Socket push fan-out은 recipient blockedUsers relation을 전송 직전에 확인하며 조회 실패도 해당 recipient에 fail closed한다. Socket room broadcast는 유지한다.
- Firebase/Socket/iOS의 Development·Production 배포와 운영 데이터 mutation은 수행하지 않았다.
- 자동 검증은 Functions lint/build·188/188, Socket check·72/72, `OutPick-Development` generic Simulator build, iOS block session/action policy/GRDB migration·store/media dedupe 대상 suite, JSON parse와 `git diff --check`를 통과했다. Functions의 기존 non-null assertion warning 9개와 iOS 기존 warning은 남아 있다.

### Phase 4 Production rollout·두 계정 QA — 2026-08-11

- 배포 직전 Functions lint/build·188/188과 Socket check·72/72를 다시 통과했다. Functions lint는 기존 non-null assertion warning 9개, Socket image audit는 기존 moderate 8개만 남았고 high/critical은 0개다.
- `blockUser`, `unblockUser`만 exact target으로 `outpick-664ae`에 배포했다. 두 Function은 asia-northeast3 Node.js 24 Gen 2 `ACTIVE`이며 배포 직후 severity ERROR 로그는 0건이다. Firestore Rules/Indexes와 Storage Rules는 변경하지 않았다.
- Cloud Build `9affa13a-d5a5-4770-b7fd-ec1a341994aa`로 Socket image `sha256:42180bd7eca45c4bb4a9d29a51f63179bd889b31f5f334305cc7d2022c1ea17d`를 생성했다. revision `outpick-socket-p4-block-0811`, tag `p4-block-qa`를 0% candidate로 배포해 readiness·Ready/Active/ContainerHealthy·ERROR 0을 확인한 뒤 Production traffic 100%로 전환했다. 직전 `outpick-socket-p31-close-dedupe-0811`은 0% rollback revision이다.
- `OutPick-Production`을 iPhone 17 Pro Max/Pro Simulator 두 대에 빌드·설치해 기존 Production 내부 계정 두 개로 QA했다. QA 방 `40811`에서 차단 전 메시지 `1111`은 차단 성공 직후 현재 window에 유지됐고, 차단 뒤 상대가 보낸 `2222`는 실시간 화면에 admission되지 않았다.
- 차단 뒤에도 상대 사용자가 참여자 목록에 남아 membership과 visibility 차단이 분리됨을 확인했다. MyPage 차단 사용자 목록에는 상대가 표시됐고, 차단 해제 성공 즉시 목록이 비워졌다.
- 차단 해제 직후 열린 채팅 화면의 강제 원격 재조회는 수행하지 않았다. 방을 나갔다 다시 열자 차단 중 숨겨졌던 `2222`가 일반 동기화로 복원됐고, 이후 상대가 보낸 `3333`도 실시간 수신됐다.
- 답장 동작은 차단 상태에서 진행되지 않았고 action policy와 화면 구현이 `먼저 차단을 해제해 주세요` 안내 계약을 사용함을 확인했다. 짧은 토스트의 접근성 캡처와 실제 기기 background FCM/APNs 제외는 Apple Developer Program 가입 후 출시 전 외부 gate에서 확인한다.
- QA 종료 시 방장 계정이 `40811` 방을 종료했고 다른 계정에 종료 안내가 도착해 QA 방이 정리됐음을 확인했다. 차단 관계도 해제해 차단 목록을 빈 상태로 복원했다.

### Phase 4 오프라인 visible unread 보정 — 2026-08-11

- 앱이 실행되지 않은 동안 차단 사용자와 정상 사용자의 메시지가 함께 누적되는 경우를 위해 `ChatVisibleUnreadUseCase`를 추가했다. 참여방 projection의 `lastReadSeq`부터 목록 fetch 시점의 `latestSeq`까지 원본 메시지를 page 단위로 조회하며 본인·삭제·현재 차단 UID의 메시지를 제외해 방별 visible unread와 최신 visible preview를 계산한다.
- `JoinedRoomsViewModel`은 초기에는 기존 raw unread를 보수적으로 표시하고 보정 성공 방만 정확한 visible unread로 교체한다. 보정 실패 방은 raw unread를 유지하며 차단 작성자의 room preview는 노출하지 않는다. 전역 seq, 다른 참여자의 ordering, 서버 `lastReadSeq`는 변경하지 않는다.
- `ChatVisibleUnreadUseCaseTests`에서 혼합 발신자 pagination, 전부 숨김, 고정 latestSeq, ViewModel 성공 교체와 실패 fallback을 검증했고 `JoinedRoomsClosureNoticeTests` 회귀도 함께 확인한다.

### Phase 4 Production 앱 종료 혼합 unread QA — 2026-08-11~12

- `OutPick-Production` 최신 빌드를 iPhone 17 Pro/Pro Max Simulator에 설치하고 기존 Production Google·Kakao 내부 계정으로 신규 QA 방을 생성·참여했다. 수신 계정의 `lastReadSeq=1`을 확인한 뒤 앱 프로세스를 종료하고 상대 계정을 차단했다.
- Production Auth가 기존 두 계정뿐이어서 비차단 제3자 계정을 만들지 않았다. 차단 계정이 Socket으로 보낸 `seq=2` 메시지와 QA 방에만 Admin SDK로 추가한 비차단 합성 발신자 `seq=3` 메시지를 함께 누적해 실제 Firestore pagination 경로를 검증했다.
- 수신 앱 재실행 후 참여방 목록은 raw unread `2`가 아니라 visible unread `1`과 비차단 preview `3003`을 표시했다. 방 재진입에서는 `3003`만 표시되고 차단 계정의 `1001`·`2002`는 모두 admission되지 않아 앱 종료 중 혼합 메시지 보정을 통과했다.
- QA 종료 후 방·Messages 3건·members·두 계정 joinedRooms/roomStates projection·QA 차단 relation·`rooms/{roomID}/` Storage prefix를 삭제했다. 사후 감사는 Production Auth 2명 유지, room/projection/roomState/cross-block/Storage 잔존 모두 0건을 확인했고 앱 재실행 목록에서도 QA 방 미복원을 확인했다.

### Phase 4 최종 리뷰·검증 — 2026-08-12

- 최종 리뷰에서 이전 계정의 bootstrap 원격 실패가 늦게 도착해 새 계정의 visibility Store를 비울 수 있는 경쟁 조건을 발견했다. 실패 처리 전에 active user를 다시 확인하고, 지연 실패와 계정 전환을 재현하는 회귀 테스트를 추가했다.
- hidden `seq=11` 뒤 visible `seq=12`가 이어질 때 visible-only 연속 계산이 10에서 멈추는 결함을 발견했다. 현재 window의 visible seq와 admission된 hidden seq의 합집합으로 read frontier 연속 구간을 계산하도록 보정하고 테스트를 추가했다. 서버 seq와 다른 참여자 ordering은 변경하지 않는다.
- 룩북 댓글 프로필이 차단 UseCase/Store를 주입받지 않아 서버 호출 없이 UI만 `차단됨`으로 바뀔 수 있는 경로를 발견했다. Lookbook Container의 공용 UseCase/Store를 프로필 SwiftUI/UIKit bridge까지 전달하고 의존성 누락은 오류로 처리하도록 보정했다.
- Functions lint/build·188/188, Socket check·72/72, Phase 4/GRDB/closure iOS 대상 suite와 `OutPick-Production` generic Simulator build, `git diff --check`를 통과했다. Functions 기존 non-null assertion warning 9개와 iOS 기존 migration/AppIntents warning만 남았다.

### Phase 5 Production 두 계정 앱 QA — 2026-08-12

- iPhone 17 Pro/Pro Max의 기존 로그인 세션을 유지한 채 최신 `OutPick-Production` Production-Debug 빌드를 덮어 설치했다. 빌드는 성공했고 기존 경고 9개만 남았다.
- QA 방 `08121825`에서 B 검색·명시적 참여, B→A `222222`, A→B `111111` 실시간 수신을 확인했다. A가 B를 `spam` 사유로 내보내자 B 화면은 즉시 `재입장이 제한된 채팅방입니다` 읽기 전용 상태로 전환되고 입력·첨부 UI가 제거됐다.
- B는 검색에서 active 방을 다시 찾고 두 baseline 메시지를 읽을 수 있었지만 참여·쓰기는 계속 차단됐다. A의 제한 목록에는 ban 시점 표시명 `AD`만 나타났고 내부 식별자·email은 노출되지 않았다.
- A가 unban한 뒤 B membership은 자동 복원되지 않았다. 열린 B 화면의 참여 버튼은 즉시 갱신되지 않았으나 앱 완전 종료·재실행 뒤 `채팅 참여하기`가 복원됐고, 명시적 재참여와 `333333` 전송이 성공했다. 이 재시작 의존 UI 갱신은 후속 UX 보정 후보다.
- A의 방장 나가기로 방을 종료하고 B의 방 이름 포함 종료 안내 1회를 확인했다. 확인 뒤 Production 감사는 active room 0, member/active ban/메시지/mediaIndex/projection/block/Storage object 0, succession job 0으로 수렴했다. `closedByOwner` tombstone과 `awaitingExpiry` cleanup job은 14일 보존 계약대로 남았다.
- remove/unban/owner close 감사 로그에는 canonical action과 `spam`/`ownerUnban`/`ownerDeleted`만 남고 email·provider subject·자유 입력은 없었다. Functions 7개 `ACTIVE`, Socket Phase 5 revision traffic 100%, scheduler `ENABLED`, QA 시간대 관련 ERROR 0을 재확인했다.
- 22KB Simulator 녹화 영상은 대용량 pending upload를 재현하지 못해 pending upload 취소와 같은 provider 로그아웃/로그인은 보류했다. 앱 완전 종료·재실행의 ban 유지와 unban 후 참여 복원은 확인했다.

### Phase 5 Production pending 동영상 보충 QA — 2026-08-12

- 사용자가 `Test Room`에서 iPhone 17 Pro Max 일반 참여자의 대용량 동영상 업로드 중 iPhone 17 Pro 방장이 해당 참여자를 내보냈다. 업로더 화면에는 `업로드 실패 — 서버 ACK 실패 또는 timeout` 안내 후 `재입장이 제한된 채팅방입니다`가 표시됐다.
- 업로더 앱 완전 종료·재실행 뒤 GRDB `chatOutgoingOutbox`는 0건이고 `ChatOutgoingOutbox` 보존 영상 파일도 없었다. Production에는 matching 확정 메시지가 없는 pending video reservation 1건과 부분 Storage 객체가 남았지만, 재실행 전후 메시지·예약·객체 수와 총 bytes가 증가하지 않아 자동 재시도는 없었다. 잔존 예약·객체는 다음 날 만료 scheduler 또는 방 종료 cleanup 대상이다.
- 서버는 ban 대상 member/joinedRooms/roomState 0, room memberCount/member 1, active principal ban 1로 수렴했다. 기존 완료 동영상과 텍스트는 방 재진입에서 계속 읽혔다.
- 재실행·방 재진입 뒤 active ban인데도 `채팅 참여하기`가 노출되는 UI 결함을 발견했다. 탭 뒤 서버는 fail-closed해 membership/projection·메시지·Storage가 변하지 않았지만 실패 안내 없이 메시지 목록이 비었다. 서버 보안 계약은 통과하며 클라이언트의 non-member 진입 시 ban 상태 재조회와 join 거부 오류 표시를 보정해야 한다.
- `getMyRoomAccess` 보정 배포와 최종 Production-Debug 앱 설치 후, iPhone 17 Pro Max의 내보낸 Google 계정을 로그아웃하고 같은 Google 계정으로 재로그인했다. `Test Room` 기존 텍스트·완료 동영상 읽기는 유지되고 입력·첨부 없이 `재입장이 제한된 채팅방입니다`가 표시됐다. 사후 Production 읽기 전용 감사도 방장 member 1·active ban 1, 대상 member/joinedRooms/roomState 0으로 불변이어서 같은 provider 재로그인 우회 차단을 통과했다.
- 사용자가 후속 실앱 QA 1~8을 완료해 메시지 long press 내보내기, 참여자 프로필/별도 관리 버튼, 사용자 친화적 upload 중단 안내, unban 뒤 명시적 재참여·양방향 메시지, 방 종료와 미완료 media/local retry 정리까지 확인했다.
- 후속 UX로 기존 action sheet 목록을 독립 `차단 사용자` 화면으로 교체하되 진입점은 방 설정 하단 나가기 옆 방장 전용 버튼으로 유지했다. 독립 화면은 패션 매거진의 accent eyebrow·serif 제목·hairline 목록, `Default_Profile`, 안전한 snapshot/사유/시각, pagination·retry·빈 상태와 확인 후 `해제`를 제공한다. 메시지와 참여자 관리 액션은 `내보내기`, owner 종료 안내는 `방장이 채팅방을 종료했어요.`로 통일했다. 뒤로 가기는 독립 화면만 닫아 설정 패널로 복귀하며 방 이름 부제는 제거했다.
- 신규 `ChatRoomBannedUsersViewModelTests` 3개와 `ChatMessageActionPolicyTests`·`JoinedRoomsClosureNoticeTests`를 합친 13/13, `OutPick-Production` Production-Debug Simulator build, `git diff --check`를 통과했다. 기존 QA 방은 사용자 확인 뒤 이미 종료·정리돼 독립 화면의 실제 목록/빈 상태 시각 QA는 새 fixture를 만들지 않고 다음 방장 QA 때 확인한다.
- 사용자는 후속 방장 QA에서 위 피드백 항목을 제외한 나머지 화면·강퇴/해제·종료 문구 흐름을 모두 확인했다.
## Phase 7.3 일반 동영상 실패 팝업 제거 — 2026-08-20

- 이미지 실패 경로와 달리 `ChatViewController.uploadPendingVideoMessage`의 일반 오류 catch에만 `동영상 전송 실패` 전역 팝업이 남아 있음을 확인했다.
- 일반 영상 실패는 팝업을 표시하지 않고 기존 실패 버블의 재시도·삭제 액션으로만 복구하도록 통일했다. room access 재확인 결과 ban인 경우의 `채팅방 참여가 제한되어 전송을 중단했어요.` 안내는 유지했다.
- `ChatPendingMediaUploadStoreTests` 8개와 `ChatOutgoingOutboxUseCaseTests` 9개가 통과했고, iPhone 14 대상 Development 서명 빌드와 설치를 완료했다. 사용자가 일반 동영상 실패 시 별도 팝업 없이 버블의 재시도·삭제만 표시되는 것을 확인해 해당 QA를 완료했다.

## Phase 7.3 영상 앱 종료·방 화면 이탈 QA 완료 — 2026-08-20

- 사용자가 큰 영상 전송 중 앱 종료·재실행 및 채팅방 화면 뒤로 이탈·재진입 시나리오를 확인했다.
- 재진입 뒤 실패 팝업이나 왼쪽 실패 표시 없이 서버에서 이미 완료된 경우 조용히 성공하고, 미완료 작업은 자동 파일 PUT 재개 없이 재시도·삭제 상태로 수렴했다. 중복 영상 메시지는 생성되지 않았다.
- 명시적 완료 기준인 분할/FIFO, capacity 동일 identity 대기, waiter·turn 반환, 앱 재실행 silent pending/status reconciliation, cancel/ready 경합과 7일 보존은 자동 검증과 실기기 QA로 충족했다. 정확한 350 MiB 경계·길이 제한 없는 장시간 영상 실파일과 실패 액션 확인창의 시각 점검은 Production 전 확장 QA로 분리하고 Phase 7.3을 완료 처리했다.

## Phase 7.4A evidence 순수 계약 로컬 구현 후 설계 변경 — 2026-08-20

- 최초 로컬 구현은 `moderation/media/contracts.ts`에 선택 attachment 1...30개·video timestamp 입력, 결정적 signal/reporter/bundle/object identity, 긴급 2명·일반 3명 threshold와 retention 계산을 추가했고 Functions lint/build 및 targeted 14/14를 통과했다.
- 이후 사용자 결정으로 attachment 선택·video timestamp·신고 직후 자동 개인 숨김을 폐기했다. 최신 계약은 텍스트·미디어 공통 메시지 전체 evidence, 일반 단일 `holding`, 같은 메시지 고유 2명 `reviewRequired`, 기한 경과 holding 직접 조회, 같은 작성자 서로 다른 메시지 3개 + 전체 고유 신고자 2명/7일, 긴급 단일 `urgent`, 긴급 2명 또는 전체 사유 3명의 24시간 전역 비노출이다. 별도 queue projection/scheduler는 없고 삭제 우선 신고는 저장하지 않는다.
- 사용자 승인으로 폐기된 최초 7.4A Functions WIP와 신규 media contract/test를 제거해 Phase 7.3 이후 committed baseline으로 복원했다. 이전 검증 통과 이력은 역사 기록일 뿐 최신 설계 구현 완료를 의미하지 않는다. Phase 7.4A는 최신 계약 기준 설계 확정·구현 미착수이며 bucket 생성·IAM·Rules·배포도 수행하지 않았다.

## Phase 7.4A evidence-first 순수 계약 완료 — 2026-08-21

- 후속 설계 논의에서 신고 성공 의미를 `evidence available`로 강화했다. `processing`은 server-only preparation/request receipt/guard/bundle/job만 만들고 count·queue·작성자 패턴·visibility에 포함하지 않으며, text snapshot 또는 전체 media evidence 확보 뒤에만 `accepted`를 확정한다. 응답 유실·앱 종료 뒤 같은 요청은 durable receipt, 새 clientRequestID는 semantic preparation과 결정적 bundle을 재사용한다. accepted 뒤 재신고는 `alreadyReported`, terminal failed cleanup 뒤 재신고는 새 준비를 허용한다.
- `functions/src/moderation/messageEvidence/contracts.ts`에 domain/version canonical tuple SHA-256 기반 incident/reporter/preparation/submission/bundle/copy·cleanup job ID, 최초 revision 0과 terminal reopen, report/evidence/job 상태·전이, queue 비강등, 24시간 고유 reporter 전역 비노출, 7일 `3 messages + 2 reporters`, 처리 결과별 retention·appeal/legal hold를 구현했다.
- `contracts.test.ts` 12개가 exact golden ID, processing/accepted 효과 분리, 긴급/전체 임계치와 24시간·7일 경계, distinct message/reporter, 30일 retention과 상태 전이를 검증한다. Functions 전체 226/226, build, lint 오류 0, `jq empty contracts/chat-moderation-v1.json`, `git diff --check`가 통과했다. lint의 기존 moderation non-null assertion 경고 17개는 이번 범위와 무관하다.
- 계약·DATA_SCHEMA·ADR·ENTRYPOINTS/FIREBASE/TESTS·계획/QA 문서를 최신화했다. Firestore transaction, Storage copy/cleanup, Rules/index, iOS `신고 처리 중` 화면, bucket/IAM과 Development/Production 배포는 수행하지 않았으며 Phase 7.4B 이후 범위다.
