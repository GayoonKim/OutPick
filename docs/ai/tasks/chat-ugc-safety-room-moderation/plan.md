# Chat UGC Safety And Room Moderation Implementation Plan

## 상태

- 기준 문서: `decisions.md`
- 계획 상태: Phase 0~6 구현·자동 검증·Development QA·Production backend rollout 완료. 2026-08-18 Phase 6 종료 처리
- 코드 변경: Phase 1 capability, Phase 2 신고/관리자 API, Phase 3 삭제·종료 lifecycle과 account capability v2/Storage reservation 보정, Phase 4 전역 차단 단방향 visibility, Phase 5 room ban·내보내기·owner succession, Phase 6 텍스트 입력 상한·rate limit·멱등성·senderEmail/로그 최소화 반영
- 운영 배포: Production `outpick-664ae`에 Phase 1-P~6 Functions·Rules·Indexes·Socket 범위를 단계적으로 반영했다. Phase 6은 `createComment`·`createReply`, Firestore Rules·rate bucket TTL과 Socket `outpick-socket-p6-log-min-0818` traffic 100%를 검증했다. Production iOS binary/TestFlight/App Store 업로드는 출시 단계로 분리했다.
- 원칙: 각 Phase는 이전 Phase의 계약과 검증을 전제로 순차 진행한다. 같은 권한·상태·DI 경계를 여러 Phase가 공유하므로 별도 스레드 병렬 구현을 기본값으로 사용하지 않는다.

## Phase 1-P — Production readiness와 내부 active smoke

### 목표

현재 지원 provider인 Google·Kakao 기존 Production 내부 계정을 검증된 identity로 backfill하고, Phase 1 인프라를 외부 공개 없이 단계적으로 검증할 수 있는 상태를 만든다.

### 변경 범위 후보

- `functions/src/moderation/`: Kakao Admin API 응답을 raw 필드 저장 없이 검증하는 migration helper와 단위 테스트
- `functions/scripts/backfill-moderation-principals.mjs`: Development/Production 명시 경계, Kakao 검증, 예상 계정 수 gate, 개인정보 비노출 summary
- `functions/package.json`: 기존 backfill 명령 유지, 별도 broad deploy 자동화는 추가하지 않음
- `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,plan,progress,qa-checklist}.md`
- `docs/ai/entrypoints/{FIREBASE,TESTS}.md`, `HANDOFF.md`

### 구현 디테일

- Google은 Firebase Admin `providerData`의 단일 `google.com` subject만 사용한다.
- Kakao는 `kakao:{id}` UID에서 숫자 후보를 파싱한 뒤 `KAKAO_ADMIN_KEY`를 메모리에서 읽어 Kakao 사용자 조회 API 응답 ID와 정확히 대조한다. 불일치·미연결·HTTP 실패는 unresolved다.
- provider ID, 이메일, access token, Admin Key와 HMAC Secret은 stdout/stderr·Firestore·로컬 파일에 기록하지 않는다.
- Production dry-run은 Secret 생성 전에도 Kakao provider resolution을 검증할 수 있어야 한다. HMAC Secret은 apply 단계에서만 요구한다.
- Production apply는 `--project outpick-664ae`, `--apply`, exact Production confirmation, 예상 total/Google/Kakao 건수를 모두 요구한다. 현재 감사 기대값은 total 2, Google 1, Kakao 1이지만 실행 직전 재감사 결과와 다르면 계획을 갱신한다.
- backfill 완료 뒤 moderationAccounts/principals/aliases 건수, 모두 active, raw 민감 필드 0개를 읽기 전용으로 검증한다.

### Production 반영 순서

1. 구현·전체 회귀·Production build와 Firebase Rules dry-run을 완료한다.
2. 현재 Firestore·Storage ruleset과 Functions·Socket rollback 대상을 확보한다. 원격 ruleset을 읽지 못하면 배포를 중단한다. — Functions 15개 이전 generation, Firestore·Storage 이전 ruleset 확보 완료
3. 사용자 별도 승인 후 `MODERATION_PRINCIPAL_HMAC_KEY_V1`을 생성한다. — 2026-08-07 version 1 enabled 완료
4. `getMyModerationState`만 먼저 배포하고 상태·Secret binding·App Check를 확인한다. — 2026-08-07 ACTIVE/Secret v1 binding/무인증 401 완료
5. Production Auth dry-run이 exact total 2/Google 1/Kakao 1/unresolved 0인지 확인한다. — 2026-08-07 완료
6. 사용자 별도 데이터 mutation 승인 후 backfill을 apply하고 active projection 2개를 검증한다. — 2026-08-07 account/principal/alias 각 2개, active·참조·민감 원문 0개 완료
7. capability 영향을 받는 기존 callable 14개와 `finalizeExpiredAccountDeletions`를 exact target으로 배포한다.
   - profile 4개: `checkNicknameAvailability`, `completeOnboarding`, `updatePublicProfile`, `updateStylePreferences`
   - engagement 4개: `setBrandEngagement`, `setPostEngagement`, `setSeasonEngagement`, `setCommentEngagement`
   - comment 3개: `createComment`, `createReply`, `deleteComment`
   - safety 3개: `reportComment`, `blockUser`, `loadHiddenCommentUserIDs`
   - 2026-08-07 완료: 15/15 ACTIVE, 배포 후 ERROR 0, finalizer scheduler ENABLED, 이전 source generation 15개 보존.
8. Firestore Rules와 Storage Rules를 각각 dry-run 결과와 대조한 뒤 별도 승인으로 배포한다. indexes 변경은 없다. — 두 Rules 배포·운영 hash·이전 ruleset rollback 검증 완료
9. Socket candidate를 `--no-traffic`으로 배포해 readiness와 내부 인증 smoke를 확인한 뒤 별도 승인으로 100% 전환한다. — 완료. Auth·Firestore·Storage·FCM 실제 permission 11개의 `outpickSocketRuntime` 단일 role과 새 identity를 적용한 `outpick-socket-moderation-p1p-r3-lp`의 인증·격리 read/write/delete·Storage·FCM smoke 후 Production 100% 전환했다. canonical 인증/readiness와 ERROR 0 확인, old identity도 통합 role로 교체, broad 3개 및 구 Auth verifier binding 회수·구 role soft-delete, 임시 Token Creator/QA 잔존 0
10. Production 앱에서 Google·Kakao active 로그인, main tab, 기본 read/write smoke만 확인한다. 제한·정지·계정 삭제는 수행하지 않는다. — 2026-08-08 완료. 두 provider 모두 메인 탭과 기본 read를 통과했고, Kakao 세션에서 브랜드 좋아요 `0→1→0`으로 write와 원복을 확인했다. Simulator App Check debug token은 원문 비노출로 임시 등록한 뒤 QA 직후 삭제했다.

### 완료 기준

- Production 기존 내부 Auth 2명이 unresolved 없이 각자의 active canonical principal에 연결된다.
- raw provider subject·email·token·Secret이 moderation collection, migration 출력과 로그에 없다.
- 신규 bootstrap Function, 영향 callable, Rules·Storage·Socket이 같은 active capability를 판정한다.
- `supportURL: null` 상태에서 restricted/suspended mutation과 계정 삭제 후 복원 QA가 수행되지 않는다.
- Production rollback 대상과 명령이 실제 revision/ruleset 기준으로 확보돼 있다.

### 검증 방법

- Functions migration helper unit test: 유효 Kakao ID, UID/API 불일치, 미연결, HTTP 실패, 비숫자 UID, 개인정보 비노출 summary, Production confirmation/expected-count gate.
- Functions 전체 `npm test`, `npm run lint`, `npm run build`.
- Socket `npm run check`, `npm test`.
- Firestore·Storage Emulator 전체 회귀와 Production dry-run.
- iOS targeted moderation bootstrap test와 `OutPick-Production` generic Simulator build.
- Production 단계별 Auth/Firestore count, Function/Socket revision, Rules release, App Check·로그 오류 읽기 전용 검증.

### Rollback

- backfill 문서는 기존 앱과 기존 Rules가 참조하지 않으므로 Functions/Rules/Socket 전환 전 실패 시 그대로 두고 원인을 수정한 뒤 idempotent 재실행한다. 삭제 rollback은 별도 파괴 승인 없이는 하지 않는다.
- Functions는 배포 전 exact source/target과 이전 revision을 기록하고 실패 target만 이전 source로 재배포한다.
- Firestore·Storage Rules는 배포 전 확보한 이전 ruleset으로 복구한다. 이전 ruleset을 확보하지 못하면 배포하지 않는다.
- Socket은 기존 `outpick-socket-00008-4wl`을 rollback revision으로 보존하고 candidate 검증 실패 시 traffic을 전환하지 않는다.

