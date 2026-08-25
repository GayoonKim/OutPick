# Chat UGC Safety And Room Moderation QA Checklist

## Phase 0 — 계약

- [x] `contracts/chat-moderation-v1.json`이 유효한 JSON이다.
- [x] account lifecycle UID와 장기 moderation principal의 책임이 분리돼 있다.
- [x] HMAC alias에 raw email·provider subject·token 저장이 금지돼 있다.
- [x] active/restricted/suspended capability matrix가 안전 action 예외를 포함한다.
- [x] 메시지 incident·사용자·방 신고 submission, reporter dedupe, 사용자 aggregate와 review state가 분리돼 있다.
- [x] 모든 신고·관리자 mutation의 idempotency와 optimistic concurrency가 정의돼 있다.
- [x] transaction 밖 message/room cleanup의 deterministic job과 retry 상태가 정의돼 있다.
- [x] room creator API가 전역 `moderationPrincipalID`를 노출하지 않고 room-scoped ban token을 사용한다.
- [x] 메시지 신고는 attachment 선택 없이 이미지 묶음 전체 또는 동영상 전체를 결정적 evidence bundle로 보존하고 접근·삭제 경합·retention 계약이 정의돼 있다.
- [x] media technical validation/normalization 완료 전 message·seq·broadcast·push가 없다는 계약이 정의돼 있다.
- [x] Production TTL과 개인정보·운영·App Review 조건이 출시 전 필수 확인으로 분리돼 있다.
- [x] ADR·DATA_SCHEMA·ENTRYPOINTS·CHAT·FIREBASE·TESTS가 exact contract를 가리킨다.

## Phase 1 — Moderation principal과 capability

- [x] 현재 지원 provider인 Google/Kakao identity가 재가입 뒤 같은 principal에 연결된다.
- [x] HMAC old/new key dual lookup과 alias 추가가 idempotent하다.
- [x] provider subject를 확보하지 못한 기존 계정이 silent active 상태로 우회하지 않는다.
- [x] restricted 사용자의 read/report/block/unblock/delete-own/support/account-delete만 허용된다.
- [x] suspended 사용자는 notice/support/account-delete 외 일반 앱에 접근하지 못한다.
- [x] restrictedUntil 만료를 server clock으로 판단한다.
- [x] Rules·Functions·Socket·Storage capability 결과가 일치한다.
- [x] restriction/suspension 상태·version 변경 시 기존 Socket이 종료되어 재평가된다.

자동 테스트에서는 같은 provider identity의 동시 UID binding과 suspended 복원을 확인했다. Development Google·Kakao 실제 탈퇴·재가입까지 통과해 Phase 1을 완료 처리한다. Apple은 현재 로그인 진입점이 없어 별도 후속 작업으로 분리했다.

- [x] Development Google 계정은 실제 탈퇴·재가입 뒤 기존 restricted principal과 제한 안내 root로 복원된다.
- [x] Development Kakao 계정은 실제 연결 해제·탈퇴·재가입 뒤 HMAC alias 1개와 기존 restricted principal·stateVersion 2로 복원된다.
- [x] 제한 안내 root가 제한 상태를 경고성 에디토리얼 UI로 표시하고 계정 삭제 확인 화면으로 이동·복귀한다.
- [x] 접근성 최대 글자 크기에서 제한 정보와 account action을 scroll로 모두 탐색할 수 있다.
- [x] `supportURL`이 없으면 고객지원 문구와 CTA를 함께 숨기고 계정 삭제·로그아웃 경로는 유지한다.
- 후속 작업: Apple 계정의 실제 탈퇴·재가입 principal 복원은 Sign in with Apple 구현·외부 계정 준비 후 확인한다. Phase 1 완료 조건에서는 제외했다.

## Phase 1-P — Production Socket candidate

- [x] 패치 candidate `outpick-socket-moderation-p1p-r2`가 0% traffic에서 Ready이고 tagged `/readyz` 200, ERROR 0이다.
- [x] live `outpick-socket-00008-4wl`이 100% traffic을 유지한다.
- [x] 기존 Production Google QA 계정의 Firebase ID Token으로 candidate 인증 handshake가 성공한다. token은 메모리에서만 만들고 signed claims를 Production UID/project와 대조했으며 신규 Auth 사용자·Firestore write·token/credential 저장은 없었다.
- [x] Socket runtime service account에 `firebaseauth.users.get` 단일 permission custom role을 부여하고 candidate 인증 smoke를 재실행했다. 임시 Token Creator binding은 즉시 회수했고 잔존 0건이다.
- [x] candidate 인증 성공 뒤 최근 15분 ERROR 로그가 0건이다.
- [x] Auth·Firestore·Storage·FCM permission 11개를 합친 `outpickSocketRuntime` role 하나를 만들고 새 candidate identity에만 부여했다.
- [x] 새 identity의 0% candidate에서 인증, Firestore read/write/delete, Storage list/delete, FCM fanout을 격리 `qa-*` 데이터로 실제 검증했다. ERROR와 smoke 잔존 데이터는 0건이다.
- [x] 최소 권한 candidate를 Production 100%로 전환하고 canonical readiness·Google QA 인증·ERROR 0건을 확인했다.
- [x] old runtime identity에도 통합 role을 적용한 뒤 broad Datastore·Storage·FCM 및 Auth verifier binding을 회수했다. 구 Auth verifier custom role은 soft-delete했다.

## Phase 2 — 신고·관리자 처리

- [x] 같은 clientRequestID 재전송이 submission/count를 중복 생성하지 않는다.
- [x] 같은 clientRequestID 재전송은 rate counter를 소비하지 않고 원래 접수 결과를 반환한다.
- [x] 서로 다른 사건의 1분 10건까지 접수되고 11번째 요청은 재시도 가능 시각과 함께 `resource-exhausted`로 거부된다.
- [x] 신고 rate-limit counter와 로그에 detail·message snapshot·provider identity가 저장되지 않는다.
- [x] 같은 reporter의 새 사건은 total count만 증가하고 unique reporter count는 유지된다.
- [x] terminal review 뒤 새 사건은 open/reviewRevision/caseVersion 계약대로 전이된다.
- [x] 동시에 처리한 stale caseVersion mutation이 거부된다.
- [x] 자기 신고·존재하지 않는 target·권한 없는 room context가 거부된다.
- [x] 신고 aggregate/submission/reporter/audit의 client direct read/write가 거부된다.
- [x] 관리자 자신과 active platform admin 제재가 일반 API에서 거부된다.
- [x] 5분이 지난 auth_time의 고위험 관리자 action이 거부된다.
- [x] Phase 2의 현재 구현에는 미디어 evidence copy가 없고, 메시지 전체 copy는 Phase 7 구현 범위로 명시돼 있다.
- [x] Production 활성 Kakao platform admin의 인증·App Check 포함 목록 호출이 성공한다.
- [x] Production 활성 Google 비관리자의 같은 목록 호출이 `PERMISSION_DENIED`로 거부된다.
- [x] smoke 후 관리자 read rate bucket, 임시 App Check debug token과 Token Creator binding이 남지 않는다.

