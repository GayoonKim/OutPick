# OutPick Handoff

## 1. 최종 목표

- 현재 핵심 task `chat-ugc-safety-room-moderation`은 Phase 0~7 구현·자동 검증·Development 공동 QA와 Production backend rollout을 완료했다. Phase 7.5 통합 PR #22 merge commit `951333cae0f37f6f395f7aade41e6d64e8650b6e`가 `main`에 반영됐고, 2026-08-28 Production Rules/index/TTL·Functions·Evidence 최소 IAM/감사·Socket 100% 전환과 사후 감사를 마쳤다. Production message/deletion/evidence 데이터가 0건이라 migration은 수행하지 않았다. TestFlight/App Store 출시는 별도 단계다.
- 실제 기기 background FCM/APNs 검증은 Apple Developer Program 가입·APNs 설정 후 수행하는 출시 전 외부 gate이며 Phase 4 완료를 막지 않는다.
- Sign in with Apple은 현재 iOS 로그인 진입점이 없어 사용자 결정으로 별도 후속 작업으로 분리했다. Production moderation rollout과 개인정보 보존 gate도 Phase 1 Development 완료와 분리한다.
- 핵심 task `lookbook-extraction-issue-operations-production-rollout`은 Production 읽기 전용 감사, contract 3 Worker candidate QA·traffic 100% 전환, backend prerequisite/Functions, exact Firestore rules, canonical 앱 E2E, 앱 원문 오류 문구 교정, QA·legacy cleanup까지 완료해 2026-08-06 종료했다.
- 이전 `lookbook-extraction-issue-operations`도 Phase 1~7 구현, Development contract 3 배포와 AMOMENTO/OUTSTANDING 실데이터 QA 완료로 종료 상태다.
- 하나의 Xcode 프로젝트와 app target을 유지하면서 Development 앱은 `GayoonKim.OutPick.dev`와 `outpick-test`, Production 앱은 `GayoonKim.OutPick`과 `outpick-664ae`를 사용한다.
- 잘못된 Bundle ID·Firebase plist/project·Socket 조합은 build-time과 runtime에서 fail closed 처리한다.
- Development 앱은 `OutPick DEV`로 표시하고 Production 앱과 같은 기기에 동시에 설치할 수 있어야 한다.
- Development는 제한 모드가 아니라 현재 앱의 수동 QA가 가능한 Functions·Rules·Indexes·Storage·Socket 기능 동등성을 목표로 한다. 외부 배포는 각 범위 감사와 사용자 승인 뒤 진행한다.
- 코드·설정·백엔드·배포 계약 기준의 Development/Production 환경 분리는 PR #3 병합, Production Worker traffic 전환과 실제 import smoke까지 완료해 종료 처리했다.

## 2. 완료한 작업

### Development 상대 프로필 이미지 Storage Rules drift 교정

- 2026-08-28 Production에서는 정상인 채팅 메시지·채팅방 설정 참여자 목록의 상대 프로필 이미지가 Development에서 표시되지 않는 현상을 진단했다. 두 화면은 `userPublicProfiles.avatarThumbPath`와 공용 `AvatarImageService`를 사용한다.
- Development/Production의 Firestore Rules는 로컬 hash와 일치했고, Development 공개 프로필·active `users`/`moderationAccounts` projection·avatar thumbnail 객체도 2/2 존재했다. 직접 원인은 Development 기본 bucket의 Storage Rules만 구버전 hash `78ebf3d161284be1ac3aa4ff4c3a5a86ad4d325287ebefaa79fa36c0e32b94d1`로 남은 배포 drift였다.
- 구버전 cross-user avatar read는 요청자의 `users`·`moderationAccounts`와 대상자의 `users` 세 문서를 참조해 Storage Rules의 Firestore 문서 접근 한도 2개를 초과했다. 최신 Rules는 요청자/대상자의 `moderationAccounts` 두 문서만 사용해 account capability와 대상 active 상태를 확인한다.
- profile Storage Rules emulator 5/5를 통과한 뒤 `outpick-test` 기본 Storage target만 배포했다. 새 ruleset `c44c38b3-713f-49b8-9db2-814d73a15dcd`, source SHA-256 `712a87a7d47b8bc9c8c77b146cd453df65846ecf231b943b24ec7f41a19966c4`로 로컬·Production과 일치하며, 사용자 재확인에서 두 Development 화면의 상대 프로필 이미지가 정상 표시됐다. Firestore·Production·앱 코드는 변경하지 않았다.

### Chat UGC Safety Phase 7 — Production backend rollout 완료

- 2026-08-28 `main`이 PR #22 merge commit `951333cae0f37f6f395f7aade41e6d64e8650b6e`와 정확히 일치함을 확인하고 Production 읽기 전용 감사를 수행했다. message·삭제 tombstone·deletion delivery·Evidence 관련 데이터가 모두 0건이라 migration은 만들거나 실행하지 않았다.
- Firestore Rules와 전체 index manifest를 배포해 rules source hash 일치, composite 61/61 `READY`, TTL field 22/22 `ACTIVE`를 확인했다. 신규 `chatMessageDeletionDeliveryJobs.expiresAt`, `moderationMessageReportPreparations.expiresAt`도 `ACTIVE`다. Evidence 전용 deny-all Storage Rules도 로컬 source hash와 일치한다.
- 관리자 조회/처리·Evidence copy/cleanup/drain·신고·삭제·탈퇴 finalizer·media ready trigger의 exact Function 11개를 배포했고 모두 Node.js 24 `ACTIVE`다. Evidence worker/viewer는 분리된 최소 권한 service account를 사용하고, drain은 5분마다, 탈퇴 finalizer는 매시간 Asia/Seoul에서 `ENABLED`다. 배포 후 관련 ERROR는 0건이다.
- 서울 Evidence bucket은 UBLA·PAP enforced·soft delete 0·versioning off이며 운영자에게 object read를 주지 않고 worker object manager·viewer object reader만 부여했다. 프로젝트 Firestore/Eventarc/Logging와 viewer self-sign 권한도 exact custom role 경계로 확인했다.
- 서울 전용 Log Analytics bucket은 Storage DATA_READ와 앱 발급 audit만 수집하고 `_Default`는 앱 audit과 모든 GCS DATA_READ를 제외한다. 격리 임시 admin/Auth/App Check·68-byte PNG fixture로 실제 callable 200, 5분 exact-generation V4 GET 200, Range 206와 `private, no-store, max-age=0`을 확인했다. 같은 opaque issuanceID의 앱 audit 1건·Storage GET 2건이 전용 view에 연결되고 `_Default`는 0건이었다. 임시 Auth/Firestore/Storage/rate bucket 잔여 0을 확인한 뒤 감사 bucket을 `ACTIVE`·Analytics·1,095일·`locked=true`로 영구 잠갔다.
- Socket image `p75-951333c-0828`, digest `sha256:56a538714aece8c4cf53d33acaea38e4d5fda0bc854976eed89877ae5cdd763e`, revision `outpick-socket-p75-del-0828`을 0% candidate로 검증한 뒤 100% 전환했다. canonical readiness 200과 실제 Firebase 인증 handshake, maxScale 1·concurrency 80·timeout 3,600초·runtime identity·quarantine bucket을 확인했고 새 revision ERROR는 0건이다. rollback revision은 0%의 `outpick-socket-p73-prod-0820`이다.
- 최종 사후 감사는 composite 61/61 READY, TTL 22/22 ACTIVE, Function 11/11 ACTIVE, scheduler 2/2 ENABLED, 관련 Function/Socket ERROR 0, Phase 7 message/deletion/evidence/job 잔여 0으로 종료했다. 앱 binary·TestFlight·App Store 출시는 수행하지 않았다.

### Chat UGC Safety Phase 7.6 — 열린 미디어·durable cache cleanup QA 완료

- 2026-08-28 사용자 공동 QA 완료 보고 기준으로, 삭제 대상 이미지 viewer와 video player가 열려 있는 동안 원본 메시지를 삭제했을 때 신규 미디어 read가 중단되고 열린 화면이 안전하게 닫힌 뒤 채팅의 기존 메시지 셀 tombstone으로 복귀하는 흐름을 확인했다.
- 미디어 삭제 직후 앱 강제 종료·재실행에서도 tombstone이 유지되고 durable cleanup queue가 재개돼 로컬 이미지·영상 파일과 Storage download URL cache 정리가 수렴하는 것을 확인했다.
- Phase 7.5F 공동 수동 QA의 열린 미디어 삭제와 durable cache cleanup을 완료 처리했다. 다음 실행 순서는 플랫폼 관리자 처리 → disposable 계정 탈퇴 bulk → 종료 감사 → 최종 자동 회귀 → 전체 diff 리뷰·수정 → 단위별 커밋 → PR·리뷰·차단 수정 → 최종 체크·머지다.

### Chat UGC Safety Phase 7.6 — 플랫폼 관리자 처리 QA 완료

- Development Auth 2명·provider별 eligible active 1명·active platform admin 0명을 사전 감사한 뒤 단일 Kakao 계정만 일시 승격했다. reviewable incident 2건 중 미디어 incident 정확히 1건을 선택해 실제 `resolveMessageModeration` callable에서 `violation + delete + none`으로 처리했다.
- 동일 request replay는 같은 결과와 audit 1건으로 수렴했다. incident `resolved/caseVersion 2`, message deletion revision 5·Room head 일치·sender 표시 보존, delivery `completed/attempt=1`, Evidence cleanup `succeeded/attempt=1`·bundle 잔여 0을 확인했다.
- Simulator 기존 Development 세션 재실행 뒤 방 목록 preview도 일반 `삭제된 메시지입니다` tombstone으로 반영됐다. Function/Socket ERROR는 0건이며 일시 Kakao admin은 회수해 provider별 active platform admin 0명으로 원복했다.
- 다음은 이미 생성한 별도 disposable 계정의 두 방·텍스트 2건·이미지 1건·답장 참조 1건을 사용하는 계정 탈퇴 bulk QA다. 첫 finalizer는 정상적으로 `verify/message_cleanup_pending`에서 retry 대기 중이며 cleanup 완료 뒤 재실행해야 한다.

### Chat UGC Safety Phase 7.6 — 계정 탈퇴 bulk QA 완료

- 별도 disposable password Auth 1개와 전용 방 2개에 텍스트 2건·이미지 1건, 기존 사용자 답장 참조 1건, mediaIndex·실제 ready Storage 객체를 구성했다. 기존 Google/Kakao QA 계정과 기존 방은 fixture 작성에 사용하지 않았다.
- 첫 finalizer는 tombstone과 cleanup job 생성 뒤 `verify/message_cleanup_pending`에서 retry 대기해 cleanup 전 완료 선언을 차단했다. cleanup 3건이 `completed/attempt=1`이 된 뒤 5분 backoff 재실행으로 요청 `completed/attemptCount 2`, Auth·user/moderation/profile 삭제와 request UID/generation scrub까지 완료했다.
- 작성 메시지 3건은 sender UID·아바타·원문·첨부를 제거하고 `알 수 없는 사용자`·전송 시각을 보존했다. 방별 revision은 0→2와 4→5, reply preview 삭제 scrub, mediaIndex·Storage 객체 0, 방별 delivery 2건 `completed/attempt=1`을 확인했다.
- 다음은 남은 텍스트 신고 incident를 `dismissed + keep + none`으로 종결해 Evidence를 정리하고, bulk QA 방·job·receipt·임시 marker를 제거한 뒤 전체 종료 감사를 수행하는 것이다.

### Chat UGC Safety Phase 7.6 — 공동 QA 종료 감사 완료

- 남은 text incident 1건은 실제 관리자 callable의 `dismissed + keep + none`으로 종결했다. replay 동일 결과·audit 1건, 원문 visible, Evidence cleanup `succeeded/attempt=1`, bundle 제거를 확인하고 일시 Kakao admin을 다시 회수했다.
- bulk QA 전용 방 2개와 관련 cleanup 3·delivery 2·notification 1·account deletion audit 1·suppression 1·guard 3·request 1·marker 1만 exact 제거했다. 기존 Auth 2명과 기존 채팅방은 보존했다.
- 최종 Development 상태는 Auth 2명, active platform admin 0, open incident 0, Evidence bundle/object 0, 관련 job non-terminal·failed 0, bulk QA marker/room/Storage 잔여 0이다. 영향 Function과 Socket ERROR도 0이다.
- deletion audit은 Rooms 4개·삭제 메시지 21건, revision 누락/reply/media 잔존/probe 실패 0, 삭제가 있는 방 3개 모두 max revision=Room head, delivery 11건 모두 completed다. Production은 변경하지 않았다.
- 다음은 최종 자동 회귀 검증 → 전체 diff 리뷰·수정 → 앱·테스트·Functions/Rules·Socket·문서 단위 커밋 → PR·리뷰·차단 수정 → 최종 체크·머지다.

### Chat UGC Safety Phase 7.6 — 최종 자동 회귀 완료

- Functions 245/245·build·lint 오류 0(기존 warning 24건), Rules·Storage 46/46, Firestore transaction 52/52, Socket check·103/103을 통과했다.
- iPhone 17 Pro Max iOS 26.2 Simulator에서 관련 10개 suite 66/66과 `OutPick-Development` Simulator build가 통과했다. 첫 실행에서 방 생성자의 타인 메시지 신고를 금지하던 과거 테스트 기대값 1건을 확정 정책인 `신고 + 삭제` 동시 허용으로 보정했고 해당 suite 16/16과 전체 66/66을 재통과했다.
- 계약/index JSON parse와 `git diff --check`가 통과했다. 다음은 전체 diff 리뷰·수정 → 앱·테스트·Functions/Rules·Socket·문서 단위 커밋 → PR·리뷰·차단 수정 → 최종 체크·머지다. Production은 변경하지 않았다.

### Chat UGC Safety Phase 7.6 — 전체 diff 리뷰·수정 완료

- 앱·GRDB·Functions/Rules·Socket·계약·하네스를 경계별로 검토했다. 삭제 admission의 중복 message ID 배열 크래시 위험을 tombstone·높은 revision 우선 병합으로 보정하고 회귀 테스트를 추가했다.
- 직접 닫힌 미디어 화면의 stale `ObjectIdentifier`가 재사용될 수 있는 위험은 약한 controller 참조 대조와 소멸 항목 정리로 보정했다. migration의 불필요한 `var`와 동기 메서드 `await`도 제거했다.
- 보정 후 GRDB deletion sync·migration 10/10, 관련 iOS 10개 suite 67/67과 Development Simulator build를 재통과했다. 차단 발견 사항은 남지 않았고, 다음은 앱·테스트·Functions/Rules·Socket·문서 단위 커밋 → PR·리뷰·차단 수정 → 최종 체크·머지다.

### Chat UGC Safety Phase 7.6 — 신고 화면 에디토리얼 UI 보정

