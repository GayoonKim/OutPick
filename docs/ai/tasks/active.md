# Active Task

## 현재 상태

- 현재 다음 핵심 task는 `admin-web-brand-season-management`다.
- 2026-07-06 기준 이 task의 구현 방향은 별도 Admin 웹이 아니라 iOS 앱 내 관리자 계정 전용 Lookbook 관리 콘솔로 전환했다.
- Phase 6B iOS 관리자 추가/삭제, 브랜드 수정/로고 수정, import 관리 진입 정리까지 구현했다.
- 2026-07-06 기준, 별도 Admin 웹 구현 phase는 iOS 관리자 화면 phase로 치환했다.
- 아래 핵심 작업은 완료/마감 처리했다.
  - `chat-legacy-identity-naming`
  - `chat-membership-model-transition` 핵심 구현 및 운영 배포
  - 운영 smoke QA 기반 legacy cleanup/index 배포 결정 및 실행
  - `chat-member-profile-cache-boundary` Phase 1~4
  - `grdb-schema-cleanup`
  - `chat-membership-model-transition` destructive 수동 QA
  - `Socket dependency audit` 보수 업데이트
  - `Storage rules/preview 권한 확인` read-only 운영 상태 점검
  - `Storage rules 최소 권한 설계/적용` 운영 배포와 핵심 chat upload QA
  - `chat-profile-snapshot-cache-refactor`
  - Realtime DEBUG 로그 정리

## 완료한 핵심 작업

### 1. `chat-legacy-identity-naming`

- canonical user ID 기준 명명을 `userID`로 정리했다.
- `LocalChatUser.userID`, `RoomMember.userID` 등 Swift/API/GRDB 물리 schema를 canonical UID 의미로 맞췄다.
- legacy `userProfile`/`roomParticipant` runtime fallback은 제거했다.
- 최종 검증:
  - forbidden pattern 재검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

### 2. `chat-membership-model-transition`

- membership authoritative source를 `Rooms/{roomID}/members/{uid}`로 전환했다.
- 참여중 목록 source를 `users/{uid}/joinedRooms/{roomID}` projection + `Rooms` batch fetch + 클라이언트 정렬로 전환했다.
- Socket room access, push fanout, 방장 close cleanup, Firestore rules, Functions cleanup 경계를 새 membership 모델에 맞췄다.
- 운영 배포:
  - Socket Cloud Run `outpick-socket` revision `outpick-socket-00004-76z` 100% traffic 배포 완료
  - `firebase deploy --only firestore:rules --project outpick-664ae` 완료
  - `firebase deploy --only functions --project outpick-664ae` 완료
  - `firebase deploy --only firestore:indexes --project outpick-664ae --force` 완료
- 운영 legacy field count는 0으로 확인했다.

### 3. `chat-member-profile-cache-boundary`

- Phase 1:
  - `RoomProfileDisplayCache(roomID, userID)` GRDB schema/API/migration 추가
  - room당 20명 LRU eviction 구현
  - room cleanup과 orphan `LocalChatUser` prune 기준 반영
- Phase 2:
  - 메시지 저장 경로가 `LocalChatUser` + `RoomProfileDisplayCache`만 갱신하도록 전환
  - 메시지 경로의 local `RoomMember` write 제거
- Phase 3:
  - 설정 참여자 목록 source를 remote `Rooms/{roomID}/members` pagination으로 전환
  - 전체 members fetch + local `RoomMember` reconcile 제거
- Phase 4:
  - production 경계의 local membership replica API 제거
  - `RoomMember` table/model/migration은 migration chain 호환 흔적으로만 유지
  - `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/CHAT.md` 갱신
- 최종 검증:
  - forbidden pattern 검색 통과
  - `git diff --check` 통과
  - iOS generic simulator build 통과
  - `GRDBManagerMigrationTests` 통과

## 남은 작업 목록

### 1. `admin-web-brand-season-management`

