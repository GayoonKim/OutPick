# OutPick Handoff

## 1. 최종 목표

- 2026-07-06 기준 다음 핵심 작업은 `admin-web-brand-season-management`다.
- 목표는 iOS 앱 안에 있던 운영자용 브랜드/시즌 생성/import 흐름을 일반 사용자 기능에서 분리하되, 별도 Admin 웹이 아니라 관리자 계정 전용 iOS Lookbook 관리 콘솔로 재배치하는 것이다.
- 총 관리자와 브랜드별 관리자를 구분하고, 브랜드별 관리자는 normalized email로 기존 `users.email`을 조회해 `brands.ownerUIDs/adminUIDs`에 추가하는 최소 모델로 도입한다.
- Phase 2 백엔드 계약 구현을 진행했다. 기존 Lookbook import worker/Functions/App 진입점 문서를 기준으로 iOS 관리자 콘솔 구현을 phase 단위로 이어가야 한다.
- 이전 chat identity/membership/profile cache boundary 핵심 전환은 완료했다.
- 완료 처리한 핵심 작업:
  - `chat-legacy-identity-naming`
  - `chat-membership-model-transition` 핵심 구현 및 운영 배포
  - 운영 smoke QA 기반 legacy cleanup/index 배포 결정 및 실행
  - `chat-member-profile-cache-boundary` Phase 1~4
  - `grdb-schema-cleanup`
  - `chat-membership-model-transition` destructive 수동 QA
  - `Socket dependency audit` 보수 업데이트
  - `Storage rules/preview 권한 확인` read-only 운영 상태 점검
  - `Storage rules 최소 권한 설계/적용` 운영 배포와 핵심 chat upload QA

## 2. 완료한 작업

### `chat-legacy-identity-naming`

- canonical user ID 기준 명명을 `userID`로 정리했다.
- `LocalChatUser.userID`, `RoomMember.userID` 등 Swift/API/GRDB 물리 schema를 Firebase Auth UID 의미로 맞췄다.
- legacy `userProfile`/`roomParticipant` runtime fallback과 backfill 동작을 제거했다.
- 프로필 문서 없는 사용자 fallback은 UID suffix가 아니라 “알 수 없는 사용자”로 표시한다.
- 최종 검증:
  - forbidden pattern 재검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

### `chat-membership-model-transition`

- membership authoritative source를 `Rooms/{roomID}/members/{uid}`로 전환했다.
- joined room projection은 `users/{uid}/joinedRooms/{roomID}`에 `roomID`, `role`, `joinedAt`, `lastReadSeq`, `isClosed`, `updatedAt` 중심으로 둔다.
- 참여중 목록은 joinedRooms projection fetch 후 `Rooms` batch fetch, 클라이언트 `Rooms.lastMessageAt DESC` 정렬로 구성한다.
- `lastMessage`, `lastMessageAt`, `lastMessageSeq`는 joined room projection에 fan-out하지 않는다.
- unread는 `Rooms.lastMessageSeq - users/{uid}/joinedRooms/{roomID}.lastReadSeq`로 계산한다.
- Socket room access, push fanout, 방장 close cleanup은 `Rooms/{roomID}/members` 기준으로 전환했다.
- Functions `onRoomClosed`의 legacy `participantUIDs` 배열 기반 cleanup은 Socket 즉시 cleanup과 충돌하지 않도록 비활성화했다.
- 운영 배포:
  - 2026-07-03 Socket Cloud Run `outpick-socket` revision `outpick-socket-00004-76z` 100% traffic 배포 완료
  - 2026-07-03 `firebase deploy --only firestore:rules --project outpick-664ae` 완료
  - 2026-07-03 `firebase deploy --only functions --project outpick-664ae` 완료
  - 2026-07-03 `firebase deploy --only firestore:indexes --project outpick-664ae --force` 완료
- 운영 legacy field count는 0으로 확인했다.

### `chat-member-profile-cache-boundary`

- 설계:
  - `LocalChatUser`는 전역 profile display cache다.
  - `RoomProfileDisplayCache(roomID, userID)`는 최근 메시지 sender 표시 전용 bounded relation이다.
  - room당 최대 20명, time-based TTL 없음, `lastSeenAt`/`lastMessageSeq` 기준 LRU eviction을 사용한다.
  - 설정 화면 참여자 목록은 remote `Rooms/{roomID}/members` pagination을 source로 한다.
  - local display cache는 전체 참여자 목록 대체 source로 쓰지 않는다.
- Phase 1:
  - `GRDBManager`에 `RoomProfileDisplayCache` model/table/migration/API를 추가했다.
  - room cleanup에서 `RoomProfileDisplayCache`를 삭제한다.
  - orphan `LocalChatUser` prune 기준을 display cache 중심으로 정리했다.
- Phase 2:
  - `ChatMessageManager`의 incoming/fetched message 저장 경로가 sender snapshot으로 `LocalChatUser`를 upsert하고 `RoomProfileDisplayCache`를 갱신한다.
  - 메시지 경로의 `RoomMember` write를 제거했다.
  - `ChatProfileSyncManager`는 `LocalChatUser` refresh만 담당한다.
- Phase 3:
  - `LoadChatRoomParticipantsUseCase`를 remote members pagination source로 전환했다.
  - 전체 members fetch + local `RoomMember` reconcile을 제거했다.
  - `ChatRoomParticipantsRepositoryProtocol`은 `LocalChatUser` read/upsert만 남겼다.
