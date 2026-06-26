# Implementation Docs Map

## 목적

작업 문서 기준과 구현 후 문서 지도 갱신 기준을 정리한다.

## 작업 문서 기준

- `plan.md`: phase 단위 구현 계획 인덱스. phase별 상세 계획이 길어지면 `plan/{phase}.md` 또는 `{phase}-design.md`로 분리하고, 이 파일에는 목표/상태/링크만 남긴다.
- `progress.md`: 현재 진행상황 인덱스. 완료한 일, 남은 일, 변경 파일, 검증 상태의 최신 요약만 유지하고, phase별 상세 진행 기록은 `progress/{phase}.md`에 분리한다.
- `decisions.md`: 결정 인덱스. 해당 작업 안에서 생긴 결정의 번호, 제목, 상태, 상세 문서 링크만 유지하고, 결정 이유/대안/트레이드오프/재검토 조건은 `decisions/{phase-or-domain}.md`에 분리한다.
- `{phase}-design.md` 또는 `design.md`: 구현 전 설계 기준만 담는다. 구현 진행 로그, 검증 결과, 운영 배포 기록, smoke QA 결과를 계속 덧붙이지 않는다. 구현이 끝나면 최종 설계 요약과 상세 진행/결정 문서 링크만 남긴다.
- `ADR.md`: ADR 인덱스만 유지한다. 여러 feature나 이후 작업의 이해에 영향을 주는 아키텍처, 데이터 흐름, 상태 동기화, 서버 최신화 정책의 상세 본문은 `docs/ai/adr/ADR-XXX-title.md`에 기록한다.
- ADR 후보를 발견하면 구현 완료 보고에만 남기지 말고, 사용자와 합의한 뒤 구현 전 또는 해당 phase 종료 전에 공식 하네스에 반영한다.

## task 문서 기본 구조

큰 작업이나 여러 phase로 나뉘는 작업은 아래 구조를 기본값으로 사용한다.

```text
docs/ai/tasks/{task-name}/
├── plan.md
├── progress.md
├── decisions.md
├── design.md 또는 {phase}-design.md
├── progress/
│   └── {phase}.md
└── decisions/
    └── {phase-or-domain}.md
```

책임 경계:

- 설계 문서: 요구사항, 사용자 흐름, 화면/API/데이터/아키텍처 설계, 최종 정책.
- 계획 문서: phase 목표, 변경 범위, 완료 기준, 검증 방법, 논의 필요 사항.
- 진행 문서: 실제로 수행한 작업, 변경 파일, 검증 결과, 배포/smoke 기록, 남은 작업.
- 결정 문서: 선택한 구조와 기술, 선택 이유, 보류한 대안, 트레이드오프, 재검토 조건.

한 phase가 끝날 때 설계/진행/결정/검증이 한 파일에 섞이기 시작하면 다음 phase로 넘어가기 전에 위 구조로 분리한다.

## 문서 지도 갱신 기준

작업 후 다음 사람이 전체 관련 파일을 다시 읽지 않아도 필요한 맥락을 찾을 수 있어야 한다.

코드 변경이 생긴 경우 문서 지도 갱신은 필수다. 코드 파일 추가, 수정, 이동, 삭제가 있었다면 아래 질문에 답할 수 있게 하네스를 갱신한다.

- 어떤 파일/디렉터리를 보면 새 책임 또는 변경된 책임을 알 수 있는가.
- 어떤 파일/디렉터리를 보면 서버/API/Firestore/Storage/socket 계약을 알 수 있는가.
- 어떤 파일/디렉터리를 보면 DI, CompositionRoot, Container, Coordinator 연결을 알 수 있는가.
- 어떤 파일/디렉터리를 보면 테스트, 수동 QA, 검증 명령을 알 수 있는가.
- 삭제된 파일이나 제거된 public API가 있다면 이제 어느 파일을 보면 같은 흐름을 알 수 있는가.

아래 중 하나라도 생기면 문서 지도를 갱신한다.

- 새 패키지, 모듈, feature, worker, script, endpoint, trigger, queue, rules/indexes가 추가됐다.
- 코드 파일이 추가, 수정, 이동, 삭제됐다.
- 기존 책임 경계가 바뀌었다.
- 기술 선택이나 외부 서비스 선택이 확정됐다.
- 상태 모델, 데이터 모델, API payload, Firestore path, Storage path가 바뀌었다.
- 검증 명령, 배포 명령, smoke QA 흐름이 새로 생겼다.
- 다음 작업자가 “어느 파일부터 봐야 하는지”를 모를 가능성이 있다.

갱신 위치:

- 기능별 코드 진입점: `docs/ai/entrypoints/{domain}.md`
- 장기 책임 경계와 읽는 순서: `docs/ai/architecture/*.md`
- phase별 현재 작업 상태: `docs/ai/tasks/{task-name}/progress.md`
- phase별 목표와 완료 기준: `docs/ai/tasks/{task-name}/plan.md`
- 기술 선택과 대안/트레이드오프: `docs/ai/tasks/{task-name}/decisions.md` 또는 `docs/ai/ADR.md`
- 반복 검증/배포 흐름: `docs/ai/workflows/*.md` 또는 `scripts/ai` 후보

문서 지도에 반드시 남길 항목:

- 목적: 이 문서는 어떤 질문에 답하는가.
- 코드 진입점: 실제 구현을 볼 파일/디렉터리.
- 설계 진입점: 책임 경계와 기술 선택을 볼 문서.
- 진행상태 진입점: 현재 phase와 검증 상태를 볼 문서.
- 결정 진입점: 왜 이 선택을 했는지 볼 문서.
- 다음 작업 진입점: 이어서 구현할 때 먼저 볼 문서.
- 삭제/대체 진입점: 제거된 파일/API가 있으면 대체 파일/API.

문서 지도 작성 원칙:

- 전체 설명을 반복하지 않고 “무엇을 알고 싶으면 어디를 보면 되는지”를 짧게 쓴다.
- 장기 공유 지식은 `architecture`, `entrypoints`, `ADR`, `workflows`로 승격한다.
- 세션 상태나 임시 진행상황은 task 문서에만 둔다.
- 커밋 전에는 문서 지도 변경이 공유 지식인지, 세션 상태인지 분류한다.

완료 보고 전 체크:

- 새로 추가한 코드 파일이 진입점 문서나 읽는 순서에서 발견 가능한가.
- 수정/삭제한 코드 파일의 책임 변화와 대체 진입점이 문서 지도에 반영됐는가.
- 새로 추가한 SwiftUI/ViewController 코드가 root, row/cell, preview, status/fallback, confirmation bar, presentation modifier, ViewModel, UseCase/factory 책임을 한 파일에 섞지 않았는가.
- 임시로 한 파일에 묶은 하위 View나 helper가 있으면 다음 phase로 넘어가기 전에 분리 완료 또는 분리 후보를 명시했는가.
- 새 기술 선택의 이유와 대안이 decisions/ADR/architecture 중 한 곳에 연결됐는가.
- 다음 phase 작업자가 전체 파일을 훑지 않고도 시작 문서를 찾을 수 있는가.
- 커밋 가치가 낮은 task/progress/HANDOFF 변경을 커밋 후보에서 분리했는가.