- 공동 QA에서 신고 기능은 정상 동작했지만 화면만 UIKit 기본 폼 스타일로 남아 OutPick의 패션 매거진 디자인과 단절됐고, 상세 입력 중 화면의 다른 영역을 탭해도 키보드가 내려가지 않는 문제를 확인했다.
- `ChatMessageReportViewController`를 OutPick dark editorial token으로 재구성했다. serif 제목, monospaced eyebrow/index, accent line, 신고 범위 카드, 선택 상태가 분명한 reason card, placeholder·글자 수가 결합된 상세 입력, accent capsule CTA를 사용하며 신고 데이터·ViewModel·Coordinator 계약은 변경하지 않았다.
- 상세 입력창 자체를 제외한 영역의 tap gesture는 `cancelsTouchesInView=false`로 키보드만 닫아 reason·취소·제출 동작을 보존한다. scroll drag도 interactive dismissal을 사용한다.
- CTA 문구는 `신고`로 단순화하고 사유가 없으면 중립 색상·비활성, 사유 선택 뒤 accent 색상·활성 상태로 전환한다. ViewModel의 사유 누락 검증은 방어 로직으로 유지한다.
- `ChatMessageReportViewModelTests` 3/3과 Development build가 통과했다. iPhone 17 Pro Max iOS 26.2 Simulator에서 실제 신고 화면의 시각·scroll reachability, detail focus 뒤 reason tap의 편집 종료와 같은 tap의 선택 상태 반영을 확인했다. 접근성 최대 글자 크기에서 reason symbol 상한, multiline 안내·placeholder, 가변 높이 CTA를 보정하고 reason/detail/CTA 도달·선택 상태·활성 CTA를 재확인했다. 기존 UIKit 접근성 label/value/error announcement는 유지하되, 사용자 결정으로 VoiceOver 실제 발화·포커스 수동 QA는 이번 Phase 완료 범위에서 제외했다. 다음 순서는 일반 사용자 신고 결과 → 카카오 계정 관리자 승격 → 관리자 처리 → 탈퇴 bulk → 종료 감사다.
- 2026-08-28 일반 사용자 실제 신고 첫 제출에서 `reporters(priorityClass ASC, createdAt DESC, __name__ DESC)` 복합 인덱스 누락으로 transaction이 `FAILED_PRECONDITION` 중단되는 배포 계약 결함을 발견했다. manifest에 추가하고 Development exact index `CICAgNjp84oK`만 생성해 `READY`를 확인했으며 Production은 미변경이다. 실패 화면의 동일 UUID 재시도는 `accepted`, 새 UUID의 같은 사용자·메시지 재신고는 `alreadyReported`로 수렴했고 incident는 `holding`, 고유 신고자 1명, 원문 `visible`, caseVersion 1을 유지했다. 다음은 새 A 미디어 메시지의 `processing` 결과다.
- 이어서 A가 이미지를 보냈을 때 B의 활성 채팅방에 실시간 표시되지 않고 재진입 뒤에만 보이는 결함을 확인했다. ready message seq 5는 정상 생성됐지만 `chatMediaDeliveryJobs`의 `status+nextAttemptAt`, `status+leaseExpiresAt` 복합 인덱스가 Development 원격에 누락돼 watcher의 `Promise.all` drain 전체가 `FAILED_PRECONDITION`으로 중단된 것이 원인이었다. manifest에는 이미 두 인덱스가 있었으므로 코드 변경 없이 Development exact index `CICAgNi4t5oK`, `CICAgOj3gpIK`를 생성해 `READY`를 확인했다. 기존 seq 5와 밀린 job은 모두 `attempt=1/completed`로 자동 수렴했고 READY 이후 watcher 오류는 없다. B가 방을 계속 보고 있는 상태에서 A가 보낸 새 이미지 seq 6이 재진입·새로고침 없이 즉시 표시됐고 서버 delivery job도 `attempt=1/completed`, 오류 없음이다. Production은 미변경이며 다음은 seq 6 이미지의 `processing` 신고 결과다.
- seq 6 이미지 신고 첫 시도는 `failed-precondition` 400으로 transaction 전에 거부됐다. 현재 local `readyService`는 evidence source descriptor인 `generationOriginal/contentTypeOriginal`을 Message와 mediaIndex에 쓰지만 Development의 `onChatMediaWorkerCompleted` 배포본이 오래돼 실제 seq 6 두 문서에 필드가 없었던 배포 drift가 원인이었다. Functions 245/245·build·lint 오류 0을 확인하고 해당 trigger 하나만 Development에 재배포해 Node.js 24 `ACTIVE`, 기존 전용 service account·512MiB·120초를 확인했다. seq 6은 남아 있던 `MediaUploads.normalizedManifest`와 message ID·seq·attachment ID·bucket·path·bytes를 transaction에서 exact 대조한 뒤 누락 필드 2개만 Message/mediaIndex에 보정했다. Production은 미변경이다.
- 사용자 결정에 따라 제출 중 CTA의 회전 indicator를 제거하고 `신고` 문구를 유지한 비활성 버튼만 표시하도록 `ChatMessageReportViewController`를 보정했다. ViewModel의 중복 제출 차단과 network 실패 입력·UUID 보존은 그대로이며 관련 테스트 3/3과 Development build가 통과했다. 수정 빌드를 다시 설치한 뒤 B가 seq 6 이미지 신고의 `신고를 처리 중이에요` 결과를 확인했다. 서버는 request/preparation `accepted`, copy job `attempt=1/succeeded`, bundle `available`·evidence object 1개·pending 0, incident `open/reviewable/holding`, 고유 신고자 1명과 원문 `visible`로 최종 수렴했다. 이후 delete-first 제출에서 spinner 미표시와 비활성 `신고` 버튼도 명시적으로 확인했다.
- delete-first QA에서 A가 seq 7을 삭제한 뒤 B가 열어 둔 신고 화면을 제출해 `이미 삭제된 메시지예요` 결과를 확인했고, 제출 중 spinner 없이 `신고` 버튼만 비활성화되는 것도 확인했다. 최초 중앙 시스템 행은 철회하고 기존 메시지 셀의 본문만 `삭제된 메시지입니다`로 교체했다. 사용자 확정에 따라 일반·관리자 tombstone은 sender UID·닉네임·아바타·전송 시각·답장 presentation을 보존하고 원문·미디어·검색 데이터만 제거하며, 계정 탈퇴 bulk만 UID·아바타·답장 정보를 제거하고 `알 수 없는 사용자`와 전송 시각을 남긴다. iOS delta/GRDB marker의 `anonymizesSender`와 `addDeletionMarkerSenderPolicy` migration까지 반영했다. Functions build·lint 오류 0(기존 warning 24건), chat moderation emulator 10/10, moderation reports emulator 28/28, iOS build-for-testing, GRDB deletion sync 6개·migration 2개가 통과했다.
- 사용자 승인으로 Development `outpick-test`의 `deleteChatMessage`, `resolveMessageModeration`, `finalizeExpiredAccountDeletions`만 exact-target 배포했다. 모두 Node.js 24 `ACTIVE`, finalizer Scheduler는 매시간·Asia/Seoul·`ENABLED`, 배포 후 ERROR 0건이다. 활성 방 seq 9 실제 삭제에서 우측 정렬·기존 버블·닉네임 `AD`·시간 `01:52`·답장 원문 영역 보존과 본문만 tombstone 교체, Firestore sender 표시 필드 보존·revision 2·delivery `completed/attempt=1`을 확인했다. 비활성 방 seq 11 실제 삭제도 Room revision 3·delivery `completed/attempt=1`, AD2 재진입 원문 flash 없음으로 통과했다.
- 비활성 재진입 중 과거 seq 9의 닉네임이 AD2 기기에서 사라지는 결함을 발견했다. `ChatMessageRecordMapper`의 삭제 메시지 표시 필드 nil 처리와 legacy `anonymizesSender=true` marker의 선적용·`MAX` 고착이 원인이었다. mapper는 일반 tombstone의 sender·시간·reply를 보존하고, UseCase는 서버 tombstone policy를 먼저 기록하며 같은/더 최신 revision으로 marker를 exact 교정한다. 오래된 visible payload에 대한 marker 우선은 유지한다. 관련 mapper·GRDB deletion sync 11/11과 Development build가 통과했고, AD2 수정 앱에서 seq 9 닉네임 `AD` 복구와 seq 11 tombstone 유지를 확인했다.
- 앱 종료·오프라인 복구는 AD2가 seq 12를 로컬에 받은 뒤 방 밖에서 앱 종료·네트워크 단절한 상태로 방장 AD가 삭제해 검증했다. Development 서버는 Room head/message revision 4, 원문·첨부 제거, 표시 필드 보존, delivery `completed/attempt=1`로 수렴했다. AD2 온라인 복귀·앱 재실행·방 진입에서 원문 flash 없이 닉네임·시간·버블을 유지한 tombstone이 처음부터 표시됐고 삭제 원문의 방 검색 결과도 0건이었다. 활성 방·비활성 방·앱 종료/오프라인 deletion sync 핵심 수동 QA는 모두 통과했다.

### Chat UGC Safety Phase 7.6 — 공동 QA message menu 보정 진행

- 공동 QA에서 방장 A가 타인 B 메시지의 삭제 권한 때문에 신고를 보지 못하는 결함과 커스텀 long-press 메뉴가 touch 종료 시 닫히고 하단 `내보내기`가 잘리는 문제를 확인했다.
- 기존 제품 결정대로 pending·삭제·본인 메시지만 신고를 차단하고 방장은 타인 메시지에서 `신고 + 삭제`를 동시에 허용하도록 `ChatMessageActionPolicy`를 보정했다.
- `ChatCustomPopUpMenu`와 collection view long-press recognizer를 제거하고 UIKit native context menu로 전환했다. 답장·복사·공지와 신고·삭제·차단·내보내기는 권한별 별도 항목이며 touch 유지·외부 탭 종료·safe-area 배치·접근성은 시스템 동작을 사용한다.
- `ChatMessageActionPolicyTests` 7/7과 `OutPick-Development` Simulator build/run이 통과했다. iPhone 17 Pro Max iOS 26.2 Simulator와 Development 실기기에서 방장 타인 메시지의 7개 항목, 신고/삭제 동시 노출, `내보내기` 미잘림, touch 종료 뒤 유지와 표준 dismissal을 확인했다. 신고 화면 QA부터 재개한다.

### Chat UGC Safety Phase 7.6 — Development backend rollout 완료, 공동 수동 QA 대기

- 2026-08-27 `outpick-test`에 client deny-all Firestore Rules를 release하고 `chatMessageDeletionDeliveryJobs`의 `status+nextAttemptAt`, `status+leaseExpiresAt` 복합 인덱스 2개를 `READY`, `expiresAt` TTL을 `ACTIVE`로 확인했다. 전체 index manifest는 기존 drift 때문에 배포하지 않고 승인된 exact 항목만 생성했다.
- `submitMessageReport`, `deleteChatMessage`, `resolveMessageModeration`, `finalizeExpiredAccountDeletions` 네 함수만 exact target으로 배포했다. 모두 asia-northeast3 Node.js 24 `ACTIVE`이고 배포 직후 ERROR는 0건이다.
- Socket revision `outpick-socket-development-p75-del-0827`, image digest `sha256:e3d26a46a75252ae683a14c8f0aa8e9e3cef28e72e019d02abdb080b5e591625`를 0% candidate로 배포했다. tagged readiness, 기존 active 계정의 메모리 custom token 인증 handshake, ERROR 0을 확인한 뒤 traffic 100%로 전환했다. 직전 `outpick-socket-development-00015-ruw`는 0% rollback으로 보존한다.
- 전환 후 canonical readiness 200, 삭제 revision 10/10·Room head 10·mismatch 0, reply/media 잔존 0, deletion delivery job 0을 재감사했다. iPhone 17 Pro Max iOS 26.2 Simulator에서 Phase 7.5 관련 9개 suite 60/60과 Development generic Simulator build가 통과했다.
- 활성 방 즉시 삭제, 비활성 재진입, 앱 종료·오프라인 delta 복구, 열린 viewer/player 종료와 durable cache cleanup은 실제 공동 QA로 통과했다. 다음은 플랫폼 관리자 처리, disposable 계정 탈퇴 bulk와 종료 감사다. 신고 keyboard/일부 실기기 UX 항목은 최종 종료 감사에서 완료 여부를 재확인한다. Production은 변경하지 않았다.

### Chat UGC Safety Phase 7.5F — 자동 통합 회귀·Development deletion cutover 완료, 공동 QA 대기

- 공용 계약의 `moderationRemoved` 신규 쓰기 표현을 제거하고 일반 tombstone 단일 계약으로 맞췄다. 자동 hide/restore producer와 기존 Firestore deletion listener는 신규 실행 경로에 없으며, Socket의 구형 `hiddenPendingReview` read는 legacy media 재전송 방지 guard로만 유지한다.
- Functions 245/245, lint 오류 0·기존 warning 24건, Rules·Storage 46/46, Firestore transaction 52/52, Socket check·103/103, iOS 관련 9개 suite 60/60과 generic Simulator build, JSON parse와 `git diff --check`가 통과했다.
- `functions/scripts/audit-chat-deletion-revisions.mjs`로 환경별 legacy tombstone을 내용·사용자 식별자 출력 없이 읽기 전용 감사했다. Development는 Rooms 2개/삭제 10건이며 10건 모두 revision 누락, 영향 방 1개·현재 head 0이다. 10건 모두 message 경로·roomID·messageID·seq·deletedAt이 유효하고 seq 중복도 없어 기존 삭제 시각을 보존한 결정적 backfill이 가능하다. Production은 Rooms 1개/삭제 0건이라 migration이 필요 없다.
- Development 10건은 attachment/storage target 0건이지만 cleanup job 10건이 모두 20회 뒤 `failed/cleanup_failed`이며 media index가 메시지별 1건 남았다. 원인은 manifest의 `Messages.replyPreview.messageID` field override가 COLLECTION_GROUP만 보유한 반면 cleanup은 COLLECTION query를 사용한 계약 불일치였다.
- 승인된 cutover에서 COLLECTION ASC를 field-level exact patch해 두 scope READY를 확인했다. failed cleanup 10건을 attempt 0으로 재개하고 scheduler를 실행해 모두 1회 `completed`, reply/media 잔존 0으로 수렴시켰다. 이후 기존 삭제 시각을 보존한 최소 tombstone revision 1...10과 Room head 10을 한 transaction으로 backfill했다. outbox는 만들지 않았다.
- 사후 감사는 Development revision 보유 10/누락 0/max 10=head 10/mismatch 0, Production 삭제 0건이다. Production index·데이터는 변경하지 않았다. 이후 Development 서버 rollout은 위 Phase 7.6 기록대로 완료했으며 실제 Firebase E2E, 강제 종료·오프라인 복구, viewer/player 삭제와 신고 접근성·keyboard 수동 QA가 남았다.

### Chat UGC Safety Phase 7.5E — 사용자 메시지 신고 UX 로컬 완료

- 2026-08-27 `submitMessageReport` callable wrapper/root export와 iOS message receipt/repository/use case를 연결했다. Chat long press와 신고 가능한 이미지 뷰어는 `ChatCoordinator`의 동일 reason/detail 화면을 사용하며 이미지에서는 메시지 전체가 신고됨을 안내한다.
- 중복 신고는 로컬 flag가 아니라 서버 transaction이 최종 판정한다. 별도 GRDB·메모리 신고 캐시 없이 현재 신고 화면의 network retry 동안만 UUID와 입력을 유지하며 terminal failed 또는 화면 종료 뒤 새 제출은 새 UUID를 사용한다.
- accepted/processing/alreadyReported/messageAlreadyDeleted 문구를 분리하고 삭제 선행은 기존 Deletion Sync로 즉시 수렴시킨다. pending·삭제·본인 메시지는 신고 액션을 노출하지 않고 방 관리자는 타인 메시지에서 신고와 삭제를 함께 사용할 수 있다.
- generic Simulator build, 관련 iOS suite 13개, Functions 245/245와 build·lint 오류 0이 통과했다. Development·Production 배포와 실기기 접근성/keyboard QA는 하지 않았으며 다음 단계는 Phase 7.5F다.

### Chat UGC Safety Phase 7.5D — iOS/GRDB Deletion Sync 로컬 완료

- 2026-08-27 `ChatDeletionSyncUseCase`와 Firebase repository, GRDB store를 추가해 Room `messageDeletionRevision`과 account+room cursor 차이만 revision ASC 100개 page로 적용한다. Socket 단건 연속 revision은 즉시 적용하고 중복·gap·bulk head는 같은 reconciliation으로 복구한다.
- GRDB는 일반 삭제 표시 보존/계정 탈퇴 익명화 tombstone, `anonymizesSender` 방 수명 삭제 마커, durable media cleanup queue를 저장한다. message/reply/FTS/media index/발신 outbox scrub, marker·cleanup enqueue와 cursor 전진은 하나의 transaction이다.
- 초기 진입·pagination·검색·실시간 수신을 공통 admission sanitizer로 통합했고 새 설치는 server page와 page 밖 reply target 묶음 확인 뒤 current head로 bootstrap한다. 기존 Firestore `isDeleted` listener와 `fetchDeletionStates/syncDeletedStates`는 제거했다.
- 이미지·영상·Storage URL cache eviction과 in-flight 취소, 삭제 대상 viewer/player 종료를 연결했다. `OutPick-Development` Simulator build와 build-for-testing, GRDB deletion sync 5/5, migration 2/2, Realtime binder 15/15가 통과했다.
- Development·Production 배포는 하지 않았다. 다음 순차 단계는 Phase 7.5E 사용자 신고 UX이며 실제 Socket/Firestore E2E와 강제 종료 수동 QA는 Phase 7.5F 자동 회귀 뒤 Phase 7.6 배포 승인과 함께 수행한다.

### Chat UGC Safety Phase 7.5C — transactional outbox·Socket fast path 로컬 완료

- 2026-08-27 `Socket/src/deletion/deletionDeliveryWatcher.js`에 Firestore outbox 직접 소비기를 추가했다. 단건 `chat:messageDeleted`와 bulk `chat:messageDeletionHeadAdvanced`를 현재 Socket room에만 emit하며 사용자별 inbox·push fan-out은 만들지 않는다.
- watcher는 snapshot wake-up+5초 poll, 60초 transaction lease, 최대 10회·최대 5분 backoff를 사용한다. 만료 processing은 같은 attempt로 회수하고 terminal completed/failed에는 처리 시점부터 7일 TTL을 적용한다.
- `createProductionDependencies.js`가 watcher start/stop을 graceful shutdown lifecycle에 연결했고, due retry·만료 lease 쿼리용 복합 인덱스 2개와 index contract test를 추가했다.
- 이 Phase 7.5C 완료 시점에는 Socket check·103/103, Functions 245/245, Rules 46/46, Firestore transaction 52/52, index JSON·diff whitespace가 통과했고 iOS/GRDB는 미구현이었다. 후속 Phase 7.5D 결과는 바로 위 절에 반영했다.

### Chat UGC Safety Phase 7.5B — 공통 deletion mutation·계정 탈퇴 bulk 로컬 완료

- 2026-08-27 `functions/src/chat/deletion/mutation.ts`에 transaction을 직접 열지 않는 snapshot-in/write-only 공통 deletion core를 추가했다. 작성자·방 관리자, 플랫폼 관리자 incident resolution, 계정 탈퇴 worker가 각자의 transaction 안에서 표시 보존/계정 익명화 tombstone·Room revision·cleanup job·delivery outbox를 사용한다.
- 일반·관리자 공개 tombstone은 sender UID·닉네임·아바타·전송 시각·답장 presentation을 보존하고 원문·첨부·룩북·검색 필드와 삭제 주체 표현을 제거한다. 계정 탈퇴 bulk만 sender 식별정보를 제거한다. 최초 visible→deleted만 revision과 outbox를 만들고 replay·legacy 정규화는 revision을 소비하지 않는다.
- 계정 탈퇴는 collection group 결과를 최대 30건씩 방별로 묶어 `seq → document ID` 순서로 연속 revision을 부여하고 방 batch당 head-advanced outbox 하나를 만든다. 각 transaction은 `deletionPending + accountGenerationID` fence를 재확인한다.
- 계정 탈퇴가 생성·재사용한 cleanup job에 서버 전용 `accountDeletionRequestID`를 연결한다. final verify는 연결 job 전부가 `completed`일 때만 통과하므로 reply preview·media index·Storage 정리 실패를 두고 탈퇴 완료를 선언하지 않는다. 영구 batch journal은 만들지 않았다.
- `chatMessageDeletionDeliveryJobs`는 Rules client deny-all과 7일 TTL manifest만 추가했다. 실제 claim/lease/retry/Socket emit은 Phase 7.5C 범위다.
- Functions 245/245, Rules 46/46, Firestore transaction 52/52, build·lint 오류 0, index JSON parse가 통과했다. Development·Production 배포와 Socket/iOS/GRDB 변경은 수행하지 않았다. 다음은 Phase 7.5C다.

### Chat UGC Safety Phase 7.5A — 신고 queue-only·관리자 종결 계약 로컬 완료

- 2026-08-27 사용자 결정에 따라 Phase 7.5A를 `codex/chat-media-phase7-5-report-ux`에서 로컬 구현했다. 신고 임계치는 관리자 queue/count만 갱신하고 Message visibility를 쓰지 않으며 신규 `hiddenPendingReview`, 검토 tombstone과 restore payload를 생성하지 않는다.
- 관리자 종결 입력·audit·incident/revision·confirmed violation을 `reviewOutcome`, `contentAction`, `accountAction`으로 분리했다. 기각은 keep+none만, 위반은 delete 또는 non-none account action을 요구하고 `contentAction=delete`만 기존 `삭제된 메시지입니다` tombstone mutation을 실행한다.
- 활성 방은 `chat:messageDeleted(roomID,messageID,seq,deletionRevision)` Socket fast path로 즉시 반영한다. 다른 화면·다른 방·앱 종료·오프라인·Socket 유실은 Room `messageDeletionRevision`과 계정·방별 로컬 `lastAppliedDeletionRevision` 이후 tombstone delta query로 복구한다.
- 작성자·방 관리자·플랫폼 관리자 종결·계정 탈퇴 정리를 포함한 모든 서버 확정 메시지 삭제는 같은 공통 deletion mutation을 사용한다. 삭제 원인은 서버 audit에만 남기고 공개 tombstone·Socket·revision·로컬 scrub 경로는 구분하지 않는다.
- 계정 탈퇴 메시지는 원문·첨부·sender UID·아바타·답장 정보를 제거하고 `알 수 없는 사용자`와 전송 시각만 남기는 `삭제된 메시지입니다` tombstone으로 확정했다. collection group query 결과를 방별 batch로 처리하고 단건은 message outbox, 계정 탈퇴 bulk는 revision 범위당 head-advanced outbox 하나를 사용한다.
- Phase 7.5 구현 계획은 7.5A 서버 신고·관리자 계약 cutover → 7.5B 공통 삭제 core·계정 탈퇴 bulk → 7.5C outbox·Socket → 7.5D iOS/GRDB Deletion Sync → 7.5E 신고 UX → 7.5F 통합 회귀·하네스 순서다. 7.5A만 완료했고 다음은 7.5B다.
- 별도 deletion journal, 사용자별 deletion inbox와 삭제 push fan-out은 만들지 않는다. 삭제 message tombstone 자체를 durable delta로 사용하고 방이 존재하는 동안 유지한다.
- GRDB 원문·첨부·reply preview·FTS·media index scrub과 durable local cache cleanup queue, revision 중복·gap·역순·앱 종료 복구, offline cache 한계를 `docs/ai/tasks/chat-ugc-safety-room-moderation/phase-7-5-design.md`에 확정했다.
- Functions 243/243, Rules 46/46, Firestore transaction 51/51, build·lint 오류 0과 JSON parse를 통과했다. Firestore rules/index 수정은 필요하지 않았고 Firebase·Socket·Development·Production 배포는 수행하지 않았다.