- Phase 4:
  - production 경계의 local membership replica API를 제거했다.
  - `RoomMember` table/model/migration은 migration chain 호환 흔적으로만 유지한다.
  - `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/CHAT.md`, task docs를 최신 구조로 갱신했다.
- 최종 검증:
  - forbidden pattern 검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

### `chat-membership-model-transition` destructive 수동 QA

- 테스트 room 기준으로 메시지 전송, 일반 방 나가기, 방장 close, Storage `rooms/{roomID}/` prefix 삭제를 확인했다.
- 방장 close 실패 원인은 Socket Firebase Admin 초기화에 Storage bucket 미지정 및 Cloud Run service account의 Storage object 권한 누락이었다.
- `Socket/src/firebaseAdmin.js`에 `OUTPICK_FIREBASE_STORAGE_BUCKET`/`FIREBASE_STORAGE_BUCKET` 기반 `storageBucket` 설정과 기본 bucket fallback을 추가했다.
- Cloud Run service account에 `roles/storage.objectAdmin`을 부여했다.
- 2026-07-03 Socket Cloud Run `outpick-socket` revision `outpick-socket-00005-jwg` 100% traffic 배포 완료.
- 방장 close 후 방장 화면의 참여중/전체 방 목록에서 즉시 로컬 제거되도록 `JoinedRoomsSessionStore` change stream과 room list cache 제거 경로를 추가했다.
- 최종 수동 QA에서 의도한 대로 동작함을 사용자 확인했다.

### `Socket dependency audit`

- Cloud Build 중 나온 `npm audit` 취약점 경고를 `Socket/` 패키지 기준으로 점검했다.
- `npm audit fix`와 보수 patch 업데이트만 적용해 `Socket/package-lock.json`을 갱신했다. `Socket/package.json`은 변경하지 않았다.
- direct/runtime dependency lock 상태:
  - `express` `4.21.2` -> `4.22.2`
  - `firebase-admin` `13.4.0` -> `13.10.0`
  - `socket.io` `4.8.1` -> `4.8.3`
  - `bufferutil` `4.0.9` -> `4.1.0`
  - `utf-8-validate` `6.0.5` -> `6.0.6`
- audit 결과는 24건에서 8건으로 감소했고, critical/high는 0건이 되었다.
- 남은 8건은 모두 `firebase-admin -> @google-cloud/firestore/storage -> google-gax/retry/uuid` 계열 moderate 취약점이다.
- `npm run check`와 `git diff --check -- Socket/package.json Socket/package-lock.json`는 통과했다.
- 운영 배포는 아직 하지 않았다. 배포는 별도 사용자 승인 필요.

### `Storage rules/preview 권한 확인`

- 2026-07-03 read-only 점검 당시에는 repo에 Storage rules source file과 `firebase.json`의 `storage.rules` 배포 설정이 없었다.
- 점검 당시 root `firebase.json`은 Firestore rules/indexes와 Functions만 관리했다.
- `OutPick/firebase.json`은 Functions 설정만 갖고 있어 Firebase source of truth로 쓰지 않는다.
- Firebase Rules REST API로 운영 release를 read-only 확인했다.
  - release: `projects/outpick-664ae/releases/firebase.storage/outpick-664ae.appspot.com`
  - ruleset: `projects/outpick-664ae/rulesets/a9ad4934-efaf-40d4-bdba-7e088743c817`
  - updateTime: `2024-10-03T10:51:50.370558Z`
- 당시 운영 Storage rules 본문은 `match /{allPaths=**} { allow read, write; }` 전역 허용 상태였다.
- 따라서 비참여 preview 이미지/비디오 read는 당시 운영 권한상 허용됐지만, write까지 열려 있어 출시/외부 테스트 전 최소 권한 rules로 좁혀야 했다.
- 조회 명령과 재확인 경로는 `docs/ai/entrypoints/FIREBASE.md`에 기록했다.

### `Storage rules 최소 권한 설계/적용 논의`

- 사용자 결정:
  - legacy prefix는 TestFlight/App Store 배포 전이고 초기화 가능 기준이 있으므로 기본 deny한다.
  - Lookbook read는 우선 `signedIn()` 기준으로 둔다.
  - Chat media read는 비참여 preview 요구사항과 Firestore message read 정책에 맞춰 `signedIn()` 기준으로 둔다.
  - Client 직접 업로드는 현재 구조상 유지하되 path별 권한과 contentType/size 제한으로 좁힌다.
- 확인된 client 직접 업로드 경로:
  - chat image/video message attachment
  - chat room cover
  - profile avatar
  - lookbook brand logo
  - lookbook season cover
- 로컬 변경:
  - `storage.rules` 신규 추가
  - root `firebase.json`에 `"storage": { "rules": "storage.rules" }` 추가
- rules 초안:
  - 기본 deny
  - `rooms/{roomID}/...` get은 로그인 사용자, write/delete는 room member 또는 creator 기준
  - `profileImage/{userID}/...` get은 로그인 사용자, write/delete는 본인 기준
  - `brands/{brandID}/...` get은 로그인 사용자, write/delete는 `brands/{brandID}.ownerUIDs/adminUIDs` 기준
  - legacy prefix는 기본 deny
- 검증:
  - `firebase deploy --only storage --project outpick-664ae --dry-run --non-interactive` 통과
  - `git diff --check -- firebase.json storage.rules` 통과