Phase 2 자동 검증은 audited platform admin 운영 테스트를 포함한 Functions 177/177, Rules 35/35, Firestore transaction 17/17, iOS 대상 6개와 generic Simulator build를 통과했다. rate bucket/log 민감정보 부재와 별도 Storage write 부재는 구현 경로 정적 점검을 함께 근거로 한다. Production index/rules와 exact Function 6개를 배포했고, index `READY`, Function `ACTIVE`, 무인증 401, 활성 관리자 성공, 비관리자 `PERMISSION_DENIED`, ERROR 0건을 확인했다. 임시 rate bucket·App Check token·Token Creator binding의 사후 잔존은 모두 0건이다. 관리자 운영 UI는 Phase 2 범위가 아니며 Phase 8에서 연결한다.

## Phase 3 — 메시지 삭제·방 lifecycle

- [x] 작성자, active room creator, platform admin만 허용된 범위의 메시지를 삭제한다.
- [x] restricted 사용자는 자기 메시지만 삭제할 수 있다.
- [x] direct Firestore message mutation과 direct ready Storage delete가 거부된다.
- [x] isDeleted/seq tombstone을 유지하면서 payload·reply·announcement·room summary·media index·Storage가 수렴한다.
- [x] cleanup 일부 실패 뒤 retry가 중복 부작용 없이 완료된다.
- [x] closedByModeration 방은 join/read/write/Socket/push가 차단된다.
- [x] 일반 creator delete와 관리자 폐쇄 audit/lifecycle이 구분된다.

Phase 3 최종 보정 뒤 Functions 185/185, Socket 70/70, Rules 40/40, transaction 20/20와 Development·Production generic Simulator build를 통과했다. 170명 추가 참여자 방 종료도 Firestore batch 한도 안에서 수렴했다. Production 전체 index/TTL 감사는 index 41개·field override 29개가 로컬과 일치해 index를 변경하지 않았고, capability 영향 Function 27개·Firestore/Storage Rules·Socket `outpick-socket-account-cap-v2-0810` traffic 100%를 반영했다. 실제 앱에서 이미지 메시지 표시, 참여자 오프라인 중 관리자 종료 안내 1회 표시, 확인 즉시 notice 삭제와 재진입 중복 없음까지 통과했다. QA 데이터·임시 App Check token과 최근 Production ERROR 로그 잔존은 0건이다.

## Phase 3.1 — 공용 종료 tombstone

- [x] 종료 시 신규 사용자별 notice를 만들지 않고 공용 room tombstone 하나만 만든다.
- [x] 방 콘텐츠·메시지·Storage·이미지 경로는 즉시 제거하고 tombstone은 최대 14일만 유지한다.
- [x] 참여자 확인 시 본인 member/joinedRooms/roomStates와 legacy notice가 멱등 정리된다.
- [x] 방장 삭제 creator는 안내 없이 즉시 정리되고, 관리자 종료 creator는 확인 대상에 포함된다.
- [x] 참여중 목록에 종료 전용 배지·색·subtitle·마지막 메시지 문구를 추가하지 않는다.
- [x] 14일 만료 시 150명 단위 batch로 잔여 membership과 tombstone이 정리된다.
- [x] joinedRooms projection 보유자만 종료 tombstone을 읽고 Messages/media는 읽지 못한다.
- [x] Production Functions·Firestore Rules 배포 전 원격 구성 차이를 감사한다.
- [x] `acknowledgeRoomClosure`, owner/admin close, room cleanup trigger/scheduler와 Firestore Rules를 exact target으로 배포하고 ACTIVE/source hash/scheduler/ERROR를 확인한다.
- [x] 접속 중 방장 삭제: 재보정 Socket과 앱 재빌드 뒤 방 이름 안내가 정확히 한 번 표시되고, 확인 즉시 기존 오픈채팅/참여중 목록으로 복귀함을 확인했다.
- [x] 오프라인 방장 삭제: 일반 목록 행 → 선택 시 방 이름 안내 → 확인 후 제거·재실행 중복 없음 흐름을 확인했다.
- [x] 접속 중 관리자 종료: Google/Kakao가 같은 방을 보고 있을 때 안내가 각각 한 번만 표시되고, 문구가 정확하며, 확인 즉시 기존 목록으로 복귀하고 pull-to-refresh 없이 해당 방이 사라짐을 확인했다.
- [x] 오프라인 관리자 종료: Google/Kakao 모두 일반 행 → 안내 1회 → 확인 즉시 행 제거 → 앱 재실행 시 행·안내 미복원을 확인했다. 사후 member/joinedRooms/roomStates 0건과 14일 retention 예약, 관련 Production ERROR 0건도 확인했다.

## Phase 4 — 전역 차단

- [x] A가 B를 차단하면 A만 B 콘텐츠를 숨기고 B는 A 콘텐츠를 계속 본다.
- [x] 참여자 목록·프로필·공동방은 양쪽 모두 유지되고 B에게 차단 사실이나 차단 유추 오류가 노출되지 않는다.
- [x] 현재 존재하는 직접 상호작용인 답장은 A에게만 차단 해제 안내를 표시하고 자동 해제하지 않는다. 후속 멘션·초대는 같은 Store guard를 사용한다.
- [x] 차단 성공 전 현재 채팅 window의 B 메시지는 유지되고, 강제 reload나 기존 GRDB·FTS·미디어 cache 삭제가 발생하지 않는다.
- [x] 차단 성공 뒤 Socket·pagination·재진입·재동기화로 admission되는 B 메시지는 작성 시각과 무관하게 숨겨진다.
- [x] hidden seq와 원본 pagination cursor를 소비해 gap recovery와 같은 page 요청이 반복되지 않는다.
- [x] 기존 cache 원문이 남아도 reply/search/gallery/user announcement/room preview/banner/visible unread/push에서 차단 대상이 새로 노출되지 않는다.
- [x] 방 종료·제재 같은 서버 시스템 이벤트는 사용자 차단과 무관하게 표시된다.
- [x] 계정별 마지막 성공 UID snapshot이 로컬→메모리→서버 최신값 순서로 수렴하고, 서버 실패 시 마지막 성공값을 유지하며 최초 snapshot도 없으면 UGC가 fail closed한다.
- [x] 차단·해제 성공 뒤 메모리 Store와 로컬 snapshot이 즉시 동기화된다.
- [x] unblock 뒤 future content가 즉시 보이고 현재 화면 강제 재조회 없이 재진입·pagination·일반 동기화로 과거 content가 복원된다.
- [x] Lookbook의 기존 양방향 숨김이 단방향 visibility로 전환된다.
- [x] Socket push는 recipient 차단 relation과 조회 실패에서 fail closed한다.
- [x] 앱 재실행 시 `lastReadSeq...latestSeq` 고정 구간을 조회해 차단·본인·삭제 메시지를 제외한 visible unread를 계산하고, 조회 실패 시 raw unread를 유지한다.
- [x] Production 앱 종료 중 차단 `seq=2`와 비차단 `seq=3` 메시지를 함께 누적한 뒤 재실행 목록이 raw 2 대신 visible unread 1·비차단 preview를 표시하고, 방 재진입에서 차단 메시지를 제외한다. QA 방·projection·차단 relation·Storage 잔존은 0건으로 정리했다.
- [x] 최신 앱 단일 Production 전환 결정에 따라 Development 중복 QA 대신 Production 두 계정으로 current-window 유지, 재진입과 unblock 자연 복원을 확인한다.
- [x] Production 두 계정에서 차단 전 current-window 유지, 차단 뒤 실시간 메시지 제외, 참여자 유지, unblock 뒤 재진입 과거 메시지 자연 복원과 future 실시간 수신을 확인한다.
- 출시 전 외부 gate: Apple Developer Program 가입·APNs 설정 후 실제 기기 background FCM/APNs 제외와 답장 안내의 접근성 표시를 확인한다. Phase 4 완료 차단 조건은 아니다.
- [x] Lookbook은 차단 성공 즉시 현재 댓글·답글에서 대상 작성자 콘텐츠를 숨긴다.