### Chat UGC Safety Phase 7.4D — 관리자 Evidence 조회 Development 완료

- 2026-08-26 canonical message queue/current-revision detail, decision별 same-seq restore/moderationRemoved/계정 제재·Evidence retention, terminal preparation scrub+TTL, 분리 signer와 exact-generation 5분 V4 GET, 응답 전 `EVIDENCE_VIEW_URL_ISSUED`를 로컬 구현했다. Functions 243/243, Rules 46/46, Firestore transaction 49/49, build·lint 오류 0을 통과했다.
- Development에 Firestore/Evidence Storage Rules, exact index 5개, preparation TTL, 영향 Function 7개와 signer 최소 IAM을 반영했다. Function은 `ACTIVE`, index는 `READY`, TTL은 `ACTIVE`이며 Production은 변경하지 않았다.
- 서울 전용 Log Analytics bucket은 1,095일 보존·`locked=true`다. Evidence app audit와 Evidence GET만 전용 sink에 route하고 `_Default`에서는 app audit와 프로젝트 전체 GCS DATA_READ를 exact exclusion한다.
- 유효 PNG와 정확히 350 MiB인 재생 가능 MP4로 원격 probe·전체 GET·앞/뒤 Range, 실제 5분 만료 후 이미지·영상 HTTP 400, recent-auth 갱신 뒤 새 URL·새 issuanceID와 Range 성공을 확인했다. 운영 필드 결합 조회 2건의 내림차순, issuance별 Storage GET 6/1/1건과 `_Default=0`을 확인했다.
- 영구 App Check debug token은 만들지 않았고 임시 Auth/Firestore/Storage/rate bucket 잔여 0, 기존 Auth 2명·active platform admin 0명, 최근 Function ERROR 0으로 종료했다. 다음 구현 경계는 위 Phase 7.5 신고 UX·관리자 종결 분리·Deletion Sync이며 Production은 별도 승인 전 변경하지 않는다.

### Chat UGC Safety Phase 7.4C-1~C-3 — evidence copy/cleanup Development 검증 완료

- 2026-08-25 `functions/src/moderation/messageEvidence/{evidenceCopy,evidenceStorage,evidenceCleanup,evidenceFunctions}.ts`에 exact ready source 검증, generation-scoped Storage copy/delete, lease-fenced acceptance/failure drain과 retention cleanup을 구현했다. copy는 최초 포함 3회, 1분/2분 backoff, 9분 timeout/12분 lease를 사용한다.
- destination은 `{bundleID}/g{attemptGeneration}/{attachmentID}/display`이고 source generation 고정, create-if-absent, destination generation precondition, ownership metadata 검증을 결합한다. 한 실행은 preparation 최대 30건만 처리하고 남은 batch는 새 lease로 이어간다.
- 마지막 copy 실패는 같은 generation의 부분 객체를 전부 삭제한 뒤 preparation·최초 receipt·guard를 failed로 확정하고 report-first public cleanup을 해제한다. retention cleanup은 Storage evidence 전부 삭제 뒤 bundle 문서를 완전 삭제하며 scrub된 cleanup receipt만 7일 보존한다.
- C-2에서 root export와 환경별 runtime fence를 추가하고 Development에 전용 `outpick-test-moderation-evidence` 버킷, `outpick-msg-evidence-dev@outpick-test.iam.gserviceaccount.com`, 최소 custom IAM과 서비스별 Run invoker를 구성했다. 세 Function은 Node.js 24, 512MiB, 540초, maxInstances 1로 ACTIVE이고 scheduler는 5분 주기 ENABLED다.
- C-3 선행 조건으로 preparation acceptance와 copy/cleanup scheduler용 복합 인덱스 3개만 Development에 생성해 READY를 확인했다. 30장×5MiB=150MiB는 4.084초, MP4 350MiB는 2.073초에 copy됐고 익명·버킷 운영자·무관한 chat-media 서버 계정 read가 모두 거부됐다. 기본 Compute 계정도 IAM Policy Troubleshooter에서 `CANNOT_ACCESS`다. cleanup 뒤 ready/evidence/Firestore QA 잔여는 0이고 READY 이후 scheduler는 HTTP 200이다.
- Development 전체 index 감사에는 이번 범위와 별개인 기존 drift가 남는다: local/remote index 53/46, local-only/remote-only 9/2, field override local/remote 33/22와 only-local/only-remote 14/3이다. Phase 7.4D도 전체 sync 없이 승인된 exact index 5개만 추가했으므로, 향후 전체 `firestore:indexes` 동기화 전에는 반드시 reconcile한다.
- Functions 236/236, Firestore/Storage Rules 45/45와 전체 transaction 41/41(신규 moderation 18/18), 계약 JSON·diff 검증을 통과했다. 이 C 단계에서 보류했던 Rules·TTL·관리자 Evidence 조회의 Development 적용은 위 Phase 7.4D에서 완료했고 Production은 여전히 별도 승인 gate다.

### Chat UGC Safety Phase 7.4B — evidence-first 신고/삭제 transaction 로컬 완료

- 2026-08-24 `functions/src/moderation/messageEvidence/service.ts`에 메시지 신고 parser/service와 evidence available drain transaction을 구현했다. revision과 무관한 최상위 `moderationMessageReportRequests/{requestID}`를 현재 revision보다 먼저 조회하므로 관리자 종결 뒤 같은 UUID의 지연 retry는 최초 결과를 반환하고, 새 UUID만 새 revision을 연다.
- 신규 ready schema의 attachment evidence descriptor, text/lookbook 즉시 accepted, media preparation/bundle/copy job processing, 최대 30건 draining, reporter dedupe·작성자 aggregate·24시간 visibility, report/delete guard와 public cleanup `awaitingEvidence`를 반영했다.
- 동일 UUID replay는 무료이고 이전에 보지 못한 새 UUID receipt는 preparation 재사용·alreadyReported·messageAlreadyDeleted여도 user/room 요청과 공유하는 1분 10회 transport limiter를 소비하도록 확정했다. 앱은 최초 UUID를 terminal 결과까지 유지하며 moderation count/evidence와 신규 semantic preparation 관측치는 분리한다.
- 최종 리뷰에서 한 preparation의 추가 UUID receipt 전체를 drain transaction이 무제한 갱신하던 경계를 `initialRequestID` 1건 확정과 조회 시 개별 terminal 수렴으로 보정했다. 실패 재시작은 partial cleanup 완료·빈 objectPaths와 preparation/bundle/copy job 동일 generation을 검증한 뒤 세 문서를 원자적으로 `+1` 전환하며 stale generation을 거부한다.
- Functions build/test 228/228, lint 오류 0(기존 포함 non-null assertion warning 19개), Firestore/Storage rules 45/45와 transaction 35/35, 계약 JSON·diff 검증을 통과했다. 지연 retry emulator 회귀가 revision 0 replay와 새 UUID revision 1 reopen을, limiter 회귀가 새 UUID 10회·11번째 거부·동일 UUID 무료 replay를, media 회귀가 최초 receipt drain·추가 alias 개별 수렴·generation fence와 신고/삭제 양쪽 순서를 확인한다.
- `functions/src/index.ts` callable export, Rules/index 추가, 실제 Storage copy/cleanup worker, iOS `신고 처리 중` UX, Development/Production 배포는 수행하지 않았다. 다음 구현 경계는 Phase 7.4C다.

### Chat UGC Safety Phase 7.4A — evidence-first 순수 계약 완료

- 2026-08-21 확정한 최신 설계를 문서와 `functions/src/moderation/messageEvidence/{contracts,contracts.test}.ts`에 반영했다. 신고는 `processing` 동안 server-only preparation/request receipt/guard/bundle/job만 소유하고 text snapshot 또는 메시지 전체 media evidence가 `available`이 된 뒤에만 `accepted`와 incident/reporter/aggregate·queue·visibility를 확정한다. processing/failed는 신고 임계치에 포함하지 않는다.
- domain/version canonical tuple SHA-256 ID, 최초 revision 0과 terminal reopen, `holding → reviewRequired → urgent` 비강등, 긴급 2명 또는 전체 3명/24시간 전역 비노출, 서로 다른 메시지 3개 + 고유 신고자 2명/7일, retention·appeal/legal hold와 evidence/copy/cleanup job 상태 전이를 순수 함수로 구현했다.
- 신규 대상 12/12, Functions 전체 226/226, build, lint 오류 0, 계약 JSON과 diff 검증을 통과했다. 기존 moderation non-null assertion 경고 17개만 남았다. Firestore/Storage/Rules/index/iOS/외부 리소스/배포는 변경하지 않았으며 다음은 Phase 7.4B transaction이다.

### Chat UGC Safety Phase 7.3 — 실패 outbox 재실행 크래시 보정

- iPhone 14 crash log 3건에서 실패 메시지 복원 직후 `ChatViewController.applyInitialWindowSnapshotAndWait`의 diffable `appendItemsWithIdentifiers`가 동일하게 `SIGABRT`한 것을 확인했다.
- server window 뒤 과거 날짜 실패 메시지가 붙을 때 같은 날짜 separator가 비연속으로 두 번 생성되는 것이 원인이었다. `ChatMessageListItem.dateSeparator` identity에 occurrence를 추가하고 현재 window occurrence를 이어받아 identifier 유일성을 보장했다.
- 과거 날짜 실패 outbox 복원 회귀를 추가했고 관련 window/pending/action suite 26/26, Development 실기기 build·설치·재실행을 통과했다. 신규 crash log는 없으며 TR-1 재진입 육안 확인만 사용자 QA로 남는다.
- 후속 확인에서 실패 메시지는 남지만 재시도·삭제 아이콘이 사라졌다. terminal 실패 시 signed URL session을 제거하는 보안 계약과 session을 필수로 요구하던 UI 복원 코드가 충돌한 것이 원인이었다. terminal 실패는 local/uploaded retry payload로 pending `.failed`를 복원하고 서버 진행 상태만 monitoring을 재개하도록 수정했으며 관련 34/34와 실기기 빌드·설치를 통과했다. TR-1 아이콘 육안 확인은 사용자 응답 대기다.
- 사용자가 TR-1 아이콘 복원을 확인했다. 재시도·삭제는 각각 prominent/destructive `ConfirmView`를 거치고 확인 callback 이후에만 상태를 변경하도록 보정했으며 관련 34/34와 Development 실기기 build·설치·실행을 완료했다. 확인창 문구·취소·확인 동작의 실기기 QA만 남는다.
- 이미지 실패와 달리 영상 일반 실패에만 남아 있던 `동영상 전송 실패` 팝업을 제거했다. 일반 실패는 버블의 재시도·삭제만 표시하고 ban으로 인한 중단 안내는 유지한다. pending/outbox 회귀 17개와 iPhone 14 Development 서명 빌드·설치를 통과했으며, 사용자가 팝업 미표시와 재시도·삭제 노출을 실기기에서 확인했다.

### Chat UGC Safety Phase 5 — 방 차단·owner succession 완료

- room ban은 활성 방·기존 메시지 read를 유지하고 membership 생성과 참여자 전용 Socket/message/media write를 차단한다. 내보내기 뒤 앱은 읽기 전용으로 전환하고 해당 방의 pending upload/outbox만 취소하며, 같은 provider 재로그인에도 canonical principal ban을 유지한다.
- 방장 전용 메시지 long press `내보내기`, 참여자 프로필/별도 관리 버튼, 설정 나가기 옆 `차단 사용자` 독립 화면과 `해제` 흐름을 Production 두 계정 앱에서 확인했다.
- 계정 삭제 최종 확정과 영구 정지는 durable membership sweep과 방별 transaction으로 적격 참여자 승계 또는 기존 종료 lifecycle에 수렴한다.
- PR 리뷰에서 최대 시도에 도달한 succession job이 stale `processing`에 남을 수 있는 경계를 발견해 `failed`/`max_attempts_exceeded`로 종결하도록 보정하고 emulator 회귀를 추가했다.
- 최종 Functions lint 오류 0·build/test 191/191, Socket check/test 76/76, Rules 41/41, transaction 25/25와 iOS 관련 suite·Production Simulator build를 통과했다.
- PR #12를 리뷰 완료 후 merge commit `83ba7ca2116146e58bcddefafab1727e0f8a882c`로 `main`에 반영했다. 후속 lease 리뷰에서 유효 lease의 `processing` job 중복 claim 경계를 보정해 PR #13 merge commit `4fbdb5cc257878f0734f261507de1346c4d5892b`로 반영했고 transaction 26/26을 통과했다. 관련 Production Functions 2개만 exact-target 재배포해 `ACTIVE`, scheduler 5분·Asia/Seoul `ENABLED`, 빈 queue smoke·ERROR 0·queue 0을 확인했다. 실제 기기 background FCM/APNs는 출시 전 외부 gate로 유지한다.

### Chat UGC Safety Phase 4 — 전역 사용자 차단 완료

- 기존 `users/{uid}/blockedUsers/{targetUID}`를 채팅·룩북·프로필의 단방향 visibility source로 통일했다. 계정별 마지막 성공 UID snapshot을 세션 시작 시 메모리 Store에 올리고 서버 응답으로 원자 교체하며, block/unblock 성공 직후 Store와 snapshot을 동기화한다.
- 채팅은 차단 성공 전 현재 window를 유지하고 이후 live/pagination/재진입/검색/reply/공지/room preview/banner/gallery admission에서 차단 작성자를 제외한다. hidden seq와 raw cursor는 소비하며 기존 GRDB·FTS·미디어 cache는 소급 삭제하지 않는다.
- 앱 종료 중 unread는 joined projection의 `lastReadSeq...latestSeq` 고정 구간을 page 단위로 조회해 차단·본인·삭제 메시지를 제외한다. 성공 방만 visible unread와 최신 visible preview로 교체하고 실패 시 raw unread를 유지하며 전역 seq와 서버 read frontier는 변경하지 않는다.
- 룩북은 차단 성공 즉시 현재 댓글·답글을 숨기고, 채팅 current window는 강제 reload하지 않는다. 프로필·참여자·공동방은 유지하며 차단 대상에게 답장하려는 사용자에게만 해제 안내를 표시한다.
- Production Functions `blockUser`/`unblockUser`와 Socket revision `outpick-socket-p4-block-0811`을 반영했다. 두 계정 QA에서 차단 전 window 유지, 차단 뒤 live 제외, 참여자 유지, unblock 재진입 복원과 future live 수신을 통과했다.
- Production 앱 종료 혼합 QA는 `lastReadSeq=1`, 차단 `seq=2`, 비차단 `seq=3`에서 목록 visible unread 1·비차단 preview와 방 재진입 차단 메시지 제외를 확인했다. QA 방·메시지·projection·차단 relation·Storage는 잔존 0건으로 정리했다.
- 최종 리뷰에서 이전 계정 bootstrap 실패가 새 계정 Store를 비우는 경쟁 조건, hidden seq 뒤 정상 메시지에서 read frontier가 멈추는 결함, 룩북 댓글 프로필의 차단 UseCase 주입 누락을 발견해 계정 guard·visible/hidden 합집합 연속 계산·공용 프로필 DI와 회귀 테스트로 보정했다.
- iOS visible unread/기존 closure 회귀 대상 테스트와 Production build가 통과했다. Phase 4 전체 기존 검증은 Functions 188/188, Socket 72/72와 관련 iOS/GRDB 테스트를 통과했다.
- Phase 4 변경과 최종 리뷰 기록은 PR #11에서 관리한다. 실제 기기 background FCM/APNs 외부 gate 외에 Phase 4 잔여 구현은 없다.

### Chat UGC Safety Phase 3.1 — 공용 종료 tombstone Production 배포 완료