- 운영 배포:
  - 사용자 승인 후 `firebase deploy --only storage --project outpick-664ae --non-interactive` 성공
  - release: `projects/outpick-664ae/releases/firebase.storage/outpick-664ae.appspot.com`
  - ruleset: `projects/outpick-664ae/rulesets/148e8921-6195-42df-b575-09b17bbc88c4`
  - updateTime: `2026-07-03T10:04:35.211531Z`
  - 배포 후 ruleset 본문이 로컬 `storage.rules`와 같은 최소 권한 rules임을 REST API로 확인했다.
- 배포 직후 QA:
  - 참여자 이미지 메시지 전송 실패
  - 참여자 비디오 메시지 전송 실패
  - 방장 채팅방 커버 생성/수정/삭제 실패
- 원인:
  - 해당 실패 경로는 `isRoomParticipant()`/`isRoomCreator()`처럼 Storage rules에서 Firestore 문서를 조회한다.
  - Firebase Storage service agent에 cross-service rules용 `roles/firebaserules.firestoreServiceAgent` IAM binding이 없었다.
- 조치:
  - 사용자 승인 후 `service-715386497547@gcp-sa-firebasestorage.iam.gserviceaccount.com`에 `roles/firebaserules.firestoreServiceAgent`를 부여했다.
  - `gcloud projects get-iam-policy`로 `roles/firebaserules.firestoreServiceAgent`와 `roles/firebasestorage.serviceAgent`가 모두 부여된 것을 확인했다.
- IAM 반영 후 앱 수동 QA:
  - 참여자 계정이 `채팅 참여하기`로 `Rooms/{roomID}/members/{uid}`를 만든 뒤 이미지/비디오 메시지 전송 성공을 사용자 확인했다.
  - 방장 계정의 채팅방 cover 생성/수정/삭제 성공을 사용자 확인했다.
  - 남은 증상은 전송/업로드 실패가 아니라, 양쪽이 채팅방 화면을 보고 있을 때 새 텍스트/이미지/비디오 메시지가 즉시 UI에 들어오지 않는 realtime 수신 문제로 전환됐다.
- Realtime 수신 조치:
  - 원인 후보: `RealtimeSocketService.openRoomSession(for:)`가 메시지 리스너를 socket connect 전에 먼저 붙여, socket 객체가 아직 없는 첫 연결 경로에서 listener attach가 no-op이 될 수 있었다.
  - `openRoomSession(for:)`에서 connect 이후 `bindMessageListenersIfNeeded()`를 호출하도록 순서를 조정했다.
  - `handleConnected()`에서도 활성 room session이 있으면 메시지 리스너를 다시 보장하도록 했다.
  - `XcodeBuildMCP build_sim` 검증은 통과했다.
- 참여중 목록 unread badge 조치:
  - 증상: unread 5개인 방에 들어가 “여기까지 읽었습니다” marker 이후 나와도 `JoinedRoomsViewController` badge가 5로 남을 수 있었다.
  - 원인 후보: 채팅방에서 `lastReadSeq` flush가 먼저 shared `ChatRoomReadStateStore`에 반영된 뒤, 목록 fetch가 오래된 `users/{uid}/joinedRooms/{roomID}.lastReadSeq` projection을 seed하면서 shared snapshot의 `lastReadSeq`를 낮은 값으로 되돌릴 수 있었다.
  - `ChatRoomReadStateStore.seed(_:)`가 `latestSeq`/`lastReadSeq`를 단조 증가로 병합하도록 수정했다.
  - `JoinedRoomsViewModel`의 unread 계산은 seed 후 병합된 snapshot 기준으로 계산하도록 수정했다.
  - `ChatRoomReadStateStoreTests`에 stale projection seed가 최신 `lastReadSeq`를 되돌리지 않는 테스트를 추가했고 통과했다.
- 추가 조치:
  - 사용자가 realtime 수신과 unread badge가 모두 여전히 동작하지 않는다고 확인했다.
  - realtime은 `RealtimeSocketService.openRoomSession(for:)`에서 `identity`가 없으면 `SocketSessionIdentity.current()`로 identity를 만들고 connect를 보장하도록 했다.
  - 채팅 화면의 room session은 `join room` ACK가 성공한 뒤에만 열린 것으로 처리하도록 `joinRoomAwaitingAck(_:)`를 추가했다.
  - unread badge는 방을 나갈 때 서버 `lastReadSeq` write 완료를 기다리기 전에 shared `ChatRoomReadStateStore`에 final seq를 먼저 반영하도록 했다.
  - 관련 테스트 `ChatRoomViewModelMessageActionTests`, `ChatRoomReadStateStoreTests`, `ChatRoomRealtimeUseCaseTests`와 `XcodeBuildMCP build_sim`은 통과했다.
- GRDB senderID 잔존 오류 조치:
  - 사용자 로그에서 `SQLite error 19: NOT NULL constraint failed: chatMessage.senderID`가 확인됐다.
  - 원인: 기존 개발 DB의 `chatMessage` 테이블에 legacy `senderID NOT NULL` 컬럼이 남아 있는데, 현재 저장 SQL은 `senderUID`만 insert한다.
  - `GRDBManager`에 `rebuildChatMessageSenderUIDSchema` migration을 추가해 legacy `senderID` 테이블을 현재 `senderUID` schema로 재작성한다.
  - 재작성 시 기존 `senderUID`가 없으면 `senderID` 값을 `senderUID`로 backfill하고, `senderID` 컬럼은 제거한다.
  - `GRDBManagerMigrationTests.rebuildChatMessageSenderUIDSchemaRemovesLegacySenderIDNotNullColumn` 테스트를 추가했고 통과했다.