## Phase 5 — Room ban·owner succession

- [x] remove가 member/joinedRooms/memberCount/ban/Socket leave를 수렴시킨다.
- [x] ban 사용자는 활성 방 목록·검색·preview·메시지·공개 미디어를 읽을 수 있다.
- [x] 같은 provider 재가입 뒤에도 ban room의 membership 생성·참여자 전용 Socket join·메시지/미디어 write를 할 수 없다.
- [x] 내보내기 뒤 현재 화면은 읽기 전용 non-member로 전환되고 pending outbox·미완료 upload만 취소하며 기존 메시지·FTS·완료 media cache는 유지한다.
- [x] unban은 membership을 자동 복원하지 않는다.
- [x] ban list API가 moderationPrincipalID와 재가입 새 UID 연결을 노출하지 않고 ban 시점 최소 표시 snapshot만 반환한다.
- [x] owner 수동 leave는 방 삭제를 유지한다.
- [x] 일시 제한·deletionPending에서는 승계하지 않고 계정 삭제 최종 확정·영구 정지에서만 succession job이 시작된다.
- [x] 영구 정지는 모든 room membership을 제거하고 정지 해제 뒤 자동 복구하지 않는다.
- [x] owner 삭제·영구 정지 시 joinedAt 오름차순·UID tie-break의 oldest eligible active member로 방별 승계된다.
- [x] 적격 successor가 없으면 계정 삭제는 closedByOwner, 영구 정지는 closedByModeration으로 폐쇄된다.
- [x] transaction 재검증·멱등 job·bounded retry로 동시 remove/leave/suspension이 적격 owner 또는 종료로 수렴한다.

### Phase 5 Production 두 계정 앱 QA 실행 체크리스트

상태: 2026-08-12 핵심 흐름과 대용량 pending upload 취소·같은 provider 재로그인까지 통과. 기존 Production Google·Kakao 내부 QA 계정과 iPhone 17 Pro/Pro Max Simulator 두 대를 사용했고 A는 방 생성자, B는 일반 참여자로 고정했다.

사전 gate:

- [x] 두 Simulator에 같은 최신 `OutPick-Production` 빌드를 설치하고 A/B가 active moderation 상태로 로그인된다.
- [x] Socket canonical `/readyz` 정상, Phase 5 revision traffic 100%, 보정용 `getMyRoomAccess` 포함 Functions 8개 `ACTIVE`, 신규 index 3개 `READY`, succession scheduler `ENABLED`를 재확인한다.
- [x] QA 시작 전 active room 0, bans 0, succession jobs 0, 두 계정 간 전역 block relation 0, 최근 Phase 5 ERROR 0을 식별자 비노출 summary로 기록한다.
- [x] 비민감 대용량 동영상과 QA 방 `Test Room`을 준비했다. 최초 자동 QA 방과 다른 수동 보충 QA 방이다.

방 생성·정상 참여 baseline:

- [x] A가 QA 방을 생성하고 B가 명시적으로 참여한다. 서버에서 active lifecycle, member 2, memberCount 2, A/B joinedRooms·roomState projection을 확인한다.
- [x] A/B가 각각 고유 baseline text를 전송하고 두 화면 모두에서 동일하게 읽힌다.
- [x] 일반 참여자 기기(iPhone 17 Pro Max)가 QA 동영상 업로드를 시작하고 방장 기기(iPhone 17 Pro)가 업로드 중 내보냈다.

내보내기·ban 수렴:

- [x] A가 방 설정의 B 참여자 → `채팅방에서 내보내기` → canonical 사유 1개를 선택한다.
- [x] B의 열린 채팅 화면이 Socket 이벤트로 즉시 읽기 전용 non-member 상태가 되고 `재입장이 제한된 채팅방입니다`가 비활성 표시된다.
- [x] 기존 완료 동영상·텍스트는 재진입 시 그대로 읽혔다. pending 동영상은 서버 ACK 실패로 끝났고 로컬 pending/outbox·보존 파일이 제거돼 앱 재실행 뒤 재시도·확정 메시지·Storage 증가가 없었다. 서버의 미확정 예약 1건과 부분 업로드 객체는 즉시 삭제 계약이 아니라 만료/방 종료 cleanup 대상으로 남았다.
- [x] 서버에서 대상 member/joinedRooms/roomState 제거, memberCount 1, active principal ban 1을 확인했다. 방장 membership과 active room은 유지됐다.
- [x] A의 `재입장 제한 사용자 관리`에 B의 ban 시점 표시 snapshot만 나타나고 UID·moderationPrincipalID·email·재가입 최신 프로필 연결은 노출되지 않는다.

읽기 허용·참여/쓰기 차단:

- [x] B가 목록/검색에서 active QA 방을 다시 찾고 preview·baseline message를 읽을 수 있다. 이번 방에는 공개 완료 media를 만들지 않아 media 읽기는 기존 자동 검증 근거를 유지한다.
- [x] B는 앱 UI에서 재참여·메시지·미디어 전송을 할 수 없고, 재실행 및 같은 Google provider 로그아웃/로그인 뒤에도 제한 상태가 유지된다.
- [x] 이 수동 QA는 새 UID 재가입을 만들지 않았다. canonical principal의 새 UID 우회 차단은 Production 계정 삭제 금지 gate 때문에 emulator/transaction 자동 검증 결과를 근거로 유지한다.

unban·명시적 재가입:

- [x] A가 `재입장 제한 사용자 관리`에서 B를 해제하고 성공 뒤 active ban 목록이 비워진다.
- [x] unban 직후 B membership/joinedRooms/memberCount는 자동 복원되지 않는다.
- [x] B가 방을 다시 열어 `채팅 참여하기`를 명시적으로 눌러 참여하고 member 2/memberCount 2/projection 복원 뒤 새 메시지를 A/B가 모두 수신한다.

정리·사후 감사:

- [x] A가 QA 방을 종료하고 Messages/mediaIndex/members/A·B projection/bans/Storage prefix를 정리한다. room은 Phase 3.1 계약대로 `closedByOwner` tombstone과 `awaitingExpiry` cleanup job으로 14일 보존한다.
- [x] B의 미완료 동영상 예약·Storage object·확정 메시지·local retry가 남지 않았음을 확인한다.
- [x] active room 0, active bans 0, succession jobs 0, QA projection/block/Storage 잔존 0과 Phase 5 Functions·Socket·Scheduler ERROR 0을 확인한다.
- [x] remove/unban `moderationAuditLogs`는 append-only 운영 감사 계약이므로 삭제하지 않는다. 자유 입력·provider subject·email이 없고 canonical action/reason/snapshot만 남는지 확인한다.