- 신규 사용자별 종료 notice 생성을 제거하고 공용 `Rooms/{roomID}` tombstone 하나를 최대 14일 유지한다. 방 콘텐츠·Messages/media·Storage·이미지 경로는 즉시 정리하며 목록 마지막 메시지에 종료 문구를 넣지 않는다.
- `acknowledgeRoomClosure` callable은 확인 사용자의 member/joinedRooms/roomStates와 legacy notice를 멱등 정리한다. 활성 방은 거부하고 방장 삭제 creator는 안내 없이 즉시 정리한다.
- `moderationRoomCleanupJobs` schema v2는 `content → retention`으로 전이하며 `awaitingExpiry` 상태와 기존 `status + nextAttemptAt` index를 사용한다. 14일 만료 정리는 150명 단위, 최대 450 writes로 나눈다.
- Firestore Rules는 본인 joinedRooms projection이 남은 활성 계정만 종료 tombstone을 단건 읽게 하고 Messages/media read는 거부한다.
- iOS는 오프라인 종료 방을 참여중 목록에서 일반 방과 같은 cell로 복원하고, 행 선택 시에만 방 이름 포함 안내를 표시한다. 접속 중에는 Socket 종료 유형을 Coordinator까지 전달해 확인 후 공통 local cleaner로 정리한다.
- Functions lint/build와 185/185, Socket check·70/70, Firestore·Storage Rules 40/40과 transaction 21/21, iOS targeted 10개와 Production generic Simulator build를 통과했다. 기존 Functions non-null assertion warning 9개 외 오류는 없다.
- 배포 전 원격 index 41개·field override/TTL 29개가 로컬과 완전히 일치함을 확인했다. Storage Rules도 일치했고 Firestore Rules는 이전 `HEAD`와 정확히 같아 Phase 3.1 diff만 배포 대상으로 확정했다.
- Production Functions 5개는 hash `793eb4c2cbdaee4f6c57751deb9e3834537b83f4`, Node.js 24, asia-northeast3에서 모두 `ACTIVE`다. 신규 `acknowledgeRoomClosure`와 owner/admin close, room cleanup trigger/scheduler만 exact 배포했다.
- Firestore Rules 새 ruleset은 `d1a9ab22-d85b-4794-964c-8a9b9bc1197c`, source SHA-256 `5a298ab24098dc44179c805cde4720f4de5d807ee5f4f2222789fa551e9e8865`로 로컬과 일치한다. 이전 `943f0af9-d161-4f2c-ac01-cf376a4631b6`은 rollback 기준이다.
- Index/TTL, Storage Rules와 iOS artifact는 변경하지 않았다. 5분 cleanup scheduler는 `ENABLED`이고 배포 대상 서비스 최근 30분 ERROR는 0건이다.
- 2026-08-11 접속 중 방장 종료 QA에서 확인 후 채팅 route가 남는 문제와 Socket 즉시 이벤트의 종료 유형 누락을 보정했다. Socket build `a97273b4-46b5-4134-a82f-39a95e9b8eb0`, digest `sha256:29ddb169d993b5623fe3f7a9b8cf5bf2ac3ac2d508275a35604e7b47598ae379`, revision `outpick-socket-p31-owner-close-0811`을 candidate readiness·ERROR 0 확인 뒤 Production traffic 100%로 전환했다. 이전 `outpick-socket-account-cap-v2-0810`은 0% rollback으로 보존한다.
- 재QA에서 방장 종료 안내가 두 번 교체되고 확인 뒤 route가 남는 현상을 다시 확인했다. Socket 종료 side effect를 cleanup watcher 하나로 통일하고, iOS 전달·표시의 동일 room 중복을 차단하며 확인 탭 즉시 route를 제거하도록 재보정했다. Socket 70/70, iOS 대상 suite와 Production generic Simulator build가 통과했다.
- Socket build `74f8b018-1b4c-46ea-97de-9a226518d257`, digest `sha256:7cb2082aea3755a9f7bb395551bfe499cf0dfbb787e590a530a15e7103738fda`, revision `outpick-socket-p31-close-dedupe-0811`을 0% candidate readiness·ERROR 0 확인 뒤 Production traffic 100%로 전환했다. 직전 `outpick-socket-p31-owner-close-0811`은 0% rollback으로 보존한다.
- 오프라인 방장 삭제와 접속 중 방장 삭제 QA를 통과했다. 접속 중 관리자 종료에서 발견한 Google 참여중 목록 stale row는 retained 목록 즉시 제거와 stale fetch 재삽입 차단으로 보정했고, 변경 앱 재QA에서 Google/Kakao 모두 안내 1회·정확한 문구·확인 즉시 목록 복귀·pull-to-refresh 없는 방 제거를 통과했다. 오프라인 관리자 종료에서 발견한 서버 왕복 뒤 행 제거 지연도 확인 즉시 optimistic 제거·stale 재삽입 차단·서버 실패 복원으로 보정했다. 새 Production 방의 Google/Kakao 순차 재QA에서 안내 1회·확인 즉시 행 제거·재실행 미복원을 모두 통과했고, 사후 Production Auth 2개 전체 기준 member/joinedRooms/roomStates 0건, cleanup `awaitingExpiry`/`retention`과 정확한 14일 예약, 관련 ERROR 0건을 확인했다.
- Phase 3.1 변경은 4개 커밋으로 정리해 PR #10에서 리뷰했으며, 2026-08-11 merge commit `96111b8`로 `main`에 반영했다. TestFlight/App Store 앱 배포는 수행하지 않았다.

### Chat UGC Safety Phase 2~3 — Production 보정·실제 앱 QA 완료

- 신고·관리자 처리 Phase 2와 서버 권위 메시지 삭제·방 종료 lifecycle Phase 3을 구현하고 Production Functions·Rules·Indexes·Socket에 반영했다.
- 폐쇄 방을 제외하는 활성 `Rooms` query를 전체 목록·검색·참여방 ID·이름 중복 확인에 공통 적용하고 필요한 index 3개를 배포했다.
- 이미지 메시지 403 원인이 Storage Rules의 Firestore 문서 조회 3개로 인한 플랫폼 한도 2개 초과임을 확인했다. `moderationAccounts/{uid}` schema v2에 `accountStatus`를 포함해 Rules·Functions·Socket·Storage capability를 한 문서로 통합하고, 계정 삭제 transaction이 `users` 원본과 projection을 함께 갱신하도록 교정했다.
- 채팅 media read는 account projection + active room을 확인한다. upload는 Socket capability/room access를 통과해 발급된 짧은 TTL의 서버 전용 pending `MediaUploads/{messageID}` reservation + active room에서 sender·kind·path·expiry가 일치할 때만 허용한다.
- Production 사용자/projection 2건을 privacy-safe gate로 schema v2 backfill했고 사후 update/missing/unresolved는 0건이다. 원격 index 41개·field override 29개는 로컬과 완전히 일치해 이번 보정에서 index는 배포하지 않았다.
- 최종 Firestore ruleset은 `943f0af9-d161-4f2c-ac01-cf376a4631b6`, Storage ruleset은 `808a41e6-88f7-459a-b2fe-67fe6d351c04`이며 로컬·운영 source hash가 일치한다. 직전 두 ruleset도 rollback용으로 보존한다.
- capability 영향 Function 27개는 모두 ACTIVE다. Socket build `0f7842a6-c16a-4ae7-9436-bcc4d5f244a5`, revision `outpick-socket-account-cap-v2-0810`을 readiness·ERROR 0 뒤 traffic 100%로 전환했고 이전 `outpick-socket-moderation-p3-0810`은 0% rollback으로 보존한다.
- Functions lint/build·185/185, Socket check·70/70, Rules 40/40, transaction 20/20, JSON parse와 Production Rules dry-run을 통과했다. 170명 추가 참여자 방 종료도 Firestore batch 한도 안에서 완료됐다. 기존 Functions non-null assertion warning 9개 외 오류는 없다.
- PR 전 리뷰에서 대규모 closure notice batch 한도 초과 가능성, invalid roomName 때문에 물리 삭제가 중단될 가능성, exact contract schema 불일치를 발견해 모두 교정했다.
- 실제 Production 앱에서 이미지 메시지 정상 표시를 확인했다. 참여자 오프라인 중 관리자 종료 후 `“{방 이름}” 채팅방이 종료됐어요`가 정확히 한 번 표시되고, 확인 즉시 notice 삭제·재진입 중복 없음도 확인했다.
- QA room/job/audit/notice/Storage와 임시 App Check debug token을 정리했다. 최종 Production Cloud Run 최근 1시간 severity ERROR는 0건이다.

### Chat UGC Safety Phase 1 — Development 완료

- versioned HMAC alias, canonical moderation principal, current UID capability projection과 active/restricted/suspended 판정을 Functions·Rules·Storage·Socket·iOS bootstrap에 연결했다.
- Functions 154/154, Socket 69/69, Firestore·Storage Rules 35/35, transaction 11/11, iOS bootstrap targeted 6개와 Development generic Simulator build를 통과했다.
- Development Google 실제 제한 → 탈퇴 finalizer → 재가입에서 기존 restricted principal과 제한 안내 root 복원을 확인했다. 재가입 missing users 문서 read 경계도 Rules 보완·Emulator·Development 재배포 후 통과했다.
- Development Kakao 실제 로그인 → 제한 → 앱 재인증 삭제 예약 → 사용자 승인 단일 요청 즉시 finalizer → 동일 Kakao 재연결에서 HMAC alias 1개와 기존 restricted principal·stateVersion 2 복원을 확인했다. finalizer는 1회 completed·오류 0이며 Auth/users/moderationAccounts 삭제와 alias/principal 보존, 보존 원장의 민감 원문 필드 0개를 확인했다.
- 제한 안내 root를 경고성 패션 매거진 스타일로 교정하고 사용자 피드백에 따라 좌상단 원형 느낌표를 제거했다. `supportURL`이 없을 때 고객지원 문구/CTA를 함께 숨기고 계정 삭제·로그아웃은 유지한다.
- Apple 실제 QA는 현재 로그인 UI·Repository·재인증 진입점이 없어 별도 `sign-in-with-apple-account-lifecycle` 후속 작업으로 분리했다. Phase 1은 현재 지원 provider인 Google·Kakao 기준으로 완료 처리했다.
- Phase 1-P는 Kakao UID 숫자 후보를 Admin API `/v2/user/me` 응답 ID와 대조하는 helper, privacy-safe 건수 summary, Production exact 확인 문자열·expected total/Google/Kakao·unresolved 0 apply gate를 구현했다. persistent custom claims는 추가하지 않는다. 신규 10개를 포함한 Functions 164/164와 lint/build가 통과했으며 Production 환경은 변경하지 않았다.
- Production Auth dry-run은 total 2/resolved 2/unresolved 0, Google 1/Kakao 1/Apple 0으로 기대값과 일치했다. `--apply` 없이 종료했으며 Secret·Auth·Firestore·Functions·Rules·Storage·Socket 변경은 없었다.
- 사용자 별도 승인으로 Production `MODERATION_PRINCIPAL_HMAC_KEY_V1`을 256-bit 난수로 생성했다. 원문은 출력·로컬 저장하지 않았고 version 1 enabled를 metadata로 확인했다.
- Production `getMyModerationState` exact target만 배포했다. Node.js 24 Gen 2 ACTIVE, Secret version 1 binding과 해당 compute service account accessor를 확인했다. 무인증·App Check 없는 요청은 401로 거부됐고 배포 후 service ERROR는 0건이며, 인증 callable 호출은 아직 수행하지 않았다.
- Production backfill apply 직전 dry-run은 total 2/Google 1/Kakao 1/unresolved 0으로 재확인했고 exact gate로 2명을 처리했다. account/principal/alias는 각각 2개, Google/Kakao alias 각 1개, 모두 active이고 참조 무결성 정상, 금지 필드·Auth 민감 원문 값 0개다.
- Production capability 영향 callable 14개와 `finalizeExpiredAccountDeletions`를 exact target으로 배포했다. 15/15 Node.js 24 Gen 2 ACTIVE, 배포 후 ERROR 0, finalizer scheduler ENABLED이고 배포 전 source generation 15개가 모두 보존돼 있다. exact generation은 task `progress.md`에 기록했다.
- Production Firestore Rules는 배포 직전 Emulator Rules 35/35·transaction 11/11을 통과했다. 새 ruleset `82942b4b-d110-4ab0-8f09-ab0b4e5aad62`의 source hash는 로컬과 일치하고 이전 `bce94c07-bb86-4f9c-a74e-e14dc954085c`도 보존돼 있다.
- Production Storage Rules 새 ruleset `599b1ae1-21b0-4be1-a2f6-aa576369221a`의 source hash는 로컬과 일치하고 이전 `e0e75181-a23b-4dcf-a13c-df95bb9a70c6`도 보존돼 있다.
- Socket preflight `check`·69/69 통과 후 Cloud Build `2719bc50-1c06-45d6-923a-1549ad2d7ffe` image로 `outpick-socket-moderation-p1p` 0% tagged candidate를 배포했다. Ready/readiness 200/ERROR 0이고 live `outpick-socket-00008-4wl`은 100%다.
- Candidate `npm audit`에서 `socket.io-parser 4.2.6`의 비인증 원격 메모리 고갈 high GHSA-2m8v-j782-fhvr가 확인됐다. 패치 4.2.7은 현재 Socket.IO 허용 범위 안이므로 lockfile patch·69/69·audit·새 0% candidate 전 traffic 전환을 금지한다. moderate 8의 firebase-admin 전이 경로는 npm이 major downgrade만 제시해 별도 분석이 필요하다.
- 사용자 승인으로 `Socket/package-lock.json`의 parser만 4.2.7로 올렸다. `npm ci`, check·69/69, 설치 버전 4.2.7, production audit high 0/critical 0/moderate 8을 확인했다. 기존 4.2.6 candidate는 traffic 금지다.
- 패치 Cloud Build `3c6db117-22f6-46a9-93fb-112f6a0f64ae`, digest `sha256:a7c0a095c64adf0b83459f16a0caf3f68378ce3fffdaea0e919555a1da3b7dc5`로 `outpick-socket-moderation-p1p-r2` 0% candidate를 배포했다. Ready/readiness 200/ERROR 0이고 live `00008-4wl`은 100%다. 인증 handshake와 traffic 전환은 미수행이다.

### Production Worker contract 3 no-traffic candidate QA 완료

- 사용자 승인으로 Production Worker `lookbook-import-worker-00026-qes`를 source `1dbe6e1`, contract 3, traffic 0%로 배포했다. live `00024-fow` traffic 100%와 기존 rollback `00023-879`는 유지했다.
- 배포 전 Worker 115/115, lint/build와 fixture 9/9를 통과했다. candidate는 Ready이며 runtime은 source `1dbe6e1`, contract 3, extractor `1.2.3`, Cafe24 `1.0.1`이다.
- 사용자 `gayunkim.1@gmail.com`에 Production task/functions service account 두 exact 리소스의 `roles/iam.serviceAccountOpenIdTokenCreator`만 영구 부여했다. `generateIdToken` 직접 호출만 사용하며 project-level Token Creator, access token impersonation, signing과 key는 사용하지 않는다.
- OIDC caller matrix에서 task identity는 `/readyz` 200, import/discovery 빈 payload 500, runtime 403이었고 functions identity는 runtime 200, diagnostic 빈 payload 500, import/discovery 403이었다.
- 기존 Production 해칭룸 실제 URL로 discovery 후보 20개·목록 대표 이미지 20개, image extraction 후보 12개를 확인했다. 두 stage 모두 HTTP 200, failure 0, logic issue 없음이었다.
- caller matrix의 의도한 빈 payload 세 요청만 request ERROR로 기록됐고 이후 actual smoke의 unexpected ERROR와 import queue pending은 0건이다.
- token response와 candidate QA 임시 파일, 배포용 임시 clean worktree를 정리했다.

### Production Worker contract 3 traffic 전환 완료

- 전환 직전 candidate Ready, 기존 `00024-fow` traffic 100%, import queue pending 0과 actual smoke 이후 unexpected ERROR 0을 재확인했다.
- 사용자 명시 승인으로 `lookbook-import-worker-00026-qes=100`만 적용했다. `00024-fow`는 traffic 0% rollback revision으로 보존했다.
- canonical service URL의 `/readyz`, `/runtime-contract`와 기존 해칭룸 성공 import job의 실제 image smoke가 모두 HTTP 200이었다.
- live runtime은 `00026-qes`, source `1dbe6e1`, contract 3, extractor `1.2.3`, Cafe24 `1.0.1`이고 image 후보 12개·logic issue false·failure 0이었다.
- 전환 후 import queue pending 0, 검증 시작 이후 severity ERROR 0을 확인했다.

### Production durable discovery/issue operations backend 완료

- Firestore `candidates(resolution ASC, sortIndex ASC)` composite 1개, collection-group field override 3개, TTL 6개를 배포해 모두 `READY`/`ACTIVE`를 확인했다. `--force`를 사용하지 않아 기존 remote override 5개는 보존했다.
- `lookbook-discovery-jobs`를 초당 1건·동시 1건·최대 3회·30~300초 backoff·1시간 retry duration으로 생성했고 `RUNNING`을 확인했다.
- Production operator `outpick-extraction-ops-prod@outpick-664ae.iam.gserviceaccount.com`과 exact 최소 IAM을 적용했다. 사용자에게 operator OIDC ID token 생성 역할만, operator에게 private read/write/release invoker만 부여했고 public invoker는 없다.
- durable discovery 7개, issue operations 4개와 `createBrand`를 합친 Function 12개를 배포했다. 모두 ACTIVE/Node 24이며 실제 URI·audience와 10분 scheduler 2개가 일치한다.
- 운영 CLI는 broad `gcloud --impersonate-service-account`를 제거하고 고정 사용자 access token으로 exact operator IAM Credentials `generateIdToken`만 직접 호출하도록 교정했다. CLI 9/9·lint/build, Functions 146/146·lint/build가 통과했다.
- Production private API는 무인증 read 403, operator read 성공, 존재하지 않는 fingerprint write 404로 데이터 변경 없이 검증했다. 배포 후 두 queue task 0, `seasonDiscoveryJobs` 0, Worker/Function 12개 신규 severity ERROR 0이다.

### Production Phase 5 첫 smoke와 rules blocker

- Production Simulator build가 성공했고 Kakao 총 관리자 `kakao:3647141989`로 앱 로그인했다. Google 앱 계정에는 `brandAdmins`가 없으며 새 권한을 추가하지 않았다.
- QA 브랜드 `PC1aBgoDY9PbWHCroRXq`, job `NBNCRkQ6Q8m9gA4kJ0EN`을 생성했다. job은 contract 3·attempt 1·retry 0 `succeeded`, candidate 80·list cover 80이다.
- 앱은 candidate 조회에서 `Missing or insufficient permissions`를 표시했다. Production ruleset과 로컬 전체 diff는 `seasonDiscoveryJobs`, `candidates`, `reviews`의 `hasBrandWriteAccess` read와 client write deny 15줄뿐이다.
- rules emulator는 rules 30/30, transaction 7/7과 seed 재-dry-run 변경 0을 통과했다. Firebase CLI wrapper는 성공적인 정리 뒤 unexpected error로 exit 2였으므로 명령 전체 종료는 미통과다.
- 최초 URL로 `/archive`를 사용한 것은 판단 오류다. 현재 상품 목록 80개를 반환하므로 이 결과는 유효한 시즌 QA가 아니다. 기존 Production 해칭룸의 canonical URL `https://hatchingroom.com/product/archive-list.html?cate_no=226`로 교정해야 한다.
- 첫 smoke 이후 import/discovery queue task 0, Worker/Functions severity ERROR 0을 확인했다.
- 첫 smoke 시점에는 QA 데이터를 삭제하지 않았고 rules 배포, URL 교정, 재검증과 cleanup을 각각 별도 승인 게이트로 유지했다. 이후 승인된 cleanup까지 완료했다.

### Production Phase 5 canonical smoke 완료

- 사용자 승인으로 exact `firestore.rules`를 Production에 배포했다. 새 ruleset은 `bce94c07-bb86-4f9c-a74e-e14dc954085c`이며 로컬·운영 SHA-256 `d1978d27b63a73ae5bc230c3fed4bf9c3b0484b6fd44f7305fd8372ffb59cc74`가 일치한다.
- QA 브랜드 `PC1aBgoDY9PbWHCroRXq`의 archive URL을 canonical 해칭룸 URL로 교정하고 job `x7JF1V6Y9byFJI6NyStR`을 요청했다. 후보 20·대표 이미지 20·목록 대표 이미지 20으로 성공했고 Kakao 총 관리자 앱 카드에서 실제 이미지와 제목을 확인했다.
- 재검증 뒤 discovery queue는 `RUNNING`·task 0, smoke 이후 Worker/Functions severity ERROR 0이다.
- `CreateBrandDiscoveryViewModel`은 Firebase/infrastructure 원문을 내부 진단 로그로만 남기고 화면에는 `시즌 목록을 불러오지 못했어요. 브랜드 등록을 마친 뒤 다시 찾아올 수 있어요.`를 전달하도록 교정했다. 실패 원문 비노출과 성공 결과 발행 targeted 테스트를 추가해 관련 9/9와 Production Simulator 구성을 빌드 통과했다.
- 이후 빠른 화면 조작·시각 QA는 사용자가 체크리스트로 수행하고, Codex는 Simulator를 직접 조작하지 않는다. Codex는 코드 변경, 자동 테스트·빌드, backend/log 자동 검증을 담당한다.
- 사용자 파괴 승인으로 QA 브랜드 부모 1개, 두 job과 후보 100개를 포함한 하위 102개, `brandNameIndex` 1개를 영구 삭제했다. Firestore·Storage 잔존은 0건이다.
- 코드·앱 참조가 제거된 `requestLookbookExtractionReanalysis`를 삭제하고 현재 fixed/runtime 경계를 강제하는 `retryLookbookExtractionAfterFix` 하나를 exact 배포해 ACTIVE를 확인했다. 삭제 뒤 replacement 미배포 상태를 발견해 보완했으며 Functions lint/build와 전체 146/146이 통과했다.
- 7일 retention 만료 후 legacy cluster 3개, evidence 문서 3개와 대응 Storage JSON 3개를 영구 삭제해 잔존 0건을 확인했다. 게시된 시즌이 참조하는 해칭룸·언어팩티드·이그노타 import job 3개와 시즌·포스트는 보존했다.
- 최종 검증은 두 queue task 0, 2026-08-06T07:14:00Z 이후 Cloud Run ERROR 0, replacement ACTIVE, legacy callable 404, 보존 import job·시즌 3쌍 200이다.

