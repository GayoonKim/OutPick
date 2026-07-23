# OutPick Handoff

## 1. 최종 목표

- 2026-07-23 extraction review를 최종 content-hash 후보 수와 expected-count evidence의 차이에 집중하도록 단순화했다. 예상 수 일치+hash 완료는 첫 signature도 자동 진행하고, 예상 수 미확인·수량 불일치·hash 미완료만 검토한다. iOS는 가로 이미지 스크롤, 단일 `승인`, 미달 시 승인 제거와 `누락된 이미지 알리기` 카드로 변경했다. Worker 66/66·lint/build·fixture 5/5, iOS targeted 10/10·Simulator build/run이 통과했고 extractor `1.2.2` worker `lookbook-import-worker-00021-ghs`를 Ready/traffic 100%로 배포했다. rollback은 `lookbook-import-worker-00019-ftd`다.
- 2026-07-24 마감 QA 후속으로 expected-count를 활성 grid에 scope하고 정적 후보를 합산하는 extractor `1.2.3` 코드와 Season 상세 24개 cursor pagination을 구현했다. 저장한 YOUTH HTML에서 Spring 2nd `46`, Summer `49` evidence를 확인했다. iOS는 마지막 12개 trigger·PostID 중복 제거·refresh race 방지, 첫 12개·앞 32개·append page 최대 24개 `.memoryAndDisk` prefetch와 concurrency 4를 사용한다. append 직후 카드 노출 전 큐 등록과 반복 경로 중복 방지를 포함한 targeted 11/11·Simulator build/run이 통과했다. Worker 67/67·fixture 5/5이며 worker `lookbook-import-worker-00022-5gn`은 Ready/Active·traffic 100%, ERROR 0건, queue RUNNING/pending 0건, rollback은 `00021-ghs`다.
- 2026-07-24 사용자 승인으로 재등록한 운영 YOUTH(`HiqC4hP1PnsepTJSPnib`)와 과거 잔존 데이터를 완전 삭제했다. 현재 브랜드 root+하위 102개, 이름/요청/진단/evidence/전용 issue cluster/과거 Chat 공유 snapshot/과거 삭제 감사 로그를 포함한 전역 문서 17개, 브랜드 Storage 154개와 evidence JSON 4개를 영구 삭제했으며 신규 감사 로그는 만들지 않았다. 사후 재감사에서 현재·과거 YOUTH 브랜드, 전역 문서, 사용자 state, Chat snapshot, 감사 로그, Storage가 모두 0건이고 import queue도 pending 0건이다. 회귀 방지용 코드 fixture와 문서는 운영 데이터가 아니므로 유지한다.
- 2026-07-23 YOUTH 신규 등록에서 시즌 discovery가 0건이던 완료 후 회귀를 수정했다. Cafe24 `collection_detail.html` underscore 경로와 같은 URL로 분리된 이미지/제목 anchor를 공통 worker가 인정하도록 하고 최소 platform fixture를 추가했으며 extractor를 `1.2.1`로 올렸다. Worker lint/build·65/65, corpus 5/5·diff 0건과 현재 공개 YOUTH 목록 정적 후보 20개를 확인했다. 운영 worker `lookbook-import-worker-00019-ftd`를 Ready/traffic 100%로 배포했고 startup probe·port 8080 listen, ERROR 0건, queue task 0건을 확인했다. 별도 health task는 Cloud Run 인증 계층 404로 container request log에 도달하지 않아 모두 삭제했지만, 이후 사용자가 실제 앱에서 YOUTH 시즌 추출 목록을 정상 확인해 callable→worker→후보 저장·표시 smoke를 완료했다.
- `lookbook-extraction-learning-loop`는 Phase 1~8을 완료했다. YOUTH 시즌 URL의 정적 hero 1장과 script 기반 gallery 45장을 기존 worker가 성공 처리하던 silent under-extraction을 차단하고, 저신뢰 결과의 `awaitingReview`, 관리자 ground truth·구조 evidence·fixture differential·Generic→Platform→Domain adapter 경계를 운영에 배포했다.
- 다음 핵심 task는 사용자 결정으로 `lookbook-discovery-learning-loop`다. season discovery에도 구조 evidence, issue cluster, 관리자 정상/누락/오탐 ground truth, 최소 fixture 승격, extractor version gate를 season-image extraction과 같은 원칙으로 연결한다. 현재는 범위와 우선순위만 기록했으며 요구사항·데이터/API·관리자 UX·보존 정책 논의와 구현 승인 전에는 task 문서나 코드를 만들지 않는다.
- `development-production-environment-separation`은 그다음 핵심 후속 후보로 유지한다. 하나의 Xcode 프로젝트/app target에서 Development는 `GayoonKim.OutPick.dev`와 `outpick-test`, Production은 `GayoonKim.OutPick`과 `outpick-664ae`를 사용하고 `feature/* → PR → main → release tag → 승인 기반 운영 배포` 흐름을 구성한다. `docs/ai/tasks/development-production-environment-separation/`에 설계·결정·보류 상태만 기록했으며 사용자 재개 승인 전에는 브랜치 이동이나 구현을 시작하지 않는다.
- Phase 1 extraction core/evidence/version 경계를 완료했다. 후보 배열과 기존 fallback 동작은 유지하면서 candidate별 strategy/source evidence, query-value 없는 fingerprint, extractor `1.0.0`과 adapter version placeholder를 worker job/diagnostic에 연결했고 worker build/lint/test 34/34가 통과했다.
- Phase 2 YOUTH fixture/programmatic gallery evidence/quality gate를 완료했다. script total 45와 DOM image 생성 신호가 strong section 1장이어도 rendered fallback을 활성화하고 hero 1+gallery 45를 canonical source 후보 46개로 병합한다. content hash first-wins와 quality reason을 연결했으며 extractor `1.1.0`, worker build/lint/test 39/39가 통과했다.
- Phase 3 fixture corpus/differential runner를 완료했다. fixture는 브랜드별이 아니라 `generic/platform/incident` 구조로 분류하고 YOUTH, OUTSTANDING discovery/NNEditor, HATCHINGROOM archive-source 최소 fixture 4종을 고정했다. positive/negative/order/strategy/adapter/quality와 후보 추가·제거·이동/title 변경을 비교하며 worker 43/43, corpus 4/4가 통과했다.
- Phase 4 제품·권한·재개 계약 D18을 확정했다. `awaitingReview`에서 generation/hash snapshot을 고정하고 정상/오탐 제외 승인은 재파싱 없이 같은 job의 materializing부터 재개한다. 이미지 부족은 correctionRequired로 유지하며 task identity에는 dispatch generation을 포함한다. 권한 있는 관리자의 안전한 정상 승인은 `brandID + host + signature + version` 범위의 trust baseline을 자동 등록한다.
- Phase 4 D19도 확정했다. correctionRequired는 총 관리자가 같은 job의 새 review/dispatch generation으로 재분석하고, iOS 검토 상세는 Coordinator push로 연다. 별도 signature trust 체크박스는 없으며 오탐·부족·강제 승인·위험 reason은 trust 대상에서 제외한다. 초기 허용 reason은 안전 조건을 만족한 `programmatic_gallery_requires_review` 하나다.
- Phase 4 구현을 완료했다. worker는 고정 generation/hash와 scoped trust를 판정해 `awaitingReview`에서 materialization을 차단하고, Functions 3개 callable은 권한·stale·중복·audit·재분석을 처리하며, iOS는 import 현황에서 Coordinator push로 검토 상세에 진입한다. worker 47/47와 fixture 4/4, Functions 53/53 및 lint/build, iOS targeted 6/6와 Simulator build가 통과했다.
- Phase 5를 완료했다. failed/needsReview run의 allowlist 구조 evidence만 전용 Storage prefix와 7일 ledger에 보존하고, 동일 원인을 deterministic fingerprint cluster로 집계한다. 같은 dispatch retry는 occurrence를 중복시키지 않으며 fixed version 이후 재발은 recurrence로 기록한다. 운영 bucket에 lifecycle rule이 없음을 확인해 전역 정책 대신 04:45 전용 scheduled cleanup을 추가했다.
- Phase 6을 완료했다. 기존 import job을 repair generation으로 재분석해 canonical URL/content hash 기반 keep/add/reorder/remove-candidate preview를 만들고 generation/hash가 맞을 때만 같은 season에 적용한다. 기존 post ID/createdAt/reference는 유지하고 누락만 deterministic ID로 추가하며 삭제 후보는 마지막 순서에 보존한다. Functions 3개 callable과 iOS Coordinator push 검토 화면을 연결했고 worker 57/57, fixture 4/4, Functions 57/57, iOS 관련 targeted 9/9가 통과했다.
- 2026-07-23 운영 worker revision `lookbook-import-worker-00016-thf`와 Firebase Functions를 `outpick-664ae`에 배포했다. 인증된 관리자 화면에서 YOUTH repair preview `keep 1/add 45/reorder 0/remove 0`을 확인하고 적용해 같은 season `import_MTTKsL7GJPY0VdrYqjmb`의 post를 1개에서 46개로 복구했다. 기존 `post_0000`은 유지됐고 post asset 46개가 모두 `ready`, job asset은 completed 47/failed 0이며 repair generation 1 hash는 `15c90360b392d131571ccf81d51852555620d065`다.
- Phase 7 전 review UI 보완으로 extraction review와 repair가 메모리/디스크 캐시·동일 URL in-flight 병합·8개 window/동시 4개 prefetch를 제공하는 단일 remote preview loader를 공유한다. repair 네 구역은 2열 `LazyVGrid`와 상태 badge/순번 overlay로 바꿨다. Functions 57/57와 lint/build, iOS 관련 targeted 11/11, Simulator build/install/launch가 통과했으며 실제 운영 YOUTH grid 스크롤 시각 QA는 남아 있다. 이 UI 변경은 아직 별도 앱 release로 배포하지 않았다.
- repair diff가 0건일 때 의미 없는 검토 대기를 만들던 lifecycle을 수정했다. add/reorder/remove-candidate가 모두 0이면 audit `noChanges`, job `succeeded/completed`로 종료하고 season/post를 쓰지 않는다. iOS는 상세를 자동 닫아 `원본과 다시 비교` 상태로 복귀하며 진행 indicator는 문구 아래 accent 색상이다. Worker 59/59·fixture 4/4, Functions 58/58, iOS targeted 10/10과 Simulator build/run이 통과했다. 2026-07-23 worker revision `lookbook-import-worker-00017-stx`와 Firebase Functions 전체를 `outpick-664ae`에 재배포했고, worker Ready/traffic 100%, 큐 RUNNING, 새 revision recent ERROR 0건과 repair callable ACTIVE를 확인했다. 이 배포에서는 운영 데이터 mutation을 실행하지 않았다.
- Phase 7 adapter registry를 구현했다. Generic 추출은 adapter 없이 유지하고 Cafe24 공통 section/noise 규칙을 `cafe24@1.0.0`으로 격리했으며, discovery와 season-image가 같은 registry를 사용한다. 실제 domain adapter는 추가하지 않고 host+등록 fixture gate만 만들었다. extractor `1.2.0`과 전체 adapter version cache 검증을 연결해 과거 `null` adapter cache를 재사용하지 않는다. Worker lint/build, 65/65와 corpus 4/4·diff 0건이 통과했고 Phase 8에서 운영 worker에 배포했다.
- Phase 8 통합 회귀와 승인된 운영 검증을 완료했다. Worker 65/65·corpus 4/4, Functions 58/58, iOS targeted 14/14와 Simulator build/run이 통과했다. worker `lookbook-import-worker-00018-zwl`를 Ready/traffic 100%로 배포했고 rollback은 `00017-stx`다. OUTSTANDING은 운영 Cloud Run diagnostic에서 static 12 → rendered 44와 `needsReview`, YOUTH는 실제 URL read-only compiled dry-run에서 static 1 → source 46, HATCHINGROOM은 후보 17의 static 경로를 확인했다. queue pending 0건, 새 revision ERROR 0건이며 YOUTH 운영 데이터 mutation은 수행하지 않았다.
- 이후 2026-07-23 사용자 승인으로 운영 YOUTH(`sEr3SZDZJ5i3oDFegyT1`) 룩북 데이터를 즉시 영구 삭제했다. 브랜드와 시즌 5개·포스트 82개·import job 5개·repair 4개, 이름 인덱스 2개, diagnostic 3개, evidence/JSON 4개, YOUTH 전용 issue cluster 2개와 브랜드 Storage 176개·17,493,819 bytes를 삭제했다. 당시 보존했던 Chat 공유 snapshot 메시지 1개와 최소 감사 로그 `manual_purge_sEr3SZDZJ5i3oDFegyT1_20260723`도 2026-07-24 완전 삭제 승인에 따라 제거됐다.
- `docs/ai/tasks/lookbook-extraction-learning-loop/`의 design, D1~D20, Phase 0~8 계획과 QA를 기준으로 완료 처리한다.
- `chat-route-lifecycle-hardening`은 2026-07-22 완료했다. 오픈채팅/참여중 채팅의 탭별 navigation stack은 독립 유지하면서, 같은 stack의 Chat route는 기존 방을 제거하고 새 방으로 교체한다. `openRoom` 경쟁은 stack별로 격리해 같은 방 coalesce·다른 방 latest-wins를 적용하고 terminal route와 정상 transient 복귀 lifecycle을 분리했다.
- Phase 6 UIKit Chat edge-pop 복구, Phase 7 미사용 custom transition 제거, Phase 7B Profile modal threshold edge-swipe, Phase 8 Chat gesture 책임 축소와 Phase 9 최종 회귀를 완료했다. 최신 Debug build/install/launch, route/navigation/lifecycle/request 24/24와 session/ingress/read/window/ViewModel 영향 범위 86/86이 통과했다. 검색 prefix, RoomCreate 취소 흐름, Lookbook→참여중 Chat 이동과 두 탭 stack 복원도 실제 Simulator에서 통과했다.
- 2026-07-22 사용자 수동 QA로 룩북 채팅방 이동 중 interactive dismiss 잠금과 이미 화면에 보이는 realtime target의 preview card 억제를 추가 확인했다.
- `socket-ingress-ordering-hardening`은 2026-07-17 Phase 1~6 구현, 자동 회귀와 실제 Firebase/Simulator 핵심 QA를 완료하고 종료했다. realtime-only 3초 preview와 Phase 6 관련 52개 자동 테스트를 완료했고, explicit persistence는 `92 → transaction 89→92 → server 92`, 재진입 `lastRead/latest=92`로 정상 확인했다. 초기 latest 위치도 reload-data snapshot + bounded self-sizing 안정화로 수정해 `999999` 재진입 표시가 통과했다.
- `socket-message-dedupe-hardening`은 2026-07-16 구현·자동 회귀·candidate closeout을 완료하고 종료했으며, 2026-07-22 사용자 승인 후 `outpick-socket-dedupe0715`를 운영 traffic 100%로 전환했다.
- 서버는 instance 내부 single-flight와 Firestore transaction winner로 persist 이후 emit/push를 한 번만 수행하고, iOS는 `ChatRoomSessionActor`에서 방별 최근 message ID 300개를 consumer fan-out 전에 제거한다. Phase 1~3 구현, 공통 send receipt 수렴, Socket 62개와 iOS receipt/ingress 회귀 및 candidate text 동일 ID retry QA를 완료했다.
- `core-infrastructure-modularization`은 완료됐다. iOS Cloud Functions/GRDB, Firebase Functions와 Socket의 대형 concrete 진입점을 기능별 계약·구현과 공통 runtime, 얇은 entrypoint 구조로 전환하면서 기존 앱/Functions/Cloud Run 배포 단위와 wire/data 계약을 보존했다.
- `firestore-document-id-boundary-cleanup`은 완료됐다. 문서 경로 ID를 canonical source로 통일하고 앱 `@DocumentID`, 신규 중복 ID write, 운영 Rooms의 legacy `ID`를 제거했다.
- 해당 task의 Phase 1~4 구현·자동·수동 검증, Firestore rules 운영 배포, 운영 `Rooms.ID` 4건 cleanup과 사후 재감사를 모두 완료했다.

