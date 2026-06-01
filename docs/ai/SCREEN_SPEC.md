# OutPick Screen Spec

## 목적

OutPick의 화면 구성과 화면별 책임을 AI 에이전트가 빠르게 확인하기 위한 문서다.

## 작성 원칙

- 화면에는 사용자가 실제로 필요한 정보와 액션만 둔다.
- 요청하지 않은 부가 화면을 만들지 않는다.
- 화면 이동이 2단계 이상 이어지거나 modal/sheet/push 정책이 섞이면 Coordinator 책임을 먼저 검토한다.
- 화면별 상세 구현은 관련 `View`, `ViewModel`, `Coordinator`, `Container` 진입점을 함께 기록한다.

## 현재 상태

- 확실하지 않음: 전체 화면 목록은 아직 완성 정리되지 않았다.
- 기능별 화면 명세는 `docs/ai/features/` 또는 `docs/ai/tasks/`에서 먼저 작성한 뒤, 안정화된 내용만 이 문서에 반영한다.