### Lookbook extraction issue operations — Development 범위 종료

- 이전 task를 Development 구현·배포·실데이터 QA 완료로 종료했다.
- 실제 `seasonImageImport` 결함의 `fixed → retry success → verified`는 결함 발생 시 이벤트 기반 운영 게이트로 유지한다.
- Production rollout은 별도 핵심 task로, legacy callable/data cleanup은 rollout과도 분리된 파괴 승인 작업으로 전환했다.
- 새 task 하네스는 `docs/ai/tasks/lookbook-extraction-issue-operations-production-rollout/`에 작성했다.

### Phase 7 시즌 대표 이미지 보강 — Development 배포·실데이터 QA 완료

- 시즌 identity와 대표 이미지 표시를 분리하고 `coverImageURL` 유무로 유효 시즌 후보를 제거하지 않기로 확정했다.
- 대표 이미지 우선순위는 모든 브랜드에 `목록 행 이미지 → 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지 → 없음`으로 고정했다.
- 상세 fallback은 platform adapter 유무와 관계없이 적용한다. Generic 규칙으로 실제 시즌 콘텐츠 영역을 찾고 Cafe24 등 Platform/Domain 규칙은 식별 정확도만 보강한다. header/navigation/banner/footer/related와 low-confidence 전체 페이지 후보는 제외한다.
- 보강은 저장 대상 중 이미지 없는 앞 30개, 동시 3개, 전체 15초의 best-effort이며 실패는 후보 이미지만 `null`로 남기고 discovery 상태와 issue 판정을 바꾸지 않는다.
- candidate provenance, job cover 집계, snapshot hash와 season discovery `contract:3` 경계를 확정했다. extractor는 `1.2.3`을 유지했고 실제 QA에서 구형 `collection-images` 직접 영역을 보강해 Cafe24 adapter를 `1.0.1`로 올렸다.
- 기존 import 이미지 선택을 `image-candidates.ts` 순수 모듈로 분리하고, Generic 콘텐츠 영역과 Cafe24 상세 페이지 대표 이미지 fixture를 추가했다. 기존 import 선택 결과와 extractor/adapter version은 유지했다.
- 이미지 없는 저장 대상 앞 30개만 동시 3개·전체 15초 안에서 best-effort로 상세 페이지를 읽는 `season-cover.ts`를 추가했다. 목록 이미지 우선, 후보 순서·identity 보존, 개별 실패 격리와 deadline skip을 테스트로 고정했다.
- 시즌 후보의 cover 기반 제거를 삭제하고 candidate provenance, job cover 집계, snapshot hash와 Worker/Functions `contract:3` 저장 계약을 구현했다.
- 최종 로컬 검증은 Worker 115/115·fixture 9/9·lint/build, Functions 146/146·lint/build, iOS Development Simulator build가 모두 통과했다.
- Development Functions 9개를 contract 3으로 배포했고 Worker `00012-fih` source `3597b2b`, contract 3, extractor `1.2.3`, Cafe24 `1.0.1`로 traffic 100% 전환했다. rollback은 `00010-hiq`다.
- 앱에서 생성한 최종 AMOMENTO job `GwToZCXiZ9iUfKp4tDMg`은 후보 15개·대표 이미지 15개·상세 실패 0으로 성공했다. 저장 URL 15개와 실제 상세 첫 유효 이미지가 모두 일치하고 Simulator 카드 전체 이미지, queue pending 0과 신규 ERROR 0을 확인했다.
- 목록 cover 회귀는 Development OUTSTANDING 브랜드 `Mb9JqermkE2ZalNAPJXH`의 generation 1 `xr4zoCHdp3vr0AXQXMcE`과 generation 2 `Yl9353dPQLywApLqrZTU`로 확인했다. 후보 44개 snapshot hash가 동일하고 누락·추가·변경 0건, 전부 `list/listElementImage`, 상세 fallback 0회, 실제 이미지 HTTP 성공 44/44였다. 기존 동적 페이지 감지 때문에 상태는 예상대로 `correctionRequired`이며 두 queue와 신규 ERROR는 0건이다. 사용자 삭제 승인 후 브랜드 subtree 91문서, QA evidence 2문서, 전용 cluster 1문서와 Storage 객체 3개를 영구 삭제했고 잔존 0건을 확인했다.
- Development와 Production OIDC QA는 각각 두 exact task/functions 서비스 계정 리소스에 사용자 `gayunkim.1@gmail.com`의 `roles/iam.serviceAccountOpenIdTokenCreator`만 영구 유지한다. project-level Token Creator와 서비스 계정 key는 사용하지 않는다.

### AMOMENTO 첫 실제 extraction fix — Development 실제 loop 완료

- AMOMENTO archive가 링크가 아니라 `button.archive-modal-link[data-url]`로 15개 시즌을 제공해 기존 anchor-only discovery가 0건이 된 원인을 실페이지에서 확인했다.
- Worker가 `button[data-url]`의 `collection-single.html`을 기존 URL 안전 검증과 후보 scoring으로 읽고, 버튼 본문의 끝자리 ISO 날짜를 제목에서 제거하도록 Cafe24 공통 로직을 보강했다. 브랜드 전용 adapter나 15개 모달 클릭은 추가하지 않았다.
- 새 시즌 discovery job과 Worker runtime을 `contract:2`로 일치시키도록 Functions canonical revision과 Development/Production 공용 배포 script 값을 함께 올렸다. Production 배포는 수행하지 않았다.
- 앱의 시즌 목록·이미지 issue 설명에서 `추출 로직/개선된 방식` 표현을 제거하고 `가져오지 못했어요/확인하고 있어요/다시 가져올 수 있어요`로 단순화했다.
- 최종 검증은 Functions 145/145·lint/build, Worker 103/103·fixture 6/6·lint/build, iOS targeted test 12개와 Development Simulator build가 통과했다.
- Development Worker `lookbook-import-worker-development-00008-foq`를 source `a9a57b5802f24eb83e051efb6733a8eb2deadbe4`, contract 2로 traffic 100% 전환했다. rollback은 `00006-pob`다.
- AMOMENTO ground truth 15개 actual smoke로 cluster `fixed` version 5를 열고, Simulator 총 관리자 재시도 job `eK2fR8yhIZQ23gNDKuVs`가 후보 15개·contract 2로 성공한 뒤 cluster `verified` version 6을 확인했다. 관련 queue와 ERROR는 0건이다.
- 통합 중 tag-only 0% traffic 오인, 삭제된 대표 job, 새 시즌 재시도 job의 fix projection 누락을 발견해 Functions에 회귀 테스트와 함께 보강했다. verifier 재배포 뒤 Development operator invoker binding도 정확한 전용 계정만 복구했다.

### 이전 Phase 2 변경 보존

- extraction 검토가 `correctionRequired`로 전환된 뒤 저장된 입력을 더 이상 미저장 초안으로 취급하지 않고 interactive-pop 차단을 해제했다.
- browse controller의 edge/content pop 가능 상태를 명시적으로 갱신하는 회귀 테스트를 보완했다.
- iPhone 17 Pro Max iOS 26.2 Simulator에서 다음 targeted test 12개가 통과했다.
  - `LookbookExtractionReviewViewModelTests` 9개
  - `LookbookNavigationControllerTests` 3개
- 기존 Swift 6 actor isolation, deprecated API, library search path 경고는 남아 있으나 이번 변경 관련 실패는 없었다.
- 커밋:
  - `df74e29 fix: 검토 완료 후 스와이프 복귀 허용`
  - `7496d2e test: 검토 화면 스와이프 복귀 회귀 검증`
  - `12c35cd chore: Xcode 개발 서명 설정 명시`
  - `319bbf2 docs: 환경 분리 작업을 현재 task로 전환`

### 환경 분리 읽기 전용 조사

- 현재 Xcode는 app target 1개, `OutPick` scheme 1개, `Debug`/`Release` configuration 2개다.
- 두 app configuration 모두 `GayoonKim.OutPick`을 사용하고 xcconfig 환경 분리는 없다.
- 운영 plist는 `GayoonKim.OutPick`/`outpick-664ae` 조합이다.
- 기존 실제 Firebase UI test plist는 `GayoonKim.OutPick`/`outpick-test` 조합이고 Google OAuth `CLIENT_ID`가 없다. 새 Development 앱 plist로 재사용할 수 없다.
- Firestore·Storage·Auth·Functions는 기본 `FirebaseApp`을 사용하므로 올바른 plist를 주입하면 프로젝트가 함께 분리된다.
- iOS Socket은 운영 Cloud Run URL을 하드코딩하고 Firebase ID Token을 전송한다.
- 조사 당시 scheme의 `OUTPICK_SOCKET_URL`과 코드의 `OUTPICK_DEBUG_SOCKET_URL` 이름이 달라 기존 override가 동작하지 않았다. 현재는 `AppRuntimeConfiguration`과 `RealtimeSocketService`가 `OUTPICK_SOCKET_URL`을 사용하도록 통일했다.
- 2026-08-01 Cloud Run 읽기 전용 조회 결과 `outpick-test`에는 Socket 서비스가 없고 Functions도 운영보다 오래된 일부만 존재한다.
- Socket Firebase Admin의 기본 Storage bucket이 운영 bucket으로 고정되어 있어 동일 이미지를 test project에 그대로 배포하면 안 된다.

### 사용자 확정 결정

- 이전 Phase 2는 정상 커밋으로 보존하고 별도 worktree는 사용하지 않는다.
- 환경 분리 구현은 전용 `codex/development-production-environment-separation` 브랜치에서 진행한다.
- Development backend는 Functions·Rules·Indexes·Storage·Socket 기능 동등성 모드로 진행한다.
- Simulator 환경 분리를 우선 완료하고 Development 실기기 App Attest는 Apple/Firebase 등록 가능 상태를 확인한 뒤 진행한다.
- `main` branch protection은 PR 경유·대화 해결·관리자 적용·force push/삭제 금지로 구성했다. 유료 Rulesets와 필수 CI status check, release tag 자동화, preview project, 미사용 capability는 이번 범위에서 제외한다.

### Phase 1 — Xcode 환경 골격과 fail-fast

- `OutPick-Development`, `OutPick-Production` shared scheme과 Development/Production 각각 Debug/Release configuration을 추가했다.
- `Configurations/`의 공통·환경별 xcconfig가 Bundle ID, 표시 이름, Firebase project/plist 경로, Socket URL을 제공한다.
- 실제 Firebase plist는 `LocalSecrets/Firebase/{Development,Production}/GoogleService-Info.plist`에서만 읽는다.
- Build Phase가 plist 존재 여부, `BUNDLE_ID`, `PROJECT_ID`, 환경별 Socket 조합을 검증한 뒤 앱 번들에 단일 plist만 복사한다.
- validator fixture test, Xcode scheme/configuration 조회, 양 환경 build setting 확인을 통과했다.
- Production generic Simulator build와 생성된 앱 번들 값 대조를 통과했다.
- Development generic Simulator build는 Development plist가 없어 명시적 오류로 실패했으며 운영 설정으로 fallback하지 않았다.

### Phase 2 — Firebase·Auth runtime 완료

- `outpick-test`에 `OutPick Development` / `GayoonKim.OutPick.dev` Firebase iOS 앱을 생성하고 전용 plist를 LocalSecrets에 저장했다.
- `AppRuntimeConfiguration`이 Bundle ID, Firebase project, Google callback, Kakao Native App Key/callback, Socket URL을 runtime fail-closed 검증한다.
- AppDelegate는 검증한 plist로 Firebase를 명시 구성하고 Kakao Native App Key를 환경값에서 읽는다.
- RealtimeSocketService는 하드코딩 운영 URL 대신 검증된 runtime Socket URL을 사용한다.
- 실제 Firebase UI test override 기본 경로를 새 Development plist로 전환했다.
- validator test, Production build, 환경 unit test 6개(총 12건), Production Simulator launch를 통과했다.
- Google Auth Platform 외부 테스트 구성, Development iOS OAuth client, 테스트 사용자 등록을 완료하고 새 Firebase plist의 callback 정합성을 확인했다.
- Kakao 운영 Native App Key/Bundle ID는 보존하고 Development 전용 Native App Key `f5f18b00bc7b163aa5be39fef99e646d`와 `GayoonKim.OutPick.dev`를 등록했다.
- Development xcconfig에 Google/Kakao callback 값을 연결했다.
- Phase 3 Development Socket `outpick-socket-development`를 `outpick-test`에 배포하고 Development xcconfig에 canonical URL을 연결했다.
- 전용 service account는 Firestore/FCM/Auth Viewer project 역할과 Development Storage bucket 한정 객체 역할만 사용한다.
- Socket 정적 검사·64개 테스트, `/readyz`, 배포 직후 ERROR 0건을 확인했다.
- Development generic Simulator build, Production/Development 동시 설치, Development 로그인 화면 실행을 확인했다.
- Development 테스트 ID Token으로 실제 Socket handshake와 `server:connect:ready` 수신을 확인했다.
- reset gate의 운영 project 오지정을 `outpick-test` 전용으로 교정했고 Functions 100개 테스트를 통과했다.
- Firestore/Storage Rules를 `outpick-test`에 배포하고 Rules 29개·transaction 7개 emulator 검증을 통과했다.
- 로컬 Firestore index 33개를 배포했으며 기존 레거시 Rooms index 2개를 보존하고 전체 35개 `READY`를 확인했다.
- Secret Manager/Cloud Tasks API와 Development 계정 삭제 Secret 2개를 구성했다.
- 사용자 명시 승인 후 자동 삭제 Scheduler를 포함한 비-worker Functions 53개를 배포했다. 61개 Function이 모두 `ACTIVE`이고 Scheduler 3개가 `ENABLED`다.
- 48개 callable transport를 검증하고 IAM quota로 invoker가 누락된 `exchangeKakaoToken` 하나를 복구했다. 감사 로그 제외 runtime ERROR는 0건이다.
- Development 전용 Lookbook import worker, Cloud Tasks queue와 task/worker identity를 구성하고 worker 의존 Functions 15개를 연결했다. Functions 74개가 모두 `ACTIVE`다.
- worker `lookbook-import-worker-development-00003-5kc`는 traffic 100%이며 `outpick-test` project/bucket을 명시한다. Cloud Run 비공개 IAM과 애플리케이션 OIDC 이중 검증을 사용하고 task/Functions 호출 경로를 분리한다.
- `/readyz`와 경로별 빈 payload smoke로 IAM·OIDC·routing을 확인했다. 실제 import/materialization은 실행하지 않았다.
- Phase 3 reset allowlist 실제 QA를 완료했다. `outpick-test` dry-run과 실제 reset, 비-allowlist Firestore/Auth sentinel 보존, fixture 복구, 운영 project 시작 거부를 확인했다.
- QA Kakao token은 logout API HTTP 200으로 폐기했고 token 원문이 있던 local runtime log를 삭제했다.
- `outpick-test` Google provider를 활성화하고 실제 Google OAuth callback → Firebase login → Development 온보딩 진입을 확인했다.
- `outpick-auth-functions-dev@outpick-test.iam.gserviceaccount.com`을 만들고 자기 자신에만 Token Creator를 부여했다. `exchangeKakaoToken` 한 함수만 이 계정으로 재배포했으며 `ACTIVE`와 실제 runtime identity를 확인했다.
- 인증 runtime parameter 누락·형식·프로젝트 불일치 테스트를 추가했고 Functions lint/build/test 104개가 통과했다.
- Simulator App Check debug token을 Development iOS 앱에 등록했다. 앱 재설치 뒤 기존 token을 폐기하고 새 token으로 회전했으며 token 원문은 기록하지 않았다.
- `outpick-test.styleMoods`가 0건이라 Google QA 로그아웃을 위해 임시 profile 3개 문서를 만들었고 정상 로그아웃 직후 모두 삭제했다.
- Kakao 재인증·동의 후 Development callback, custom-token Firebase 로그인과 온보딩 진입을 확인했다. Firebase Auth에 `kakao:*` 사용자가 생성됐고 callable App Check는 `VALID`, signBlob/IAM/runtime ERROR는 0건이다.
- 운영과 동일한 v1 style mood seed를 `outpick-test`에 적용했다. 무드 56개·검색어 인덱스 137개·metadata version 1/count 56이며 운영과 content hash가 같다. 사후 dry-run 변경은 0건이다.
- Kakao 신규 사용자 온보딩에서 스타일 목록 표시, 캐주얼 1개 선택, active account/public profile 저장과 메인 화면 진입을 확인했다. `completeOnboarding` ERROR는 0건이다.
- Phase 4 마감 검증에서 네 Xcode configuration build와 산출물 환경 대조, validator/runtime test, Functions 104개, Socket 64개, worker 74개·fixture 5개, Test Admin Server build를 통과했다.
- Development Functions 74개 ACTIVE, Socket/worker Ready와 traffic 100%, queue pending 0, Socket `/readyz`와 Engine.IO handshake를 재확인했다. tracked secret과 민감 token/private-key 패턴은 발견되지 않았다.
- Production 무변경 dry-run은 `OUTPICK_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL` 누락으로 실패했다. 테스트된 resolver는 실제 Function 옵션에서 쓰이지 않고 필수 parameter가 직접 연결된 상태라 Phase 4를 완료 처리하지 않았다.
- 사용자 승인으로 Production 전용 인증 계정 `outpick-auth-functions-prod@outpick-664ae.iam.gserviceaccount.com`을 생성했다. project 역할은 없고 자기 리소스 Token Creator만 가진다.
- Firebase parameter가 Development/Production 승인 계정만 허용하도록 실제 계약 테스트를 교정하고 Production `.env`에 연결했다. Functions lint/build/test 103개와 Production non-interactive dry-run이 통과해 Phase 4 차단을 해제했다.
- dry-run만 수행했으므로 실제 Production `exchangeKakaoToken`은 기존 revision과 compute runtime identity를 유지한다. Production identity 전환 배포는 별도 승인 전에는 수행하지 않는다.
- 이후 사용자 명시 승인으로 Production `exchangeKakaoToken` 한 함수만 배포했다. revision `exchangekakaotoken-00042-geb`가 ACTIVE/Ready·traffic 100%이며 runtime identity가 Production 전용 계정으로 전환됐다.
- 빈 callable payload는 앱 계층 INVALID_ARGUMENT HTTP 400을 반환했고 배포 이후 severity ERROR 로그는 0건이다. 이후 Production Kakao 실제 로그인에서 callback, Function HTTP 200, 기존 프로필 복원과 앱 로그아웃까지 확인했다.
- 미사용 Cloud Run `lookbook-import-worker`는 실제 요청·Functions/Cloud Tasks 참조가 없음을 감사한 뒤 사용자 승인으로 삭제했다. 정식 `lookbook-import-worker-development-00003-5kc`는 Ready·traffic 100%다.
- Google/Kakao QA Auth 2개와 연결된 사용자/profile/nickname/device/meta 데이터, 테스트 잔여 `commentDeletionLogs` 2건을 삭제했다. `uitest-*` fixture와 스타일 무드 seed는 보존했다.
- W3C 전용 sample로 Firestore trigger → Cloud Tasks → Development worker → review → materialization 실제 smoke를 완료했다. job은 `succeeded`, post 5개, asset 6/6 `ready`, worker ERROR 0건이었다.
- smoke 브랜드 tree, Storage 12개, evidence ledger/JSON과 단독 issue cluster를 삭제했고 Firestore·Storage 잔존 0건을 확인했다.
- PR #3 리뷰에서 Development에 Production Kakao 키·scheme을 함께 넣으면 기존 자기 일치 검증을 통과하는 P2를 재현했다. xcconfig와 독립된 환경별 canonical 키를 build/runtime에 고정하고 양방향 교차 테스트를 추가했다.
- Firebase validator test, `AppRuntimeConfigurationTests` 8개, Development/Production Debug·Release 네 구성을 다시 검증했고 모두 통과했다. 전체 diff 재리뷰에서 추가 차단 사항은 없었다.
- 중간 리뷰에서 구현·테스트·문서 3개 후속 커밋을 push하고 PR #3 본문에 P2 수정과 Production Kakao QA를 반영해 head `5d89377`을 Ready로 전환했다. 이후 추가 P2 보완·candidate 검증·병합 결과는 아래 최종 종료 기록이 우선한다.
- DEV 아이콘 배지는 사용자 결정으로 추가하지 않는다. `OutPick DEV` 표시 이름은 유지한다.

