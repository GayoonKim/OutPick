# Firestore Document ID Boundary Cleanup Progress

## 현재 상태

- 2026-07-14 설계 결정 D1~D8 사용자 승인 완료.
- task/phase 하네스 생성과 Phase 1 구현 진행 승인 완료.
- Phase 1~4 구현·자동·수동 검증과 하네스 최종화를 완료했다.
- Phase 4의 정적 검사, Firestore Emulator 11개 테스트, rules dry-run, generic Simulator build와 test target 전체 build-for-testing이 통과했다.
- iOS targeted runtime test 59개와 실제 Firebase 수동 QA를 완료했다.
- 시즌 write는 `SeasonWriteDTO` 자동 테스트로 완료 판정했다. production 진입점이 없는 직접 생성 UI의 복원 또는 미사용 코드 제거는 별도 후속 후보다.
- Firestore rules 운영 배포와 운영 `Rooms.ID` 4건 cleanup·사후 재감사까지 완료해 현재 task를 종료했다.

## Phase 1 완료

- Lookbook DTO 14개의 `@DocumentID`를 제거하고 read DTO를 `Decodable`로 제한했다.
- 기본 identity가 필요한 10개 mapper가 `documentID`를 명시적으로 받도록 변경했다.
- 14개 Firestore Repository가 snapshot과 DTO의 연관을 유지하며 경로 ID를 Domain mapper에 전달한다.
- `SeasonWriteDTO`를 분리해 Season 생성 payload에서 자기 문서 ID를 제거했다.
- `FirestoreDocumentIDBoundaryTests` 3개가 통과했다.
- generic iOS Simulator build가 성공했다. 출력된 경고는 기존 Chat actor isolation/deprecated API/link search path 항목이며 Phase 1 신규 warning은 확인되지 않았다.

## Phase 2 완료

- `ChatRoom.id: String`을 non-optional identity로 전환하고 Domain에서 Firebase import, Codable, `@DocumentID`, write dictionary를 제거했다.
- `ChatRoomFirestoreDTO`와 `ChatRoomFirestoreMapper`를 추가해 경로 document ID를 canonical identity로 주입한다.
- read mapper는 document ID, 방 이름, 생성자 UID, 생성일을 핵심 불변식으로 검증하고 나머지 필드는 legacy 기본값을 허용한다.
- `CreateRoomRepositoryProtocol`로 생성 UseCase의 최소 계약을 분리하고, Firestore document ID 생성 책임을 Repository로 이동했다.
- 방 문서, owner member 문서, joinedRooms projection을 하나의 Firestore transaction에서 생성하며 room payload에서 `ID`, `id`, `participantUIDs`를 제외한다.
- Mapper 5개와 CreateRoomUseCase 3개 테스트, 영향 Chat/Lookbook 테스트가 통과했고 test target 전체가 build-for-testing에 성공했다.
- generic iOS Simulator build가 성공했다. 현재 rules의 `existsAfter/getAfter` 계약과 transaction payload는 정적으로 호환됨을 확인했으며 실제 rules 허용/거부는 Phase 3 emulator test에서 검증한다.

## Phase 3 완료

- `Rooms` create에서 `ID`/`id` 키가 존재하면 거부하고 update에서는 두 필드의 추가·변경·삭제를 거부하도록 rules를 강화했다.
- 기존 legacy `ID`/`id` 값이 그대로인 metadata update는 허용한다.
- `firebase.json`에 Firestore Emulator 8080 포트와 UI 비활성 설정을 추가했다.
- `firestore-tests/`에 Node test 기반 rules 테스트 하네스를 추가했다.
- 정상 owner room/member/joinedRooms transaction, 비인증·creator/member/projection 오류의 원자 실패, create/update ID 차단과 legacy metadata update를 포함한 11개 테스트가 통과했다.
- Firebase CLI `firestore:rules --dry-run` 컴파일이 성공했다. 운영 rules는 배포하지 않았다.
- Emulator 실행용 OpenJDK 21을 Homebrew로 설치했다. 설치 중 기존 Node 22.5.1의 ICU 연결이 깨져 Node 22.23.1로 같은 메이저 범위에서 복구했고 `node`/`npm` 명령 정상 동작을 확인했다.

