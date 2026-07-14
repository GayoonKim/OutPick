# ADR-020: Firestore 문서 identity는 문서 경로 ID를 단일 기준으로 사용한다

## 상태

accepted

## 결정

- 자기 문서의 기본 identity는 `DocumentSnapshot.documentID`만 사용한다.
- 저장 payload에 같은 값을 `ID`/`id`로 중복 저장하지 않는다.
- Repository가 경로 ID를 read DTO→Domain mapper에 명시적으로 전달한다.
- read DTO와 write payload를 분리하고 앱의 `@DocumentID` 사용을 제거한다.
- `Rooms`는 Firestore rules에서도 `ID`/`id` 신규 쓰기를 차단한다.
- 부모·컨텍스트 ID와 query projection용 ID 필드는 이 결정의 중복 기본키로 보지 않는다.

## 이유

- 경로 ID, 저장 필드와 wrapper가 동시에 source가 되면 불일치 우선순위가 생긴다.
- `@DocumentID`는 write에서 제외되지만 non-nil 초기화와 동일 이름 저장 필드 충돌 제약이 있어 read/write 겸용 모델에 부적합하다.
- snapshot을 소유한 Repository에서 경로 ID를 주입하면 Domain과 SDK 경계가 명확하고 단위 테스트가 결정적이다.

## 트레이드오프

- DTO mapper와 Repository 호출부가 명시적 인자를 추가로 전달한다.
- ChatRoom의 optional `ID`를 non-optional `id`로 바꾸는 Phase에서는 사용처 변경량이 크다.
- rules 강화는 별도 emulator 검증과 운영 배포 승인이 필요하다.

## 보류한 대안

- `@DocumentID`를 read-only로 유지하는 최소 수정은 SDK 결합과 collision 위험을 남겨 선택하지 않았다.
- 모든 ID를 값 타입으로 전환하는 방식은 이번 경계 정리보다 범위가 커 별도 Chat 강타입화 작업으로 보류했다.

## 재검토 조건

- Firestore 외 저장소가 같은 Domain entity의 identity를 생성해야 할 때.
- offline/local-first identity 생성 정책이 필요해질 때.
- Chat 전체 ID를 일관된 값 타입으로 전환할 때.