### 환경 분리 최종 종료

- PR #3 리뷰에서 Socket canonical origin, Kakao canonical key, Firebase project, Functions identity, Worker OIDC caller·Storage bucket 교차 경계를 exact contract로 보완했다.
- Worker는 최종 83개 테스트·fixture 5개, Functions 104개, iOS `AppRuntimeConfigurationTests` 13개, 배포 계약 테스트를 통과했다.
- 첫 Production candidate 배포에서 Cloud Run service명+traffic tag 46자 제한을 발견했다. revision 생성 전 안전하게 중단된 뒤 `cand-YYYYMMDD-HHMMSS`와 결합 길이 회귀 테스트로 수정했다.
- PR #3 head `5a61d1f`의 candidate `lookbook-import-worker-00024-fow`를 traffic 0%로 검증했다. canonical task `/readyz` 200, task 빈 import 500, Functions 빈 diagnostic 500, Functions→import 403을 확인했다.
- PR #3은 기능·테스트·백엔드·문서·배포 계약의 16개 작업 단위 커밋을 보존한 merge commit `7383a0e`로 병합했다. main tree와 candidate source가 동일함을 확인한 뒤 Production traffic을 `00024-fow` 100%로 전환했다. rollback은 `00023-879`이다.
- Production W3C import smoke는 trigger → Cloud Tasks → Worker → review → materialization에서 `succeeded/completed`, season 1개, post 5개, asset 6/6 `ready`로 완료됐다.
- smoke Firestore tree·Storage 12개·evidence ledger/JSON·단독 issue cluster를 삭제했다. 전환 후 Worker ERROR, queue pending, smoke 데이터 잔존은 모두 0건이다.
- 운영 결과는 문서 전용 PR #4의 커밋 `6a88016`과 merge commit `9d6a7db`로 `main`에 반영했다.

## 3. 완료 범위 밖 후속 후보와 현재 설계 task

- 최우선: `chat-ugc-safety-room-moderation` Phase 7.4D Development 완료 뒤 Phase 7.5 신고 UX·관리자 종결 분리·Deletion Sync 설계를 확정했다. 구현은 사용자 별도 승인 전 시작하지 않고 Production은 변경하지 않는다.
- Phase 7.4A~D에 구현된 긴급 2명 또는 전체 3명/24시간 자동 비노출과 단일 관리자 decision은 완료 이력으로만 남는다. Phase 7.5 구현에서 threshold를 queue-only로 바꾸고 `reviewOutcome + contentAction + accountAction`, 일반 tombstone Deletion Sync 계약으로 migration해야 한다.

1. Development 실기기 App Attest는 Apple Developer Program 가입 후 외부 의존 후속 작업으로 재개한다.
2. Phase 4 실제 기기 background FCM/APNs와 답장 안내 접근성 표시는 Apple Developer Program 가입·APNs 설정 후 출시 전 외부 gate에서 확인한다.
3. Production Google 실제 로그인과 provider별 계정 삭제 요청·취소 재인증 smoke는 출시 전 QA로 남는다.
4. PITR·예약 백업·Storage soft delete·복구 훈련은 출시 운영 게이트로 남는다.
5. 후속 후보 `lookbook-discovery-learning-loop`는 브랜드 생성 직후 시즌 후보를 자동 추출하고 관리자 확인 후 선택 시즌 이미지를 추출하는 흐름을 유지한다. 2026-08-04 사용자 승인으로 Firestore job + 전용 Cloud Tasks + Cloud Run Worker의 핵심 구현과 iOS 관찰 접합부를 완료했다. 앱은 화면 종료 시 서버 job을 취소하지 않으며 최초 job ID 또는 published pointer로 상태를 복원한다.
6. 같은 후속 후보의 시즌 동일성은 URL을 우선하되, URL이 달라도 동일 브랜드 안에서 정규화한 시즌 이름이 기존 시즌 하나와 유일하게 일치하면 기존 시즌으로 연결하고 최신 source URL만 갱신한다. 모호한 일반명이나 복수 일치는 관리자 검토로 보내며 URL 변경만으로 이미지 재추출을 자동 시작하지 않는다.
7. 추출 규칙 변경은 계층과 무관하게 전체 fixture corpus를 실행하고 Domain/Platform/Generic 영향 범위별 추가 증거를 요구한다. 기존 성공 결과의 후보 수·집합·순서·제목·strategy·adapter·quality에 예상하지 못한 differential이 생기면 배포를 중단한다. 의도된 개선만 ground truth, golden 갱신, version bump, Development 실제 URL smoke와 사용자 승인 뒤 Production으로 전환하며, CI required check와 직접 배포·traffic 전환 우회 차단을 후속 설계 범위에 포함한다.
7. fixture는 브랜드별로 무조건 추가하지 않고 같은 platform/template/strategy/reason/구조 원인은 기존 issue cluster와 대표 fixture에 통합한다. 수정 버전 이상에서 같은 fingerprint가 재발하면 `open`/recurrence로 처리해 우선 조사하며, 기존 fixture 재실패는 회귀와 배포 중단·rollback, fixture 통과 후 실제 URL 실패는 불충분 fixture·새 변형·adapter 미선택·잘못된 계층·네트워크/차단 문제로 분류한다. cluster 통합은 중복 fixture 방지일 뿐 재발 무시나 자동 승인이 아니다.
8. 동일 brand/canonical archive URL/extraction contract의 active 요청은 하나의 job으로 합치고 다른 입력만 새 generation으로 처리한다. candidate snapshot과 일반 완료 job은 30일, 실패 요약과 관리자 검토 audit은 60일, evidence는 7일 보존하며 active와 `awaitingReview/correctionRequired`에는 TTL을 두지 않는다.
9. 최초 discovery job은 `createBrand` transaction에서 브랜드와 함께 생성한다. active job은 watchdog이 누락 task·만료 lease·stale generation·retry 소진을 감시해 복구 또는 `failed/cancelled/superseded`로 수렴시키며, `awaitingReview/correctionRequired`는 TTL이 아니라 관리자 판단·로직 보강 후 재분석·취소로 닫는다.
10. 추출 로직 보강 뒤 시즌 목록은 새 discovery generation으로, 특정 시즌 이미지는 기존 import job의 새 review/dispatch generation으로 다시 분석한다. transient 재시도, URL 수정, 관리자 검토, 보강 대기, 재분석, 취소를 원인별 action으로 구분하고 모든 과거 실패를 자동 재실행하지 않는다.
11. 2026-08-04 Development `outpick-test`에 `lookbook-discovery-jobs`, 관련 Functions 8개, rules/index/TTL과 Worker `lookbook-import-worker-development-00004-xal`을 배포했다. OUTSTANDING 실제 URL 2회와 동일 callable 3건 병합을 통과했고 queue·ERROR·QA 데이터 잔존은 0건이다.
12. 실제 OUTSTANDING 페이지는 후보 44개와 `load_more_detected`/`dynamic_rendering_detected`로 `correctionRequired`가 됐다. 파이프라인은 안전하게 동작했지만 extractor/fixture ground truth 보강이 필요하다.
13. active 상태 카드의 `ProgressView + 주 문구 + 보조 문구` 묶음 전체는 카드 본문 중앙에 두고 header와 취소 action은 분리한다. 고정 pixel offset 대신 작은 화면과 Dynamic Type에서 검증한다.
14. 현재 Phase 4A의 `correctionRequired`는 `추출 개선 요청 → 개선 요청됨 → 다시 가져오기 가능`으로 구현돼 있다. 확정된 Phase 4B에서는 버튼을 제거하고 시즌 목록·시즌 이미지 추출 로직 불충분을 서버가 자동 기록하며, 앱은 `개선 대기 중 → 개선 처리 중 → 다시 가져오기 가능`만 표시한다.
15. 개선 준비 판정은 문자열 version이 아니라 단조 증가 정수 `extractionContractRevision`을 사용한다. Worker candidate 검증과 환경 traffic 준비가 끝난 뒤 Functions canonical revision을 올리는 순서를 강제한다.
16. Phase 3A는 `SeasonImportManagementView.activeDiscoveryContent`에서 spinner·주 문구·보조 문구 묶음 전체를 카드 본문 중앙에 배치하고, phase를 사용자 언어로 바꿨다. Development build/install/launch는 통과했지만 이전 QA fixture와 임시 총관리자 권한을 삭제한 상태라 새 데이터 mutation 없이 시각 QA는 보류했다.
17. Phase 4A는 개선 요청 callable, 총 관리자 재분석 callable, 10분 readiness reconciler의 별도 bounded query, `status + improvementRequested` 복합 인덱스, Worker revision/fingerprint 계약과 iOS 3단계 UI를 구현했다. 기존 무필드 task/job은 최초 revision 1로, 기존 64자 issue fingerprint는 앞 40자로 호환한다. Functions 111개, Worker 89개, iOS targeted 7개와 `git diff --check`가 통과했다.
18. Phase 4B 방향은 `실패 자동 기록 → Codex 내부 운영 API/CLI 조회·분류 → 사용자 보강 승인 → 기존 코드·fixture·Development·PR·Production 하네스 → revision 검증 → 다시 가져오기 활성화`로 확정했다. 완전 자동 code-generation·PR·Production rollout은 제외하며 기존 실패 job도 자동 재실행하지 않는다.
19. 현재 1인 운영 범위는 cluster 실패 목록 요약과 선택 issue 처리뿐이다. 상태는 `open/inProgress/needsGroundTruth/fixed/verified/wontFix`로 제한하고 담당자·연차별 할당, Jira, 댓글·멘션, SLA, 칸반 보드와 전역 issue UI는 제외한다. Codex는 여러 fingerprint의 상세를 bounded batch로 비교할 수 있다.
20. 2026-08-05 `lookbook-extraction-issue-operations` 상세 하네스를 작성했다. IAM private read/write/release API, 공통 fingerprint, runtime registry와 Worker `/runtime-contract`, Production 100% traffic·실제 URL smoke verifier, job retry projection을 확정했다. occurrence evidence는 7일, cluster 대표 evidence 한 개는 미해결 동안 유지하고 `verified/wontFix` 뒤 60일 보존한다. `fixed`는 Production 검증, `verified`는 새 revision 실제 재시도 성공이며 재발 시 자동 reopen한다. 앱이 배포된 적 없으므로 레거시 개선 요청 호환 계층은 만들지 않는다. 공식 문서 점검 결과를 반영해 Production identity는 환경별 전용 operator service account impersonation으로 확정했다.
21. 착수 대기 핵심 작업 `chat-ugc-safety-room-moderation`을 등록했다. 메시지 서버 삭제, 신고·차단·규칙 기반 필터링, 방 생성자의 사용자 내보내기·재입장 금지와 총관리자 제재 결정을 `docs/ai/tasks/chat-ugc-safety-room-moderation/decisions.md`에 기록했다. 계획·구현은 미승인이다.
22. 착수 대기 핵심 작업 `admin-web-operations-migration`을 등록했다. 브랜드 요청 수요, 권리 확인 뒤 등록, 브랜드·시즌·이미지·스타일·신고 운영의 총관리자 웹 이전 범위를 `docs/ai/tasks/admin-web-operations-migration/decisions.md`에 기록했다. 웹 기술 스택·계획·구현은 미확정 또는 미승인이다.
23. 착수 대기 핵심 작업 `ios-admin-console-removal`을 등록했다. 관리자 웹 필수 기능 동등성 검증 뒤 Development/Production과 Debug/Release 모든 구성에서 iOS 관리자 콘솔을 제거하는 결정을 `docs/ai/tasks/ios-admin-console-removal/decisions.md`에 기록했다. 계획·구현은 미승인이다.
24. 착수 대기 핵심 작업 `chat-room-moderator-delegation`을 별도로 등록했다. 최초 방 관리자는 방 생성자로 유지하고, 다른 참여자의 관리자 임명·회수는 `chat-ugc-safety-room-moderation`이 마련할 공통 room moderation authorization 경계를 확장하는 후속 작업으로 기록했다. 임명 수·세부 권한·소유권 이전 등은 미확정이며 계획·구현도 미승인이다.
25. `sign-in-with-apple-account-lifecycle`을 후속 작업으로 기록했다. Apple/Firebase 콘솔, 로그인 UI, Repository/UseCase/DI, 계정 삭제 재인증과 동일 Apple provider 재가입 principal 복원이 범위 후보이며 요구사항·계획·구현은 미승인이다.
26. Production Kakao Auth migration은 persistent custom claims 대신 UID 숫자 후보를 Kakao Admin API로 재검증하는 방식으로 보완했다. Production dry-run과 backfill에서 Kakao 1명이 unresolved 없이 처리됐고, 신규 로그인 bootstrap과 Development 실제 탈퇴·재가입 복원도 통과했다.
27. Production 앱은 현재 개발자·내부 QA 전용이다. 고객지원 URL/이메일은 아직 없으므로 `customer-support-https-page` 후속 작업으로 분리했다. `supportURL: null`은 내부 smoke에만 허용하고 restricted/suspended 실제 운영, App Store 제출·외부 TestFlight·일반 사용자 배포는 HTTPS 지원 페이지 연결 전까지 금지한다.
28. 사용자는 Phase 1-P에서 내부 계정의 active HMAC principal/alias 생성과 active smoke만 수행하고 restricted/suspended·Production 탈퇴/재가입은 하지 않는 임시 정책을 승인했다. 계정 삭제 후 HMAC 보존 기간·법적 근거·고지는 외부 공개 전에 별도 확정한다.
29. 사용자는 기존 Production Kakao 계정을 persistent custom claims로 보강하지 않고, UID 후보를 Kakao Admin API로 재검증해 메모리에서만 HMAC binding하는 migration 방식을 승인했다. Production apply는 예상 total/provider 건수와 확인 문자열을 요구하고 unresolved 시 전체 중단한다.

## 4. 수정한 파일 목록

- Phase 7.5 설계 문서 변경:
  - 신규 로컬 하네스 `docs/ai/tasks/chat-ugc-safety-room-moderation/phase-7-5-design.md`: 신고 표시, 관리자 종결 분리, Deletion Sync 데이터/API/Socket/GRDB/cache/실패·테스트 계약. `docs/ai/tasks/`는 `.git/info/exclude` 대상이라 커밋하려면 사용자가 명시한 이 파일만 `git add -f`해야 한다.
  - `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,phase-7-implementation-plan,progress,qa-checklist}.md`: 기존 자동 비노출 설계를 Phase 7.5 queue-only + Deletion Sync로 갱신. 이 파일들은 기존 tracked 파일이므로 status에 표시된다.
  - tracked 하네스 `docs/ai/{DATA_SCHEMA,ENTRYPOINTS}.md`, `docs/ai/entrypoints/{CHAT,FIREBASE,TESTS}.md`, ADR-024와 `HANDOFF.md`: 최신 Phase 7.5 진입점·데이터·테스트·현재 경계를 연결했다.
  - 기존 미추적 `docs/portfolio/`는 사용자 작업으로 보고 건드리지 않았다.

- Phase 7.1·7.2: `Socket/src/{handlers/mediaHandlers.js,media/mediaUploadService.js,media/mediaDeliveryWatcher.js,app/createProductionDependencies.js}`, `functions/src/chat/media/`, `tools/chat-media-processing-worker/`, 두 Storage Rules와 Firestore Rules/index/TTL, bucket-aware cleanup 계약을 구현했다. Development bucket/IAM/queue/Job/Functions/Rules/index/TTL을 반영했고 Production은 변경하지 않았다.
- Development media bucket은 Quarantine `outpick-test-chat-media-quarantine`과 일반 표시용 `outpick-test-chat-media`로 분리했다. orchestrator·cleanup에는 승인된 `roles/eventarc.eventReceiver`를 부여해 두 Firestore trigger가 `ACTIVE`다. Socket 자기 계정의 self `roles/iam.serviceAccountTokenCreator`와 task identity의 dispatcher 한정 `roles/run.invoker`를 적용했다. Gen2 Functions 재배포 뒤 latter binding을 재감사해야 한다. worker digest는 `sha256:4741213f15d40de2ba8d916203df6f57523c2133fcbd4da6a4d34de687d56a4f`다.
- 배포 감사에서 기존 cleanup scheduler가 요구하지만 Development 원격에 없던 `chatMessageCleanupJobs(status, nextAttemptAt)`와 `moderationRoomCleanupJobs(status, nextAttemptAt)` manifest index 2개를 exact 생성했다. 둘 다 `READY`이며 다음 자동 실행은 HTTP 200이다. due cleanup을 유발하는 수동 scheduler 실행은 하지 않았다.
- Development Socket `outpick-socket-development-00013-muw`(tag `p73-350m-0819`)는 signed PUT image/video E2E와 tagged/canonical readiness 200 확인 뒤 traffic 100%로 전환했다. 이전 revision들은 0% rollback으로 보존하며 전환 후 ERROR는 0건이다.

