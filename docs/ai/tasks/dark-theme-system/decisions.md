# Dark Theme System Decisions

## 목적

다크 테마 시스템 작업에서 확정한 결정의 인덱스다. 결정의 이유, 대안, 트레이드오프, 재검토 조건은 `decisions/theme-system.md`에서 확인한다.

## 읽는 순서

- 최종 설계 요약: `design.md`
- 결정 상세: `decisions/theme-system.md`
- 현재 진행 상태와 검증 요약: `progress.md`
- 완료 상세 기록: `progress/completed.md`
- phase 지도: `plan.md`
- 장기 공유 결정: `../../ADR.md`의 ADR-010

## 결정 지도

상세: `decisions/theme-system.md`

- D-001: 앱은 다크 모드 전용으로 전환한다.
- D-002: 브랜드 포인트 색은 Volt Green `#7FDB1E` 한 가지로 제한한다.
- D-003: 의미색은 포인트 색 예외로 허용한다.
- D-004: 무채색은 역할 기반 토큰으로 정의한다.
- D-005: 룩북 이미지는 Neutral Frame 중심으로 처리한다.
- D-006: 채팅 말풍선은 무채색 위계로 정리한다.
- D-007: 접근성은 최소 WCAG AA 수준을 목표로 한다.
- D-008: Phase 4 룩북 화면군은 4A/4B/4C로 나눈다.
- D-009: 의미색도 테마 토큰으로 관리한다.
- D-010: 전체 화면 이미지 preview의 검정 배경은 의도된 예외로 둔다.
- D-011: 룩북 생성 플로우의 베이지/크림 계열은 제거한다.
- D-012: 상호작용 가능한 일반 버튼은 포인트 색을 기본으로 사용한다.

## 참조 원칙

- 다크 테마 내부 결정은 이 task 문서를 기준으로 확인한다.
- 여러 기능에 반복 적용될 장기 결정은 `docs/ai/ADR.md`로 승격한다.