실행 메모:

- QA 방 이름은 AXe 한글 입력 제한 때문에 `08121825`, baseline은 A `111111`·B `222222`, unban 후 B `333333`을 사용했다.
- ban 직후 B 화면은 즉시 읽기 전용으로 전환됐고 메시지 목록이 잠시 비었지만, 검색 결과에서 같은 방을 다시 열자 두 baseline 메시지를 읽으면서 쓰기 UI는 계속 차단됐다.
- unban 뒤 서버 membership은 자동 복원되지 않았다. 다만 이미 열려 있던 B 화면에는 참여 버튼이 즉시 갱신되지 않았고 앱 재시작 뒤 `채팅 참여하기`가 나타났다. 명시적 참여와 `333333` 전송은 성공했으므로 기능 계약은 통과하되 실시간 UI 갱신은 후속 UX 보정 후보로 기록한다.
- 최초 비민감 Simulator 녹화 영상은 22KB라 pending 상태를 안정적으로 만들 수 없었지만, 이후 `Test Room` 대용량 동영상 보충 QA로 upload 동시 취소를 확인했다.
- 최초 자동 QA에서는 같은 provider 로그아웃/로그인을 보류했지만, 이후 `Test Room`의 내보낸 Google 계정으로 동일 Google provider 재로그인을 완료했다.
- 대용량 보충 QA에서는 ban 직후 열린 화면이 올바르게 제한 상태로 전환됐지만 앱 재실행·방 재진입 뒤 active ban인데도 `채팅 참여하기`가 노출됐다. 탭해도 서버가 membership 생성을 거부해 member/projection·메시지·Storage는 변하지 않았으나, 실패 안내 없이 메시지 목록이 비는 UI 결함을 확인했다. 서버 보안 계약은 통과하고 클라이언트 ban 상태 재조회·오류 표시 보정이 필요하다.
- 위 보충 QA 결함 보정 구현: 서버 전용 `getMyRoomAccess`, 앱 진입·foreground 재조회, 기술 오류 문구 제거, 참여 실패 시 메시지 목록 유지, 메시지 long press 내보내기와 참여자 프로필/관리 버튼 분리를 완료했다. Functions 191/191, iOS Production build와 관련 단위 suite를 통과했다. OpenJDK 21 환경에서 Firestore·Storage emulator 전체를 재실행해 Rules 41/41과 transaction 26/26을 통과했으며, transaction suite에는 `member → banned → joinable`, 유효 lease 재점유 금지, 최대 시도 stale lease의 `failed` 종결 검증이 포함된다. `getMyRoomAccess` Production exact-target 배포는 완료했고 같은 provider 재로그인 실앱 QA 결과를 이어서 기록한다.
- iPhone 17 Pro Max의 내보낸 Google 계정을 로그아웃한 뒤 동일 Google 계정으로 다시 로그인했다. 최종 소스 Production-Debug 빌드를 덮어 설치한 상태에서도 `Test Room`의 기존 텍스트·완료 동영상은 읽히고 `재입장이 제한된 채팅방입니다`가 표시됐으며 메시지 입력·첨부 UI는 없었다. 사후 읽기 전용 감사는 member/memberCount 1, active ban 1, 대상 member/joinedRooms/roomState 0으로 재로그인 전과 동일했다.
- 사용자가 후속 실앱 QA 1~8을 완료해 신규 메시지 long press 내보내기, 참여자 프로필/별도 관리 진입, 수정된 업로드 중단 문구, unban 뒤 명시적 재참여·송수신, 방 종료와 미완료 media/local retry 정리까지 확인했다.

이번 두 계정 QA 제외 범위:

- 영구 정지·계정 삭제·owner succession 실데이터 QA는 기존 내부 계정을 손상시키고 고객지원/개인정보 gate와 충돌하므로 수행하지 않는다. Functions transaction 24/24, Rules 41/41, succession scheduler 빈 queue smoke를 완료 근거로 사용한다.
- 실제 기기 background FCM/APNs는 Apple Developer Program/APNs 설정 후 출시 전 외부 gate에서 별도로 확인한다.

## Phase 6 — 현재 규모의 텍스트 입력 안전·전송 남용 방어·로그 최소화

- [x] 욕설·혐오·위협·금칙어·광고·링크·반복 문장과 공백/기호/Unicode 우회를 자동 판정하거나 차단하지 않는다.
- [x] 텍스트 채팅·룩북 공유 문구·댓글·답글은 자동 의미 필터나 외부 moderation provider 호출 없이 신고·차단·방 운영·관리자 사후 검수로 관리된다.
- [x] 댓글·답글 생성은 현재 텍스트 전용이고 미디어 attachment 입력을 새로 노출하지 않는다. 이미지·동영상 채팅의 격리·기술 검증은 Phase 7 경계다.
- [x] 채팅/룩북 공유 UTF-8 4,000 bytes, trim 이후 댓글·답글 UTF-16 code unit 1,000과 기존 타입·빈 값·권한 검증을 유지한다.
- [x] 앱은 길이 counter나 제한 임박 경고 없이 채팅 4,000 bytes와 댓글·답글 1,000 UTF-16 units 상한을 넘는 입력을 막으며 서버 거부 뒤 입력을 보존한다.
- [x] text 12/2초, lookbook 6/2초, image preflight/finalize 각 4/2초, video preflight/finalize 각 4/2초가 canonical moderation principal + room + kind별로 적용된다.
- [x] limiter key가 `socket.id`, 클라이언트 UID·email을 사용하지 않고 principal 누락/오류 연결은 fail closed한다.
- [x] 동일 principal의 reconnect·다중 연결로 limiter가 초기화되거나 별도 bucket으로 우회되지 않는다.
- [x] 다른 principal·room·kind의 정상 전송은 서로 간섭하지 않는다.
- [x] 같은 유효한 messageID 재시도는 같은 process에서 quota를 다시 소비하지 않고 기존 Firestore transaction이 최종 멱등성을 보장한다.
- [x] Socket bucket은 60초 idle TTL·30초 bounded sweep·50,000 cap을 지키고 cap 도달 시 새 bucket을 fail closed하며 restart 초기화가 메시지 원장에 영향을 주지 않는다.
- [x] Development·Production Socket의 Cloud Run `maxScale=1`을 읽기 전용으로 확인했다.
- [x] 댓글·답글은 principal 전역 합산 20/분이고 동일 clientRequestID replay는 quota·UGC를 중복 생성하지 않는다.
- [x] 전송 탭에서 UUID를 생성하고 네트워크 재시도에는 같은 ID를 유지하며 입력 수정·취소·성공 후 새 작성에는 새 ID를 사용한다.
- [x] rate limit 시 자동 재전송하지 않고 입력과 UUID를 유지하며 안내 후 `retryAt` 이후 사용자 직접 재전송만 수행한다.
- [x] 댓글·답글 counter는 server-only이고 본문·target detail 없이 `expiresAt` 2일 TTL만 가진다.
- [x] 초과 요청은 저장·broadcast·push 전에 `RATE_LIMITED/resource-exhausted`와 `retryAt`으로 거부된다.
- [x] 신규 text/lookbook/media 메시지의 Firestore·Socket·FCM·iOS model·GRDB 어디에도 `senderEmail`이 저장·전송되지 않고 client email은 무시된다.
- [x] Development·Production의 active principal projection과 기존 message senderEmail을 읽기 전용 감사했다. 양 환경 message 0건, Production active principal 2건 모두 유효해 데이터 migration은 만들지 않았다.
- [x] 성공·invalid payload·예외 로그에 메시지/답장 원문, email, nickname/avatar와 전체 payload가 남지 않는다.
- [x] 과거 내부 QA 로그는 별도 삭제·신규 export 없이 기존 Cloud Logging retention으로 자연 만료된다.
- [x] 신고된 텍스트만 Phase 2의 제한된 evidence snapshot으로 보존된다.
- [x] 관리자 queue는 기존 고정 우선순위 정렬을 유지하고 arbitrary count/history 정렬은 후속 관리자 웹 task로 분리된다.
- [ ] App Review Notes에 신고·차단·방 내보내기·관리자 사후 제재·고객지원 흐름과 자동 필터 미사용의 심사 불확실성을 기록한다.
- [ ] 외부 출시 전 관리자 웹 또는 제한된 운영 도구로 실제 신고를 확인·처리할 담당자와 긴급 24시간/일반 72시간 내부 경고 경로가 준비된다.