- 채팅방 밖 realtime 수신 목록 반영 조치:
  - 증상: 앱 실행 중 채팅방을 보고 있지 않을 때 참여중 방 메시지 배너는 뜨지만, `RoomListsCollectionViewController`/`JoinedRoomsViewController`는 pull-to-refresh 전까지 최신화되지 않았다.
  - 원인: `BannerManager`가 별도 realtime stream으로 메시지를 받아 배너만 표시하고, shared `ChatRoomReadStateStore`나 전체 방 목록 preview cache를 갱신하지 않았다.
  - `BannerManager`에 `ChatRoomReadStateStore`와 `FirebaseChatRoomRepositoryProtocol`을 configure하고, 수신 메시지마다 `seedLatest`와 `applyLocalIncomingMessagePreview(_:)`를 호출하도록 했다.
  - `FirebaseChatRoomRepository`는 realtime 수신 메시지를 top-room preview cache와 room summary에 로컬 반영한다.
  - `RoomListsViewModel`은 shared read-state stream을 구독해 cache snapshot을 다시 발행한다.
  - `JoinedRoomsViewModel`은 기존 read-state stream 구독으로 unread count가 즉시 갱신된다.
  - 추가 확인 후 남은 문제: unread count는 즉시 반영되지만 마지막 메시지/preview text가 즉시 바뀌지 않았다.
  - `ChatRoomReadSnapshot`에 `latestMessagePreview`/`latestMessageAt`를 추가하고, `seedIncomingMessage(_:)`로 배너 수신 메시지의 summary를 read-state change에 실어 보내도록 했다.
  - `JoinedRoomsViewModel`은 read-state change에 summary가 있으면 해당 room의 `lastMessage`, `lastMessageAt`, `lastMessageSenderUID`, `seq`를 즉시 갱신하고 정렬한다.
  - `RoomListsViewModel`은 read-state change 때 repository cache snapshot을 다시 발행하므로 top-room preview cache 변경이 화면에 반영된다.

### `Storage rules` 남은 수동 QA

- 2026-07-04 사용자 수동 QA로 남은 Storage rules 시나리오를 모두 확인했다.
- 완료 확인:
  - 비참여 사용자가 방 preview에서 이미지/비디오 thumbnail을 볼 수 있음.
  - 본인이 profile avatar를 업로드할 수 있음.
  - 브랜드 관리자/owner가 brand logo 또는 season cover를 업로드할 수 있음.
  - legacy prefix가 필요한 화면은 확인되지 않음.

### `chat-profile-snapshot-cache-refactor`

- 2026-07-04 구현 완료.
- `ChatProfileSyncManager`를 `NSLock` 기반 임시 cache에서 actor + MainActor snapshot 구조로 전환했다.
- `ChatProfileCacheActor`가 mutable cache, remote profile fetch, GRDB upsert를 소유한다.
- `ChatProfileSyncManager.profile(for:)`는 UI 동기 read용 MainActor snapshot만 읽고, snapshot miss 시 GRDB를 즉시 읽지 않는다.
- `reset()`과 진행 중인 refresh가 엇갈릴 때 오래된 결과가 snapshot/actor cache로 되살아나지 않도록 generation guard를 둔다.
- `ChatViewController`는 refresh 후 변경된 senderUID가 있으면 `ChatMessageWindowStore`의 현재 메시지 nickname/avatar snapshot을 갱신하고 해당 item을 reconfigure한다.
- 선택 이유:
  - UI render path에서 DB I/O를 제거해 동시 read/write 충돌 가능성을 줄인다.
  - 기존 `refreshProfiles(from:) -> Set<String>` 계약을 유지해 변경 범위를 좁힌다.
  - 설정 화면 참여자 목록은 remote members pagination source를 유지하고 profile snapshot을 전체 참여자 source로 공유하지 않는다.
- 보류한 대안:
  - snapshot miss 시 GRDB 즉시 read는 UI 동기 경로에 DB I/O가 남아 제외했다.
  - Combine/AsyncStream 기반 snapshot 변경 알림은 현재 반환 계약으로 충분해 도입하지 않았다.
- 검증:
  - `git diff --check` 통과.
  - `xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' test -only-testing:OutPickTests/ChatProfileSyncManagerTests` 통과.
  - `xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.

### Realtime DEBUG 로그 정리

- 2026-07-04 정리 완료.
- `RealtimeSocketService`에서 QA 중 추가했던 정상 흐름 반복 로그를 제거했다.
  - room session open requested/ready
  - incoming message publish
  - join room ACK success/failure DEBUG print
  - reconnect retry attempt/max-attempt DEBUG print
- `ChatViewController`에서 realtime message 수신마다 찍히던 DEBUG 로그와 전체 message dump 로그를 제거했다.
- 실패/예외 원인 파악에 필요한 오류 로그는 유지했다.
- 검증:
  - `git diff --check -- OutPick/Infra/Realtime/RealtimeSocketService.swift OutPick/Features/Chat/Controllers/ChatViewController.swift` 통과.
  - `xcodebuild -project OutPick.xcodeproj -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.

## 3. 아직 남은 작업

### `admin-web-brand-season-management`