### 아직 필요한 승인

- Functions, Firestore Rules, Storage Rules, Socket candidate/traffic의 단계별 배포 승인

## 목표

- 메시지 삭제, 사용자·방 신고, 전역 차단, 계정 제재, room ban, 전송 남용 방어, 미디어 격리·정규화와 신고 evidence를 서버 권위의 공통 moderation capability로 통합한다.
- 고객용 iOS는 신고·차단·방 운영·제재 안내를 MVVM-C + Repository + UseCase + DI 경계로 제공한다.
- 관리자 웹이 사용할 신고 조회·처리·제재 API와 감사 계약을 제공하되 관리자 웹 화면 구현은 `admin-web-operations-migration`에 맡긴다.
- 후속 `chat-room-moderator-delegation`이 생성자 전용 권한 판정을 한 경계에서 확장할 수 있게 한다.
- 구현 완료와 Production 출시 가능 상태를 분리해 개인정보·운영·App Review 확인 없이 운영 데이터를 처리하지 않는다.

## 범위 제외

- 관리자 웹 프레임워크·페이지·배포 구현
- 고객용 iOS의 기존 내부 관리자 콘솔 제거
- 방 관리자 임명·회수
- 신고된 이미지·동영상의 별도 moderation Storage 증거 복사
- 생성형 AI 또는 사람 대신 제재를 확정하는 자동 moderation
- 다중 Socket 인스턴스용 분산 rate limiter
- 서로 다른 provider 계정을 자동으로 동일인으로 추정하는 identity graph

## 선행·후속 의존성

| 구분 | 작업 | 이 계획의 경계 |
| --- | --- | --- |
| 선행 계약 | 기존 Chat membership·seq·GRDB·Socket strict ordering | 기존 authoritative membership과 seq ordering을 유지한다. |
| 동시 의존 | `admin-web-operations-migration` | 이 계획은 API·데이터 계약까지 제공하고 웹 UI는 넘긴다. |
| 후속 | `chat-room-moderator-delegation` | 공통 room moderation authorization에 moderator membership만 추가한다. |
| 후속 | `ios-admin-console-removal` | 관리자 웹 기능 동등성 확인 뒤 별도로 진행한다. |

## Phase 지도

| Phase | 목표 | 구현 시작 조건 |
| --- | --- | --- |
| 0 | API·데이터·상태·오류 계약 고정 | 완료 |
| 1 | moderation principal과 계정 capability 기반 구축 | Phase 0 계약 완료 |
| 2 | 신고 접수·집계·관리자 처리·audit API 구축 | Phase 1 principal/capability 완료 |
| 3 | 서버 권위 메시지 삭제와 방 제재 lifecycle 구축 | Phase 1 완료, Phase 2 audit 재사용 가능 |
| 4 | 전역 차단의 단방향 visibility·push·로컬 경계 통합 | Phase 1 완료 |
| 5 | room ban·내보내기·owner succession 구축 | Phase 1·3 room authorization/lifecycle 완료 |
| 6 | 현재 규모의 텍스트 입력 안전·혼합 rate limit·senderEmail/로그 최소화 | 완료 — 2026-08-18 구현·QA·Production backend rollout·PR 병합 |
| 7 | 미디어 격리·정규화·신고 evidence·가시성 상태 머신 구축 | Phase 7.0 완료·Phase 7.1 설계 확정 — 로컬 구현 승인, 외부 리소스 생성·배포 미승인 |
| 8 | iOS 신고·차단·삭제·방 운영·제재 UX 통합 | Phase 2~7 서버 계약 안정화 |
| 9 | migration·통합 회귀·Development QA·문서 마감 | Phase 1~8 완료 |
| Production gate | 개인정보·운영·App Review 필수 확인 | Phase 9와 외부 확인 모두 완료 |

## Phase 0 — 계약 고정

### 목표

코드보다 먼저 서버 권위 source, collection, API, 상태 전이, idempotency와 오류를 exact contract로 고정한다.

### 변경 범위 후보

- `docs/ai/DATA_SCHEMA.md`
- `docs/ai/ADR.md`의 moderation principal·capability ADR 후보
- `docs/ai/entrypoints/CHAT.md`
- `docs/ai/entrypoints/FIREBASE.md`
- 필요 시 신규 `contracts/chat-moderation-v1.json`
- `docs/ai/tasks/chat-ugc-safety-room-moderation/qa-checklist.md`

### 데이터 계약

#### Identity·계정 제재

- `moderationPrincipals/{moderationPrincipalID}`: canonical 제재 원장. `moderationStatus`, `restrictedUntil`, `stateVersion`, `createdAt`, `updatedAt`을 서버만 기록한다.
- `moderationPrincipalAliases/{keyVersion_hmacAlias}`: `moderationPrincipalID`, `provider`, `keyVersion`, `createdAt`을 저장한다. 원본 provider subject·email·token은 저장하지 않는다.
- `moderationAccounts/{uid}` schema v2: 현재 Firebase UID를 canonical principal에 연결하고 Rules·Functions·Socket·Storage가 한 번에 읽을 `accountStatus`, `moderationPrincipalID`, `moderationStatus`, `restrictedUntil`, `stateVersion`, `updatedAt`을 서버만 투영한다.
- 사용자가 볼 수 있는 제한 사유·종료 시각·지원 경로는 서버 API의 안전한 DTO로 제공하며 내부 audit reason 원문을 직접 노출하지 않는다.

#### 신고

- `moderationUserReports/{targetModerationPrincipalID}`: 누적 집계와 현재 `reviewState`, `reviewRevision`, `caseVersion`, `uniqueReporterCount`, `totalSubmissionCount`, `reasonCounts`, `firstReportedAt`, `lastReportedAt`, `updatedAt`.
- `moderationUserReports/{target}/submissions/{submissionID}`: 사건별 신고자 principal, canonical reason, 제한된 detail, `roomID`, 선택적 `triggerMessageID`, text snapshot, 서버가 파생한 메시지 전체 `evidenceAttachmentIDs`, evidence 상태, `createdAt`.
- `moderationUserReports/{target}/reporters/{reporterPrincipalID}`: 고유 신고자 dedupe와 최초·최근 신고 시각. 무제한 reporter 배열을 aggregate 문서에 저장하지 않는다.
- `moderationConfirmedViolations/{targetModerationPrincipalID}`와 하위 `incidents/{actionID}`: 관리자 확정 위반만 기록하고 최근 90일 count·활성 경고를 bounded projection으로 제공한다. 신고 접수는 이 원장을 변경하지 않으며 incident 만료는 관리자 audit을 삭제하지 않는다.
- `moderationRoomReports/{roomID}`와 하위 `submissions`, `reporters`: 사용자 신고와 같은 review/version/idempotency 원칙을 사용한다.
- 신고 idempotency는 인증된 reporter + target + 클라이언트가 생성한 UUID를 서버에서 canonical identity로 변환한다. 재전송은 같은 `submissionID`를 반환하고 새 사건만 새 UUID를 사용한다.
- 신고·audit·principal·room ban의 Production TTL은 개인정보 보존 기간 승인 전 활성화하지 않는다. 신고 evidence는 Phase 7의 처리 결과별 계약으로 삭제하고, 만료·실패 quarantine object와 7일이 지난 실패 outbox cleanup은 이 법적 보존 조건과 분리한다.

#### 방 제재·감사

- `Rooms/{roomID}.lifecycleStatus`: 기존 활성 상태와 `closedByModeration`을 구분한다. `closedByModeration`은 가입·read/write·Socket·push를 즉시 차단하고 cleanup 진행 상태는 별도 서버 필드로 관리한다.
- `Rooms/{roomID}/bans/{moderationPrincipalID}`: room ban의 canonical source. `bannedAt`, `bannedByUID`, `reasonCode`, `stateVersion`을 서버만 기록한다.
- `moderationAuditLogs/{actionID}`: actor UID, action, target type/ID, before/after, reason code, report reference, request ID, 시각을 append-only로 기록한다.
- `chatMessageCleanupJobs/{jobID}`와 `moderationRoomCleanupJobs/{roomID}`: transaction 밖 message/Storage/projection·room 물리 정리를 deterministic ID와 retry 상태로 수렴시킨다.