### Phase 6 Development 사용자 수동 QA

- [x] `OutPick-Development`로 앱을 실행하고 Development 계정 로그인·bootstrap이 정상 완료된다.
- [x] 2026-08-18 `getMyModerationState` 보정 배포 후 앱을 완전히 종료·재실행하고 방 생성이 정상 완료되는지 재확인한다. 실패하면 Production QA로 진행하지 않는다.
- [x] Development composite `CICAgOi3z5wK` READY 후 오픈채팅 탭을 pull-to-refresh해 생성한 방이 표시되는지 확인한다.
- [x] 일반 텍스트 메시지, 룩북 공유, 댓글과 답글을 각각 한 건 작성하고 즉시 표시·재진입 후 유지되는지 확인한다.
- [x] 채팅 입력은 counter를 표시하지 않고 ASCII 4,000 bytes까지 허용하며 4,001 bytes 입력은 반영하지 않는다.
- [x] 댓글·답글 입력은 counter를 표시하지 않고 1,000자까지 허용하며 1,001자 입력은 반영하지 않는다.
- [x] 네트워크 실패 뒤 댓글 또는 답글 본문이 지워지지 않고, 같은 본문 재시도 성공 후 한 건만 보이는지 확인한다.
- [x] 채팅방을 나갔다 다시 들어가거나 앱을 재실행해 기존 메시지가 정상 표시되는지 확인한다. 이 항목은 GRDB `senderEmail` column 제거 migration의 사용자 경로 smoke다.
- [x] 위 항목에서 오류 문구, 중복 콘텐츠, 입력 유실, 앱 crash가 없고 실패 시 재현 단계와 화면을 기록한다.

서버 burst 수치와 동시 멱등성은 수동 반복으로 재현하지 않는다. Socket 85/85와 Firestore transaction 29/29 자동 검증을 근거로 사용하며, 사용자는 화면 상태와 실제 Development 연동만 확인한다.

2026-08-18 사용자 수동 QA의 로그인·기본 전송·재진입 항목과 Codex Simulator 경계값 QA를 합쳐 완료했다. 채팅은 실제 3,200/4,000-byte 입력과 4,001번째 차단, 댓글·답글은 각각 800/1,000 UTF-16 counter와 1,001번째 차단을 확인했다. 재시도는 실제 네트워크 토글 대신 iOS 실패 주입·UUID transport 14/14, Functions 계약 5/5, Firestore Rules 41/41·transaction 29/29의 동일 요청 동시 3회 단건 수렴으로 결정적으로 검증했다. Development collection-group 사후 감사에서 800자 이상 QA 댓글·답글은 0건이라 경계값 입력이 실수로 저장되지 않았다.

## Phase 7 — 미디어 격리·정규화·신고 evidence

- [x] Phase 7.0 Node.js 24 worker가 sharp 0.35.3/libvips 8.18.3과 ffmpeg/ffprobe 5.1.9로 Linux build된다.
- [x] JPEG·PNG·animated GIF, raw HEIC/HEIF 거부, 실제 201-frame GIF 선제 거부와 1시간 H.264/AAC remux·metadata/부가 track 제거를 포함한 12/12가 통과한다.
- [x] Linux benchmark를 근거로 static 64M pixel, GIF 200 frame·frame당 16,777,216 pixel·총 100M pixel, 이미지당 60초, remux 10분과 2 vCPU·1 GiB·순차 처리를 확정한다.
- [x] 검증 Cloud Build는 registry push·Cloud Run 배포·traffic 전환·Firebase 데이터 변경 없이 종료된다.

- [x] 로컬 Rules/Socket 계약에서 reservation owner만 exact quarantine path에 최초 1회 업로드하고 v2 finalize 전후 message·seq·Socket·push를 만들지 않는다. Development Rules 배포와 실제 iOS image/video upload smoke를 완료했다.
- [x] Development quarantine·media bucket은 분리했고 quarantine의 `asia-northeast3` Standard, soft delete/versioning off, 1일 lifecycle과 일반 client deny Rules를 반영했다. evidence bucket은 Phase 7.4 범위이며 Production은 미생성이다.
- [x] Development image/video ready 확정에서 quarantine source와 execution/principal slot이 삭제·반환됐다. canceled/final failed/expired의 실제 원격 smoke는 자동 계약 근거만 있으며 확장 QA에 남아 있다.
- [x] 로컬 구현에서 `MediaUploads` 한 문서가 reservation·upload parts·attempt·lease·execution·retry·manifest를 소유하고 별도 1:1 processing job 문서를 만들지 않는다. reservation/signed target 24시간·processing deadline 6시간·terminal 7일 TTL과 UUID replay 멱등성을 자동 검증했다.
- [x] dispatcher transaction이 Development image/video 각 1, Production image 4/video 1 고정 slot만 claim하고 duplicate/stale lease를 watchdog으로 수렴시키는 계약을 자동 검증했다. Development image/video Job execution 각 1건이 실제 slot claim 뒤 성공했다. 동시 포화 smoke는 미수행이다.
- [x] Development 이미지/영상 Job이 task count·parallelism 1, 2 vCPU·1 GiB, retry 0과 전체 timeout 40분/12분을 사용한다.
- [x] principal별 active 이미지 메시지 2개·영상 1개가 고정 server-only slot transaction으로 제한되고 동일 UUID replay가 slot을 다시 소비하지 않는 서버 계약을 자동 검증했다. iOS local queue는 Phase 7.3 범위다.
- [x] iOS 공유 local FIFO가 image/video kind별 순서를 유지하고 `active_upload_limit`을 실패가 아닌 동일 identity backoff 대기로 처리한다.
  - [x] 자동 테스트에서 kind별 FIFO, image/video lane 독립성, waiter 취소, capacity 동일 identity backoff, 비비용량 오류 즉시 실패와 60→30+30·70→30+30+10 분할을 검증했다.
  - [x] iPhone 14에서 70장이 30+30+10 세 메시지로 분할되어 모두 실패 없이 최종 전송됐다. 60장은 동일 count 경계의 부분집합이며 60→30+30 자동 테스트가 있어 별도 실기기 반복을 생략했다.
