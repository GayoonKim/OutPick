# Liked Tab Plan

## 목적

좋아요 탭 작업의 phase 지도와 완료 기준 인덱스다.

현재 상태는 `progress.md`, 상세 완료 기록은 `progress/completed.md`, 결정 이유는 `decisions/liked-tab.md`를 본다.

## Phase 지도

| Phase | 목표 | 상태 |
| --- | --- | --- |
| Phase 1 | 현재 상태 재확인 | 완료 |
| Phase 2 | 좋아요 탭 섹션별 상태 분리 | 완료 |
| Phase 3 | `AsyncLoadGate` 도입 | 완료 |
| Phase 4 | 좋아요 포스트 목록 연결 | 완료 |
| Phase 5 | 수동 QA와 커밋 정리 | 일부 완료, 일부 남음 |

## 완료 기준

- 좋아요 탭은 `LikedView`/`LikedViewModel` 이름으로 브랜드/시즌/포스트를 포괄한다.
- 브랜드/시즌/포스트 섹션은 독립 상태를 갖는다.
- 한 섹션 실패가 다른 섹션 성공을 막지 않는다.
- 화면 최초 로드, 재진입 refresh, pull-to-refresh 중복 실행 방지는 `AsyncLoadGate`로 정리한다.
- 좋아요 포스트 목록은 2열 grid로 표시하고 기존 `PostDetailView`로 push한다.
- 브랜드/시즌/포스트 카드 모두 좋아요 취소 메뉴를 제공한다.
- 좋아요 취소는 optimistic remove 후 실패 시 복구한다.

## 남은 QA

- 브랜드/시즌/포스트 pagination 끝까지 스크롤.
- 섹션별 빈 상태, 실패 상태, 로딩 상태 시각 QA.

## 커밋 정리 원칙

- 앱 Swift 코드와 테스트 코드는 별도 커밋 후보로 나눈다.
- `HANDOFF.md`, `.codex/`, 로컬 설정 파일은 사용자가 명시하지 않으면 제외한다.
