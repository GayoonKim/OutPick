# Phase 2. Chat Domain and Firestore Boundary

## 상태

- 구현 완료.
- Chat mapper 5개, CreateRoomUseCase 3개와 영향 회귀 테스트 통과.
- test target build-for-testing 및 generic iOS Simulator build 통과.
- 실제 Firestore rules transaction 검증은 Phase 3 emulator gate로 유지.

## 목표

- `ChatRoom.id: String` non-optional 전환.
- ChatRoom Domain에서 Firebase/Codable/write mapping 제거.
- read DTO와 write mapper 분리.
- room/member/joined projection 단일 transaction 생성.

## 완료 기준

- ChatRoom이 Firebase를 import하지 않는다.
- UseCase가 Firestore ID 생성기를 알지 않는다.
- room write payload에 `ID`, `id`, `participantUIDs`가 없다.
- 부분 성공 없는 원자 생성 계약을 갖는다.

## 검증

- Chat mapper tests.
- CreateRoomUseCase fake repository tests.
- 영향받은 Chat targeted tests.
- generic Simulator build.

## 논의 필요 사항

- 없음. 사용자 승인 완료.