## 2. 완료한 작업

### Chat route lifecycle 분석·설계

- LLDB synchronous expression 경로의 autorelease pool page가 navigation stack snapshot과 Chat 객체를 잡는 진단 오염을 격리했다. Chat 객체를 expression으로 검사하지 않은 normal main run loop Back에서는 `ChatViewController` deinit이 즉시 확인돼 production retain leak 수정은 제외했다.
- 같은 stack에서 A → B push 뒤 A가 stack에 남은 채 finished/realtime nil/room-close nil/사용자 활성 false가 되고, B Back 후 `didAppear`가 finished를 되돌리며 일부 binding만 복원하는 lifecycle 결함을 확인했다.
- `openRoom` production 진입점을 룩북 Brand/Season/Post 이동, push notification, `DefaultAppContentRouter`/`DefaultMainTabBuilder` 경계까지 추적했다. 목록/검색은 `ChatRoom`을 이미 가진 동기 presentation 경로로 분리했다.
- D1~D13을 확정했다. 탭별 stack 독립, 같은 stack Chat 교체와 non-Chat prefix 보존, stack별 request 격리, same-room coalesce/top no-op, same-stack latest-wins, 탭 전환 시 현재 탭 유지, same-target mutation stale drop, terminal/transient lifecycle 분리와 룩북 loading/이동·닫기 잠금 UX가 핵심이다.
- `docs/ai/tasks/chat-route-lifecycle-hardening/`에 design, decisions, Phase 1~5 plan, progress와 QA checklist를 생성하고 Phase 1~4 구현·자동 검증 결과를 반영했다.

### Chat route lifecycle Phase 6~7B 완료

