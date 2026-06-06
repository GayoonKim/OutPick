# Implementation Commits

## 목적

하네스 문서와 작업 변경분의 커밋 후보 분류, 커밋 안내 형식을 정리한다.

## 하네스 커밋 기준

하네스 문서는 모두 같은 커밋 가치가 있는 것이 아니다. 커밋 후보는 팀/미래 작업자/다른 AI 세션이 반복 참조할 공유 지식만 우선한다.

커밋 후보:

- `docs/ai/ADR.md`
- `docs/ai/architecture/*.md`
- `docs/ai/entrypoints/*.md`
- `docs/ai/workflows/*.md`
- 여러 작업에 반복 적용되는 데이터 구조, 아키텍처, 검증 명령, 기술 결정 문서

기본 제외 후보:

- `HANDOFF.md`
- `docs/ai/tasks/active.md`
- `docs/ai/tasks/*/progress.md`
- 개인 세션 진행상황, 임시 phase 메모, 압축/복원용 작업 상태
- `.codex/` 내부 개인 설정, 로컬 스킬, 로컬 워크플로우

조건부 커밋 후보:

- `docs/ai/tasks/*/plan.md`
- `docs/ai/tasks/*/decisions.md`

조건부 문서는 작업 근거 추적이 실제로 필요하거나 사용자가 명시적으로 포함하라고 한 경우에만 커밋 후보로 둔다. 장기적으로 반복 적용될 결정은 task 문서에만 두지 말고 `ADR.md` 또는 `docs/ai/architecture/*.md`로 승격한 뒤 task 문서는 커밋 후보에서 제외한다.

커밋 안내 전에는 `git status --short`를 확인하고, 커밋 가치가 낮은 하네스/AI 파일은 명시적으로 제외 후보로 분류한다.

## 커밋 안내 형식

- 단순 커밋 메시지 후보 한 줄만 제시하지 않는다.
- 변경 성격별로 커밋 단위를 나누고 각 단위의 목적을 짧게 설명한다.
- 각 커밋 단위마다 `git add {file-or-dir}`와 `git commit -m "{message}"` 명령을 함께 제안한다.
- 커밋 메시지는 사용자가 다르게 요청하지 않으면 한글로 제안한다.
- 앱 Swift 코드, 테스트 코드, Firebase Functions/Firestore rules, 프로젝트 설정, 공유 하네스 문서는 가능한 별도 커밋 후보로 분리한다.
- `HANDOFF.md`, `.codex/`, 개인 세션 상태, 커밋 가치가 낮은 task/progress 문서는 사용자가 명시하지 않으면 커밋 명령에서 제외한다.
