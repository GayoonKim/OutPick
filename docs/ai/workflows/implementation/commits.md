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

- 사용자가 `커밋 정리`, `커밋 나눠줘`, `커밋 명령어 정리`처럼 짧게 요청하면 이 문서의 기준을 자동 적용한다.
  - 먼저 `git status --short --untracked-files=all`을 확인한다.
  - 이번 작업과 무관한 변경, 개인 산출물, `HANDOFF.md`/active/progress 같은 세션 상태 문서는 기본 커밋 명령에서 제외한다.
  - 앱 Swift 코드, 테스트 코드, Firebase/Firestore, 공유 하네스 문서, 프로젝트 설정을 나눠 커밋 후보를 제안한다.
  - 각 후보마다 실제 `git add ...`와 `git commit -m "..."` 명령을 제공한다.
- 단순 커밋 메시지 후보 한 줄만 제시하지 않는다.
- 커밋 안내 전에는 `git status --short --untracked-files=all`을 확인한다.
- 필요하면 `git diff --name-only`, `git diff --cached --name-only`, `git ls-files -- {path}`, `git check-ignore -v {path}`로 추적/제외 상태를 확인한다.
- 변경 성격별로 커밋 단위를 나누고 각 단위의 목적을 짧게 설명한다.
- 각 커밋 단위마다 `git add {file-or-dir}`와 `git commit -m "{message}"` 명령을 함께 제안한다.
- 커밋 메시지는 사용자가 다르게 요청하지 않으면 한글로 제안한다.
- 앱 Swift 코드, 테스트 코드, Firebase Functions/Firestore rules, 프로젝트 설정, 공유 하네스 문서는 가능한 별도 커밋 후보로 분리한다.
- `HANDOFF.md`, `.codex/`, 개인 세션 상태, 커밋 가치가 낮은 task/progress 문서는 사용자가 명시하지 않으면 커밋 명령에서 제외한다.
- `git add .`는 제안하지 않는다.
- ignore/exclude 대상 파일이 실제 작업 결과에 포함되어야 하면 일반 `git add`로는 staging되지 않을 수 있음을 명시한다.
- ignore/exclude 대상 파일을 커밋해야 하는 경우에는 사용자가 명시적으로 포함을 승인한 뒤 파일별로 `git add -f {file}`을 제안한다.
- 기존에 수정되어 있으나 이번 작업과 무관한 파일은 별도 보류 항목으로 분리하고, 커밋 명령에 포함하지 않는다.

## 커밋 안내 예시

아래처럼 실제 명령어 블록까지 제안한다.

```bash
git status --short --untracked-files=all

git add OutPick/DesignSystem/OutPickTheme.swift \
  OutPick/Assets.xcassets/AccentColor.colorset/Contents.json \
  docs/ai/ADR.md
git commit -m "다크 전용 디자인 시스템 기반 추가"
```

ignore/exclude 대상 파일을 사용자가 명시적으로 포함하기로 한 경우에만 아래처럼 안내한다.

```bash
git add -f OutPick/App/AppDelegate.swift OutPick/Info.plist
git commit -m "앱 다크 전용 appearance 적용"
```
