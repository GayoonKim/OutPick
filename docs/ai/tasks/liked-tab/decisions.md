# Liked Tab Decisions

## 목적

좋아요 탭 작업에서 확정한 결정의 인덱스다. 결정 이유, 대안, 트레이드오프, 재검토 조건은 `decisions/liked-tab.md`에서 확인한다.

## 읽는 순서

- 현재 상태와 남은 작업: `progress.md`
- 완료 상세 기록: `progress/completed.md`
- phase 지도: `plan.md`
- 결정 상세: `decisions/liked-tab.md`

## 결정 지도

상세: `decisions/liked-tab.md`

- D-001: 좋아요 탭 이름은 `Liked`로 일반화한다.
- D-002: 좋아요 탭은 섹션별 상태로 분리한다.
- D-003: 시즌 좋아요 목록은 user state 기준으로 조회하고 최신 Season 문서를 합성한다.
- D-004: 시즌 좋아요 변경은 Repository/UseCase 경계를 통해 처리한다.
- D-005: 중복 로드 방지는 `@MainActor struct AsyncLoadGate`로 정리한다.
- D-006: 원격에만 남은 `updateBrandLogoDetailPath` 함수는 삭제하지 않는다.
- D-007: 좋아요 포스트 목록은 2열 grid와 기존 PostDetail push를 사용한다.
- D-008: 좋아요 취소는 카드 메뉴에서 optimistic remove 후 실패 시 복구한다.
- D-009: 좋아요 탭 진입은 앱 실행 중 캐시를 우선하고 pull-to-refresh로 서버 최신화한다.
