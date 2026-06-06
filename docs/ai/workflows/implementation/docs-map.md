# Implementation Docs Map

## 목적

작업 문서 기준과 구현 후 문서 지도 갱신 기준을 정리한다.

## 작업 문서 기준

- `plan.md`: phase 단위 구현 계획.
- `progress.md`: 현재 진행상황, 완료한 일, 남은 일, 변경 파일, 검증 상태.
- `decisions.md`: 해당 작업 안에서 생긴 결정. 프로젝트 전체에 영향이 있으면 `docs/ai/ADR.md`로 승격한다.
- `ADR.md`: 여러 feature나 이후 작업의 이해에 영향을 주는 아키텍처, 데이터 흐름, 상태 동기화, 서버 최신화 정책을 기록한다.
- ADR 후보를 발견하면 구현 완료 보고에만 남기지 말고, 사용자와 합의한 뒤 구현 전 또는 해당 phase 종료 전에 공식 하네스에 반영한다.

## 문서 지도 갱신 기준

작업 후 다음 사람이 전체 관련 파일을 다시 읽지 않아도 필요한 맥락을 찾을 수 있어야 한다.

아래 중 하나라도 생기면 문서 지도를 갱신한다.

- 새 패키지, 모듈, feature, worker, script, endpoint, trigger, queue, rules/indexes가 추가됐다.
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

문서 지도 작성 원칙:

- 전체 설명을 반복하지 않고 “무엇을 알고 싶으면 어디를 보면 되는지”를 짧게 쓴다.
- 장기 공유 지식은 `architecture`, `entrypoints`, `ADR`, `workflows`로 승격한다.
- 세션 상태나 임시 진행상황은 task 문서에만 둔다.
- 커밋 전에는 문서 지도 변경이 공유 지식인지, 세션 상태인지 분류한다.

완료 보고 전 체크:

- 새로 추가한 코드 파일이 진입점 문서나 읽는 순서에서 발견 가능한가.
- 새 기술 선택의 이유와 대안이 decisions/ADR/architecture 중 한 곳에 연결됐는가.
- 다음 phase 작업자가 전체 파일을 훑지 않고도 시작 문서를 찾을 수 있는가.
- 커밋 가치가 낮은 task/progress/HANDOFF 변경을 커밋 후보에서 분리했는가.