- [x] 앱 종료·방 이탈 시 대기/활성 미디어 작업이 취소되고 보호된 source에서 수동 재시도 가능한 실패 상태로 복원되는지 실기기에서 확인했다. 큰 영상 전송 중 채팅방 화면을 이탈한 뒤 재진입했을 때 실패 팝업·왼쪽 실패 표시 없이 server success 또는 재시도·삭제로 수렴하고 중복 메시지와 자동 background PUT이 없음을 사용자가 확인했다.
  - [x] 첫 영상 앱 종료 QA에서 발견한 transient `isFailed` 표시와 `uploading` restore race를 silent pending 선복원 + 2·4·8초 status-only reconciliation으로 보정했다. 재실행 뒤 왼쪽 실패 표시 없이 server success 또는 재시도·삭제로 수렴하고 일반 실패 팝업도 표시되지 않는 것을 확인했다.
    - [x] status-only active 전환·cancel/ready·retry 소진·조회 오류의 자동 PUT 미호출과 manual retry session 제거/local payload 보존을 포함한 targeted test 26개, Development 기기 build·설치를 완료했다.
- [x] worker integration에서 실제 MIME·codec·dimensions·size·duration·track 검증, 이미지/동영상 metadata 제거와 512px video thumbnail을 자동 검증했다.
- [x] 로컬 단위 테스트에서 이미지 선택 결과를 메시지당 30장·합산 150 MiB로 순서 보존 분할하고 각 메시지 index를 다시 부여한다.
  - [x] 첫 두 번의 iPhone 14 31장 전송에서 마지막 1장이 reservation 전 실패한 원인을 보정했고, 세 번째 QA에서 30+1 모두 전송 성공했다. 분할 안내는 노출되지 않았다.
- [x] 사용자가 JPEG·HEIC·PNG와 animated GIF를 선택할 수 있고, iOS 정적 source가 orientation bake·4096px·sRGB·metadata 제거를 적용한다. HEIC/HEIF·JPEG는 JPEG quality 0.92, PNG와 GIF animation은 보존하며 서버는 raw HEIC/HEIF와 확정된 resource 제한 초과를 안전하게 거부한다.
  - [x] iPhone 14 JPEG가 `image/jpeg` source와 display로 ready 수렴했다.
  - [x] iPhone 14 실제 HEIC가 iOS에서 `image/jpeg` source로 변환되어 JPEG display로 ready 수렴했다.
  - [x] iPhone 14 PNG가 `image/png` source와 display로 ready 수렴했다.
  - [x] animated GIF 선택·animation 보존·ready 표시를 확인했다. 첫 재전송 upload `BEB3FFC5-D0C2-4376-B78C-A5AFBA959E04`의 ready 원본은 `image/gif`, 800×800, 50프레임, 각 40ms, loop 0을 정확히 보존했다. 표시 계약 배포 뒤 새 upload `0B635AEC-8AB9-4C4D-95CE-F5A4D17D6780`은 attempt 1, seq 20, `ready`, cleanup `completed`, failure 없음이며 message/mediaIndex 모두 `mediaFormat: gif`, `animated: true`다. 사용자가 iPhone 14에서 정적 thumbnail 우하단 `GIF` badge, viewer animation, 닫은 뒤 정적 thumbnail 복귀를 모두 확인했고 처리 구간 Function·image Service ERROR는 0건이었다.
  - 2026-08-20 세 건 모두 processing attempt 1, cleanup `completed`, Quarantine 잔존 0건이며 처리 구간 chat-media ERROR는 0건이었다.
- [x] 이전 resumable iOS E2E와 별개로 새 signed PUT 계약의 Development backend E2E에서 31,364,213 bytes MP4를 16 MiB 기준 두 조각으로 전송해 Compose→video Job→thumbnail/display→ready/cleanup 수렴을 확인했다. 350 MiB 상한·재생 시간 무제한 장시간 영상 실기기 QA는 남아 있다.
- [x] 현 로컬 계약은 이미지·영상 모두 attachment당 단건 signed PUT을 사용하고, 응답 유실 뒤 서버 reconciliation을 한 번 수행한 뒤 성공 또는 로컬 실패로 수렴한다.
- [x] 현 영상 finalize는 단일 source의 generation·크기·SHA-256·MIME를 검증하며 GCS Compose와 part path를 사용하지 않는다.
- [ ] 동일 finalize·worker retry가 message와 seq를 한 번만 만들고 failed/expired/canceled reservation은 seq tombstone 없이 정리된다.
- [ ] ready/cancel race는 먼저 commit된 상태로 수렴하고 기술 오류는 최대 3회 서버 retry 뒤 수동 retry로 전환된다.
- [ ] 앱 재실행 뒤 uploading/queued/processing/failed 상태가 복원되고 실패한 로컬 outbox는 7일 뒤 삭제된다. GRDB session payload 영속화·terminal credential 제거 자동 테스트는 통과했고 background relaunch 실제 QA는 남아 있다.
- [x] server window 뒤 과거 날짜의 실패 outbox 메시지가 복원돼도 날짜 separator diffable identifier가 중복되지 않는다. 실제 crash log의 `appendItemsWithIdentifiers` SIGABRT를 기준으로 회귀 테스트와 Development 실기기 재실행을 통과했다.
- [x] terminal 실패 outbox가 signed URL session을 지운 뒤에도 local/uploaded retry payload로 pending `.failed`를 복원해 재실행 후 시간 위치의 재시도·삭제 아이콘을 유지한다. 자동 회귀 34/34와 실기기 TR-1 육안 확인을 완료했다.
- [ ] 재시도·삭제 아이콘 탭 시 각각 확정 문구의 prominent/destructive 확인창이 표시되고, 취소는 상태를 유지하며 확인 이후에만 재시도/삭제가 실행되는지 실기기에서 확인한다.
- [x] 일반 이미지·동영상 전송 실패 시 별도 실패 팝업 없이 버블의 재시도·삭제만 표시된다. 동영상 실패 보정 빌드에서 iPhone 14 실기기 확인을 완료했고, 참여 제한으로 중단된 경우의 제한 안내는 기존 정책대로 유지한다.
- [x] 자동 정책 검증에서 uploading/queued/processing은 로컬 버블만 조용히 유지하고 failed/expired만 재시도·삭제 UI 대상으로 분류되며, 확정 전 활성 seq 0 메시지의 서버 액션을 모두 차단한다.
- [x] iPhone 14에서 정규화 직후 선명한 로컬 버블이 표시되고 warm 성공까지 로딩·진행률·전송 중 표시는 나타나지 않으며, 네트워크 단절 시에만 재시도·삭제가 나타나고 재연결 후 재시도 성공 시 조용히 사라지는 것을 확인했다.
- [ ] 실패 UI 리팩토링 빌드에서 미디어 dim/overlay와 시간 라벨이 사라지고, 같은 시간 위치의 소형 재시도·삭제 아이콘이 겹침 없이 표시되며 두 44pt 영역이 각각 정상 동작하는지 iPhone 14에서 확인한다.
- [x] 첫 실기기 정상 전송은 서버 ready까지 성공했지만 즉시 버블의 500px/quality 0.5 local thumbnail이 지나치게 흐려 화질 기준으로 실패 처리하고 source 기반 최대 1024px 메모리 다운샘플링으로 보정했다.
- [x] 보정 빌드에서 동일 upload source 기반 최대 1024px 다운샘플링 즉시 버블이 충분히 선명한 것을 iPhone 14에서 확인했다. 네트워크 실패 QA는 사용자 후속 진행 요청 시 수행한다.