#### 미디어 격리·evidence

- 기존 `Rooms/{roomID}/MediaUploads/{uploadID}`를 reservation source로 유지하고 `uploading → queued → processing → ready | canceled | failed | expired` 상태와 cleanup 상태를 분리한다.
- processing 전에는 `clientMutationID`만 유지하고 message document와 room `seq`를 만들지 않는다. 격리 Storage와 공개 ready Storage path를 분리하고 ready transaction 이후에만 message·media index·room summary·Socket·push가 보이게 한다.
- 전용 Cloud Run worker는 실제 MIME·codec·dimensions·size·duration·track 검증, metadata 제거와 공개 객체 정규화만 담당하며 유해성 의미 판정을 하지 않는다.
- `moderationMessageIncidents/{incidentID}`는 같은 `reviewRevision`의 긴급/전체 고유 신고 principal 수, queue/visibility/evidence 상태를 서버 전용으로 집계한다. 결정적 `moderationMessageEvidence` bundle은 신고 메시지의 제한된 텍스트 snapshot과 전체 attachment를 함께 복사하고 동일 객체를 중복 저장하지 않는다.

### API 계약

#### 일반 사용자·방 생성자

- `getMyModerationState`
- `submitUserReport`
- `submitMessageReport`
- `submitRoomReport`
- `blockUser`, `unblockUser`
- `deleteChatMessage`
- `removeRoomMember`, `unbanRoomMember`, `listRoomBans`
- Socket media `chat:mediaPreflight`, `chat:mediaFinalize`, `chat:mediaProcessingStatus`, `chat:mediaCancel`. 수동 재시도는 실패 job 재활성화가 아니라 새 `uploadID`·`clientMutationID` reservation 생성이다.

#### 플랫폼 총관리자

- `listModerationReports`, `getModerationReportDetail`
- `mutateModerationReview`
- `mutateAccountModeration`
- `closeRoomByModeration`
- 기존 `deleteChatMessage`의 platform admin authorization 경로

#### 공통 오류

- Firebase callable 표준 code와 안정된 app error code를 함께 사용한다.
- 최소 오류 계약: 인증 필요, principal binding 필요, 자기 신고 금지, 대상 없음, 참여 권한 없음, room moderation 권한 없음, room ban, 계정 일시 제한, 영구 정지, stale case version, idempotency conflict, media pending/failed/expired, evidence unavailable, rate limited.
- 내부 provider·HMAC·정책 상세와 관리자 메모는 사용자 오류에 포함하지 않는다.

### 완료 기준

- 모든 mutable state의 authoritative writer가 하나로 정해진다.
- Rules·Functions·Socket·Storage가 같은 capability 표를 사용한다.
- API DTO와 collection field가 versioned contract로 고정된다.
- 기존 메시지·membership·seq 계약과 migration 순서가 문서화된다.
- 관리자 웹과 후속 moderator task의 인수 경계가 명확하다.

### 검증 방법

- 문서·contract schema inspection.
- collection과 API 명칭의 중복·무제한 배열·클라이언트 권위 필드 점검.
- `git diff --check`.

### 논의 필요 사항

- 없음. 구현 중 기존 provider token 경계가 계약과 다르면 Phase 1을 중단하고 보고한다.

## Phase 1 — Moderation principal과 account capability

### 목표

탈퇴·재가입에도 같은 provider identity의 제재를 복원하고, 모든 서버 경계가 동일한 읽기·쓰기 capability를 판정하게 한다.

### 변경 범위 후보

- Functions: `functions/src/auth/`, `functions/src/profile/`, `functions/src/accountDeletion/`, `functions/src/shared/accountStatus.ts`, 신규 `functions/src/moderation/identity/`, `functions/src/moderation/capability/`, `functions/src/index.ts`
- Socket: `Socket/src/users/userLookup.js`, `Socket/src/auth/socketAuthMiddleware.js`, `Socket/src/handlers/connectionHandlers.js`, 신규 moderation capability helper
- Rules: `firestore.rules`, `storage.rules`
- iOS bootstrap: `LoadCurrentUserBootstrapUseCase`, `UserAccount`/DTO/Mapper, `AppCoordinator`
- tests: Functions identity/capability, Socket auth/watch, Firestore·Storage rules, iOS bootstrap state

### 구현 내용

- Google/Apple은 서버가 검증한 Firebase provider identity에서 subject를 얻고, Kakao는 현재 `exchangeKakaoAccessToken`에서 이미 검증하는 `providerUserID`를 사용한다.
- HMAC secret과 key version을 Functions runtime secret으로 분리한다. alias lookup → 기존 principal 연결 또는 신규 principal 생성 → UID projection 생성을 transaction으로 수행한다.
- key 회전은 old/new alias dual-lookup과 새 alias 추가를 먼저 수행하고 기존 alias 삭제는 별도 보존 정책 승인 전 진행하지 않는다.
- 기존 계정은 dry-run으로 provider별 확보 가능 수와 불명확 계정을 보고한 뒤 backfill한다. Kakao `kakao:{id}`와 custom claim 경계는 실제 Development 재로그인으로 검증한다.
- `accountStatus`와 `moderationStatus` 조합을 capability table로 분리한다. 자기 콘텐츠 삭제·신고·차단·지원·계정 삭제 예외를 명시적으로 허용한다.
- restriction/suspension 변경 시 `moderationAccounts/{uid}` projection을 갱신하고 Socket watch가 해당 연결을 즉시 제한 또는 종료한다.
- `restrictedUntil`은 scheduler 없이도 요청 시 server clock으로 판정하고, 정규화 worker는 projection 정리만 담당한다.

### 완료 기준

- 현재 앱이 지원하는 Google·Kakao provider 계정 재가입 시 같은 principal 제재가 새 UID에 적용된다. Apple은 별도 로그인 기능 구현 후 같은 계약으로 검증한다.
- raw provider subject·email·token이 moderation collection과 로그에 남지 않는다.
- active/restricted/suspended/deletionPending의 capability가 Functions·Rules·Socket·Storage에서 일치한다.
- 영구 정지 상태에서도 제재 안내·지원·계정 삭제 경로가 유지된다.
- 기존 활성 사용자의 migration 실패가 silent active 우회로 이어지지 않는다.

### 검증 방법

- Functions unit test: alias idempotency, key version, 동시 가입, 재가입, 제한 만료, capability matrix.
- Socket unit test: handshake 거부, 기존 연결 disconnect, 제한 만료.
- Firestore·Storage emulator rules test: UGC write 거부와 안전 action 허용.
- iOS fake repository test: active/deletionPending/restricted/suspended bootstrap routing.
- Functions `npm run lint`, `npm run build`, `npm test`; Socket `npm run check`, `npm test`; targeted iOS tests와 build.

### 논의 필요 사항

- provider subject를 안전하게 확보할 수 없는 기존 계정이 dry-run에서 발견되면 해당 계정의 재인증 UX를 별도로 논의한다.

## Phase 2 — 신고·관리자 처리·audit

### 목표

사용자·방 신고를 사건별로 접수하면서 대상별 누적 신호와 관리자 검토 상태를 안전하게 유지한다.

### 변경 범위 후보

- 신규 `functions/src/moderation/reports/`, `functions/src/moderation/admin/`, `functions/src/moderation/audit/`
- `functions/src/index.ts`
- `firestore.rules`, `firestore.indexes.json`
- iOS 신고 Domain/Repository/UseCase/ViewModel/Coordinator 계약과 Cloud Functions adapter
- Functions·Rules·iOS fake/spy tests

### 구현 내용