- `ChatNavigationController`가 system edge recognizer delegate를 소유하고 root/active transition을 차단한다. iOS 26 content-pop은 유지하며 `RoomCreateViewController`는 화면 정책으로 swipe를 거부해 기존 취소 확인창을 보존한다.
- 호출자가 없던 navigation/modal interactive transition extension과 `PushAnimator`/`PopAnimator` 네 파일, 마지막 no-op detach 호출을 제거했다. 실제 Profile modal의 `ChatModalTransitionManager`는 유지했다.
- Profile 상세 modal에만 왼쪽 edge pan을 추가했다. 종료 시 거리 35% 또는 오른쪽 속도 900pt/s를 넘으면 X 버튼과 같은 ViewModel/Coordinator 경로로 기존 왼쪽→오른쪽 닫기 애니메이션을 실행한다.
- navigation/route/lifecycle/request 24/24와 generic Simulator build가 통과했다. 사용자가 Chat·검색 swipe, 방 생성 차단/확인창, Profile modal 임계값·X 버튼·avatar 확대 viewer를 확인했다.

### Chat route lifecycle Phase 8 완료

- root background tap 하나가 키보드, attachment와 message menu 닫기를 담당하고, text input과 일반 `UIControl`은 제외한다. `ChatMessageCell` 내부 retry control과 cell action은 A안에 따라 background dismiss와 동시 인식한다.
- message long press는 collection view 범위로 제한하고 announcement/settings dim과의 불필요한 failure dependency를 제거했다. 미사용 gesture state와 delegate symbol도 정리했다.
- 선택 이유는 dismiss 책임을 하나로 모으면서 media/profile/retry/Lookbook의 기존 action 전달을 보존하는 최소 변경이기 때문이다. UIKit touch arbitration 전용 추상화와 별도 UI unit test는 범위 대비 이득이 작아 추가하지 않았다.
- 정적 참조 0건, `git diff --check`, generic Simulator build가 통과했다. Simulator에서 keyboard/attachment/menu dismiss, input/control, message/announcement long press, settings dim, Lookbook/retry cell을 확인했고 사용자가 실제 media/profile cell tap까지 확인해 수동 QA를 완료했다.
- QA용 공지는 해제했고 ACK 유실 fixture의 `880088` 메시지는 삭제해 서버 tombstone만 남겼다.
- 사용자 결정으로 media cell QA에 사용한 이미지 메시지는 삭제하지 않고 유지한다.

### Chat route lifecycle Phase 9 완료

- 최신 Debug 앱을 iPhone 17 Pro Max iOS 26.2 Simulator에 build/install/launch했고 기존 missing linker search path 경고 외 신규 오류가 없었다.
- `ChatNavigationControllerTests`, route stack, request state/registry와 lifecycle 5개 suite 24/24, session/ingress/read/window/ViewModel 9개 suite 86/86이 통과했다.
- `오픈채팅 목록 → 검색(공유) → OOTD 공유`에서 짧은 edge gesture 취소 뒤 Chat 유지와 일반 Back 뒤 검색어·결과 보존을 확인했다.
- 방 생성 진입과 Back 취소 확인창, `개설 취소하기` 뒤 목록 복귀를 확인했다. 실제 성공 생성은 영구 QA 방 생성을 피하고 Phase 9의 데이터 생성 불필요 결정에 따라 수행하지 않았다.
- Lookbook UNAFFECTED Brand를 `OOTD 공유`에 공유했다. 성공 직후 Lookbook 상세가 유지되고 사용자가 `채팅방으로 이동`을 선택한 뒤에만 참여중 Chat으로 전환됐다. Chat Back 뒤 참여중 목록, Lookbook 재선택 뒤 기존 Brand 상세가 복원돼 탭별 stack 독립을 확인했다.
- 실제 Firebase 요청 완료 순서 역전은 fetch가 빨라 deterministic하게 재현하지 않았다. stack별 coalesce/latest-wins/stale 차단은 24개 자동 회귀를 정확성 판정 근거로 사용한다.

### Socket message dedupe 설계·계획

- 기존 `socket-media-dedupe-hardening`을 `socket-message-dedupe-hardening`으로 확장했다. 서버 대상은 text, Lookbook, image, video 전체다.
- 요청별 인증·권한·rate limit과 media reservation 검증 후 `kind + roomID + messageID` 단위 single-flight에 참여한다.
- 공통 sequence transaction은 `{ seq, created }`를 반환하고 새 문서를 만든 winner만 transaction 밖에서 Socket emit과 FCM push를 수행한다.
- 완료 캐시와 별도 owner timeout은 첫 구현에서 제외한다. local in-flight는 같은 instance의 동시 요청 병합 최적화이고 Firestore message document가 instance 간 최종 권위다.
- iOS는 `ChatRoomSessionActor`가 방별 최근 message ID 300개를 보관하며 첫 ingress event만 consumer에게 전달한다. 같은 ID의 다른 seq는 두 번째 event를 drop하고 DEBUG에서 식별자와 old/new seq만 기록한다.
- `BannerManager`의 별도 최근 ID cache는 제거하고 `ChatMessageWindowStore`와 GRDB upsert는 최종 방어선으로 유지하는 계획을 확정했다.
- task의 design, D1~D13, Phase 1~4 계획과 QA checklist를 개정했다.
- Phase 1에서 `messageDeliverySingleFlight`와 상세 sequence outcome을 구현했고, Phase 2에서 `allocateSeqAndPersist`를 최종 `{ seq, created }` 계약으로 통일했다.
- text/Lookbook/image/video handler가 공통 single-flight를 공유하며 Firestore `created: true` winner만 emit/push한다. follower와 transaction loser는 기존 seq의 duplicate ACK만 반환한다.
- 완료된 media retry는 저장된 senderUID, media 종류와 attachment path가 일치할 때만 성공한다. reservation 삭제 race에서는 기존 message를 한 번 재확인한다.
- legacy `mediaDeliveryState`와 숫자 sequence wrapper를 제거했다. Socket syntax check와 전체 62개 테스트가 통과했다.
- Phase 3에서 `ChatRoomSessionActor`의 방별 최근 ID 300개 first-wins ingress dedupe와 actor lifecycle 정리를 구현했다.
- 로컬 실패 메시지 publish는 ingress recent-ID state를 우회해 같은 ID의 후속 서버 확인 event가 차단되지 않게 했다.
- `BannerManager`의 `recentPerRoom`/`RecentSet`을 제거하고 ingress actor를 중복 제거 단일 owner로 통일했다.
- 신규 actor 테스트 6개와 window/GRDB/listener 회귀를 합친 고유 테스트 20개, generic Simulator build가 통과했다.
- text/Lookbook/images/video ACK를 `ChatMessageSendReceipt`로 통일하고 optimistic message의 seq/attachment/실패 상태, GRDB와 outbox를 공통 reconciliation 경로로 수렴시켰다.
- Lookbook 결과 불명 retry는 최초 message ID를 재사용한다.
- candidate text `messageID=9B79F1C2-E3BC-431A-AF3E-D4C0D50C8B4E`, `seq=17`에서 ACK 유실→동일 ID retry 후 발신 실패 아이콘 해제와 수신 room preview 단일 표시를 확인했다.
- candidate Lookbook `seq=19`, image `seq=20`, video `seq=21`의 ACK 유실→동일 ID retry에서 서버 문서·Storage·수신·발신 GRDB/outbox 단일 수렴을 확인했다. image/video는 자기 ingress가 먼저 성공 수렴해 Simulator GRDB/outbox만 결과 불명 상태로 복원한 뒤 동일 ID finalize를 재전송했다.
- 더 오래된 image retry가 최신 video 이후 수행될 때 iOS ACK 후 client summary write가 Firestore `lastMessage`를 image로 역행시키는 회귀를 발견했다. iOS ACK 후 summary write를 제거하고 Socket transaction을 단일 owner로 확정했다.
- 신규 source 계약 테스트와 ACK/outbox/Lookbook targeted test 26개가 통과했다. candidate에서 최신 video B(`seq=21`) 뒤 오래된 image A(`seq=20`) retry를 재검증해 Firestore room `[동영상]`/`lastMessageSeq=21`/기존 `lastMessageAt`, 수신 preview와 A/B 단일 행 유지를 확인했다.
- 실제 transport 실패 text `F35EAECA-58D2-4EF1-B09B-BE9131407756`는 Firestore 미생성·발신 `seq=0/isFailed=1`·outbox failed에서 앱 재연결 후 같은 ID retry로 `seq=22`, Firestore 한 문서, 발신 성공/outbox 삭제와 수신 preview 한 건에 수렴했다. candidate Chat emit과 push fanout log는 각각 한 세트였고 ERROR log는 0건이었다.
- 2026-07-22 사용자 승인으로 candidate `outpick-socket-dedupe0715`를 운영 traffic 100%로 전환했다. 전환 직전 image digest와 런타임 설정, candidate·운영 readiness, Socket syntax check와 62/62 테스트를 재확인했다. 전환 직후 서비스 Ready, 운영 `/readyz` 200과 전체 Socket revision의 ERROR 이상 로그 0건을 확인했다. rollback 대상은 `outpick-socket-00006-k8k`다.

### Socket ingress ordering Phase 6 계획 확정·6-A~C 및 persistence/preview 후속 구현 완료