- 목적:
  - 브랜드/시즌 생성/import 기능을 일반 사용자 기능에서 분리하고, iOS 앱 내 관리자 계정 전용 Lookbook 관리 콘솔로 재배치한다.
  - 기존 시즌 import Cloud Tasks/Cloud Run worker 흐름은 가능한 재사용하고, 호출 주체와 운영 UI를 관리자 콘솔로 정리한다.
  - iOS 앱 내 운영자용 생성/import 진입점은 일반 사용자에게 비노출하고, 관리자 계정에서만 접근하게 한다.
  - 총 관리자와 브랜드별 관리자를 구분한다.
  - 총 관리자는 `brandAdmins/{uid}` 문서 존재 여부, 브랜드별 관리자는 `brands.ownerUIDs/adminUIDs` 포함 여부로 판단한다.
  - 관리자 추가는 normalized email로 기존 `users.email`을 조회해 브랜드 owner/admin에 추가하는 방식으로 시작한다.
  - 브랜드 요청 일일 제한은 `brandRequestDailyCounters/{uid}/brandRequestDays/{yyyyMMdd}`로 관리하고, TTL field는 `expiresAt`으로 둔다.
  - spam 누적 제한은 `brandRequestUserLimits/{uid}`에 기록한다.
  - 브랜드 요청 운영 단계는 `requested`, `processing`, `completed`, `rejected`로 둔다.
  - `spam`은 운영 단계가 아니라 `rejectionReason = spam`으로 처리한다.
  - 사용자 요청 목록은 기본 `active`와 이전 요청 `history` scope로 나눈다.
- 완료한 현재 phase:
  - Phase 2 브랜드 요청 데이터/API 기반 구현 및 운영 배포.
  - Phase 3 iOS 브랜드 검색/요청 UX 구현.
  - Phase 4 iOS 관리자 권한/진입점 정리 구현.
  - Phase 5A 관리자 브랜드 요청 group 큐 모델/API 구현.
  - Phase 5B iOS 관리자 요청 group 목록/상태 변경 구현.
  - Phase 6A 요청 group 완료 처리 + 브랜드 연결 구현.
  - Phase 6B iOS 관리자 추가/삭제, 브랜드 수정/로고 수정, import 관리 진입 정리 구현.
- Phase 6B 검증:
  - Functions `npm run lint` 통과.
  - Functions `npm run build` 통과.
  - `firebase deploy --only firestore:indexes --project outpick-664ae --dry-run --non-interactive` 통과.
  - XcodeBuildMCP `build_sim` 통과.
- Phase 6B 운영 배포:
  - 2026-07-06 Functions 배포 완료.
  - 2026-07-06 Firestore rules 배포 완료.
  - 2026-07-06 Firestore indexes 배포 완료.
- Phase 7 전 권한 모델 리팩토링:
  - 총 관리자는 `brandAdmins/{uid}.isActive == true` 기준으로 정리.
  - 브랜드 owner/admin은 `brands.ownerUIDs/adminUIDs` 기준으로 유지.
  - `canCreateBrands`, `brandCreator`, `allowedBrandIDs`는 권한 판단 source에서 제외.
  - iOS 관리자 콘솔 노출을 총 관리자와 브랜드별 관리자 역할에 맞게 분리.
  - Functions lint/build, XcodeBuildMCP build 통과.
  - 2026-07-06 Functions 운영 배포 완료.
- 먼저 확인할 문서:
  - `docs/ai/ENTRYPOINTS.md`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/entrypoints/FIREBASE.md`
  - `docs/ai/DATA_SCHEMA.md`
  - `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`
  - `docs/ai/tasks/lookbook-import-worker/*`
  - `docs/ai/tasks/socket-cloud-run-deploy/design.md`
  - `docs/ai/tasks/socket-cloud-run-deploy/decisions.md`
- 다음 구현 전 확인:
  - Phase 6B 수동 QA 계정/데이터 준비 여부.
  - Phase 7 iOS 관리자 시즌 import 관리의 상세 QA/개선 범위.
- 권장 검증:
  - 설계 하네스 완료 후 phase별로 별도 확정
  - Functions 변경 시 lint/build
  - Firestore/Storage rules 변경 시 dry-run
  - iOS 변경 시 generic simulator build
  - 관리자/비관리자 계정 수동 QA

## 다음 추천 순서

1. 총 관리자/owner/admin/비관리자 권한별 Phase 6B 수동 QA
2. Phase 7 시즌 import 관리 상세 QA/개선 범위 확정
3. App Review Notes용 관리자 데모 계정/설명 준비 여부 결정