- 신고 target·reporter·room·trigger message를 서버에서 다시 검증한다. 자기 신고와 존재하지 않는 대상은 거부한다.
- submission, reporter dedupe, aggregate count와 `reviewState` 전환을 transaction으로 처리한다.
- 같은 idempotency identity의 재전송은 기존 결과를 반환한다. 같은 신고자의 새 사건은 total만 증가하고 unique reporter는 유지한다.
- resolved/dismissed 뒤 새 사건은 `reviewState=open`, `reviewRevision + 1`, `caseVersion + 1`로 전환한다.
- 관리자 mutation은 Firebase UID, `platformAdmins/{uid}`, recent auth와 기대 `caseVersion`을 검증한다.
- 일반 관리자 API는 자기 자신과 active platform admin을 제재하지 못하게 한다. 관리자 권한 사고 복구는 audited break-glass 경계에서만 수행한다.
- 모든 관리자 변경은 같은 transaction 또는 실패 시 재시도 가능한 경계에서 audit과 함께 수렴한다.
- Phase 2 현재 구현은 텍스트 snapshot만 길이 제한·최소화해 보존한다. 미디어 선택 evidence는 Phase 7에서 별도 schema와 Storage 경계로 확장한다.
- report submission과 admin query에 별도 rate limit·pagination·정렬 index를 둔다.
- 신고 submission은 일일 hard cap 없이 reporter moderation principal별 1분 10건의 단기 burst만 제한한다. 동일 `clientRequestID` 재전송은 counter를 소비하지 않고 기존 결과와 원래 `receivedAt`을 반환하며, 제한 응답은 재시도 가능 시각을 포함한다.
- Phase 2 iOS 범위는 신고 Domain/Repository/UseCase/Cloud Functions adapter와 fake/transport test까지다. 실제 신고 화면과 Coordinator navigation은 Phase 8에서 연결한다.
- 관리자 처리는 신고 review mutation과 계정 제한·정지·해제까지 포함한다. 메시지 삭제와 방 폐쇄는 Phase 3으로 유지한다.
- 기존 Lookbook `commentReports` migration과 관리자 웹 UI는 범위 밖이다.

### 완료 기준

- 중복 재전송, 동시 신고와 동시 관리자 처리가 count·상태를 손상시키지 않는다.
- 클라이언트는 신고 aggregate·submission·audit를 직접 쓸 수 없다.
- 관리자 웹이 목록·상세·처리 UI를 구현할 수 있는 안정된 API가 제공된다.
- 긴급/일반 SLO 정렬 필드가 사용자에게 법적 기한으로 노출되지 않는다.

### 검증 방법

- Functions transaction/idempotency/concurrency/unit test.
- Firestore rules deny test와 index query contract test.
- iOS fake repository 기반 신고 성공·중복·실패·navigation test.
- 관리자 API stale `caseVersion`, self/unauthorized/recent-auth test.

### 논의 필요 사항

- 2026-08-10 사용자 승인으로 신고 rate limit, Phase 2/8 iOS 경계, 관리자 mutation 범위와 rollout 경계를 확정했다.
- 실제 고객지원 URL과 운영 담당자는 Production gate에서 주입한다.

## Phase 3 — 서버 권위 메시지 삭제와 방 moderation lifecycle

### 목표

메시지 삭제 권한과 projection·Storage cleanup을 서버로 수렴시키고 관리자 방 폐쇄를 일반 방 삭제와 분리한다.

### 변경 범위 후보

- Functions: `functions/src/chat/`, `functions/src/chat/cleanup/`, 신규 moderation authorization·message deletion service
- Socket: `Socket/src/messages/sequenceStore.js`, `Socket/src/rooms/`, message handlers
- iOS: 기존 메시지 action/delete Repository·UseCase·ViewModel, GRDB/FTS/media cache cleanup
- `firestore.rules`, `storage.rules`
- Functions·Socket·iOS·GRDB·rules tests

### 구현 내용

- `deleteChatMessage`가 작성자, room creator 또는 platform admin을 검증한다.
- message seq와 `isDeleted` tombstone은 유지하고 본문·attachments·reply preview·announcement·media index·room summary를 정리한다.
- Storage·projection 정리가 transaction 밖에서 실패하면 idempotent cleanup 상태와 retry worker로 수렴시킨다.
- 클라이언트의 message direct update와 Storage 직접 삭제 권한을 제거한다.
- 공통 room moderation authorization은 초기에는 creator만 허용한다.
- `closedByOwner`와 `closedByModeration`은 join/write/content read/Socket을 즉시 막고 방 콘텐츠를 바로 정리하되, 공용 room tombstone과 미확인 membership은 최대 14일 보존한다. 사용자별 신규 안내 projection은 만들지 않는다.
- 접속 중 참여자는 실시간 종료 이벤트를 확인한 뒤, 오프라인 참여자는 일반 참여방 행을 선택해 종료 안내를 확인한 뒤 본인 membership을 정리한다. 목록에는 종료 배지·색·마지막 메시지 문구를 추가하지 않는다. 방장 삭제 creator는 안내 없이 즉시 정리한다.
- 14일 만료 시 확인하지 않은 membership과 공용 tombstone을 batch 500 write 미만으로 나눠 제거한다. 완료 cleanup job은 7일, 최종 실패 job은 운영 확인을 위해 TTL 없이 보존한다. 기존 사용자별 notice는 새로 만들지 않고 Production 30일 TTL로 자연 만료시킨다.

### 완료 기준

- 삭제 권한 우회와 message server-managed field 직접 변경이 불가능하다.
- 삭제된 마지막 메시지·reply·공지·검색·gallery·Storage가 재시도 후 같은 결과로 수렴한다.
- seq/read frontier/gap recovery는 tombstone 때문에 끊기지 않는다.
- 관리자 폐쇄 방과 일반 방장 삭제가 lifecycle과 audit에서 구분된다.
- 방장 삭제와 관리자 폐쇄 모두 당시 사용자에게 안내되며 확인 또는 30일 TTL로 제거된다.

### 검증 방법

- 권한 matrix·idempotent cleanup·lastMessage transaction Functions test.
- Socket summary/seq 회귀 test.
- Firestore·Storage rules emulator test.
- GRDB/FTS/media cache deletion unit test와 실제 두 계정 수동 QA.

### 논의 필요 사항

- 없음. 운영 데이터 물리 삭제 실행은 별도 승인 없이 수행하지 않는다.

## Phase 4 — 전역 사용자 차단

### 목표

기존 전역 차단 relation을 채팅·룩북·프로필에서 같은 단방향 visibility source로 사용한다. 채팅은 현재 화면 window를 보존하면서 이후 admission을 차단하고, 룩북은 즉시 숨기며, 상대 사용자에게 차단 사실을 노출하지 않는다.

### 변경 범위 후보

- Functions block mutation·push lookup
- 기존 `users/{uid}/blockedUsers/{blockedUID}` owner-only rules 확인(신규 rules/index 변경 없음)
- Socket `Socket/src/push/chatPushService.js`
- iOS 계정별 block snapshot Repository, 메모리 Store/UseCase와 Chat visibility policy
- `RealtimeSocketService`, ingress ordering, `ChatMessageWindowStore`, search/media/room preview/banner/reply 경계
- 로컬 UID snapshot persistence, GRDB/FTS read visibility, Lookbook 기존 hidden user policy
- 관련 Functions·Socket·Swift·GRDB tests

### 구현 내용

- block mutation은 인증 UID와 대상 UID를 검증하고 자기 차단을 거부한다.
- A가 B를 차단하면 A의 admission/visibility 경계만 B 콘텐츠를 제외한다. B의 참여자 목록·프로필·공동방과 상호작용은 그대로 유지하며 차단 사실을 알리지 않는다.
- 앱은 계정별 마지막 성공 차단 UID snapshot을 로컬에 보관하고 세션 시작 시 메모리 Store에 올린 뒤 서버 최신값으로 원자 교체한다. 최초 snapshot도 없고 서버 조회가 실패하면 UGC를 fail closed한다.
- 차단 성공 전 현재 채팅 window에 admission된 메시지는 유지한다. 성공 뒤 들어오는 실시간·pagination·재진입·재동기화 메시지는 sender가 차단 목록에 있으면 시각 비교 없이 제외한다.
- hidden event는 seq와 원본 pagination cursor를 소비하되 새 UI window, preview, banner, visible unread와 검색/gallery 결과에는 넣지 않는다. 기존 GRDB·FTS·미디어 캐시는 소급 삭제하지 않고 재표시 경계에서 필터링한다.
- 앱이 꺼진 동안 누적된 unread는 joined projection의 `lastReadSeq...latestSeq` 고정 구간을 원본 메시지 pagination으로 조회한 뒤 현재 차단 UID Set과 본인·삭제 메시지를 제외해 visible unread를 계산한다. 계산 전에는 raw unread를 표시하고 성공한 방만 정확한 visible unread로 교체하며, 조회 실패 시 정상 메시지 누락을 막기 위해 raw unread를 유지한다. 전역 room seq와 서버 read frontier는 변경하지 않는다.
- reply, search, gallery, user-authored announcement, room preview, banner가 같은 Store를 구독한다. 서버 시스템 lifecycle 이벤트는 필터링하지 않는다.
- FCM fan-out은 recipient A의 block relation을 확인해 sender B의 push만 제외한다. Socket room broadcast는 유지한다.
- 기존 룩북의 blocking-me까지 숨기는 양방향 동작을 단방향 계약으로 전환한다.
- 룩북은 차단 성공 즉시 현재 댓글·답글을 숨긴다. 채팅은 현재 window를 강제 reload하지 않는다.
- A가 B에게 직접 상호작용하려 하면 A에게만 차단 해제 안내를 표시하고 자동 해제하지 않는다.
- unblock 뒤 future content는 즉시 보이고, 과거 content는 강제 재조회 없이 재진입·pagination·일반 동기화 때 복원한다.