- 상태: iOS 앱 내 관리자 계정 전용 Lookbook 관리 콘솔로 Phase 6B 구현과 운영 배포까지 완료. 수동 QA는 별도 수행 필요.
- 2026-07-06 방향 전환: 별도 Admin 웹 구현 phase는 iOS 앱 내 관리자 계정 전용 Lookbook 관리 콘솔 phase로 치환했다.
- 목적:
  - 브랜드/시즌 생성/import 기능을 일반 사용자 기능에서 분리하고 관리자 계정 전용 iOS 관리 콘솔로 재배치한다.
  - 기존 시즌 import Cloud Tasks/Cloud Run worker 흐름은 가능한 재사용하고, 호출 주체와 운영 UI를 앱 내 관리자 콘솔로 정리한다.
  - iOS 앱 내 운영자용 생성/import 진입점은 일반 사용자에게 비노출하고 관리자 계정에서만 접근하게 한다.
  - 총 관리자와 브랜드별 관리자를 구분한다.
  - 총 관리자는 `brandAdmins/{uid}.isActive == true`, 브랜드별 관리자는 `brands/{brandID}/admins/{uid}.role`로 판단한다.
  - `brandAdmins.roles`는 표시/감사용 선택 필드이며 권한 source로 사용하지 않는다.
  - `brands.ownerUIDs/adminUIDs`, `brandAdmins.canCreateBrands`, `brandAdmins.allowedBrandIDs`, `brandCreator`는 legacy로 보고 신규 권한 판단 source에서 제거한다.
  - 관리자 추가는 normalized email로 기존 `users.email`을 조회해 `brands/{brandID}/admins/{uid}`에 추가한다.
  - 브랜드 요청 일일 제한은 `brandRequestDailyCounters/{uid}/brandRequestDays/{yyyyMMdd}`로 관리하고, TTL field는 `expiresAt`으로 둔다.
  - spam 누적 제한은 `brandRequestUserLimits/{uid}`에 기록한다.
  - 브랜드 요청 운영 단계는 `requested`, `processing`, `completed`, `rejected`로 둔다.
  - `spam`은 운영 단계가 아니라 `rejectionReason = spam`으로 처리한다.
  - 사용자 요청 목록은 기본 `active`와 이전 요청 `history` scope로 나눈다.
  - 관리자 요청 목록은 기본 `요청됨(requested)`, `처리 중(processing)` 두 목록으로 표시한다.
  - 관리자 `완료(completed)`, `거절(rejected)` 필터는 최근 14일 처리 항목만 보여주고, 14일 이전 처리 항목은 `이전 처리 목록` 버튼으로 조회한다.
  - 2026-07-06 Phase 2 Functions, Firestore rules, Firestore indexes 운영 배포 완료.
  - 2026-07-06 `brandRequestDays.expiresAt` TTL policy 적용 완료. state는 `ACTIVE`.
- 완료한 phase:
  - Phase 2 브랜드 요청 데이터/API 기반 구현 및 운영 배포.
  - Phase 3 iOS 브랜드 검색/요청 UX 구현.
  - Phase 4 iOS 관리자 권한/진입점 정리 구현.
  - Phase 5A 관리자 브랜드 요청 group 큐 모델/API 구현.
  - Phase 5B iOS 관리자 요청 group 목록/상태 변경 구현.
  - Phase 6A 요청 group 완료 처리 + 브랜드 연결 구현.
  - Phase 6B iOS 관리자 추가/삭제, 브랜드 수정/로고 수정, import 관리 진입 정리 구현.
- Phase 6B 핵심 구현:
  - `updateBrand`, `addBrandManager`, `removeBrandManager` callable 추가.
  - `isFeatured` 변경은 총 관리자(`brandAdmins/{uid}.isActive == true`)만 허용.
  - 브랜드 owner/admin은 브랜드명, 공식 홈페이지 URL, 룩북 목록 URL, 로고 경로를 수정할 수 있다.
  - 총 관리자는 owner/admin을 추가/삭제할 수 있다.
  - 브랜드 owner는 해당 브랜드 admin만 추가/삭제할 수 있고 owner 추가/삭제는 할 수 없다.
  - 브랜드 admin은 관리자 추가/삭제 권한이 없다.
  - 관리자 추가/삭제는 normalized email로 `users.email`을 조회해 대상 UID를 찾는다.
  - 마지막 owner 삭제는 서버에서 차단한다.
  - Lookbook 관리 홈에 `브랜드 관리` 진입점 추가.
  - `AdminBrandManagementView`, `AdminBrandManagementViewModel`, `BrandManagement.swift` 추가.
  - `AdminBrandManagementView`는 `searchBrands`로 브랜드를 검색/선택한 뒤 브랜드 정보 저장, 로고 업로드, 관리자 추가/삭제, 시즌 추가, 가져오기 현황 진입을 제공한다.
  - 시즌 추가와 가져오기 현황은 기존 `SeasonAdditionSheetView`, `SeasonImportManagementView`를 재사용한다.
- Phase 6B 검증:
  - Functions `npm run lint` 통과.
  - Functions `npm run build` 통과.
  - `firebase deploy --only firestore:indexes --project outpick-664ae --dry-run --non-interactive` 통과.
  - XcodeBuildMCP `build_sim` 통과.
- Phase 6B 운영 배포:
  - 2026-07-06 `firebase deploy --only functions --project outpick-664ae --non-interactive` 성공.
  - 2026-07-06 신규 callable `listBrandRequestGroups`, `updateBrandRequestGroupStage`, `resolveBrandRequestGroup`, `updateBrand`, `addBrandManager`, `removeBrandManager` 생성 성공.
  - 2026-07-06 기존 callable/trigger는 같은 codebase 기준으로 업데이트 성공.
  - 2026-07-06 `firebase deploy --only firestore:rules --project outpick-664ae --non-interactive` 성공. 최신 rules와 같아 upload는 skip됐고 release 완료.
  - 2026-07-06 `firebase deploy --only firestore:indexes --project outpick-664ae --non-interactive` 성공.
  - indexes 배포 중 운영 프로젝트에 `firestore.indexes.json`에는 없는 field override 1개가 있다는 안내가 있었으나, `--force` 삭제가 필요한 항목이므로 삭제하지 않았다.