### Phase 7.3 Development core E2E 결과

기존 resumable 실기기 이력에 더해 새 signed PUT backend core E2E를 완료했다. 실제 iOS background 확장 QA는 별도 Production 전 gate다.

2026-08-20 잔여 QA와 다음 구현은 다음 순서로 고정했다. 각 QA의 실제 결과와 backend cleanup을 확인한 뒤에만 다음 단계로 넘어간다.

1. JPEG·HEIC·PNG·animated GIF와 31장 선택 QA
2. 영상 및 앱 종료·방 이탈 실패→재시도·삭제 QA
3. Phase 7.3 완료 판정
4. Phase 7.4 evidence backend 구현 착수

- [x] 실제 로그인 세션에서 이미지 1장과 29초 동영상 1개를 Photos picker로 전송했다.
- [x] 두 건 모두 `uploading → queued → processing(attempt 1) → ready`, message/seq/mediaIndex 생성과 delivery job `completed`로 수렴했다.
- [x] ready bucket의 원본·썸네일이 존재하고 Quarantine source는 삭제됐으며 upload cleanup은 `completed`다.
- [x] 이전 조각 계약의 image/video Cloud Run Job은 각각 성공 종료했고 성공 구간 Cloud Run ERROR는 0건이었다.
- [x] Development Socket bucket IAM, Eventarc trigger invoker, task→dispatcher invoker와 dispatcher `run.app` OIDC audience 누락을 최소 권한으로 보정했다.
- [ ] JPEG/HEIC/PNG/GIF·31장/상한·장시간 동영상과 네트워크 단절·앱 종료·방 이탈→로컬 실패→재시도/삭제 확장 QA를 수행한다.
- [ ] 단일 source signed PUT 계약으로 Development 이미지·동영상 backend core E2E와 source cleanup을 다시 확인한다. PUT 응답 유실은 자동 테스트로 검증했고 이미지의 실제 네트워크 단절→로컬 실패→재연결·재시도 성공은 iPhone 14에서 확인했다. 동영상·앱 종료·방 이탈·삭제 확장 QA는 남긴다.
- [x] 실기기 JPEG 단일 source가 ready·delivery·cleanup으로 수렴하고 전용 media bucket의 기존/신규 thumbnail이 403 없이 렌더링된다.
- [x] v2 mapper가 `attachmentID`, `bucketThumb`, `bucketOriginal`, format/animation metadata를 보존하는 회귀 테스트가 통과한다.
- [x] ready Storage Rules는 account capability + visible message 두 문서만 조회하고 방 문서가 없어도 공개 message를 읽으며, 비노출 message와 비활성 account는 거부한다.
- [x] 23분 idle cold JPEG는 ready 8.85초, 직후 warm JPEG는 worker 2.43초·ready 2.56초·cleanup 2.83초로 측정됐다.
- [ ] 메시지와 이미지 뷰어 신고는 attachment 선택이나 동영상 시점 입력 없이 해당 메시지 전체 신고임을 명확히 표시한다.
- [x] Phase 7.4C-1 로컬 worker에서 이미지 묶음 전체 또는 동영상 전체를 generation-scoped 공통 evidence bundle로 copy/dedupe하고 완료 job 재실행이 object를 늘리지 않음을 fake Storage + Firestore emulator로 검증했다. C-2/C-3에서 Development bucket과 30장·350MiB 실제 E2E까지 통과했다.
- [x] Phase 7.4A 순수 계약은 versioned canonical tuple ID, 최초 revision 0, `processing → available → accepted`, queue 비강등, 24시간·7일 경계, retention·appeal/legal hold와 evidence/job 상태 전이를 단위 테스트 12개로 고정했다. Functions 전체 226/226·build·lint 오류 0과 JSON/diff 검증이 통과했다.
- [ ] 신고 성공 직후 메시지를 자동 숨기지 않고 접수 안내만 표시한다.
- [ ] 일반 단일 신고는 `holding`, 같은 메시지 고유 신고자 2명은 `reviewRequired`, 긴급 단일은 `urgent`로 분류된다. 기한이 지난 holding은 scheduler 없이 `reviewDueAt <= serverNow` 관리자 조회에 포함된다.
- [ ] 같은 작성자의 최근 7일 서로 다른 신고 메시지 3개와 전체 고유 신고자 2명을 모두 충족할 때만 사용자 검토 신호가 만들어진다. 한 신고자의 메시지 3개 신고와 한 메시지의 다중 신고만으로는 충족되지 않는다.
- [ ] 두 번째 신고자가 최근 네 번째 이전 메시지에만 있어도 분리된 `messageReporters` marker로 `메시지 3개 + 신고자 2명/7일`을 놓치지 않으며, `messagePatternReviewUntil`이 지나면 scheduler 없이 관리자 조회에서 제외된다.
- [ ] 24시간 고유 principal 기준 긴급 2명 또는 전체 사유 3명, 또는 관리자 수동 조치만 같은 review revision의 전역 임시 비노출을 만든다.
- [ ] 전역 숨김은 동일 seq 검토 tombstone이고 기각 복원은 push·banner·latestSeq·read frontier rollback·인위적 unread를 만들지 않는다.
- [x] 같은 `clientRequestID` replay는 revision-independent 최상위 receipt의 원래 성공 응답을 반환하고, terminal review 뒤에도 새 revision을 만들지 않는다. 새 ID의 같은 reporter/message/revision은 `alreadyReported`를 반환하며 moderation count·evidence를 늘리지 않는다.
- [x] 동일 UUID replay는 transport quota를 재소비하지 않고, 서로 다른 새 UUID receipt는 preparation 재사용·alreadyReported·messageAlreadyDeleted와 무관하게 user/room 요청과 합산 1분 10회까지만 허용한다. `messagePreparationCount`는 실제 신규 준비만 별도로 관측한다.
- [x] 신고/삭제 순서에서 삭제 우선은 `messageAlreadyDeleted` transport receipt와 limiter slot만 만들고 preparation·evidence·moderation count를 만들지 않는다. 신고 우선 media는 삭제 tombstone을 즉시 만들되 public cleanup을 `awaitingEvidence`로 두며, available drain이 processing receipt를 accepted로 확정한다.
- [x] evidence drain은 preparation 최대 30건과 각 최초 receipt만 직접 확정하고 추가 UUID receipt는 동일 UUID 재조회 때 개별 수렴해 receipt 수가 transaction 크기를 무제한 증가시키지 않는다.
- [x] 실패 재시작은 partial destination cleanup 완료·빈 objectPaths와 preparation/bundle/copy job의 동일 terminal generation을 요구하며 세 문서를 함께 `attemptGeneration + 1`로 전환하고 stale generation accept를 거부한다.
- [x] copy는 최초 포함 최대 3회와 1분/2분 backoff, 9분 timeout/12분 lease, generation-scoped destination과 generation+lease fence를 사용한다. 마지막 실패는 부분 객체를 모두 삭제한 뒤 receipt/preparation/guard/public cleanup을 terminal 상태로 수렴시킨다.
- [x] retention cleanup은 generation 일치 evidence 객체를 전부 삭제한 뒤 bundle 문서를 완전 삭제하고 비민감 cleanup receipt만 남긴다. Development 실제 이미지/영상 cleanup과 soft delete 0초·versioning off·잔여 0을 확인했으며 TTL field override는 Phase 7.4D gate다.
- [x] Development evidence bucket은 UBLA/public access prevention과 legacy/public binding 0을 유지하고, 익명·bucket operator 사용자·무관한 chat-media 서버 계정의 object read를 거부한다. 전용 evidence runtime의 실제 copy/cleanup 성공으로 허용 경로를 확인했다.
- [ ] Evidence 원본은 일반 클라이언트와 비활성/비관리자에게 거부되고 활성 플랫폼 관리자의 서버 인증 단건 조회와 audit만 허용된다.
- [ ] 기각·삭제만·경고만 evidence는 즉시 cleanup enqueue되고 계정 제재 evidence는 30일 이의제기 계약대로 삭제된다.