### 완료 기준

- 채팅의 기존 current window는 유지되고 이후 admission과 모든 보조 노출면에서 차단 대상 콘텐츠가 제외된다. 룩북 현재 화면은 즉시 숨긴다.
- hidden seq·pagination cursor 때문에 gap recovery와 같은 page 요청이 반복되지 않으며, 기존 원문을 삭제하지 않아도 검색·gallery·preview·banner에서 재노출되지 않는다.
- 차단이 membership·room ban으로 오인되지 않는다.
- 기존 룩북·프로필 차단 기능과 별도 채팅 차단 collection이 생기지 않는다.

### 검증 방법

- Swift snapshot bootstrap·visibility policy·publisher·ordering·window·pagination·search fake test.
- 기존 GRDB/FTS/cache 원문 유지와 read visibility test.
- Socket push recipient block test.
- Production 두 계정 block/unblock, 현재 window 유지, 재진입, 앱 종료 혼합 unread와 reconnect 수동 QA. 실제 기기 background FCM/APNs는 Apple Developer Program 가입 후 출시 전 gate에서 검증한다.

### 논의 필요 사항

- 없음. 2026-08-11 사용자 논의로 현재-window 보존, 계정별 UID snapshot, 룩북 즉시 숨김, 프로필 유지, 직접 상호작용 해제 안내와 최신 앱 단일 cutover를 확정했다. 차단은 탈퇴·재가입 제재 원장과 같은 장기 신원 제재로 확장하지 않는다.

## Phase 5 — Room ban·내보내기·owner succession

### 목표

방 생성자의 내보내기와 재입장·쓰기 금지, 해제, 계정 삭제·영구 정지 시 방별 원자적 방장 승계와 계정 전체 durable 수렴을 구현한다.

### 변경 범위 후보

- Functions room moderation·ban·owner succession service
- 기존 `functions/src/chat/cleanup/`, `functions/src/accountDeletion/cleanup.ts`
- Socket room access/registry/lifecycle/connection handlers
- iOS 참여자 목록·방 설정 Repository/UseCase/ViewModel/Coordinator
- Firestore rules/indexes, tests

### 구현 내용

- 내보내기 transaction이 member doc, joinedRooms projection, memberCount와 room ban을 함께 변경하고 Socket 퇴장을 후속 idempotent action으로 실행한다.
- 활성 방 list/search/preview/message/media read는 ban 사용자에게도 허용한다. membership 생성·재가입, 참여자 전용 Socket join과 message/media write 경계만 principal-based room ban을 검사한다.
- 내보내기 뒤 iOS는 현재 화면을 읽기 전용 non-member 상태로 바꾸고 pending outbox·미완료 upload를 취소한다. 기존 메시지·FTS·완료 media cache는 유지하며 joinedRooms 기반 push/banner/share 대상은 membership 제거로 제외한다.
- unban은 ban만 제거하고 membership을 복구하지 않는다.
- owner의 수동 leave는 기존 방 삭제를 유지한다.
- 일시 제한과 `deletionPending`은 승계하지 않는다. 계정 삭제 최종 확정·영구 정지는 durable job으로 모든 membership을 page 단위 제거하고, owned room마다 별도 transaction으로 oldest eligible member에게 승계한다.
- 승계 job 동안 방은 active로 운영하되 권위 capability가 기존 owner의 관리·전송을 차단한다. 영구 정지 해제 뒤 membership과 owner는 자동 복구하지 않는다.
- successor는 유효한 `joinedAt` 오름차순·UID tie-break로 선택하고 ban·deletionPending·restricted·suspended를 제외한다. 후보 race는 transaction 재검증과 다음 후보 retry로 수렴한다.
- 적격 successor가 없으면 계정 삭제는 `closedByOwner`, 영구 정지는 `closedByModeration`으로 기존 Phase 3.1 lifecycle을 재사용한다.
- room 삭제 cleanup은 bans subcollection을 포함한다.

### 완료 기준

- 같은 provider 재가입 뒤에도 room ban이 유지된다.
- ban 사용자는 방 콘텐츠를 읽을 수 있지만 membership·쓰기·참여자 전용 Socket join을 우회할 수 없다.
- 내보내기 후 member/joinedRooms/count/Socket/outbox가 정의된 retry 내에서 수렴하고 기존 읽기 cache는 유지된다.
- 동시 내보내기·leave·owner suspension에서도 owner 중복이 없고 부적격 owner가 권한을 행사하지 못하며, 각 방이 bounded retry 안에 적격 owner 또는 종료 상태로 수렴한다.
- 영구 정지 membership sweep과 계정 삭제 cleanup은 재실행해도 count·role·projection을 중복 변경하지 않는다.
- 후속 moderator delegation이 authorization helper만 확장할 수 있다.

### 검증 방법

- Functions remove/unban·membership sweep·방별 succession transaction/race/idempotency/successor test.
- Socket forced leave, banned membership join/write 거부와 일반 read 비회귀 test.
- Firestore·Storage rules active room read 허용, banned membership create/write 거부 test.
- iOS 읽기 전용 전환·pending outbox 취소 ViewModel/Coordinator test와 creator/non-creator 화면 수동 QA.

### 논의 필요 사항

- 없음. 2026-08-12 사용자 논의로 room ban의 read 허용·membership/write 차단, 읽기 cache 유지, 영구 정지 전체 membership 제거, 방별 succession job과 승계 중 일반 채팅 유지를 확정했다. 기존 운영 room migration·cleanup mutation과 Production rollout은 별도 실행 승인을 받는다.

## Phase 6 — 현재 규모의 텍스트 입력 안전·전송 남용 방어·로그 최소화

### 목표

사용자의 표현을 자동 판정하지 않으면서 현재 OutPick 규모에 맞는 기술적 입력·burst 방어를 적용하고 메시지 identity·로그의 개인정보 노출을 최소화한다.

### 변경 범위 후보

- Socket text/lookbook/media preflight·finalize handler, auth/capability와 `Socket/src/utils/rateLimit.js`
- Socket message payload·FCM data payload·Firestore message write의 `senderEmail` 경계
- iOS `ChatMessage`, realtime decoding, GRDB와 text/comment/reply 입력 상태
- Functions `createComment`, `createReply`와 server-only Firestore minute bucket
- Firestore rules/index/TTL과 `moderationCommentWriteRateLimitBuckets` 데이터 계약
- Socket·Functions·iOS 단위/transaction 회귀와 Development·Production 읽기 전용 데이터 감사

### 구현 내용