- Phase 7 전 권한 모델 리팩토링:
  - 총 관리자 source를 `brandAdmins/{uid}.isActive == true`로 정리했다.
  - 브랜드 owner/admin source를 `brands/{brandID}/admins/{uid}.role`로 전환했다.
  - `roles`는 표시/감사용 선택 필드로 두고 권한 판단 source에서 제외한다.
  - `canCreateBrands`, `brandCreator`, `allowedBrandIDs`, `brands.ownerUIDs/adminUIDs`는 legacy 권한 source로 보고 제거한다.
  - 총 관리자가 자동 owner로 들어간 브랜드는 owner로 마이그레이션하지 않는다.
  - 신규 브랜드 생성 시 owner/admin은 비어 있고, 관리자 콘솔에서 owner/admin 추가 시 `brands/{brandID}/admins/{uid}` 문서를 생성한다.
  - `createBrand`, `isFeatured`, 요청 group 관리, owner/admin 추가/삭제의 총 관리자 판정을 `isTotalAdmin`으로 통일했다.
  - iOS `BrandAdminSessionStore`를 `isTotalAdmin`, `ownedBrandIDs`, `adminBrandIDs`, `writableBrandIDs`로 분리했다.
  - Lookbook 관리 홈은 총 관리자에게 요청 목록/브랜드 추가/브랜드 관리를 보여주고, 브랜드별 관리자에게는 브랜드 관리만 보여준다.
  - 브랜드 관리 화면의 관리자 추가/삭제 섹션은 총 관리자 또는 해당 브랜드 owner에게만 보여준다.
  - 브랜드 admin은 브랜드 정보/로고/import 관리만 가능하고 관리자 추가/삭제 UI는 보이지 않는다.
  - iOS `BrandAdminSessionStore`는 `getBrandAdminCapabilities` callable 응답의 `ownedBrandIDs/adminBrandIDs`를 사용한다.
  - Firestore/Storage rules는 총 관리자 또는 `brands/{brandID}/admins/{uid}.role in ["owner", "admin"]` 기준으로 write/upload를 허용한다.
  - 운영 Firestore 마이그레이션 완료: 총 관리자 `kakao:3647141989`는 브랜드별 manager로 제외했고, legacy brand 배열 3건을 제거했으며, 기존 브랜드 admin 1건을 `brands/{brandID}/admins/{uid}`로 생성했다.
  - 운영 `brandAdmins/{uid}` legacy 필드 정리 완료: `allowedBrandIDs`, `canCreateBrands`, `brandCreator` 제거/정규화, `roles: ["totalAdmin"]` 유지.
  - 검증: Functions `npm run lint`, Functions `npm run build`, `firebase deploy --only firestore:rules,storage --dry-run`, `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`, `git diff --check` 통과.
  - 2026-07-07 `firebase deploy --only firestore:rules,storage --project outpick-664ae --non-interactive` 성공.
  - 2026-07-07 `firebase deploy --only functions --project outpick-664ae --non-interactive` 성공.
- 남은 작업:
  - 통합 수동 QA(Phase 6H + Phase 7): 권한 모델 전환 QA와 iOS 관리자 시즌 import 관리 QA를 한 번에 수행한다.
    - 총 관리자: 전체 브랜드 관리 가능, owner가 아니어도 브랜드 수정/로고 업로드/시즌 추가/import 관리/시즌·포스트·커버 업로드 가능, owner/admin 추가·삭제 가능.
    - 신규 브랜드 생성: 총 관리자 UID가 `brands/{brandID}/admins/{uid}`에 자동 등록되지 않는지 확인한다.
    - 브랜드 owner: 해당 브랜드 관리 가능, admin 추가·삭제 가능, owner 추가·삭제 불가.
    - 브랜드 admin: 해당 브랜드 정보/로고/import 관리 가능, 관리자 추가·삭제 UI/권한 없음.
    - 비관리자: 관리자 콘솔 진입, 브랜드 write, Storage upload가 막히는지 확인한다.
    - Phase 7 import 흐름: 시즌 import 관리 진입, URL import 요청, retry, candidate discovery, candidate 선택 import를 같은 브랜드에서 이어서 확인한다.
  - 2026-07-07 QA 중 `getBrandAdminCapabilities`가 `INTERNAL`을 반환하는 증상 확인.
    - 원인: `collectionGroup("admins").where("uid", "==", uid)` 쿼리에 필요한 `admins.uid` collection group single-field index 누락.
    - 조치: `firestore.indexes.json`에 `admins.uid` `COLLECTION_GROUP` ASC field override를 추가하고 배포했다.
    - 2026-07-07 `firebase deploy --only firestore:indexes --project outpick-664ae --non-interactive` 성공.
    - `admins.uid` collection group index state가 `READY`임을 확인했다.
    - `getBrandAdminCapabilities`는 총 관리자일 때 `brandAdmins/{uid}`만 보고 바로 반환하도록 조정해, 브랜드별 관리자 index 상태가 총 관리자 식별을 막지 않게 했다.
    - iOS `CloudFunctionsManager.getBrandAdminCapabilities`의 default region fallback은 제거했다. 이 callable은 `asia-northeast3` regional-only 함수라 fallback 시 `NOT FOUND`가 떠서 실제 원인을 흐렸다.