- 방 진입 자동 전체 읽음 대신 사용자가 `최신 메시지로 이동`을 탭하고 bounded target window의 로딩·snapshot·표시가 성공한 경우에만 고정 target까지 읽음 처리하기로 확정했다.
- [폐기된 기존 구현] 새 realtime 메시지가 없어도 entry tail이 read frontier보다 크면 preview card를 표시하도록 구현했다. 아래 최종 realtime-only 결정으로 제거 대상이다.
- 일반 읽음은 실제 visible candidate만 사용하고 newer page load, search jump, route 종료와 window max 자체는 frontier를 올리지 않는다.
- catching-up의 `liveBuffer` payload 보관을 제거하고 realtime은 persistence로 수렴시키며 UI는 scalar 상태와 최신 요약 1개, 이동 중 고정 요약 1개만 유지하는 계획을 확정했다.
- Phase 6-A read frontier 상태 → 6-B bounded persistence/target load → 6-C UI/render handshake → 6-D 통합 회귀·QA 순으로 진행한다. 상세 계획은 `docs/ai/tasks/socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md`다.
- Phase 6-A에서 `ChatReadStateStore`의 seeded monotonic frontier, 연속 visible candidate와 explicit gap candidate를 분리하고 window 없는 final frontier를 추가했다.
- 신규 `ChatUnreadCatchUpState`가 scalar high watermark/unread badge, 고정 target과 generation/loading을 소유하며 stale completion을 거부한다. 2개 suite 19개 테스트와 generic Simulator build가 통과했다.
- Phase 6-B에서 `liveBuffer`를 제거하고 catching-up incoming을 scalar latest + persistence-only로 전환했다. target window는 서버 권위 최대 80개이며 `Int64.max`를 안전하게 분기하고 target 포함을 검증한다.
- authoritative initial/history/latest와 realtime incoming은 GRDB 저장 성공 후 서버 확정 ID를 batch outbox reconciliation한다. 관련 4개 suite 22개 테스트와 generic iOS Simulator build가 통과했다.
- [폐기된 기존 구현] Phase 6-C에서 initial entry tail만으로 `ChatLatestMessageJumpView`를 표시하도록 구현했다. bounded snapshot/target 표시 handshake와 탭 target 고정은 realtime card 탭에도 유지한다.
- [폐기된 기존 구현] initial room summary의 `lastMessageSenderUID`를 GRDB local profile repository에서 읽도록 추가했다. 최종 계약에서는 realtime payload를 사용하므로 해당 DI와 테스트를 제거한다.
- 실패·취소·stale/search/route overlap은 기존 window·offset·frontier를 보존한다. 일반 읽음은 settled visible max와 증명된 연속 seq 상한만 사용하고 final flush의 `windowMaxSeq` 의존을 제거했다.
- Phase 6-D 부분 QA에서 최신 이동 후 pop/re-entry 시 unread 82가 복원되는 결함을 재현했다. 원인은 표시 성공 후 3초 debounce와 route lifecycle 경쟁, server write 이전 shared mark 순서였으며 표시 성공 직후 pending frontier를 await 저장하고 server 성공 뒤에만 flushed mark하도록 수정했다. 실패 pending은 final flush에 남긴다.
- 후속 변경 관련 5개 suite 고유 테스트 48개와 iPhone 17 Pro Max Simulator build가 통과했다. 실제 Firebase 재진입 persistence와 preview card/keyboard 핵심 수동 QA도 완료했으며, VoiceOver 실기기 QA는 2026-07-22 사용자 결정으로 후속 범위에서 제외했다.
- 실제 두 Firebase 개발 계정으로 `OOTD 공유`에 `1848001`, `1848002`를 전송해 재QA했다. card의 한 줄 요약·generic 아이콘·시각적 숫자 제거, AX label/value/button과 한글 software keyboard 배치는 통과했다.
- explicit target 표시 직후 pop-re-entry에서는 `1848001`이 unread 83개로, 충분히 대기한 pop-re-entry에서는 `1848002`가 unread 84개로 재노출됐다. card 제거가 server write 완료보다 먼저 발생하므로 즉시 이탈 cancellation 경합은 가능하지만, 대기 후에도 실패해 이것만으로 원인을 단정할 수 없다.
- 다음은 update 직전 pending seq와 masked room/user key, Firestore transaction result, 직후 authoritative fetch를 계측해 호출 누락·권한/transaction 실패·document key 불일치를 구분한다. 원인 확정 전 persistence 코드를 추가 수정하지 않는다.
- iOS 26.2 Simulator 설정에는 VoiceOver 항목이 없어 실제 음성/포커스 탐색은 실행하지 못했다. AX tree 계약은 통과했고, 2026-07-22 사용자 결정으로 실기기 VoiceOver QA는 후속 범위에서 제외했다.
- 2026-07-17 최종 사용자 결정으로 위 initial entry/local profile card 정책은 폐기했다. 기존 unread는 anchor에서 읽고 현재 세션 realtime에만 3초 preview card를 제공한다. realtime payload의 닉네임+내용을 정상 정보로 사용하고 payload 정보가 없을 때만 `새 메시지`로 fallback한다. target이 이미 실제로 보이면 card를 표시하지 않거나 즉시 제거한다.
- 이 결정은 `decisions.md` D15/D19, Phase 6 계획·QA와 Chat/Test 진입점에 반영하고 구현했다. `ChatRoomViewModel.initialLatestPreview`, `localProfileRepository` DI와 initial preview 테스트를 제거했으며 realtime payload 기반 테스트로 교체했다. `ChatViewController`가 3초 task, 실제 visible target 억제와 route/search cleanup을 담당한다.

### 다음 핵심 task 선정과 사전 조사

- 2026-07-14 사용자 결정으로 `firestore-document-id-boundary-cleanup`을 당시 `socket-media-dedupe-hardening`보다 먼저 진행할 핵심 task로 선정했다.
- `HANDOFF.md`, `docs/ai/tasks/active.md`, `ENTRYPOINTS.md`, Chat/Data entrypoint와 Data Schema를 확인했다.
- 코드 수정 없이 `@DocumentID` inventory를 확인했다. 현재 선언은 Chat `ChatRoom` 1개와 Lookbook DTO 14개다.
- `ChatRoom.init(from:)`의 wrapper 재초기화, `ChatRoom.toDictionary()`의 중복 `ID` write, `SeasonDTO.fromDomain`의 non-nil `@DocumentID` 초기화를 주요 경계 후보로 확인했다.

### Firestore document ID boundary Phase 1

- 문서 경로 ID를 canonical source로 하고 저장 payload의 자기 `ID`/`id`를 제거하는 ADR-020과 task/phase 하네스를 생성했다.
- Lookbook DTO 14개의 `@DocumentID`를 제거하고 read DTO를 `Decodable`로 제한했다.
- 기본 identity가 필요한 10개 DTO mapper가 `documentID`를 명시적으로 받으며 14개 Firestore Repository가 snapshot 경로 ID를 전달한다.
- `SeasonWriteDTO`를 분리해 Season 생성 payload에서 자기 문서 ID를 제거했다.
- `FirestoreDocumentIDBoundaryTests` 3개가 통과했고 generic iOS Simulator build가 성공했다.
- 빌드 경고는 기존 Chat actor isolation, deprecated API와 link search path 항목이며 Phase 1 신규 warning은 확인되지 않았다.

### Firestore document ID boundary Phase 2

- `ChatRoom.id: String`을 non-optional로 전환하고 Domain에서 Firebase import, Codable, `@DocumentID`, write dictionary를 제거했다.
- `ChatRoomFirestoreDTO`와 `ChatRoomFirestoreMapper`를 추가했다. 경로 document ID, 방 이름, 생성자 UID, 생성일은 엄격히 검증하고 부가 필드는 legacy 기본값을 허용한다.
- `CreateRoomRepositoryProtocol`로 생성 UseCase의 최소 계약을 분리하고, document ID 생성 책임을 Repository로 이동했다.
- 새 방의 room/member/joined projection을 한 Firestore transaction으로 생성한다. room payload에는 `ID`, `id`, `participantUIDs`가 없다.
- 앱 target의 `@DocumentID`는 0개다.
- Chat mapper 5개와 CreateRoomUseCase 3개 테스트, RoomSearch/Message/Exit/PendingMedia/LookbookShare 영향 테스트가 통과했다.
- 전체 test target build-for-testing과 generic iOS Simulator build가 성공했다.
- 현재 rules의 `existsAfter/getAfter` 조건과 새 transaction payload가 정적으로 호환됨을 확인했다. 실제 rules 허용/거부는 Phase 3 emulator test로 남겼다.

### Firestore document ID boundary Phase 3

- `Rooms` create에서 `ID`/`id`를 거부하고 update에서는 해당 필드 추가·변경·삭제를 거부하도록 `firestore.rules`를 강화했다.
- legacy `ID`/`id`가 불변인 metadata update는 허용한다.
- `firebase.json`에 Firestore Emulator 8080과 UI 비활성 설정을 추가하고 `firestore-tests/` Node test 하네스를 만들었다.
- 정상 owner room/member/joined transaction과 10개 경계·권한 실패 시나리오, 총 11개 Emulator 테스트가 통과했다.
- Firebase rules `--dry-run` 컴파일이 성공했으며 운영 rules는 배포하지 않았다.
- Emulator 실행을 위해 Homebrew OpenJDK 21을 설치했다. 설치 중 기존 Node 22.5.1의 ICU 연결이 깨져 Node 22.23.1로 같은 메이저 범위에서 복구했으며 `node v22.23.1`, `npm 10.9.8` 정상 동작을 확인했다.