- 텍스트 메시지·룩북 공유 문구·댓글·답글의 의미를 검사하지 않는다. 욕설·혐오·위협·금칙어·광고·링크·반복 문장과 공백/기호/Unicode 우회 탐지를 구현하거나 외부 moderation provider로 전송하지 않는다. 댓글·답글은 현재 텍스트 전용이며 미디어 attachment 생성은 범위 밖이다.
- 서버는 타입·빈 문자열·식별자·인증/capability·room access와 기존 최대 길이만 검증한다. 채팅/룩북 공유는 UTF-8 4,000 bytes, 댓글·답글은 trim 이후 UTF-16 code unit 1,000 상한을 유지한다.
- 앱은 길이 counter나 제한 임박 경고를 표시하지 않고 상한을 넘는 입력 자체를 반영하지 않는다. 서버 거부 뒤 입력을 보존한다. 채팅은 UTF-8 bytes, 댓글·답글은 Swift `message.utf16.count`를 사용한다.
- Socket는 현재 단일 인스턴스 메모리 limiter를 유지한다. text 12/2초, lookbook share 6/2초, image preflight/finalize 각 4/2초, video preflight/finalize 각 4/2초를 `moderationPrincipalID + roomID + messageKind`별로 적용한다.
- canonical principal이 없는 연결은 auth/capability 경계에서 fail closed한다. `socket.id`, 클라이언트 제출 UID·email을 limiter identity fallback으로 사용하지 않는다.
- 유효한 `messageID`를 limiter 전에 확정한다. bucket은 짧은 window의 최근 message ID를 기억해 같은 process 재시도 quota를 중복 소비하지 않으며, 기존 Firestore transaction의 message 존재 확인을 최종 멱등성 원장으로 유지한다. 정상 경로의 추가 클라이언트 왕복·Firestore read는 만들지 않는다.
- 메모리 limiter는 60초 idle TTL, 30초 bounded sweep, 최대 50,000 active bucket을 갖는다. cap 도달 시 새 bucket은 fail closed하고 원문 없는 metric/경고를 남긴다. restart/deploy의 짧은 제한 상태 초기화는 수용한다.
- `max-instances=1`을 배포 전 실제 Cloud Run 설정에서 확인한다. Redis/Memorystore는 도입하지 않으며 다중 Socket 인스턴스, 단일 인스턴스 자원/latency 한계, 실제 프로세스 간 우회가 전환 trigger다.
- 댓글·답글은 같은 principal 전역 합산 UTC 1분 20건으로 제한한다. `clientRequestID`를 필수로 받고 post 경로 안의 comment ID를 `SHA-256(moderationPrincipalID + ":" + operation + ":" + clientRequestID)`로 결정한다. transaction은 기존 comment가 author·parent·message와 일치하면 기존 ID와 현재 count projection을 반환하고 quota를 소비하지 않으며, 불일치하면 `IDEMPOTENCY_CONFLICT`다. 신규 요청만 server-only Firestore minute bucket을 증가시키며 counter는 본문·target detail 없이 2일 TTL로 정리한다.
- iOS는 전송 탭에서 UUID를 생성해 네트워크 재시도 동안 유지한다. 입력 수정·취소·성공 후 새 작성은 새 UUID를 사용한다. rate limit 시 자동 재전송하지 않고 입력을 유지한 채 `잠시 후 다시 시도해주세요`를 표시하며 `retryAt` 이후 사용자 직접 재전송만 허용한다.
- 신규 메시지는 text/lookbook/media 종류 모두 `senderEmail`을 저장·Socket/FCM 전송하지 않는다. 앱 model·GRDB에서도 제거하고 클라이언트 제출 email은 무시한다. 최신 앱/서버만 지원한다.
- 구현 전 Development·Production active principal projection과 message의 `senderEmail` 존재량을 읽기 전용 감사한다. 활성 메시지가 사실상 없으면 별도 migration을 만들지 않으며 데이터 삭제가 필요하면 별도 승인을 받는다.
- 성공 로그와 invalid payload 로그에서 메시지·답장 원문, 이메일, nickname/avatar와 payload 전체를 제거한다. event, 안정된 오류 코드, message ID, seq, payload bytes와 처리 시간만 필요 범위에서 구조화한다.
- 신고된 텍스트만 Phase 2의 제한된 snapshot 계약으로 보존한다. 정상 메시지 원문을 moderation/Cloud Logging에 별도 복제하지 않는다.
- 내부 QA 과거 로그는 소급 삭제하지 않고 기존 Cloud Logging retention으로 자연 만료시킨다. 새 sink/export는 만들지 않는다.
- 관리자 queue의 기존 고정 우선순위 정렬은 유지한다. arbitrary count/history 정렬과 sanction-history projection은 후속 `admin-web-operations-migration` 범위다.
- 이미지·동영상 채팅 메시지는 Phase 7에서 격리·기술 검증·metadata 제거 뒤 공개한다. Phase 6은 미디어 preflight/finalize rate-limit 경계만 준비한다.

### 완료 기준

- Socket 재연결과 동일 principal의 다중 연결로 limiter가 초기화되거나 분리되지 않으며 principal 누락은 fail closed한다.
- text/lookbook/media preflight·finalize의 다른 principal·room·message kind bucket은 서로 간섭하지 않는다.
- 동일 messageID Socket retry와 동일 clientRequestID 댓글/답글 retry는 중복 quota나 중복 UGC를 만들지 않는다.
- 정상 사용자는 기존 허용량 안에서 전송하고 비정상 burst는 저장·broadcast·push 전에 거부된다. 댓글·답글은 principal당 합산 20/분을 넘으면 `RATE_LIMITED/resource-exhausted`와 `retryAt`을 받는다.
- idle bucket 정리·cap·restart 정책이 bounded memory를 보장하고 limiter metadata에 본문·email이 없다.
- 채팅 UTF-8 bytes와 댓글·답글 UTF-16 code unit의 최대 길이·권한·빈 값 계약이 앱과 서버에서 일치한다.
- 같은 입력의 네트워크 재시도는 같은 clientRequestID, 수정·취소·성공 후 새 작성은 새 ID를 사용하며 rate limit이 자동 재전송을 만들지 않는다.
- 텍스트·이미지·동영상 모두 외부 moderation provider로 전송되지 않으며 Phase 7은 기술적 미디어 안전 경계만 추가한다.
- 신규 Firestore/Socket/FCM/iOS/GRDB 메시지 경계와 성공·유효성 실패·예외 로그에 `senderEmail`, 메시지/답장 원문 복제와 전체 payload가 남지 않는다.
- `max-instances=1` 배포 계약과 분산 limiter 전환 조건이 문서화된다.
- 신고 aggregate는 관리자 정렬·검토 우선순위에 사용되고 신고 횟수만으로 자동 제재하지 않는다.
- App Review Notes용 신고·차단·방 운영·관리자 대응·고객지원 흐름과 자동 필터 미사용의 심사 불확실성이 문서화된다.

### 검증 방법

- deterministic clock 기반 principal/room/kind/messageID bucket, 60초 idle TTL·30초 sweep·50,000 cap unit test.
- 동일 principal reconnect·다중 연결, 다른 principal/room/kind 격리, 모든 Socket send kind의 정상 허용/burst 거부 test.
- Functions transaction/emulator로 댓글·답글 합산 20/분, UTC minute 전환, 동일 clientRequestID replay, 동시 요청과 TTL metadata test.
- logger spy와 payload snapshot으로 Firestore·Socket·FCM·오류 경로의 원문 복제·email·reply preview 비노출 test.
- Swift 입력 상태 test로 채팅 UTF-8 4,000/4,001 bytes, 댓글·답글 UTF-16 1,000/1,001 units와 이모지 경계, 서버 거부 후 입력 보존을 검증한다.
- fake repository/transport로 동일 UUID 네트워크 retry, 입력 수정·취소·성공 뒤 새 UUID, rate-limit 자동 재전송 금지와 사용자 직접 retry를 검증한다.
- 모든 UGC write 경로가 외부 의미 판정 provider를 호출하지 않고 미디어 기술 검증은 Phase 7 worker 경계에만 존재하는 정적/계약 회귀를 추가한다.
- 읽기 전용 principal/message 데이터 감사 후 정상 text/lookbook/media/comment/reply 작성과 신고·차단·방 내보내기 수동 QA.

### 논의 필요 사항

- 없음. 2026-08-18 사용자 승인으로 현재 규모의 single-instance/Firestore 혼합 limiter, senderEmail 제거, UTF-8/UTF-16 입력 길이 UX, clientRequestID 수명, 수동 retry와 Redis 보류를 확정했다. 모든 UGC는 신고·차단·방 운영·관리자 사후 검수로 관리한다. App Review 피드백에 따른 게시 전 의미 필터 도입과 다중 인스턴스 전환은 별도 논의·승인 없이는 진행하지 않는다.

## Phase 7 — 미디어 격리·정규화·신고 evidence·가시성

상세 실행 순서, 변경 파일, API·데이터·IAM·테스트·rollback은 [`phase-7-implementation-plan.md`](phase-7-implementation-plan.md)를 기준으로 한다.

### 목표

이미지·동영상을 공개 전에 격리해 기술적으로 검증·정규화하고, 메시지 전체 신고 evidence와 관리자 queue·전역 비노출·복원 상태를 서버 권위로 일관되게 관리한다.

### 변경 범위 후보

- Socket media handlers/upload service/message sequence 경계
- 신규 Functions·Cloud Tasks·전용 Cloud Run media worker·cleanup
- `storage.rules`, `firestore.rules`, indexes/TTL
- iOS `ChatMediaUploadUseCase`, pending upload store, media sending Repository와 상태 UI
- 메시지 전체 신고 UI, 관리자 moderation API 계약