## 조사 완료

- Firebase iOS SDK 12.3.0의 `@DocumentID` encode/decode와 non-nil 초기화 계약 확인.
- 앱 `@DocumentID` 15개 inventory 완료: Chat 1개, Lookbook 14개.
- iOS write에서 non-nil wrapper를 만드는 경계는 ChatRoom과 SeasonDTO로 확인.
- Functions, Socket, rules/index query가 저장된 primary `ID`/`id`에 의존하지 않음을 확인.
- 운영 read-only audit에서 Rooms 4건의 `ID`가 경로 ID와 일치하고 Lookbook 확인 대상에는 primary `ID`/`id`가 없음을 확인.

## Phase 4 완료

- `rg '@DocumentID' OutPick` 결과가 0개임을 다시 확인했다.
- ChatRoom 직접 decode/write와 Season payload의 `ID`/`id` 재유입 흔적이 없음을 정적으로 재확인했다. 검색된 ChatMessage의 `ID`는 방 문서 identity가 아닌 별도 메시지 계약이다.
- Firestore Emulator의 room/member/joinedRooms 원자 transaction과 `ID`/`id` 차단 11개 테스트가 다시 통과했다.
- Firebase CLI `firestore:rules --dry-run` 컴파일이 다시 성공했다. 운영 rules는 배포하지 않았다.
- generic iOS Simulator build와 test target 전체 build-for-testing이 성공했다.
- 기존 linker search path와 App Intents metadata 경고는 남아 있으나 이번 경계 변경의 신규 compile error는 없다.
- iOS 26.2 iPhone 17 Pro Max Simulator에서 ID 경계와 영향 범위 targeted test 59개가 통과했다.
- 로그인 앱에서 전체 방·검색·참여중 목록, 기존 방 진입, legacy room metadata 수정·원복을 확인했다.
- 이미지 없는 방과 이미지 있는 방을 생성했다. 이미지 방의 Firestore `thumbPath`/`originalPath` patch와 Storage 객체를 확인했다.
- QA 방 2개는 방장 종료로 정리했고 Firestore 문서와 이미지 Storage 객체가 남지 않았다.
- 브랜드·시즌·포스트·댓글 read와 전체 로그의 `I-FST000002` 0건을 확인했다.
- 운영 read-only 재감사에서 Rooms 4건의 legacy `ID`가 모두 경로 ID와 일치하고 소문자 `id`와 불일치는 0건이었다.
- `CreateSeasonView`/`CreateSeasonViewModel` 코드는 있으나 이를 생성하는 production 호출부가 0개라 시즌 직접 생성 수동 QA는 수행할 수 없었다.
- 사용자 승인 D8에 따라 Season write 계약은 `SeasonWriteDTO` 자동 테스트로 완료 판정했다. 임시 진입점이나 Admin write는 만들지 않았고 직접 생성 UI 처리는 별도 후속 후보로 분리했다.
- 2026-07-14 Firestore Emulator 계약 테스트 11개와 rules dry-run을 다시 통과한 뒤 `outpick-664ae`에 `firestore.rules`를 운영 배포했다.
- cleanup 직전 운영 Rooms 4건 모두 `ID == documentID`, lowercase `id` 0건임을 다시 확인했다.
- 같은 transaction에서 4개 문서의 uppercase `ID` 필드만 삭제했다. 사후 감사에서 방 4개 유지, `ID`/`id` 보유 0건, roomName/creatorUID/createdAt 누락 0건을 확인했다.
- 로그인 Simulator 앱을 재실행해 오픈채팅 방 4개가 정상 표시되고 `I-FST000002`, permission/decode/mapping 오류가 0건임을 확인했다.
- `ENTRYPOINTS.md`, `CHAT.md`, `LOOKBOOK.md`, `DATA.md`, `FIREBASE.md`, `TESTS.md`, `DATA_SCHEMA.md`, `active.md`, `HANDOFF.md`를 코드·데이터·rules·검증 진입점 기준으로 최종 최신화했다.

## 별도 후속 후보

1. 시즌 직접 생성 진입점 복원 또는 미사용 코드 제거를 별도 설계한다.