## Phase 8 — iOS UX

- [ ] 메시지 long press 신고가 해당 메시지 전체 incident와 sender 사용자 aggregate를 한 번에 기록한다.
- [ ] 프로필·참여자 목록 사용자 신고와 방 설정 방 신고가 같은 taxonomy를 사용한다.
- [ ] 자기 신고·자기 차단·권한 없는 creator action이 노출되지 않는다.
- [ ] 제한·정지 화면과 서버 capability가 일치한다.
- [ ] 마이페이지·신고 완료·제재 안내의 고객지원 route가 동일하다.
- [ ] 로딩·중복 탭·오류·retry·Dynamic Type·VoiceOver를 확인한다.

## Phase 9 — 통합·출시

- [ ] Functions lint/build/test, Socket check/test, Firestore·Storage emulator, iOS targeted test/build가 통과한다.
- [ ] 기존 Chat ordering/read frontier/membership/account deletion/Lookbook 차단 회귀가 없다.
- [ ] Development 일반 사용자 2명·creator 1명·platform admin 1명 demo가 재현된다.
- [x] provider backfill dry-run과 불명확 계정 보고가 완료된다.
- [x] Kakao UID 후보를 Admin API 응답 ID와 대조하고 불일치·미연결·HTTP 실패를 unresolved로 분류한다.
- [x] Production apply가 exact 확인 문자열·예상 total/Google/Kakao·unresolved 0을 쓰기 전에 검증한다.
- [x] migration summary가 UID·provider subject·email·token·Secret·API 본문을 출력하지 않는다.
- [x] Production Auth dry-run이 total 2/Google 1/Kakao 1/Apple 0/unresolved 0으로 실행 직전 기대 건수를 만족한다.
- [x] Production HMAC Secret version 1을 원문 출력·로컬 저장 없이 생성하고 enabled 상태를 확인한다.
- [x] Production `getMyModerationState` 단일 Function이 ACTIVE이고 HMAC Secret version 1에 binding된다.
- [x] 무인증·App Check 없는 Production callable 요청이 mutation 전에 401로 거부되고 배포 후 ERROR 로그가 없다.
- [x] Production backfill apply 직전 dry-run과 exact confirmation/expected-count gate가 total 2/Google 1/Kakao 1/unresolved 0을 만족한다.
- [x] Production account/principal/alias가 각각 2개이고 모두 active이며 참조 무결성과 민감 원문 0개를 만족한다.
- [x] capability 영향 기존 callable 14개와 account deletion finalizer 1개를 exact target으로 배포하고 15/15 ACTIVE·ERROR 0을 확인한다.
- [x] finalizer scheduler ENABLED와 배포 전 Function source generation 15개의 보존을 확인한다.
- [x] Production Firestore 이전 immutable ruleset ID·source hash를 확보하고 로컬 변경본과 다름을 확인한다.
- [x] Production Firestore Rules dry-run compile이 통과한다.
- [x] Firestore·Storage Emulator Rules 35/35와 transaction 11/11을 배포 직전에 재검증한다.
- [x] Production Firestore Rules를 exact target으로 배포하고 새 ruleset의 로컬 hash 일치와 이전 ruleset 보존을 확인한다.
- [x] Production Storage 이전 immutable ruleset ID·source hash를 확보하고 로컬 변경본과 다름 및 dry-run compile을 확인한다.
- [x] Production Storage Rules를 exact target으로 배포하고 새 ruleset의 로컬 hash 일치와 이전 ruleset 보존을 확인한다.
- [x] Production Socket candidate 전 `check`와 69/69 테스트, live revision·image digest·traffic·runtime 설정을 확인한다.
- [x] Production Socket 0% candidate가 live traffic을 유지한 채 readiness·인증 smoke를 통과한다.
- [x] `socket.io-parser`를 4.2.7로 최소 patch하고 check·69/69·npm audit high 0을 확인한다.
- [x] 패치 image로 새 0% candidate를 만들고 build audit high 0·readiness·ERROR·digest를 재검증한다.
- [x] 별도 승인으로 Socket candidate에 traffic 100%를 전환하고 rollback revision과 오류를 확인한다.
- [x] Phase 1-P 운영 데이터 mutation·backfill·배포가 단계별 별도 승인을 받는다.
- [x] Production Google·Kakao active 로그인, 메인 탭, 기본 read/write smoke를 통과하고 임시 App Check debug token을 폐기한다.
- [ ] 관리자 웹 task가 API/schema/demo fixture를 인수한다.

## Production 운영 출시 전 필수 확인

- [ ] moderation principal·room ban 보존의 법적 근거·기간·고지가 승인됐다.
- [ ] Kakao User ID Fixed와 provider 재연결 QA를 통과했다.
- [ ] Google Cloud media 처리와 App Privacy 응답이 최신화됐다.
- [ ] 미성년자·불법·성적 콘텐츠 escalation과 age rating 응답이 확정됐다.
- [ ] 고객지원 URL·담당자·긴급/일반 운영 경로가 준비됐다.
- [ ] platform admin bootstrap/revoke/recent-auth/break-glass runbook이 검증됐다.
- [ ] App Review demo 계정과 신고·차단·방 내보내기·제재 복구·고객지원 경로가 준비됐다.