- 관리자 콘솔 UI 정리:
  - `LookbookAdminHomeView`의 `요청 목록`, `브랜드 추가`, `브랜드 관리` 메뉴는 더 큰 터치/시각 크기로 조정했다.
  - `AdminBrandRequestGroupsView`의 상태 변경 메뉴에서 `처리 시작`, `보류` 앞 system image를 제거했다.
  - 처리 시작/검수 후 완료 확인은 별도 sheet가 아니라 중앙 작은 확인창에서 `상태 변경`, 안내 문구, `취소`, `확인`만 보여준다. 취소 버튼은 destructive color로 둔다.
  - 보류 UI는 사유 선택이 필요하므로 sheet에서 `룩북 확인 불가`, `스팸`, `기타`를 선택한다. 선택 사유별 point color 배경을 사용하고, `기타` 선택 시 작은 admin note 입력창을 보여준다.
  - 보류 확정 시 `AdminBrandRequestGroupsViewModel.reject(_:reason:adminNote:)`가 `updateBrandRequestGroupStage`에 rejection reason과 admin note를 전달한다.
  - 처리 중 요청의 `브랜드 생성`과 `완료 처리`는 분리했다. 브랜드 생성 직후에는 `markBrandRequestGroupBrandCreated`가 `brandRequestNameIndex/{groupID}`에 `createdBrandID`, `brandCreatedAt`, `brandCreatedBy`를 저장한다. 처리중 row는 `상태 변경` 메뉴를 유지하고, `createdBrandID`가 있으면 앱 재실행 후에도 메뉴 안에 `브랜드 생성` 대신 `검수 후 완료 처리`를 보여준다.
  - `AdminBrandManagementViewModel`의 브랜드 정보 저장, 로고 저장, 관리자 추가/삭제, 중복 관리자 안내 메시지는 약 1초 후 자동으로 사라진다. 실패/입력 오류 메시지는 자동 dismiss 대상에서 제외한다.
  - 시즌 불러오기 결과 UI에서는 닫아도 작업이 계속된다는 별도 안내 문구를 제거했다.
  - 브랜드 생성/관리 모델은 `brands.name`과 `brands.englishName`을 함께 사용한다. `searchBrands`는 `normalizedName`/`normalizedEnglishName` 둘 다 prefix 검색하고, `brandNameIndex`는 한글명/영문명 중복을 함께 차단한다.
- 먼저 확인할 문서:
  - `docs/ai/ENTRYPOINTS.md`
  - `docs/ai/entrypoints/LOOKBOOK.md`: 브랜드 요청 화면, 관리자 콘솔 화면, iOS View/ViewModel/UseCase 진입점.
  - `docs/ai/entrypoints/FIREBASE.md`: callable Functions, Firestore rules, Storage rules, 배포/권한 진입점.
  - `docs/ai/DATA_SCHEMA.md`: `brandAdmins`, `brands/{brandID}/admins/{uid}`, 브랜드 요청 컬렉션 구조와 권한 source.
  - `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`: 시즌 import worker 구조와 Phase 7 import QA 기준.
  - `docs/ai/tasks/lookbook-import-worker/*`
  - `docs/ai/tasks/socket-cloud-run-deploy/design.md`
  - `docs/ai/tasks/socket-cloud-run-deploy/decisions.md`
- 주의:
  - 운영 Firestore 샘플 기준 `users.email`은 lowercased email로 저장된다. 기존 사용자 문서의 email 대소문자가 섞여 있으면 관리자 추가/삭제 조회 실패 가능성이 있다.
  - 관리자 기능이 앱 바이너리에 포함되므로 App Review Notes에 관리자 데모 계정 제공이 필요할 수 있다.

## 4. 수정한 파일 목록

- 최근 닫은 작업에서 중요한 파일:
  - `OutPick/DB/GRDB/GRDBManager.swift`
  - `OutPick/DB/Firebase/DatabaseManager/Protocols/FirebaseChatRoomRepositoryProtocol.swift`
  - `OutPick/DB/Firebase/DatabaseManager/Repositories/FirebaseChatRoomRepository.swift`
  - `OutPick/Features/Chat/Domain/UseCases/LoadChatRoomParticipantsUseCase.swift`
  - `OutPick/Features/Chat/Repositories/ChatRoomParticipantsRepository.swift`
  - `OutPick/Features/Chat/Managers/Implementations/ChatMessageManager.swift`
  - `OutPick/Features/Chat/Managers/Implementations/ChatProfileSyncManager.swift`
  - `OutPick/App/Session/JoinedRoomsSessionStore.swift`
  - `OutPick/Features/Chat/ChatContainer.swift`
  - `OutPick/Features/Chat/ChatCoordinator.swift`
  - `OutPick/Features/Chat/Domain/UseCases/RoomListUseCase.swift`
  - `OutPick/Features/Chat/ViewModels/JoinedRoomsViewModel.swift`
  - `OutPick/Features/Chat/ViewModels/RoomListsViewModel.swift`
  - `OutPickTests/GRDBManagerMigrationTests.swift`
  - `OutPickTests/ChatProfileSyncManagerTests.swift`
  - `OutPickTests/JoinedRoomsSessionStoreTests.swift`
  - `Socket/package-lock.json`
  - `Socket/README.md`
  - `Socket/src/firebaseAdmin.js`
  - `firebase.json`
  - `storage.rules`
  - `docs/ai/DATA_SCHEMA.md`
  - `docs/ai/ENTRYPOINTS.md`
  - `docs/ai/entrypoints/DATA.md`
  - `docs/ai/entrypoints/FIREBASE.md`
  - `docs/ai/entrypoints/CHAT.md`
  - `docs/ai/tasks/active.md`
  - `docs/ai/tasks/chat-member-profile-cache-boundary/*`