### 구현 내용

- Socket preflight가 reservation을 만들고 전용 quarantine bucket의 exact source path만 발급한다. finalize는 전체 object manifest를 확인해 같은 `MediaUploads`를 queued로 전환하고 Firestore trigger/Function이 kind별 Cloud Task를 enqueue한다. 별도 processing job 문서는 만들지 않으며 Socket runtime identity에 Cloud Tasks enqueue 권한을 직접 주지 않는다.
- 전용 Cloud Run worker가 실제 MIME·codec·dimensions·size·duration·track을 검증하고 불필요 metadata를 제거한 공개 객체를 만든다. worker는 외부 유해성 의미 판정 provider를 호출하지 않는다.
- ready transaction에서만 message document·seq·media index·room summary를 생성하고 delivery job을 거쳐 Socket·FCM을 발송한다. reservation/job/object/message ID는 결정적으로 만들어 finalize·retry를 멱등 처리한다.
- 이미지 선택은 무제한이고 앱이 최대 30장씩 메시지로 분할한다. iOS transport source는 각 15 MiB·합산 150 MiB·긴 변 4096px이며 orientation bake·sRGB·metadata 제거를 적용한다. HEIC/HEIF·JPEG는 JPEG quality 0.92, PNG는 초기 투명/비투명 모두 보존하고 GIF animation도 유지한다. 서버 transport는 JPEG·PNG·animated GIF만 허용한다.
- Phase 7.0 Linux fixture로 static 64M pixel, GIF 200 frame·frame당 16,777,216 pixel·총 100M decoded pixel, 이미지당 60초, video remux 10분을 확정했다. Cloud Run Job은 2 vCPU·1 GiB에서 첨부를 순차 처리한다.
- quarantine·일반 media·evidence는 환경별 3개 bucket 경계로 분리한다. quarantine은 같은 리전 Standard, soft delete/versioning off와 1일 lifecycle backstop을 사용한다. ready/canceled/final failed/expired 즉시 source를 삭제하고 비정상 잔존 객체만 lifecycle이 정리한다. media에는 `display/thumbnail`, evidence에는 신고된 메시지의 정규화 `display` 전체를 둔다.
- 이미지와 영상 queue/Job/고정 execution slot을 분리한다. Production 초기 동시는 이미지 4·영상 1, Development는 각 1이며 task count/parallelism 1·retry 0, 전체 timeout 이미지 40분·영상 12분이다. principal별 image 2/video 1 slot은 누적 전송이 아니라 동시 `uploading|queued|processing` backpressure이며 terminal 즉시 반환한다.
- 동영상은 iOS가 720p H.264/AAC MP4 source 하나를 직접 업로드하고 메시지당 1개·최대 350 MiB·길이 제한 없음이다. local pending thumbnail은 업로드하지 않고 서버가 `min(1초, duration/2)`에서 512px JPEG를 생성한다. 실제 duration과 codec/track은 서버가 검증한다.
- upload reservation은 2시간, processing deadline은 6시간이다. terminal `MediaUploads`는 source가 아니라 같은 `clientMutationID` 응답 유실 재시도를 위한 최소 결과만 7일 보존한다.
- 발신자는 ready 전 취소할 수 있으며 cancel/worker ready 중 먼저 commit된 transaction이 이긴다. 기술 오류는 최대 3회 서버 재시도 뒤 사용자 수동 재시도로 전환하고 실패한 로컬 outbox 원본은 7일 뒤 삭제한다.
- 메시지/image viewer 신고는 attachment 선택이나 동영상 시점 입력 없이 해당 메시지 전체를 신고한다. evidence는 이미지 묶음의 정규화 `display` 전체 또는 동영상 원본 전체 1개를 결정적 bundle로 복사한다.
- 신고 성공만으로 신고자 화면의 메시지를 자동 숨기지 않는다. 개인 메시지 숨김과 사용자 차단은 신고와 분리된 명시적 사용자 액션으로 유지한다.
- 일반 단일 신고는 `holding`에 저장하고 같은 메시지 고유 신고자 2명이면 `reviewRequired`, 긴급 사유는 첫 신고부터 `urgent`로 분류한다. `holding && reviewDueAt <= serverNow`는 scheduler나 상태 승격 없이 관리자 직접 조회에 포함한다.
- 같은 작성자의 최근 7일 서로 다른 신고 메시지 3개 이상과 그 메시지 전체의 고유 신고자 2명 이상이 함께 충족되면 사용자 aggregate를 검토 대상으로 표시한다. 별도 관리자 작업 목록 projection은 만들지 않고 canonical message/user/room 신고 원장을 직접 조회한다.
- 같은 review revision의 24시간 고유 신고자가 긴급 사유 2명 또는 전체 사유 합계 3명에 도달하거나 관리자가 수동 조치하면 메시지를 전역 `hiddenPendingReview`로 전환한다. 자동 계정 제재는 하지 않는다.
- 전역 숨김은 같은 seq의 검토 tombstone이고, 기각 시 같은 messageID/seq를 복원하며 push/unread/read frontier를 새로 만들지 않는다. 위반 확정은 같은 seq의 삭제 tombstone이다.
- 신고/삭제 transaction은 server-only `moderationMessageGuards/{incidentID}`를 함께 읽고 쓰며 first commit wins다. 삭제가 먼저면 `messageAlreadyDeleted`를 반환하고 신고·evidence·count·quota를 만들지 않으며 앱은 해당 seq를 삭제 tombstone으로 수렴시킨다. 신고 준비가 먼저면 메시지 전체 evidence copy를 예약하고 `processing`을 반환한다. 뒤이은 삭제는 tombstone을 즉시 만들되 ready source cleanup을 copy 완료 또는 terminal failure까지 기다린다. evidence가 `available`이 된 뒤에만 `accepted` 신고와 count·queue·visibility를 확정하며, copy 실패는 신고 미접수와 source hold 해제로 수렴한다.
- iOS는 패션 매거진 에디토리얼 시각 언어의 간결한 `신고 처리 중` 상태만 표시한다. 앱이 살아 있고 결과를 확인할 수 있으면 accepted/확정 실패를 안내하고, 앱 종료·응답 유실로 결과를 알 수 없으면 추측 안내를 하지 않는다. 사용자가 다시 신고할 때 서버가 processing/accepted/failed를 확인해 기존 작업 재사용, `이미 신고한 메시지예요`, 또는 새 처리를 결정한다.
- 총 신고 건수, 고유 신고자 수, 신고된 서로 다른 메시지 수와 관리자 확정 경고 수를 분리한다. 확정 위반 최근 90일 수는 1회 경고·2회 일시 제한 검토·3회 이상 장기 제한/정지 검토의 운영 참고값이며 자동 제재로 사용하지 않는다.
- evidence 원본은 클라이언트에 공개하지 않고 활성 플랫폼 관리자의 서버 인증·단건 객체 조회만 허용한다. 실제 byte 전달 방식은 관리자 웹 구현 시 재검토한다.
- 기각·삭제만·경고만이면 처리 직후 evidence 삭제를 enqueue한다. 계정 제재 근거면 30일 이의제기 기간을 적용하고 기간 내 이의제기는 해결 직후, 미제기는 30일에 삭제한다.

### 완료 기준

- ready 전 다른 사용자가 Firestore·Storage·Socket·push·room preview에서 미디어를 볼 수 없다.
- 처리 실패가 seq hole이나 stale pending message를 만들지 않는다.
- 동일 finalize 재전송이 메시지를 중복 생성하지 않는다.
- GIF 애니메이션, 이미지/동영상 metadata 제거, no-duration video와 모든 용량 상한이 검증된다.
- 메시지 전체 evidence·관리자 queue·신고/삭제 경합·임시 전역 숨김·기각 복원이 정의된 상태와 retention으로 수렴한다.

### 검증 방법

- Functions/Worker 상태 전이·retry·cancel race·timeout·idempotency test.
- Storage·Firestore rules emulator quarantine/ready test.
- Socket message seq·broadcast ownership test.
- iOS pending/retry/failure/relaunch/outbox expiry, 메시지 신고·전역 visibility fake test.
- JPEG·PNG·animated GIF, raw HEIC/HEIF 거부와 장시간 동영상의 실제 MIME/metadata/codec/resource-limit fixture QA. iOS HEIC/HEIF→JPEG 결과는 Phase 7.3에서 별도 검증한다.
- evidence 접근 deny, retention cleanup, threshold revision과 restore/no-unread transaction test.

