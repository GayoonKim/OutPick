# Phase 4. Integration, Documentation, and Cleanup Gate

## 상태

- 완료. 자동·수동 QA와 하네스 최종화를 마쳤다.
- rules 운영 배포와 `Rooms.ID` 4건 cleanup·사후 재감사를 2026-07-14 각각 별도 승인 후 완료했다.

## 목표

- 전체 정적·자동·수동 회귀를 통합 검증한다.
- ENTRYPOINTS, DATA_SCHEMA, ADR, task와 HANDOFF를 최신화한다.
- rules 배포와 운영 데이터 cleanup을 별도 승인 gate로 제시한다.

## 완료 기준

- 앱 `@DocumentID`가 0개다.
- targeted tests, emulator tests와 generic Simulator build가 통과한다.
- 승인된 수동 QA 결과가 기록된다.
- rules 운영 배포와 `Rooms.ID` cleanup은 명시 승인 전 실행하지 않는다.

## 중단 조건

- 경로 ID와 저장 ID 불일치 발견.
- 기존 방 decode 회귀.
- rules가 정상 metadata update 또는 membership transaction을 거부.
- Season write payload schema 변화.

## 승인된 QA 예외

- `CreateSeasonView`와 `CreateSeasonViewModel` 구현은 존재하지만 production 조립·표시 호출부가 없다.
- 현재 관리자 UI의 시즌 기능은 URL 후보 import이며 직접 생성과 다른 API·worker 흐름이다.
- 따라서 시즌 직접 생성 수동 QA를 임의의 import 실행이나 Admin SDK write로 대체하지 않는다.
- 사용자 승인 D8에 따라 `SeasonWriteDTO` 자동 테스트를 write 계약의 완료 근거로 사용하고, 직접 생성 진입점 복원 또는 미사용 코드 제거는 별도 후속 후보로 분리한다.
