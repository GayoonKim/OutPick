# Validation Proposals

## D7. Socket에 최소 자동 계약 테스트를 추가한다

상태: 확정 — 2026-07-13 사용자 승인

추천 결정:

- 새 외부 test framework 없이 Node built-in node:test를 우선 사용한다.
- handler를 dependency injection 가능한 factory로 만들고 fake socket/io/db로 검증한다.
- Socket/package.json에 test 명령을 추가한다.

우선 시나리오:

- 인증 실패 시 connection 거절.
- room join/leave ACK 계약.
- message validation 실패 ACK.
- media preflight/finalize idempotency.
- handler 등록 이벤트 이름.
- graceful shutdown과 readyz 상태 전이.

이유:

- Socket event와 ACK 회귀는 syntax check만으로 잡을 수 없다.
- 실제 Cloud Run smoke QA만으로 실패/중복/race 분기를 반복 재현하기 어렵다.

트레이드오프:

- fake socket과 handler factory 설계 비용이 추가된다.
- 실제 Socket.IO transport 통합 동작은 별도 smoke QA가 필요하다.

대안:

- npm run check와 수동 QA만 유지하면 초기 비용은 낮지만 구조 분리 중 event contract 회귀 방지가 약하다.
