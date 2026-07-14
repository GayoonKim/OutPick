# Firestore Document ID Boundary Cleanup Decisions

## D1. 문서 경로 ID가 canonical source다

- 선택: `DocumentSnapshot.documentID`만 자기 문서의 기본 identity로 사용한다.
- 이유: 저장 필드와 wrapper를 함께 사용하면 source 충돌과 write 경계 오해가 생긴다.
- 보류한 대안: `@DocumentID`를 read-only로 유지하는 최소 수정은 SDK 결합과 collision 위험을 남겨 선택하지 않았다.

## D2. 앱의 `@DocumentID`를 모두 제거한다

- 선택: Lookbook 14개 DTO와 ChatRoom 1개에서 wrapper를 제거한다.
- 이유: Repository가 이미 snapshot을 소유하므로 경로 ID를 명시적으로 전달하는 편이 테스트와 책임 경계가 선명하다.

## D3. ChatRoom ID는 `id: String`이다

- 선택: non-optional `String`을 사용한다.
- 이유: persisted/created room은 ID 없는 상태가 유효하지 않으며 `?? ""` 경로 fallback을 제거할 수 있다.
- 보류한 대안: `ChatRoomID` 값 타입은 Chat 전체 ID 강타입화 없이 단독 도입하면 변환 비용과 비대칭이 커 이번 범위에서 제외했다.

## D4. Chat 핵심 불변식만 엄격하게 검증한다

- 필수: 비어 있지 않은 경로 ID, roomName, creatorUID, createdAt.
- 호환 기본값: description, participantUIDs, memberCount, seq, isClosed와 optional media/message/announcement 필드.
- 존재하는 필드의 타입이 잘못되면 decode 실패로 처리한다.

## D5. 채팅방 생성은 단일 transaction이다

- 선택: room, owner member, joined projection을 한 transaction으로 생성하고 Repository가 생성된 ChatRoom을 반환한다.
- 이유: 현재 두 단계 저장의 부분 성공과 고아 방 위험을 제거한다.

## D6. rules에서도 중복 ID를 차단한다

- 선택: create payload의 `ID`/`id` 존재를 거부하고 update에서는 해당 key의 affected change를 거부한다.
- 이유: 앱 mapper뿐 아니라 데이터 계층에서도 canonical ID 불변식을 보장한다.
- 제약: 기존 4건의 `ID`는 변경하지 않는 일반 metadata update를 막지 않아야 한다.

## D7. 운영 cleanup은 마지막 별도 gate다

- 선택: 코드·테스트·rules 검증 후 기존 `Rooms.ID` 4건 삭제를 다시 승인받는다.
- 이유: 데이터 필드 삭제는 구현 승인과 분리한 명시적 운영 mutation이다.

## D8. Season write 계약은 자동 테스트로 완료 판정한다

- 선택: `SeasonWriteDTO`의 payload 자동 테스트를 이번 task의 Season write 완료 근거로 사용한다.
- 이유: `CreateSeasonView`와 `CreateSeasonViewModel` 구현은 남아 있지만 production 조립·표시 호출부가 없고, 현재 관리자 URL 후보 import는 다른 API·worker 흐름이다.
- 범위: 임시 debug/Admin write로 수동 QA를 대체하지 않는다. 직접 시즌 생성 진입점 복원 또는 미사용 코드 제거는 별도 후속 후보로 분리한다.