### 논의 필요 사항

- Phase 7.0 worker와 Phase 7.1 저장·queue·slot·active-upload 계약에는 남은 제품 결정이 없다. 사용자별 24시간 byte hard cap은 실제 지표를 본 뒤 별도 결정한다. Phase 7.1 이후 구현과 환경 배포는 별도 승인이 필요하다.
- 아동 성착취물·즉각적 불법 위험의 별도 restricted escalation/legal runbook과 보존 의무는 **확실하지 않음**이며 외부 출시 gate에서 법률 검토한다.

## Phase 8 — iOS 사용자·방 운영 UX 통합

### 목표

서버 기능을 고객용 iOS의 일관된 신고·차단·삭제·내보내기·제재 안내 흐름으로 연결한다.

Phase 7은 evidence를 실제 검증하기 위해 메시지·이미지 뷰어의 전체 메시지 신고와 전역 visibility까지만 선행 구현한다. Phase 8은 프로필·참여자 목록 사용자 신고, 방 설정 신고, 개인 메시지 숨김, 제한/정지·고객지원과 전체 UX 통합을 완료한다.

### 변경 범위 후보

- `ChatMessageActionPolicy`, `ChatViewController`, `ChatViewControllerExtension`
- `ChatRoomSettingViewController`/ViewModel, participant cells
- 신규 신고 화면·제재 안내 화면과 ViewModel
- `ChatCoordinator`, `ChatContainer`, `ChatCompositionRoot`
- 신규 moderation Repository/UseCase/Store, Cloud Functions adapter
- Profile·Lookbook 공통 block 진입점과 고객지원 route
- Swift unit/navigation tests와 수동 QA

### 구현 내용

- 메시지 long press 신고는 attachment 선택 없는 `이 메시지 신고` 화면으로 이동해 해당 incident와 sender aggregate를 함께 기록하고, 방 설정은 방 신고로 이동한다.
- 신고 화면은 canonical reason, 선택적 detail, 문맥을 전달하며 자기 신고를 노출하지 않는다.
- 차단·해제, 자기/creator 삭제, creator 내보내기·ban 해제를 action policy와 서버 결과로 수렴시킨다.
- restricted 사용자는 읽기와 안전 action을 유지하고 UGC create/join UI를 disabled state와 서버 오류 모두에서 차단한다.
- suspended 사용자는 일반 탭 대신 제재 안내·지원·계정 삭제 route로 진입한다.
- 화면은 Firebase/Socket 구현을 직접 알지 않고 Coordinator가 신고·지원·프로필·설정 route를 소유한다.
- 접근성, Dynamic Type, 로딩·중복 탭·실패·재시도 상태를 포함한다.

### 완료 기준

- 모든 사용자 action이 UseCase/Repository 뒤에서 서버 권한을 사용한다.
- 차단·신고·삭제 후 현재 화면과 공유 store가 즉시 일관된 결과를 표시한다.
- 제한·정지 상태에서 허용/금지 action이 서버 capability와 일치한다.
- 고객지원 경로가 마이페이지·신고 완료·제재 안내에서 동일하다.

### 검증 방법

- ViewModel state, action policy, Coordinator route spy, fake repository failure/idempotency test.
- 단순 화면 배치·문구·long press·participant action은 Simulator/실기기 수동 QA.
- generic Simulator build.

### 논의 필요 사항

- 없음. 확정된 화면 범위를 넘어 신고 내역 사용자 조회·전용 이의제기 센터는 추가하지 않는다.

## Phase 9 — Migration·통합 QA·하네스 마감

### 목표

기존 계정·차단·메시지·room을 새 계약으로 안전하게 전환하고 Development 증거를 확보한다.

### 변경 범위 후보

- 승인된 dry-run/backfill script 또는 bounded admin function
- Functions·Socket·rules·iOS 통합 tests
- `docs/ai/ENTRYPOINTS.md`, `DATA_SCHEMA.md`, `ADR.md`
- `docs/ai/entrypoints/CHAT.md`, `FIREBASE.md`, `TESTS.md`
- task `progress.md`, `qa-checklist.md`, `HANDOFF.md`, `active.md`

### Migration 순서

1. 신규 collection deny-by-default Rules와 server contract를 배포한다.
2. Development에서 provider principal binding dry-run과 backfill을 수행한다.
3. Functions moderation capability·신고·삭제·ban API를 배포한다.
4. Socket capability·block push·text/media 경계를 배포한다.
5. iOS 호환 버전을 배포하기 전 기존 direct message mutation을 계속 허용하지 않도록 cutover 순서와 최소 지원 버전을 확인한다.
6. 기존 block relation을 유지하면서 Lookbook 단방향 visibility와 로컬 cache 정리를 적용한다.
7. 기존 미디어 메시지는 소급 정규화하지 않고 신규 업로드부터 quarantine·metadata 제거 정책을 적용한다.
8. Production mutation·backfill·secret 생성·배포는 각 단계별 사용자 승인을 따로 받는다.

### 자동 테스트 설계

- Functions: principal identity, capability matrix, report idempotency/reopen/version, delete cleanup, room ban/succession, media state machine.
- Socket: auth/disconnect, room ban join, hidden push, rate limit reconnect, media ready 이후 broadcast와 seq.
- Rules: direct write deny, capability 예외, room ban read/join, quarantine/ready Storage.
- iOS: bootstrap routing, report/block/delete ViewModel, visibility ordering, GRDB redaction, pending media, Coordinator routes.
- 실제 Firebase가 필요한 provider 재연결·미디어 worker 처리와 App Review 흐름은 Development 수동 QA로 둔다.

### 완료 기준

- 모든 targeted 자동 테스트, Functions lint/build, Socket check/test, Firestore·Storage emulator, iOS build가 통과한다.
- 일반 사용자 2명, room creator 1명, platform admin 1명의 Development demo 흐름이 재현된다.
- 기존 메시지 ordering/read frontier, room membership, account deletion과 Lookbook 차단 회귀가 없다.
- 관리자 웹 task가 API·schema·권한·demo fixture를 인수할 수 있다.
- 문서가 실제 코드·API·검증 명령과 일치한다.

### 검증 방법

- `functions`: `npm run lint`, `npm run build`, `npm test`
- `Socket`: `npm run check`, `npm test`
- `firestore-tests`: `npm test`
- iOS targeted tests와 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- Development 실제 두 계정·creator·admin·media fixture QA
- `rg` 기반 legacy direct mutation/양방향 block/브랜드 관리자 권한 잔여 점검
- `git diff --check`

### 논의 필요 사항

- 실제 운영 데이터 backfill·cleanup·Rules/Functions/Socket/iOS Production 배포는 각각 실행 전 승인받는다.

## Production 운영 출시 전 필수 확인 조건

- moderation principal·room ban 보존의 법적 근거, 기간, 접근 통제와 개인정보 처리방침 반영
- 현재 지원하는 Google·Kakao provider subject 확보와 실제 탈퇴·재연결 QA. Apple은 Sign in with Apple 출시를 선택할 때 별도 구현·QA gate로 추가한다.
- 신고 evidence의 처리 목적·접근권한·보존·삭제 정책과 개인정보 처리방침/App Store Connect App Privacy 응답
- 미성년자 이용 범위, 불법·성적 콘텐츠 escalation, 최신 App Store age rating 응답
- 고객지원 URL·연락처와 긴급 24시간/일반 72시간 내부 운영 담당·경고 경로
- Development 미디어 형식·metadata 제거·GIF resource-limit·장시간 동영상 fixture 통과
- platform admin bootstrap/revoke, recent auth와 break-glass runbook
- App Review demo 계정·신고·차단·방 내보내기·제재 복구·고객지원 경로

## 배포 원칙

- 이 계획 승인과 구현 승인은 별개다. 사용자가 구현을 승인하기 전에는 Phase 0 이후 코드·rules·script를 수정하지 않는다.
- 배포는 구현 완료를 의미하지 않으며 Development 검증 뒤 Production 대상을 다시 승인받는다.
- 기본 검증·배포 명령은 각 workflow 문서를 따르되 운영 함수 삭제, index 삭제, 데이터 cleanup과 backfill은 별도 명시 승인이 필요하다.
- rollback은 이전 Rules/Functions/Socket revision과 iOS 최소 지원 버전의 호환 범위를 Phase 0 contract에 포함한다.