- Phase 4 tracked 변경:
  - iOS: `OutPick/Features/Moderation/`, Chat/Lookbook/Profile/MyPage visibility·block/unblock 흐름, `AppCompositionRoot`, `BannerManager`, `RealtimeSocketService`
  - iOS 테스트: `UserBlockSessionControllerTests.swift`, `ChatVisibleUnreadUseCaseTests.swift`, action policy·GRDB migration/media visibility 회귀
  - backend: `functions/src/lookbook/safety/` block contract와 callable, `Socket/src/push/chatPushService.js`와 recipient block test
  - 계약/진입점: `contracts/chat-moderation-v1.json`, `docs/ai/{DATA_SCHEMA,ENTRYPOINTS}.md`, `docs/ai/entrypoints/{APP,CHAT,FIREBASE,TESTS}.md`, ADR-024, `HANDOFF.md`
- Phase 4 로컬 하네스: `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,plan,progress,qa-checklist}.md`는 `.git/info/exclude` 대상이라 로컬 완료 상태만 갱신한다. 기존 미추적 `docs/portfolio/`는 사용자 작업으로 보고 커밋 대상에서 제외한다.

- Phase 3.1 tracked 변경:
  - iOS: `OutPick/Features/Chat/`, `OutPick/Infra/Realtime/RealtimeSocketService.swift`, `OutPick/Features/Login/Application/LoginManager+Bootstrapping.swift`, Firestore room DTO/mapper/repository와 관련 테스트
  - backend: `functions/src/chat/{moderation,cleanup}/`, `functions/src/index.ts`, `firestore.rules`, `firestore-tests/`
  - 계약/진입점: `contracts/chat-moderation-v1.json`, `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/{CHAT,FIREBASE}.md`, `HANDOFF.md`
- Phase 3.1 로컬 하네스: `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,plan,progress,qa-checklist}.md`는 `.git/info/exclude` 대상이라 tracked status에는 나타나지 않는다. 기존 미추적 `docs/portfolio/`는 사용자 작업으로 보고 건드리지 않았다.

- Chat UGC Safety Phase 2~3와 account capability v2 핵심 변경:
  - iOS Chat repository/use case/view model/controller, closure notice·visible room banner 회귀 테스트
  - `functions/src/{moderation,chat,accountDeletion,shared}/`, `functions/scripts/{backfill-account-capabilities,audit-firebase-rules,audit-firestore-indexes}.mjs`
  - `Socket/src/{auth,handlers,rooms,users}/`와 대응 테스트
  - `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firestore-tests/`
  - `contracts/chat-moderation-v1.json`
  - `docs/ai/{ENTRYPOINTS,DATA_SCHEMA}.md`, `docs/ai/entrypoints/{CHAT,FIREBASE,TESTS}.md`, task 하네스와 `HANDOFF.md`
- 이 task의 구현·테스트·문서 변경은 backend/iOS/tests/docs 단위 커밋으로 정리해 `codex/chat-ugc-safety-phase-2-3` 브랜치에 push했다. 기존 `docs/portfolio/` 미추적 항목은 작업 범위에서 제외했다.

- 착수 대기 핵심 작업 기록:
  - `docs/ai/tasks/chat-ugc-safety-room-moderation/decisions.md`
  - `docs/ai/tasks/chat-room-moderator-delegation/decisions.md`
  - `docs/ai/tasks/admin-web-operations-migration/decisions.md`
  - `docs/ai/tasks/ios-admin-console-removal/decisions.md`
  - `docs/ai/tasks/active.md`
  - `HANDOFF.md`

- 이번 task 전환:
  - `docs/ai/tasks/lookbook-extraction-issue-operations/{plan,progress,qa-checklist}.md`
  - `docs/ai/tasks/lookbook-extraction-issue-operations-production-rollout/{design,decisions,plan,progress,qa-checklist}.md`
  - `docs/ai/tasks/active.md`
  - `HANDOFF.md`
  - 운영 CLI OIDC 경계: `tools/lookbook-extraction-issue-ops/src/{config,gcloud,index}.js`, `gcloud.test.js`
  - Production 외부 상태: Worker traffic, Firestore index/TTL, discovery queue, operator/minimum IAM, Function 12개

- AMOMENTO 첫 실제 fix 완료·커밋 범위:
  - `tools/lookbook-import-worker/src/season-discovery.ts`, `season-discovery.test.ts`, `src/fixture/corpus.test.ts`
  - `tools/lookbook-import-worker/fixtures/discovery/platform/cafe24-modal-data-url/{input.html,metadata.json,expected.json}`
  - `functions/src/shared/seasonDiscoveryCreation.ts`, `functions/src/lookbook/import/seasonDiscoveryContract.test.ts`
  - `scripts/ai/deploy-lookbook-import-worker.sh`
  - `OutPick/Features/Lookbook/Views/BrandDetail/{SeasonImportManagementView,LookbookExtractionReviewView}.swift`
  - 관련 `docs/ai/architecture`, `entrypoints`, task progress/QA와 `HANDOFF.md`

- Phase 7 구현·문서 갱신:
  - `tools/lookbook-import-worker/src/extraction/{image-candidates,season-cover}.ts`와 대응 테스트
  - `tools/lookbook-import-worker/src/{processor,season-discovery,season-discovery-processor}.ts`와 대응 테스트
  - `tools/lookbook-import-worker/src/fixture/{types,manifest,corpus}.ts`, `corpus.test.ts`, `fixtures/season-cover/**`
  - `functions/src/shared/seasonDiscoveryCreation.ts`
  - `functions/src/lookbook/import/{functions,seasonCandidateParser,seasonCandidateDiscovery}.ts`와 대응 테스트
  - `scripts/ai/deploy-lookbook-import-worker.sh`
  - `docs/ai/tasks/lookbook-extraction-issue-operations/phase-7-season-cover-enrichment.md`
  - `docs/ai/tasks/lookbook-extraction-issue-operations/{design,decisions,plan,progress,qa-checklist}.md`
  - `docs/ai/ENTRYPOINTS.md`
  - `docs/ai/DATA_SCHEMA.md`
  - `docs/ai/entrypoints/{FIREBASE,LOOKBOOK}.md`
  - `docs/ai/entrypoints/TESTS.md`
  - `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`
  - `HANDOFF.md`
- 이번 단계에는 로컬 코드·fixture·테스트·하네스 변경이 있으며 외부 배포는 없다.