### Firestore document ID boundary Phase 4

- 정적 검사, Firestore Emulator 11개, rules dry-run, generic Simulator build와 test target build-for-testing이 통과했다.
- iOS 26.2 iPhone 17 Pro Max Simulator의 targeted runtime test 59개가 모두 통과했다.
- 실제 로그인 상태에서 Chat 목록·검색·기존 방·방 생성·이미지 patch·정보 수정·종료와 Lookbook read를 검증했고 `I-FST000002`와 permission/decode/mapping 오류는 0건이었다.
- QA 방과 Storage 객체를 정리했으며 운영 Rooms 4건의 legacy `ID`가 모두 경로 ID와 일치하고 소문자 `id`는 0건임을 읽기 전용으로 재확인했다.
- D8에 따라 Season write는 `SeasonWriteDTO` 자동 테스트로 완료 판정했다. production 진입점이 없는 직접 시즌 생성 UI는 별도 후속 후보로 분리했다.
- Firestore Emulator 11/11과 rules dry-run을 다시 통과한 뒤 2026-07-14 `outpick-664ae`에 `firestore.rules`를 운영 배포했다.
- cleanup 직전 Rooms 4건의 `ID == documentID`, lowercase `id` 0건을 재확인하고 transaction으로 uppercase `ID`만 삭제했다.
- 사후 감사에서 방 4개 유지, `ID`/`id` 보유 0건, 핵심 불변식 누락 0건을 확인했다. 로그인 앱 재실행에서도 방 4개가 정상 표시되고 관련 mapping/permission 오류가 0건이었다.
- 루트 ENTRYPOINTS와 CHAT/LOOKBOOK/DATA/FIREBASE/TESTS 세부 진입점을 DTO→Mapper→Repository, rules, 회귀 테스트와 운영 cleanup 기준으로 최종 최신화했다.

### 핵심 인프라 모듈화

- Phase 2: iOS callable 38개를 공통 transport와 기능별 adapter/capability/mapper로 이전하고 `CloudFunctionsManager.swift`와 `callHelloUser`를 제거했다.
- Phase 3: `GRDBManager.swift`를 `AppDatabase`, 기능별 Store와 소비자별 persistence Protocol로 전환했다. fresh migration, FTS strict rollback, outbox 포함 room cleanup을 자동 테스트로 고정했다.
- D19: database bootstrap 오류를 `SceneDelegate`까지 전파하고 독립 실패 화면·수동 재시도·DEBUG once/always 실패 주입을 구현했다.
- Phase 4: `functions/src/index.ts`를 49개 명시적 export의 얇은 entrypoint로 만들고 Firebase Admin/runtime 단일 owner와 기능별 module로 분리했다.
- Phase 5: `Socket/index.js`를 41줄 bootstrap으로 축소하고 application/production DI, 기능별 handler/service/state/lifecycle 경계를 추가했다.
- Phase 6: candidate SHA `7580a1e`의 전체 자동 회귀를 통과하고 Socket revision `outpick-socket-00006-k8k`와 Firebase Functions 49개를 운영 배포했다. Functions source hash는 `6ab1e46ab24ec61401c312e92ad4e7e1c5c133d9`다.
- D49: `RealtimeSocketListenerBinder`로 한 Socket client의 listener 8개를 연결 전에 한 번만 등록하고 reconnect/consumer lifecycle의 `off/on`과 raw Socket.IO logger를 제거했다.

### 검증과 수동 QA

- 최종화 재검증에서 D49 binder/Chat 관련 15개 테스트가 통과했고 generic iOS Simulator build가 성공했다.
- iOS targeted tests와 generic Simulator build, Functions 51 tests/lint/build, Socket check/43 tests와 ADC local smoke가 통과했다.
- D49 binder test 5개와 관련 Chat tests, cold launch 5회, background/foreground 5회, room rejoin/text 단일 표시와 credential log 비노출 gate가 통과했다.
- 로그인 앱에서 Functions `searchBrands`, `listMyBrandRequests` 인증 read smoke가 통과했다.
- 채팅 text/image/video/lookbook 전송과 앱 재실행 GRDB 복원, 검색, 이미지/동영상 모아보기를 확인했다.
- 실패 메시지 retry의 failed message/outbox 생성과 단일 서버 persist, 정상 상태 복원을 확인했다.
- 일반 구성원 leave와 방장 close 후 Firestore·GRDB cleanup을 확인했다.
- `QA-P6-PAGE-0714` 105-message fixture에서 최초 `seq 26...105` 80개 로드, `loadOlderMessages(before: seq 26)` 호출과 `seq 1...105` 확장, 중복 부재, 최상단 `001` 표시를 확인했다. fixture는 전부 삭제했다.

### 배포와 rollback

- core infrastructure 배포 당시 revision은 `outpick-socket-00006-k8k`였고, 2026-07-22 현재 운영 revision은 `outpick-socket-dedupe0715`, rollback revision은 `outpick-socket-00006-k8k`다.
- Functions prior source rollback 기준: Git `ccc141e`.
- Socket/Functions 배포 gate에서 rollback은 필요하지 않았다.
- D49 앱 코드 commit은 `4a628dd`, 테스트 commit은 `6ab8d73`이다.
- task 상세 기록은 `docs/ai/tasks/core-infrastructure-modularization/`의 `progress.md`, `qa-checklist.md`, Phase 6 문서를 따른다.

## 3. 아직 남은 작업

1. YOUTH 실제 job 재분석은 별도 실행 범위로 남아 있다.
2. 앱에서 Spring 26 1st를 끝까지 스크롤해 75개 표시와 이미지 prefetch 체감을 수동 QA한다.
3. `lookbook-discovery-learning-loop`의 요구사항·데이터/API·관리자 UX·보존 정책을 논의해 설계 하네스를 확정한다.
4. `development-production-environment-separation`은 discovery 학습 루프 다음 후속 후보로 유지한다.
5. 실제 APNs delivery는 유효한 push target이 준비된 FCM 후속 QA로 유지한다.
6. 시즌 직접 생성 진입점은 별도 후속 task로 유지한다.
7. 룩북 evidence cleanup 실삭제와 repair 2열 grid의 운영 긴 스크롤 시각 QA는 별도 승인 기반 선택 QA로 유지한다.

## 4. 수정한 파일 목록

