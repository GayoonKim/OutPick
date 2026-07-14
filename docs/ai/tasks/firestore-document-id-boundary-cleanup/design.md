# Firestore Document ID Boundary Cleanup Design

## 핵심 문제

Firestore 문서 경로 ID, 저장 payload의 중복 `ID`/`id`, Swift `@DocumentID` wrapper가 동시에 문서 identity의 source 역할을 한다. 이 구조는 `I-FST000002` 경고, read/write DTO 결합, optional·빈 문자열 ID 전파를 만든다.

## 목표

- Firestore `DocumentSnapshot.documentID`를 문서 identity의 canonical source로 사용한다.
- 자기 문서의 기본키 `ID`/`id`를 저장 payload에 포함하지 않는다.
- Repository가 문서 경로 ID를 DTO→Domain mapper에 명시적으로 전달한다.
- 앱 소스의 `@DocumentID` 사용을 제거한다.
- Chat Domain model에서 Firebase/Codable/write mapping 책임을 제거한다.
- Chat 방 생성과 owner membership projection을 하나의 transaction으로 저장한다.
- Firestore rules에서도 `Rooms.ID`/`Rooms.id` 재유입을 차단한다.

## 범위

- Lookbook Firestore DTO 14개와 관련 Repository mapping
- Season read DTO와 write DTO 분리
- ChatRoom Domain/Firestore DTO와 mapper 분리
- `ChatRoom.id: String` non-optional 전환
- 채팅방 생성 transaction과 현재 rules 계약 검증
- Firestore emulator rules test harness
- 승인 후 운영 `Rooms.ID` 필드 cleanup

## 범위 제외

- `brandID`, `seasonID`, `postID`, `commentID` 같은 부모·컨텍스트 ID
- `ChatMessage.ID`와 Socket message ID
- Chat 전체 ID 값 타입화
- FirebaseChatRoomRepositoryProtocol 전체의 Firestore SDK 노출 제거
- membership 모델 재설계
- Functions/Socket 변경

## 완료 기준

- `rg '@DocumentID' OutPick` 결과가 0이다.
- 모든 Firestore 기본 Domain ID가 문서 경로 ID에서 생성된다.
- Chat/Season write payload에 자기 문서의 `ID`/`id`가 없다.
- `ChatRoom`이 Firebase를 import하거나 Codable에 의존하지 않는다.
- 새 방의 room/member/joined projection이 단일 transaction으로 생성된다.
- rules가 `Rooms`의 `ID`/`id` 신규 쓰기를 차단한다.
- targeted test, Firestore emulator rules test와 generic Simulator build가 통과한다.
- 실제 운영 rules 배포와 데이터 cleanup은 각각 별도 사용자 승인을 받는다.