- working tree에는 앱/Socket/Firebase rules/문서 변경이 섞여 있다.
- 커밋 정리 전 `git status --short`와 `git diff --name-only`를 다시 확인해야 한다.

## 5. 중요한 아키텍처 결정

- membership source는 `Rooms/{roomID}/members/{uid}` 문서 존재 여부다.
- joined room projection은 최소 state만 담고 `lastMessage*`를 fan-out하지 않는다.
- 참여중 목록 정렬은 `Rooms` batch fetch 후 클라이언트 정렬로 처리한다.
- 방장 close cleanup은 job/state 문서 없이 즉시 성공/실패 응답으로 처리한다.
- 방장 destructive action의 최종 기준은 `Rooms.creatorUID`다.
- GRDB는 전체 room membership replica를 유지하지 않는다.
- `LocalChatUser`는 전역 profile display cache, `RoomProfileDisplayCache`는 최근 메시지 sender 표시용 bounded relation이다.
- 설정 화면 전체 참여자 목록은 remote members pagination만 source로 사용한다.
- GRDB `RoomMember` table/model/migration은 제거했다. local membership replica는 유지하지 않는다.
- `ChatProfileSyncManager`의 UI 동기 read는 MainActor snapshot만 사용하고, mutable cache/remote refresh/GRDB upsert는 actor가 소유한다.
- snapshot miss 시 GRDB 즉시 read는 허용하지 않는다.
- Socket audit는 운영 배포 성공을 우선 보존하기 위해 non-force 보수 업데이트만 적용했다.
- `firebase-admin@14.1.0`은 Node 22 조건은 맞지만 legacy namespace 제거로 Socket 코드 수정이 필요하고, 임시 lockfile 검토에서 `npm audit`가 8건에서 6건으로만 줄어 audit 0건 목표를 달성하지 못했다. 따라서 major upgrade 작업은 작업 목록에서 제거하고, 잔여 moderate audit은 upstream dependency 업데이트 대기 또는 npm overrides 별도 보안 리스크 검토로 분리한다.
- 운영 Storage rules는 과거 repo source of truth가 없고 전역 read/write 허용 상태였다.
- Storage rules는 기본 deny + path별 allow로 구성했고, `storage.rules`와 root `firebase.json`을 repo source of truth로 추가한 뒤 운영 배포까지 완료했다.
- 채팅방 밖 realtime 수신은 `BannerManager`가 banner 표시뿐 아니라 `ChatRoomReadStateStore`와 `FirebaseChatRoomRepository` local preview cache를 갱신해 목록 unread/마지막 메시지 summary를 즉시 반영한다.

## 6. 다시 확인해야 할 불확실한 부분

- `admin-web-brand-season-management`는 별도 Admin 웹이 아니라 iOS 관리자 콘솔 방향으로 전환했다.
- Admin 웹 위치/기술 스택 논의는 1차 범위에서 제외했다.
- 관리자 인증은 Firebase Auth 현재 사용자 + `brandAdmins/{uid}.isActive == true` 기준으로 확정했다.
- 브랜드별 관리자 권한은 `brands/{brandID}/admins/{uid}.role` 기준으로 확정했다.
- 관리자 추가는 normalized email로 기존 `users.email`을 조회해 `brands/{brandID}/admins/{uid}` 문서를 추가하는 방식으로 확정했다. 운영 Firestore 샘플 기준 `users.email`은 존재하고 `normalizedEmail`/`normalized_email`은 없다.
- 기존 Functions callable을 그대로 앱 관리자 콘솔에서 호출할지, 관리자 전용 API/Functions를 새로 둘지 재확인 필요.
- iOS 앱 내 브랜드/시즌 생성/import 진입점은 완전 제거가 아니라 관리자 전용 비노출/재사용 방향으로 확정했다.
- Storage rules 최소 권한 rules는 운영 배포했고 cross-service IAM도 부여했다. 참여자 chat image/video upload, 방장 room cover create/update/delete, 비참여 preview image/video read, profile avatar upload, lookbook brand logo/season cover upload는 성공 확인했다.
- Socket dependency audit의 남은 moderate 경고는 `firebase-admin@14.1.0`만으로 제거되지 않는다. upstream dependency 업데이트 또는 npm overrides는 별도 검토가 필요하다.
- GRDB schema cleanup은 TestFlight/App Store 배포 이력 없음과 개발 DB 초기화 가능 기준으로 진행했다.
- `chat-profile-snapshot-cache-refactor`는 자동 검증까지 완료했다. 별도 남은 설계 결정은 없다.
- Realtime DEBUG 로그 정리는 정상 흐름 반복 로그 제거 기준으로 완료했다. 실패/예외 로그는 유지했다.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. `git status --short`와 `git diff --name-only`로 현재 working tree를 재확인한다.
2. `admin-web-brand-season-management`의 iOS 관리자 콘솔 방향 문서를 기준으로 구현 전 코드 진입점을 재확인한다.
3. 먼저 관련 문서와 진입점 문서를 읽고 요구사항/구현 디테일/제약/완료 기준/사용자 흐름/화면/API/데이터/아키텍처 쟁점을 정리한다.
4. 모호한 항목이 생기면 사용자에게 질문한다.
5. 사용자 승인 전까지 코드 수정은 하지 않는다.