- 이전 Phase 2 커밋 완료:
  - `OutPick/Features/Lookbook/ViewModels/LookbookExtractionReviewViewModel.swift`
  - `OutPickTests/LookbookExtractionReviewViewModelTests.swift`
  - `OutPickTests/LookbookNavigationControllerTests.swift`
  - `OutPick.xcodeproj/project.pbxproj`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/tasks/active.md`
- 환경 분리 구현·테스트·tracked 문서는 PR #3에, Production Worker 배포 결과 문서는 PR #4에 병합했다. 이 closure 갱신 전 working tree에는 `HANDOFF.md` 수정만 남아 있었다. task `progress.md`와 `qa-checklist.md`는 `.git/info/exclude` 대상 로컬 하네스다.
- `firebase-debug.log`는 Firebase CLI 인증 실패로 생성된 임시 로그라 삭제했고 커밋하지 않았다.
- `lookbook-discovery-learning-loop` 설계 하네스 생성:
  - `docs/ai/tasks/lookbook-discovery-learning-loop/design.md`
  - `docs/ai/tasks/lookbook-discovery-learning-loop/decisions.md`
  - `docs/ai/tasks/lookbook-discovery-learning-loop/plan.md`
  - `docs/ai/tasks/lookbook-discovery-learning-loop/progress.md`
  - `docs/ai/tasks/lookbook-discovery-learning-loop/qa-checklist.md`
  - `docs/ai/tasks/active.md`
  - `HANDOFF.md`
- Phase 4A 핵심 변경:
  - `functions/src/lookbook/import/seasonDiscoveryJobs.ts`, `seasonDiscoveryContract.ts`, `functions/src/shared/seasonDiscoveryCreation.ts`, `functions/src/index.ts`
  - `tools/lookbook-import-worker/src/season-discovery-processor.ts`와 관련 Functions/Worker 테스트
  - `firestore.indexes.json`
  - `OutPick/Features/Lookbook/Domains/Entities/SeasonCandidateDiscoveryResult.swift`
  - `OutPick/Features/Lookbook/Repositories/{Protocols,Implementations}`의 season discovery Repository
  - `OutPick/Features/Lookbook/ViewModels/SeasonImportManagementViewModel.swift`
  - `OutPick/Features/Lookbook/Views/BrandDetail/SeasonImportManagementView.swift`
  - `OutPickTests/SeasonDiscoveryManagementViewModelTests.swift`
  - `docs/ai/{ENTRYPOINTS.md,DATA_SCHEMA.md}`, 관련 Firebase/Lookbook/Test/Worker 진입점 문서와 task 하네스

## 5. 중요한 아키텍처 결정

### Phase 7.5 Socket fast path + tombstone Deletion Sync

- 선택: 작성자·방 관리자·플랫폼 관리자 종결·계정 탈퇴 정리를 포함한 모든 최초 서버 삭제가 공통 transaction으로 정책별 message tombstone과 Room 단조 증가 `messageDeletionRevision`을 원자적으로 만든다. 일반·관리자 삭제는 표시 스냅샷을 보존하고 계정 탈퇴만 sender를 익명화한다. 단건은 message outbox와 `chat:messageDeleted`, 계정 탈퇴 collection group bulk는 방별 revision 범위의 head-advanced outbox와 `chat:messageDeletionHeadAdvanced`를 사용한다. 누락·비활성·오프라인은 계정·방별 로컬 cursor 이후 tombstone message만 delta query한다.
- 이유: 실시간 UX와 Socket 유실 복구를 분리하면서 참여자 수에 비례하는 write·push fan-out을 만들지 않는다. 기존에 방 수명 동안 유지하는 message tombstone 자체를 durable delta로 재사용해 별도 journal 정합성 지점도 피한다.
- 트레이드오프: 완전히 오프라인인 기기는 최신 서버 삭제를 알 수 없어 cache가 일시적으로 보일 수 있다. 대신 앱 foreground에서 모든 참여 방을 sweep하지 않고 해당 방 접근 시에만 누락 delta를 읽어 트래픽을 제한한다.
- 보류한 대안: 사용자별 deletion inbox/FCM·APNs fan-out은 참여자 수만큼 비용이 증가하고 silent push도 실행을 보장하지 않는다. 별도 deletion journal은 tombstone과 데이터를 중복하고, Socket-only는 누락 이벤트를 복구하지 못해 제외했다.
- MVVM-C 경계: Repository가 Socket·Firestore delta와 `anonymizesSender`를 숨기고 UseCase가 멱등 적용을 통합한다. GRDB Store는 표시 보존/계정 익명화 scrub·cursor·durable cache cleanup queue transaction을 소유하며 ViewModel/View는 transport 세부사항을 알지 않는다.
- 재검토 조건: 한 방의 전체 메시지 삭제 빈도가 Room 단일 revision 문서 contention을 만들거나 계정 탈퇴 bulk scrub의 방별 revision 할당이 transaction 한계를 넘거나 Socket Cloud Run 다중 인스턴스 전환이 필요해질 때 revision 할당과 Redis Streams adapter 또는 동등한 분산 broadcast를 별도 phase에서 검토한다.

### Phase 7 transport source·즉시 cleanup·principal backpressure

- 선택: iOS가 원본 byte 대신 1차 정규화한 source를 quarantine Storage에 직접 올리고, 서버가 재검증·최종 display/thumbnail을 만든다. terminal에는 source와 lease/slot을 즉시 정리하되 `MediaUploads` 최소 멱등 결과만 7일 둔다. principal별 image 2/video 1은 동시 처리 slot으로만 적용한다.
- 이유: 원본 전송량과 worker 비용을 줄이면서 client 신뢰 경계를 만들지 않고, 응답 유실 재시도의 중복 메시지·재처리를 방지한다. 동시 slot은 한 사용자의 queue 독점과 비용 폭주를 막되 local queue로 총 전송량은 제한하지 않는다.
- 트레이드오프: client와 server가 각각 정규화 단계를 가져 구현량이 늘고 terminal status 문서의 소액 Firestore 비용이 남는다. 대신 큰 quarantine byte는 즉시 삭제하고 1일 lifecycle을 비정상 cleanup 안전망으로 제한한다.
- 보류한 대안: 카메라 원본 업로드는 전송·저장·처리 비용이 크고, terminal 문서 즉시 삭제는 같은 `clientMutationID` 결과를 잃어 중복 처리 위험이 있다. 사용자별 active 무제한은 전체 queue와 비용을 한 principal이 점유할 수 있어 제외했다.
- 재검토 조건: 실제 단말 image quality, PNG 용량, 720p video 품질 또는 처리 대기 metric이 목표에 맞지 않거나 abuse/비용 지표가 확인되면 quality·slot·24시간 byte cap을 별도 조정한다.

### Phase 7.3 iOS foreground upload·pending·outbox

- 선택: picker 결과를 client transport source로 먼저 정규화한 뒤 30장/150 MiB로 분할한다. 이미지와 350 MiB·재생시간 제한 없는 영상은 attachment당 하나의 24시간 V4 signed PUT으로 foreground `URLSession`이 quarantine에 직접 업로드한다. 서버는 generation·크기·체크섬으로 PUT 응답 유실을 한 번 복구한다. pending은 uploading/queued/processing/failed/expired를 내부적으로 구분하되 활성 상태는 로컬 버블만 조용히 유지하고, failed/expired에서만 직접 재시도·삭제를 제공한다. GRDB outbox와 보호된 local source는 복구 가능성을 유지한다.
- 취소는 ready 전 server cancel과 local task cancel을 함께 요청하며 server first-commit-wins 결과를 따른다. 수동 재시도는 실패 job을 재활성화하지 않고 새 `uploadID`·`clientMutationID`를 만든 뒤 새 outbox 저장 성공 후 이전 local 상태를 정리한다.
- signed PUT URL은 bearer credential이므로 GRDB payload 외 로그에 남기지 않는다. terminal 수렴 시 target payload를 제거하고 failed local source는 7일 보존 계약을 따른다.
- 단일 source foreground 계약의 로컬 구현·자동 검증과 Development worker/Socket rollout을 완료했다. JPEG·HEIC·PNG·GIF, 31장과 70장 30+30+10은 실기기 QA를 통과했다. 공유 image/video FIFO와 `active_upload_limit` 동일 identity backoff 자동·실기기 검증도 완료했으며 앱 종료·방 이탈, 350 MiB·장시간 video는 확장 QA gate다. Production은 변경하지 않았다.

### 전역 차단 Store와 표시 시점 admission

- 선택: 별도 채팅 차단 collection 없이 기존 차단 UID 목록만 계정별 snapshot과 메모리 Store로 유지하고, 각 UI admission 경계에서 sender UID를 판정한다. 채팅 current window는 유지하고 룩북 댓글·답글만 즉시 숨긴다.
- 이유: 차단 사실을 상대에게 노출하거나 membership/seq를 변경하지 않으면서 채팅·룩북·프로필의 기준을 하나로 유지한다. 대량 과거 메시지와 캐시를 차단 시점에 삭제하는 비용도 피한다.
- 트레이드오프: 기존 로컬 원문은 남고 모든 재표시 경계가 Store를 사용해야 한다. 앱 종료 unread는 원본 메시지 page 조회가 추가되지만 정확한 visible count와 정상 메시지 보존을 얻는다.
- 보류한 대안: `blockedAt` 시각 비교, 기존 메시지·FTS·미디어 일괄 삭제, 차단 메시지의 전역 seq 미할당, unblock 직후 열린 방 강제 reload는 각각 시계 의존·대량 I/O·다른 참여자 ordering 영향·불필요한 네트워크 재조회 때문에 제외했다.
- 재검토 조건: 사용자당 unread 구간이 커져 목록 bootstrap page 조회 비용이 실제 병목으로 관측되면 서버의 사용자별 visible unread projection을 검토한다.

### 공용 room tombstone과 사용자별 확인

- 선택: 종료 이벤트는 사용자별 notice를 새로 만들지 않고 공용 room tombstone 하나와 각 사용자의 기존 membership을 확인 상태로 사용한다. 확인 시 본인 projection만 지우고, 14일 뒤 scheduler가 잔여 membership과 tombstone을 정리한다.
- 이유: 오프라인 사용자가 방이 오류로 사라진 것이 아니라 종료됐음을 확인할 수 있으면서, 참여자 수만큼 안내 문서를 복제하지 않고 일반 참여방 목록 UX를 유지할 수 있다.
- 트레이드오프: 모든 사용자가 일찍 확인해도 tombstone은 scheduler 만료 전까지 남을 수 있고, 참여방 조회에서 종료 후보를 단건 복원하는 추가 read가 생긴다. 대신 전 사용자 확인 카운터와 동시성 추적을 만들지 않아 lifecycle이 단순하다.
- 보류한 대안: 사용자별 notice 재생성은 중복 데이터·정리 비용이 크고, 즉시 모든 membership 삭제는 오프라인 설명 가능성을 잃으며, room `expiresAt` 직접 Firestore TTL은 membership보다 tombstone을 먼저 지워 orphan projection을 만들 수 있어 제외했다.
- 재검토 조건: 한 사용자에게 동시에 종료 방이 다수 누적돼 단건 복원 지연이 관측되거나 14일 내 미확인 비율·저장 비용이 의미 있게 커질 때 bounded batch read/projection 구조를 재검토한다.

### 계정 capability 단일 projection과 Storage reservation

- 선택: `users.accountStatus`는 계정 데이터 원본으로 유지하되 권한 판정은 `moderationAccounts` schema v2의 `accountStatus + moderationStatus` 한 문서에서 수행한다. media read는 projection + room, upload는 Socket capability로 발급한 서버 reservation + room 계약으로 제한한다.
- 이유: 정상 가입과 제재 여부는 하나의 capability 판단이며, Storage Rules가 허용하는 Firestore 문서 조회 2개 안에서 안전하게 room까지 검증해야 한다.
- 트레이드오프: 계정 상태를 projection에 중복 저장하므로 계정 삭제 요청·취소와 bootstrap transaction의 동기화 책임이 생긴다. 대신 모든 runtime의 판정이 단순해지고 3문서 조회 403을 제거한다.
- 보류한 대안: Storage Rules를 완화하거나 room 검증을 제거하는 방식은 권한 우회를 만들며, 사용자 문서와 moderation projection을 계속 따로 읽는 방식은 조회 한도를 초과하므로 사용하지 않는다.
- 재검토 조건: capability 필드가 더 늘어 projection 크기·동기화 오류가 관측되거나 Storage Rules 조회 한도/구조가 바뀔 때 versioned projection을 다시 설계한다.

### Development 구현 종료와 Production rollout 분리

- 선택: 기존 task는 Development 구현·QA 완료로 종료하고 Production rollout을 별도 핵심 task로 관리한다. 실제 이미지 extraction fix loop는 결함 발생 시 운영 게이트로 남긴다.
- 이유: Production 외부 상태, IAM, contract cutover와 rollback은 구현 완료 여부와 다른 승인·위험 경계를 가진다. 실제 결함이 없는 이미지 stage에 가짜 실패를 만드는 것도 운영 의미가 없다.
- 트레이드오프: task가 하나 늘지만 완료 상태를 과장하지 않고 Production mutation과 이벤트 기반 QA의 조건을 명확히 분리할 수 있다.
- 보류한 대안: 기존 task를 Production 배포까지 계속 active로 두는 방식은 완료된 Development 작업과 승인 대기를 혼합해 다음 작업의 경계를 흐리므로 사용하지 않는다.
- 재검토 조건: Production 읽기 전용 감사에서 코드 계약 자체의 gap이 발견되면 rollout을 중단하고 변경 설계와 검증 범위를 별도로 논의한다.

### Cafe24 modal data-url을 공통 시즌 후보로 처리

- 선택: 모달을 15번 클릭하거나 AMOMENTO domain adapter를 만들지 않고, 정적 HTML의 `button[data-url]`을 anchor와 같은 URL 후보 파이프라인에 합친다.
- 이유: 실제 상세 URL과 제목이 이미 정적 DOM에 있고, public URL/비시즌 경로/score 검증을 재사용하면 네트워크·시간 비용과 사이트별 결합을 줄일 수 있다.
- 트레이드오프: strategy 이름 `staticAnchors`는 기존 golden 호환을 위해 유지돼 실제 입력 종류를 완전히 표현하지는 않는다. evidence와 contract revision 2가 변경 경계를 대신한다.
- 보류한 대안: 모든 모달을 Playwright로 열어 DOM을 수집하는 방식은 느리고 이미지 요청이 많으며, AMOMENTO 전용 adapter는 같은 Cafe24 템플릿 재사용 가능성을 불필요하게 제한해 보류했다.
- 재검토 조건: `data-url`이 실제 상세 URL이 아니거나 별도 API 토큰·POST가 필요한 Cafe24 변형이 확인되면 platform interaction rule 또는 fixture가 고정된 domain adapter를 검토한다.

### 시즌 identity와 대표 이미지 보강 분리

- 선택: 시즌 후보 채택·순서는 URL/제목/score/page order로 확정하고 대표 이미지는 그 뒤 별도 best-effort 단계에서 보강한다. 모든 브랜드에서 목록 이미지가 있으면 유지하고, 없으면 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지를 사용한다.
- 이유: 대표 이미지는 선택 화면의 보조 정보이므로 이미지 제공 여부가 정상 시즌 자체를 누락시키면 안 된다. 기존 이미지 extractor의 content-section/noise 규칙을 공유하면 페이지 로고를 대표 이미지로 오인하는 위험도 줄일 수 있다.
- 트레이드오프: 이미지가 없는 후보마다 상세 HTML 요청이 추가되고 일시적 네트워크 상태에 따라 snapshot hash가 달라질 수 있다. 이를 30개·동시 3개·15초로 제한하고 cover를 표시 snapshot의 일부로 취급한다.
- 보류한 대안: HTML 전체에서 처음 나온 이미지를 쓰는 무검증 fallback은 로고·배너 오탐 위험이 커서 제외했다. AMOMENTO host 전용 코드와 Cafe24-only gate도 다른 브랜드에 공통 규칙이 적용되지 않아 제외했다. 모든 상세 이미지를 Worker가 다운로드·저장하는 방식도 비용과 책임 범위를 늘려 제외했다.
- 재검토 조건: 검증된 다른 플랫폼 상세 구조가 fixture로 추가되거나 외부 이미지 URL 만료가 실제 문제로 확인될 때 adapter 규칙 또는 asset 저장 정책을 별도로 설계한다.

### 하나의 app target과 명시적 환경 configuration

- 선택: 프로젝트와 app target은 하나로 유지하고 Development/Production scheme과 build configuration, xcconfig로 환경을 분리한다.
- 이유: 소스와 DI graph를 복제하지 않으면서 Bundle ID와 backend 연결만 명시적으로 분리할 수 있다.
- 트레이드오프: `project.pbxproj` configuration 수와 build matrix가 늘지만 target 복제보다 drift 위험이 작다.
- 보류한 대안: Development target 복제는 build setting과 capability가 장기적으로 갈라질 위험이 커서 사용하지 않는다.

### Firebase plist fail-fast 주입

- 선택: 실제 plist는 `LocalSecrets`에 보관하고 build phase가 환경별 파일의 `BUNDLE_ID`와 `PROJECT_ID`를 검증한 뒤 결과물에 복사한다.
- 이유: 두 plist가 file-system synchronized app group에 함께 포함되는 문제와 잘못된 project 오접속을 동시에 막는다.
- 트레이드오프: 새 개발 환경마다 로컬 plist 설치가 필요하지만 누락·오조합을 빌드 시점에 바로 발견한다.

### Development backend 기능 동등성

- 선택: Firebase만 분리한 제한 앱이 아니라 현재 기능을 검증할 수 있는 Development backend를 목표로 한다.
- 이유: 현재 `outpick-test`는 최신 onboarding/profile/계정 삭제 기능과 Socket이 없어 단순 plist 교체만으로는 실제 개발 QA가 불가능하다.
- 트레이드오프: Functions/Rules/Socket 배포 감사와 Secret·scheduled trigger 관리 비용이 추가된다.
- 재검토 조건: 운영과 test의 배포 충돌이 반복되거나 여러 개발자가 동시에 backend를 변경하면 CI lock 또는 preview project를 별도 도입한다.

### 환경별 Socket fail closed

- 선택: Production URL을 공통 fallback으로 사용하지 않고 환경 설정이 없거나 잘못되면 연결을 차단한다.
- 이유: Development Firebase ID Token과 운영 Socket/Firebase Admin 경계를 섞지 않기 위해서다.
- 보류한 대안: DEBUG 환경변수 override만 유지하는 방식은 scheme key 오타와 fallback을 구조적으로 막지 못해 제외한다.

### 환경별 Kakao canonical 경계

- 선택: xcconfig는 실제 키를 제공하고, Swift runtime과 build validator는 각각 환경별 canonical Native App Key를 독립적으로 보유해 actual과 대조한다.
- 이유: 실제 키와 `EXPECTED_KAKAO_KEY`를 같은 xcconfig에 두면 두 값을 함께 잘못 바꾸는 교차 설정을 차단하지 못한다.
- 트레이드오프: 공개 Native App Key가 Swift·셸·xcconfig에 의도적으로 중복되므로 키 교체 시 세 위치와 회귀 테스트를 함께 갱신해야 한다.
- 보류한 대안: 단일 환경 manifest 생성·번들 파싱은 환경이 두 개인 현재 범위에서 구조와 검증 경로를 과도하게 늘려 도입하지 않았다.
- 재검토 조건: staging/QA 등 환경이 추가되거나 Kakao 키 회전이 반복되면 versioned environment manifest와 생성 코드로 통합한다.

### Worker 환경·배포 exact contract

- 선택: Firebase project별 Storage bucket, OIDC audience, Cloud Tasks 계정, Functions 계정을 Worker 시작 시 exact 값으로 검증하고 배포 스크립트가 같은 단일 매핑을 사용한다.
- 이유: 형식상 유효한 임의 값이나 project 기반 bucket fallback은 Development/Production 교차 배포를 막지 못한다.
- 트레이드오프: project·service account·bucket 변경 시 코드, 배포 계약과 테스트를 함께 갱신해야 하지만 잘못된 운영 기동을 시작 전에 차단한다.
- 보류한 대안: 배포자 주의와 runbook만으로 값을 관리하는 방식은 반복 가능한 안전장치가 약해 사용하지 않는다.
- 재검토 조건: 환경이 세 개 이상으로 늘면 versioned environment manifest에서 앱·Functions·Worker 배포 설정을 생성하는 구조를 검토한다.

### Candidate 검증 후 main 병합·traffic 전환

- 선택: PR head를 `--no-traffic` candidate로 검증하고, main 병합 tree가 candidate source와 동일할 때만 검증 revision을 100%로 전환한다.
- 이유: 미병합 소스가 운영 traffic을 받거나 검증하지 않은 재빌드가 운영에 진입하는 상태를 피한다.
- 트레이드오프: 배포 단계가 늘지만 rollback revision을 전환 전에 고정하고 실제 OIDC·import smoke를 수행할 수 있다.
- 보류한 대안: PR 머지 직후 검증 없이 바로 source deploy하는 방식은 Production IAM·환경값·실제 import 회귀를 사전에 차단하지 못한다.

### 실패 자동 기록과 Codex 수동 보강

- 선택: 추출 로직 불충분은 서버가 issue cluster와 redacted evidence에 자동 기록하고, 사용자가 요청할 때 Codex가 IAM 내부 운영 API/CLI로 정리한다. 승인된 issue만 Codex가 기존 하네스에 따라 코드·fixture·Development·PR·Production 작업을 수행한다.
- 이유: 브랜드·시즌 추가 빈도가 낮은 1인 개발·출시 전 환경에서 완전 자동화 인프라보다 사람의 ground truth 판단과 명시적 작업 승인이 더 안전하고 운영 비용이 작다.
- 트레이드오프: 사용자가 Codex에 요청하기 전에는 보강이 시작되지 않지만 불필요한 AI 실행·배포와 잘못된 자동 수정 위험을 제거한다.
- 앱 경계: 전역 issue 목록과 개선 요청 버튼을 제거하고 해당 job 카드에 `개선 대기 중/개선 처리 중/다시 가져오기 가능`만 표시한다. 실제 claim 전에는 `처리 중`이라고 표현하지 않는다.
- 안전 경계: Production Firestore Admin SDK를 무제한 직접 읽지 않고 API가 path/field를 allowlist한다. 실제 Production revision verifier만 fixed 상태를 기록하고, 과거 실패 job은 관리자가 명시적으로 재분석한다.
- 보류한 대안: 버튼 기반 자동 patch·Development·PR·Production orchestration은 현재 요청량 대비 복잡도와 위험이 커서 제외했다.
- 1인 운영 단순화: 담당자/Jira/보드 없이 issue cluster 목록 요약과 선택 처리만 제공하며 불필요한 `triaged/fixReady` 중간 상태도 두지 않는다.
- 보존: 개별 redacted occurrence는 7일만 두고 cluster 대표 evidence 한 개는 미해결 동안 보존한다. 해결 뒤에도 회귀·배포 추적을 위해 cluster와 대표 evidence를 60일 유지한 후 삭제한다.
- release source of truth: Functions compile-time revision 대신 server-only runtime registry와 Worker의 인증된 runtime contract를 사용한다. `fixed`와 retry-ready는 live Production 100% traffic과 실제 URL smoke를 서버가 검증한 뒤에만 기록한다.
- 레거시: 앱 출시 이력이 없으므로 개선 요청 projection/no-op callable/구형 UI 호환을 만들지 않는다. 기존 데이터 필드는 즉시 파괴적으로 삭제하지 않고 새 코드가 읽고 쓰지 않게 한다.
- 재검토 조건: 월별 issue 수, 반복 유형과 수동 운영 시간이 실제로 증가하면 분류, fixture 생성, Development 검증 순서로 일부 자동화를 검토한다.
- Phase 2 구현: 이미지의 `expected_count_unverified` 단독 검토는 issue에서 제외하고, 두 stage의 확정된 로직 불충분만 Worker 공통 recorder가 자동 기록한다. cluster는 영향 domain/brand 표본과 부정확한 count를 저장하지 않고 adapter scope·원인·대표 evidence를 유지한다. 대표 선택은 결정적 정보 tuple을 사용하며 고유 `fingerprint/evidenceID` Storage 경로로 동시 교체를 안전하게 처리한다.

## 6. 다시 확인해야 할 불확실한 부분

- Phase 7.5 제품·동기화 설계의 남은 사용자 결정은 없다. 다만 현재 Phase 7.4 Functions/contract/tests에는 자동 `hiddenPendingReview`, restore와 단일 decision enum이 실제로 남아 있으므로 구현 착수 시 제거 영향 범위와 migration 순서를 코드에서 재확인해야 한다.
- `phase-7-5-design.md`는 로컬 `.git/info/exclude`의 `docs/ai/tasks/` 규칙에 해당해 일반 `git status`에 나타나지 않는다. 파일은 생성돼 있으며 커밋 시 이 파일 하나만 `git add -f`할지 사용자 의사 확인이 필요하다.

- account capability v2와 실제 이미지/오프라인 관리자 종료 안내는 Production에서 확인 완료했다. 외부 TestFlight/App Store artifact 업로드는 수행하지 않았으며 고객지원 URL·정책 gate 전에는 일반 사용자 외부 배포가 금지된 기존 결정이 유지된다.

- AMOMENTO 실페이지 ground truth 15개와 Development contract 2 실제 재시도 성공은 확인 완료했다. 이후 사이트 목록이 바뀌면 새 ground truth 판단이 필요할 수 있다.
- Phase 7 AMOMENTO 15개 실페이지의 contract 3 결과, 실제 첫 이미지 일치, 앱 표시와 queue/ERROR를 검증했다. OUTSTANDING 목록 cover 재탐색도 44개 snapshot 완전 일치와 실제 이미지 HTTP 성공으로 검증 완료했다.
- Production Worker `00024-fow`는 durable discovery 도입 전 레거시 runtime으로 확인됐고 현재 traffic 0% rollback으로 보존한다. live `00026-qes`와 Functions는 contract 3이며 operator/index/TTL/discovery queue/Function/rules와 canonical 앱 표시 E2E를 완료했다.

- Firebase/Google/Kakao Development 앱과 callback 등록은 완료했다.
- Development 실기기 App Attest의 Apple App ID·entitlement·Firebase provider 등록은 Apple Developer Program 가입 후 재확인한다.
- Sign in with Apple의 실제 제품 범위, Apple/Firebase 콘솔 상태, 로그인·재인증 UX와 App Review 요구사항은 후속 작업 착수 시 공식 문서 기준으로 재확인한다.
- HTTPS 고객지원 페이지의 문의 채널, 호스팅, 개인정보 처리방침 URL과 moderation `supportURL`은 `customer-support-https-page` 착수 시 재확인한다.
- 현재 로그인한 Kakao Developers 계정에서는 Production 앱만 확인됐다. Development Kakao 앱의 콘솔 소유 계정·팀은 재확인 필요하지만, 구성된 Development 키의 실제 연결 해제·재연결에서 동일 principal 복원은 확인했다.
- `outpick-test` Functions 74개와 scheduled trigger의 감사·승인·배포, 실제 import/materialization smoke와 smoke 데이터 정리를 완료했다.
- Production Worker `lookbook-import-worker-00026-qes` traffic 100%, rollback `00024-fow`, 전환 후 ERROR·queue pending 0건을 확인했다.
- Phase 4B의 API/data/security/보존/revision verifier 계약, Phase 1~6 Development 검증과 Production backend IAM/Functions/index/TTL/queue 적용, 실제 Production smoke와 승인된 cleanup을 완료했다.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. 플랫폼 관리자 처리, disposable 계정 탈퇴 bulk와 종료 감사는 완료했다. 다음은 Phase 7.5F 최종 자동 회귀를 동일 명령으로 재실행하고 결과를 task 문서·TESTS 진입점·HANDOFF에 반영하는 것이다.
2. 자동 회귀 통과 뒤 `review-workflow`로 전체 diff를 앱·테스트·Functions/Rules·Socket·문서 경계별 검토하고 발견 사항을 수정한다. 이후 같은 경계로 커밋을 나누고 PR 생성·리뷰·차단 수정·최종 체크·머지 순서로 진행한다.
3. 실제 기기 background FCM/APNs는 Apple Developer Program 가입 후 출시 전 gate에서 재개한다.
4. Phase 3.1 종료 tombstone은 14일 scheduler 만료 시 자동 정리되며 즉시 추가 조치는 없다.
5. Apple 로그인을 선택하면 `sign-in-with-apple-account-lifecycle`의 정책·콘솔·사용자 흐름·아키텍처 설계 하네스부터 진행하며 바로 구현하지 않는다.
6. Production HMAC Secret·backfill·영향 Functions·Firestore·Storage Rules·최소 권한 Socket traffic 100% 전환과 앱 active smoke까지 완료했다. 제한·정지·계정 삭제 Production QA는 `supportURL`과 출시 gate가 준비되기 전까지 수행하지 않는다.
7. `supportURL: null` Production은 내부 active-account smoke만 수행하고 restricted/suspended 상태 적용이나 외부 배포를 하지 않는다.
8. 실제 `seasonImageImport` 결함이 발생할 때만 이벤트 기반 `fixed → retry success → verified` 운영 게이트를 실행한다.
9. 화면 조작·시각 QA는 사용자가 재현 가능한 시나리오의 체크리스트로 수행하고, Codex는 코드·자동 테스트·빌드·backend/log 검증을 담당한다.

Phase 3 완료 메모: private read/write Functions, strict allowlist API, CAS/idempotent audit와 job projection, 고정 환경 CLI를 구현했다. Development operator IAM, Firestore projection index/audit TTL과 두 Function을 배포했으며 Functions 134/134, CLI 7/7과 lint/build를 통과했다. 실제 Development endpoint는 무인증 403, operator read 성공, 데이터 변경 없는 write 404 smoke를 통과했다. 목록에서 `brandID` filter 및 최근 브랜드/job 사례는 제거했고 정확한 영향 job은 fingerprint projection으로 조회한다. Production IAM·index·Function은 변경하지 않았다. 운영 절차는 `docs/ai/runbooks/LOOKBOOK_EXTRACTION_ISSUE_OPERATIONS.md`를 따른다.

Phase 4 완료 메모: Worker runtime/source/extractor/adapter contract와 두 stage read-only actual extraction smoke, Production Cloud Run v2 traffic/runtime/smoke/CAS verifier, 24시간 verification run, transaction 기반 cursor release projection, 실제 retry 성공 verified 전이를 구현했다. Functions 140/140, Worker 102/102, CLI 8/8, fixture 5/5와 lint/build를 통과했다. Phase 4 Worker/Functions/index/IAM은 배포하지 않았으며 Production traffic·data도 변경하지 않았다.

Phase 5 완료 메모: iOS를 `개선 대기/처리 중/다시 가져오기 가능/추가 작업 필요`로 단순화하고, 시즌 목록·이미지 모두 fixed와 상위 동일-stage runtime에서만 총 관리자 재시도를 허용했다. 서버도 같은 경계를 재검증하며 기존 개선 요청·즉시 재분석 callable/export와 앱의 `improvementRequested*` 계약을 제거했다. Functions 141/141, Worker 102/102, iOS 관련 4개 suite 22개 및 Development Simulator build가 통과했다. 배포와 운영 callable/index 삭제는 수행하지 않았다.