- `docs/ai/tasks/chat-route-lifecycle-hardening/design.md`: 확인된 결함, 탭별 stack 제품 불변식, route/request/lifecycle/룩북 UX 설계와 범위.
- `docs/ai/tasks/chat-route-lifecycle-hardening/decisions.md`: 사용자와 확정한 D1~D13.
- `docs/ai/tasks/chat-route-lifecycle-hardening/plan.md`: Phase 1~9 구현 순서와 완료 상태, 변경 파일, 테스트 설계와 검증 gate.
- `docs/ai/tasks/chat-route-lifecycle-hardening/progress.md`: Phase 1~9 구현 증거, 최종 24개·86개 자동 회귀와 Simulator QA 결과.
- `docs/ai/tasks/chat-route-lifecycle-hardening/qa-checklist.md`: stack/lifecycle/request race 자동 테스트, gesture와 최종 route 수동 QA, 선택적 후속 범위.
- `docs/ai/tasks/active.md`: `chat-route-lifecycle-hardening` 완료와 현재 진행 중인 핵심 task 없음 상태.
- `ChatCoordinator.swift`, `ChatNavigationStackPolicy.swift`: 같은 stack Chat 교체, top no-op와 non-Chat prefix 보존.
- `ChatOpenRoomRequestState.swift`, `ChatOpenRoomRequestRegistry.swift`: stack별 coalesce/latest-wins, Task 공유와 stale token 계약.
- `ChatRoomRouteLifecycleState.swift`, `ChatViewController.swift`: terminal 비가역과 정상 transient 활성 상태 복원.
- `LookbookShareConfirmationBar.swift`, Brand/Season/Post 상세 View: 이동 loading, 중복 실행과 닫기 입력 잠금.
- `OutPickTests/ChatNavigationStackPolicyTests.swift`, `ChatOpenRoomRequestStateTests.swift`, `ChatOpenRoomRequestRegistryTests.swift`, `ChatRoomRouteLifecycleStateTests.swift`: 관련 20개 자동 시나리오.
- `OutPick/Features/Chat/ChatNavigationController.swift`, `ChatCoordinator.swift`, `RoomCreateViewController.swift`: UIKit edge-pop 복구와 방 생성 swipe 차단 정책.
- 삭제한 `OutPick/Infra/Utility/Transitions/{UINavigationController+InteractiveTransition,UIViewController+InteractiveTransition,PushAnimator,PopAnimator}.swift`: 호출되지 않던 custom transition 제거.
- `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`: Profile modal threshold edge-swipe와 중복 dismiss 방지.
- `OutPickTests/ChatNavigationControllerTests.swift`: root/pushed/화면 opt-out/iOS 26 content-pop 정책 4개 검증.
- `docs/ai/ENTRYPOINTS.md`: Chat route/lifecycle/gesture, Profile modal과 변경 목적별 빠른 읽기 순서.
- `docs/ai/entrypoints/CHAT.md`: route/request/lifecycle/gesture 변경 파일별 코드 책임, 삭제 transition의 대체 owner와 검증 상태.
- `docs/ai/entrypoints/PROFILE.md`: Profile modal edge dismiss의 ViewController→ViewModel→Coordinator→transition manager 경로.
- `docs/ai/entrypoints/TESTS.md`: route 5개 suite의 파일별 계약과 Phase 9 24/24·86/86 최종 결과.
- `docs/ai/tasks/socket-message-dedupe-hardening/`: 전체 메시지 서버 idempotency와 iOS ingress dedupe의 design, D1~D13, Phase 계획, progress, QA checklist.
- `docs/ai/tasks/socket-ingress-ordering-hardening/`: Phase 0 D1~D14, 최종 design, Phase 1~5 plan, progress와 확정 QA checklist.
- `docs/ai/tasks/active.md`, core infrastructure D40 결정 문서: media 전용 참조를 새 task와 전체 메시지 범위로 전환.
- `HANDOFF.md`: 현재 설계 확정 상태, 다음 구현 순서와 승인 gate 반영.
- `Socket/src/messages/messageDeliverySingleFlight.js`: message identity single-flight owner/follower 병합.
- `Socket/src/messages/sequenceStore.js`: 최종 `{ seq, created }` transaction outcome과 duplicate no-write.
- `Socket/src/handlers/messageHandlers.js`, `lookbookShare/lookbookShareHandler.js`, `mediaHandlers.js`: 전체 message winner-only emit/push와 duplicate ACK.
- `Socket/src/media/mediaUploadService.js`: 완료된 media retry의 persisted sender/kind/path 검증.
- `Socket/src/app/createProductionDependencies.js`: process 공통 single-flight 생성·주입.
- 삭제: `Socket/src/media/mediaDeliveryState.js`, `Socket/test/media/mediaDeliveryState.test.js`.
- `Socket/test/messages/`, `test/handlers/`, `test/lookbookShare/`, `test/media/`, architecture contract: Phase 1~2 동시성·winner·retry 검증.
- `OutPick/Infra/Realtime/RealtimeSocketService.swift`: 방별 최근 ID 300개 Socket ingress dedupe와 local publish 분리.
- `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `FirebaseChatRealtimeGapRecoveryLoader.swift`: visible strict actor와 narrow Firestore recovery adapter.
- `OutPick/Infra/Banner/BannerManager.swift`, `BannerPresentationQueueState.swift`: lightweight watermark stream 소비와 bounded FIFO/summary presentation.
- `ChatRoomRealtimeRepository.swift`, `ChatRoomRealtimeUseCase.swift`, `ChatRoomViewModel.swift`, `ChatViewController.swift`: initial `entryTailSeq` baseline 전달.
- `AppCompositionRoot.swift`: production recovery loader를 단일 socket service에 주입.
- `OutPick/Features/Chat/Stores/ChatReadStateStore.swift`, `OutPick/Features/Chat/Domain/Models/ChatUnreadCatchUpState.swift`: Phase 6-A 단조 read frontier, Phase 6-B 고정 80개 latest target window, bounded 최신/고정 preview 계약.
- `ChatMessageManager.swift`, `ChatRoomMessageUseCase.swift`, `ChatInitialLoadUseCase.swift`, `ChatOutgoingOutboxUseCase.swift`: authoritative persistence 이후 서버 확정 ID batch outbox 수렴.
- `ChatRoomViewModel.swift`, `ChatViewController.swift`: catching-up scalar latest + persistence-only 처리, offscreen UI append/media warmup 차단.
- `ChatLatestMessageJumpView.swift`, `ChatMessageCollectionView.swift`, `ChatMessageWindowStore.swift`, `ChatRoomViewModel.swift`, `ChatViewController.swift`: Phase 6-C preview card, bounded snapshot/target 표시 handshake, explicit 즉시 persistence와 visible frontier.
- `OutPickTests/ChatReadStateStoreTests.swift`, `ChatUnreadCatchUpStateTests.swift`, `ChatLatestMessageWindowTests.swift`, `ChatMessageWindowStoreTests.swift`, `ChatRoomMessageUseCaseTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `ChatRoomViewModelMessageActionTests.swift`: Phase 6-A~C 상태·query·persistence/outbox/window/read 회귀.
- `OutPickTests/RealtimeChatIngressOrderingTests.swift`, `BannerPresentationQueueStateTests.swift`: strict/recovery와 Banner cap 회귀.
- `OutPickTests/ChatRoomSessionActorTests.swift`: ingress first-wins, 300개 eviction, reset, local/server 경계 테스트 6개.
- `OutPick/Features/Chat/Domain/Models/ChatMessageSendReceipt.swift`: 네 발신 종류 공통 ACK receipt와 optimistic message merger.
- `ChatViewController.swift`, `ChatViewControllerExtension.swift`: 최초 text/outbox retry/image/video finalize의 receipt 기반 UI·GRDB·outbox 수렴.
- `LookbookChatShareViewModel.swift`: 결과 불명 retry의 동일 message ID 재사용.
- `ChatMessageCell.swift`: 실패 메시지 재시도 아이콘의 버튼 접근성.
- `ChatViewController.swift`, `ChatViewControllerExtension.swift`, `ChatMessageCell.swift`: Phase 8 background dismiss 단일 owner, collection long press 범위와 cell action 동시 인식, dead gesture symbol 정리.
- `ChatMessageEmitAckMapperTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `LookbookChatShareUseCaseTests.swift`: receipt 파싱·병합·저장·ID 재사용 회귀.
- `docs/ai/ENTRYPOINTS.md`, `docs/ai/entrypoints/CHAT.md`, `docs/ai/entrypoints/TESTS.md`, task 문서: Phase 3 코드 진입점과 검증 결과 반영.
- `docs/ai/ENTRYPOINTS.md`, `docs/ai/entrypoints/CHAT.md`, `TESTS.md`: Phase 1 코드·검증 진입점.
- `OutPick/Features/Lookbook/Models/DTOs/`: read DTO 14개 경로 ID 분리와 새 `SeasonWriteDTO`.
- `OutPick/Features/Lookbook/Repositories/Implementations/Firestore*Repository.swift`: snapshot 문서 ID를 mapper에 명시 전달.
- `OutPick/Features/Lookbook/Models/Mapping/MappingError.swift`: 경로 ID 기준 오류 문구.
- `OutPickTests/FirestoreDocumentIDBoundaryTests.swift`: 경로 ID 우선·빈 ID 실패·Season write payload 테스트.
- `OutPick/Features/Chat/Domain/Models/ChatRoom.swift`, `CreateChatRoomInput.swift`: pure Domain room identity와 생성 입력.
- `OutPick/DB/Firebase/DatabaseManager/DTOs/ChatRoomFirestoreDTO.swift`, `Mappers/ChatRoomFirestoreMapper.swift`: Chat read DTO와 경로 ID/write payload mapper.
- `FirebaseChatRoomRepositoryProtocol.swift`, `FirebaseChatRoomRepository.swift`, `CreateRoomUseCase.swift`: narrow create 계약, Repository ID 생성, room/member/joined 단일 transaction.
- Chat room `.ID` 소비 파일과 관련 테스트: non-optional `.id` 계약으로 전환.
- `OutPickTests/ChatRoomFirestoreMapperTests.swift`, `CreateRoomUseCaseTests.swift`: mapper/write payload와 생성 UseCase 계약 테스트.
- `firestore.rules`: Rooms create/update의 `ID`/`id` 재유입 차단.
- `firebase.json`: Firestore Emulator 로컬 설정.
- `firestore-tests/`: rules unit testing package, 11개 계약 테스트와 Java 경로 감지 runner.
- `docs/ai/tasks/firestore-document-id-boundary-cleanup/`: design, decisions, plan, progress, QA와 Phase 1~4 문서.
- ADR-020, ENTRYPOINTS/CHAT/LOOKBOOK/DATA/TESTS/DATA_SCHEMA/active 문서: canonical document ID 경계와 Phase 1~2 결과.
- Functions와 Firestore indexes는 수정하지 않았다. 강화한 `firestore.rules`를 운영 배포하고 운영 Rooms 4개의 uppercase `ID` 필드만 삭제했다.

## 5. 중요한 아키텍처 결정

### 탭별 Chat stack 독립과 동일 stack route 교체

- 선택: 오픈채팅과 참여중 채팅은 각각의 navigation stack을 유지한다. 같은 stack의 A → B는 기존 Chat A만 제거하고 non-Chat prefix 뒤에 B를 배치한다.
- 이유: 두 탭의 제품 목적과 방문 문맥은 보존하되, terminal 종료된 A를 Back으로 부분 부활시키는 상태는 제거해야 한다.
- 트레이드오프: 같은 탭 안에서 방 A로 Back하는 방문 기록은 제공하지 않지만 종료된 realtime·observer·read/user 상태 전체를 suspended route로 복원하는 복잡성을 피한다.
- 보류한 대안: 전역 Chat stack 통합과 `A → B → Back → A` 복원은 각각 탭 문맥 손실과 lifecycle 회귀 위험 때문에 채택하지 않는다.

### navigation stack별 openRoom 경쟁 제어

- 선택: `openRoom` request token/generation은 대상 `UINavigationController`별로 관리한다. 같은 stack·같은 room은 coalesce, 다른 room은 latest-wins이며 서로 다른 stack은 독립 진행한다.
- 선택: 참여중 A 조회 중 오픈채팅 C로 이동하면 C 화면을 유지하고 참여중 stack에 A를 반영한다. 같은 참여중 stack에서 B를 열었을 때만 A를 stale 처리한다.
- 이유: 앱 전체 latest-wins는 서로 다른 탭의 정상 방문 기록을 잘못 취소하며, Task cancellation만으로는 늦은 Firebase 완료를 막을 수 없다.
- 트레이드오프: Coordinator에 stack별 요청 상태와 navigation snapshot/revision 검증이 추가된다. UIKit 상태를 ViewModel/Repository로 누출하지 않고 기능 내부 순수 상태로 테스트한다.
- 보류한 대안: global generation, first-wins와 serial queue는 각각 탭 간 간섭, 최신 의도 무시와 연속 route 적재 때문에 채택하지 않는다.

### terminal route와 transient 복귀 분리

- 선택: replacement/pop/dismiss/leave/close의 terminal finish는 `didAppear`로 되돌리지 않는다. 탭 전환·자식 화면·취소 pop 복귀에서는 사용자 활성 플래그와 transient binding을 정상 복원한다.
- 이유: 같은 stack Back에서 종료된 route가 부분 부활하는 결함을 막으면서 탭별 stack 보존에 필요한 정상 복귀는 유지한다.
- 재검토 조건: 향후 같은 stack에서 여러 Chat route를 의도적으로 suspend/resume하는 제품 요구가 생기면 별도 route state machine으로 재설계한다.

### Profile modal edge-swipe는 기존 dismiss 전환 재사용

- 선택: Profile 상세에만 왼쪽 edge pan을 두고 거리 35% 또는 오른쪽 속도 900pt/s를 넘으면 기존 ViewModel/Coordinator/`ChatModalTransitionManager.dismiss`를 호출한다.
- 이유: Profile 상세는 navigation push가 아닌 `.overFullScreen` modal이라 UIKit interactive pop 대상이 아니며, 기존 전환의 시각적·Coordinator 계약을 유지하는 최소 변경이 적합하다.
- 트레이드오프: 손가락을 따라가는 interactive progress는 제공하지 않지만 별도 transitioning delegate와 percent-driven 상태를 다시 도입하지 않는다.
- 재검토 조건: 여러 modal에서 동일한 interactive drag UX가 제품 요구로 확정될 때 공통 전환 구조를 별도 설계한다.

### Chat background dismiss와 cell action의 동시 인식

- 선택: root background tap을 dismiss 단일 owner로 두고 일반 input/control은 제외하되 `ChatMessageCell` 내부 action은 동시 인식한다. message long press는 collection view에만 설치한다.
- 이유: 키보드·attachment·menu 닫기 책임을 중복 없이 통합하면서 retry/media/profile/Lookbook의 기존 cell action을 보존해야 한다.
- 트레이드오프: UIKit gesture delegate가 cell 계층을 구분하지만 별도 arbitration abstraction을 도입하지 않아 변경 범위와 검증 비용을 제한했다.
- 보류한 대안: 모든 `UIControl`을 일괄 제외하면 retry 탭에서 background dismiss가 동작하지 않고, root long press를 유지하면 announcement/settings 영역과 불필요하게 경쟁하므로 채택하지 않았다.
- 재검토 조건: Chat 이외 Feature에서도 같은 gesture arbitration 규칙을 반복 사용하거나 UI automation 회귀가 필요해질 때 공통 policy/helper를 검토한다.

### Socket ingress ordering과 gap recovery

- 선택: `RealtimeSocketService`가 message callback의 단일 순차 ingress를, visible 방의 `ChatRoomStrictSessionActor`가 ordering/pending/gap을 소유한다. background `ChatRoomSessionActor`는 lightweight watermark 이후 metadata/Banner fan-out만 담당하고 history catch-up은 기존 UseCase/ViewModel에 유지한다.
- 선택: strict actor는 initial load의 `entryTailSeq`를 checkpoint로 삼고 `lastReleasedSeq + 1`을 expected seq로 사용한다. 같은 사용자 reconnect state 유지와 rejoin 감사 연결은 Phase 4에서 완료한다.
- 선택: pending 100개에서 즉시 recovery, 300개에서 authoritative mode, gap grace 0.5초, backfill page 100개와 최대 3회 retry를 사용한다.
- 이유: consumer별 정렬과 history/realtime 중복 상태를 피하고 기존 window/newer/reconnect 수치를 재사용해 bounded recovery를 만든다.
- 트레이드오프: recovery DI와 reconnect lifecycle 변경 범위가 넓어지지만 서버 wire/schema 변경 없이 client에서 누락·역순을 통제한다.
- 보류한 대안: room tail/read seq seed, unbounded buffer, checkpoint skip, ViewModel/Banner별 recovery와 actor의 Firestore 직접 접근은 identity 오판, 메모리 무제한, 누락 은폐 또는 아키텍처 위반 때문에 제외했다.
- 재검토 조건: server replay cursor/API, 개별 message hard delete, durable client checkpoint 또는 운영 recovery 비용 증거가 생길 때 D4/D7~D12를 다시 검토한다.

### 실시간 message end-to-end idempotency

- 선택: 인증·권한·rate limit 등 요청별 검증 뒤 같은 instance의 `kind + roomID + messageID` 요청은 single-flight로 합치고, Firestore transaction의 `{ seq, created }` 결과에서 `created == true`인 winner만 emit/push한다.
- 이유: local Promise는 같은 instance의 중복 작업을 효율적으로 합치고, Firestore winner는 재연결·재시도·다른 instance에서도 단일 side effect의 권위를 제공한다.
- 트레이드오프: 정확성 보장은 Firestore transaction에 의존하며 이미 완료된 재요청은 매번 Firestore 권위를 확인한다. 첫 구현에는 근거 없는 완료 cache와 별도 owner timeout을 넣지 않는다.
- 보류한 대안: process-local state만으로 보장, Redis 분산 lock, transactional outbox/exactly-once delivery는 각각 instance 경계 한계 또는 현재 요구 대비 운영 복잡성 때문에 제외했다.
- 재검토 조건: Firestore 확인 비용이 관측 가능한 병목이 되거나 emit/push 유실까지 복구해야 하는 요구가 생길 때 완료 cache 또는 outbox를 별도 설계한다.

### iOS ingress message ID dedupe

- 선택: `ChatRoomSessionActor`가 방별 최근 message ID 300개를 actor lifetime 동안 유지하고 첫 event만 consumer fan-out한다.
- 이유: 현재 UI active window 300개와 같은 bounded 기준을 사용하며 attachment cache, profile refresh, read state, preview, persistence 전에 중복을 차단한다.
- 트레이드오프: 300개를 벗어난 오래된 ID가 다시 유입되면 최종 `ChatMessageWindowStore`와 GRDB upsert 방어선이 처리한다. 같은 ID의 다른 seq는 첫 event를 보존하고 두 번째 event를 drop한다.
- 보류한 대안: consumer별 dedupe와 영구 저장 dedupe만 유지하는 방식은 중복된 선행 부작용을 막지 못해 제외했다.
- 재검토 조건: UI window 크기 변경, 장기 offline replay 도입 또는 room session actor lifecycle 변경 시 용량과 owner를 다시 검토한다.

### iOS 공통 send receipt 수렴

- 선택: text/Lookbook/images/video ACK를 `ChatMessageSendReceipt`로 통일하고 identity가 일치할 때만 optimistic message를 서버 확정 seq/attachment와 병합한다.
- 이유: duplicate ACK를 단순 성공 Bool로만 소비하면 서버 성공 뒤에도 실패 UI와 outbox가 남아 사용자가 재시도를 반복할 수 있다.
- 트레이드오프: legacy 빈 성공 ACK 호환을 위해 seq는 optional이지만 candidate 상세 ACK에서는 authoritative seq를 반영한다.
- 보류한 대안: text만 별도 보강하는 방식은 공통 결과 불명 계약을 종류별로 다시 분기하므로 제외했다.

### Modular monolith와 기존 배포 단위 유지

- 선택: 기능별 Protocol/Client/Store/handler/service와 공통 transport/database/runtime를 두고 앱, Functions default codebase, 단일 Socket Cloud Run service 배포 단위는 유지한다.
- 이유: giant concrete dependency와 변경 충돌은 줄이면서 MSA/codebase 분리의 운영 복잡성은 도입하지 않는다.
- 트레이드오프: 파일과 조립 type은 늘었지만 기능 소유권, 테스트 경계와 rollback 범위가 명확해졌다.
- 보류한 대안: 독립 service/codebase/Kubernetes는 독립 배포·IAM·autoscaling 요구가 구체화될 때 ADR-019 기준으로 재검토한다.

### D49 one-time Socket listener

- 선택: listener lifetime을 Socket client lifetime과 동일하게 두고 새 client 생성 때만 새 binder를 만든다.
- 이유: Socket.IO handler dispatch와 reconnect 중 `off/on`의 경쟁 가능성을 제거하고 event surface를 unit test로 고정한다.
- 트레이드오프: consumer가 없어도 listener는 유지되지만 actor의 room session lookup에서 payload를 안전하게 drop한다.
- 보류한 대안: reconnect마다 listener를 재등록하거나 Socket.IO 내부 handler 배열을 직접 검사하는 방식은 경쟁 상태와 라이브러리 private 구현 결합 때문에 제외했다.

### 종료 예외 분리

- 선택: FCM, D40, `@DocumentID` 경고와 일부 선택적 수동 QA를 미완료 Phase로 남기지 않고 별도 후속으로 분리한다.
- 이유: FCM은 외부 계정 조건, D40은 동작 변경 기능, `@DocumentID`는 별도 데이터 설계가 필요하며 이번 리팩토링의 완료 기준과 분리된다.
- 재검토 조건: Apple 개발자 계정 결제, media duplicate 운영 증거, Firestore mapping 기능 실패 또는 관련 기능 변경이 발생할 때 각각 새 task로 시작한다.

### Firestore document ID canonical boundary

- 선택: `DocumentSnapshot.documentID`만 자기 문서 identity의 source로 사용하고 write payload에 같은 `ID`/`id`를 저장하지 않는다.
- 이유: 경로 ID, 저장 필드와 `@DocumentID` wrapper의 우선순위 충돌과 `I-FST000002` 경고를 구조적으로 제거한다.
- 트레이드오프: Repository와 mapper 호출부가 문서 ID를 명시적으로 전달하고 Chat의 `.ID` 사용처를 넓게 변경해야 한다.
- 보류한 대안: wrapper read-only 최소 수정과 ChatRoomID 단독 도입은 각각 SDK 결합 잔존과 ID 체계 비대칭 때문에 제외했다.
- 추가 강제: Phase 3에서 Rooms create/update rules가 `ID`/`id` 재유입을 차단하며 2026-07-14 운영 배포했다. 기존 legacy `ID` 4건도 별도 승인 후 cleanup했다.

### Chat Domain/Firestore 생성 경계

- 선택: `ChatRoom`은 non-optional `id`와 화면에 필요한 상태만 소유하고 Firestore decode/write는 DTO/Mapper가 담당한다. `CreateRoomUseCase`는 narrow Repository 계약만 의존한다.
- 이유: Domain의 Firebase SDK 결합과 경로 ID/저장 ID 이중 source를 제거하고, 생성의 부분 성공을 Repository transaction에서 막는다.
- 트레이드오프: `.ID` optional 방어를 앱 전반에서 `.id` 계약으로 바꿔 영향 파일이 넓어졌지만 잘못된 identity 상태를 타입 경계 밖으로 밀어냈다.
- 보류한 대안: `ChatRoomID` 별도 값 타입은 현재 String 기반 경계와 비대칭 비용 때문에 도입하지 않았다. 부가 필드까지 모두 필수 decode하는 방식은 legacy room 호환성 때문에 제외했다.
- 재검토 조건: 다른 room backend 또는 복수 ID namespace가 도입되면 `ChatRoomID` 값을 다시 검토한다.

### Legacy ID를 보존하는 Rules update 경계

- 선택: create는 `ID`/`id` 키 존재를 거부하고 update는 해당 키의 diff만 거부한다.
- 이유: 신규 오염은 즉시 차단하면서 운영에 남은 legacy `Rooms.ID` 때문에 정상 방 정보 수정이 막히지 않게 한다.
- 트레이드오프: rules 배포만으로 legacy 필드는 자동 삭제되지 않아 별도 승인된 Admin SDK transaction으로 제거했다.
- 보류한 대안: legacy ID가 있는 모든 update를 거부하는 방식은 정상 metadata 수정 회귀 때문에 제외했다.
- 재검토 조건: 향후 rules 테스트 fixture를 현재 운영 상태에 맞춰 단순화할 때 legacy 불변 update 호환 테스트의 보존 여부를 별도로 결정한다.

## 6. 다시 확인해야 할 불확실한 부분

- 2026-07-24 extractor `1.2.3` 로컬 결과는 product 6052가 `[45, 46]`, 6159가 `[42, 49]`이며 비활성 grid의 75는 제외된다. 운영 worker 배포는 완료했지만 기존 운영 job은 자동 재분석하지 않아 저장된 과거 evidence는 그대로일 수 있다.
- Spring 26 1st의 75개 전체 표시는 pagination 자동 테스트와 Simulator build까지만 완료했다. 실제 운영 데이터로 끝까지 스크롤하는 수동 QA는 아직 하지 않았다.
- same-room coalescing은 fetch Task를 registry에서 공유하고 route 적용 전 token/navigation snapshot을 각 caller 경계에서 재검증하는 구조로 확정했다.
- 재확인 필요: 성공 방 생성 직후 `RoomCreateViewController` pruning과 외부 Chat 교체 조합은 실제 영구 QA 방을 생성하지 않아 수동 확인하지 않았다. 관련 생성 흐름을 바꿀 때 선택적으로 재검증한다.
- runtime 분석 결과 production Back retain leak은 확인되지 않았다. LLDB synchronous expression으로 객체를 잡는 방식은 deinit 증거로 다시 사용하지 않는다.
- 추가 retain 경로 분석은 2026-07-22 사용자 결정으로 후속 목록에서 제외했다. 디버거 expression 없이 production 경로에서 Controller/ViewModel의 지속 생존이 새로 재현될 때만 별도 leak task로 연다.
- traffic 0% candidate에서 네 종류 실제 retry와 오래된 duplicate ACK room summary 역행 수정·재검증을 완료했고, 2026-07-22 운영 traffic 100% 전환도 완료했다.
- 실제 Cloud Run 서로 다른 두 instance에 같은 요청을 deterministic하게 분산하는 검증은 수행하지 않았고 공유 Firestore transaction fake로 대체했다.
- 2026-07-22 운영 전환 직전 Cloud Run max instance 1, concurrency 80, timeout 3600과 revision/image digest를 읽기 전용으로 재확인했다. 이후 구성과 revision은 외부 상태이므로 장애 조사나 다음 배포 전 다시 확인한다.
- 서로 다른 instance의 동시 요청 자동 테스트는 독립 local single-flight state와 공유 Firestore transaction fake로 재현할 계획이며 실제 다중 revision 운영 검증 범위는 구현 후 별도 승인한다.
- FCM fanout은 실제 APNs entitlement/profile 환경에서 검증하지 않았다. Apple 개발자 계정 결제 후 재확인 필요다.
- Phase 2의 모든 상태 변경 화면을 수동으로 순회한 것은 아니다. 자동 wire/export/runtime 계약과 승인된 운영 read/통합 QA까지만 확인했다.
- `I-FST000002`는 Phase 4 전체 수동 QA 로그에서 0건이었고 기존 room 실제 read도 통과했다.
- 운영 rules는 2026-07-14 배포했다. 배포 직전 Emulator 11/11과 dry-run을 다시 통과했다.
- 운영 Rooms 4건 cleanup과 사후 재감사는 완료됐다. 감사 시점 이후 운영 데이터는 외부 상태이므로 관련 회귀 조사 시 다시 확인한다.
- Phase 1 실제 Firebase 브랜드·시즌·포스트·댓글 read는 통과했다. 시즌 직접 생성은 production 조립·표시 진입점이 없어 D8에 따라 자동 write 계약으로 완료 판정했으며, UI 처리는 별도 후속 후보다.
- 최신 Cloud Run revision, Functions 상태와 운영 데이터는 외부 상태이므로 후속 작업 시작 시 읽기 전용으로 재확인한다.

## 7. 다음 턴에서 바로 실행해야 할 작업

- 사용자 요청 시 YOUTH 재분석 전후 expected-count를 확인한다.
- 앱에서는 Spring 26 1st를 끝까지 스크롤해 24→48→72→75 append, 중복/누락 부재와 하단 retry·이미지 prefetch를 수동 확인한다.
- `lookbook-extraction-learning-loop` Phase 1~8 구현·자동 검증·운영 배포와 승인된 실제 URL smoke는 완료됐다.
- 운영 YOUTH 데이터는 사용자 승인으로 영구 삭제됐으며 과거 repair/smoke 수치는 삭제 전 증거로만 해석한다.
- 마감 QA 결함을 닫은 뒤 다음 핵심 task는 `lookbook-discovery-learning-loop`, 그다음은 `development-production-environment-separation`이다.
- evidence cleanup의 실제 만료 Storage/ledger 삭제 smoke와 repair 2열 grid 운영 긴 스크롤 시각 QA만 선택 후속으로 남아 있다.
- `chat-route-lifecycle-hardening`은 Phase 6~9와 최종 24개·86개 회귀를 완료한 종료 task로 취급한다.
- 새 핵심 task를 시작할 때 `docs/ai/tasks/active.md`에 등록하고 관련 설계 하네스를 먼저 진행한다.
- Socket 운영 traffic 전환은 완료됐다. 장애 징후가 확인되면 `outpick-socket-00006-k8k`로 100% rollback한다.
