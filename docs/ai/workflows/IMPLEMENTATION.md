# Implementation Workflow

## 목적

설계가 끝난 기능을 phase 단위로 구현하고, 진행상황과 반복 지식을 하네스에 반영하기 위한 워크플로우 인덱스다.

## 처음 읽을 순서

1. 이 문서의 `기본 순서`를 확인한다.
2. 구현 전 가치, 역할 관점, 검증 기준은 `implementation/validation.md`를 확인한다.
3. 모호한 결정이나 사용자 논의가 필요하면 `implementation/discussion.md`를 확인한다.
4. 작업 문서와 문서 지도 갱신 기준은 `implementation/docs-map.md`를 확인한다.
5. 커밋 안내와 커밋 후보 분류는 `implementation/commits.md`를 확인한다.
6. 문서가 커졌거나 책임이 섞이면 `implementation/document-size.md`를 확인한다.
7. 반복 명령을 자동화할지 판단할 때는 `implementation/scripts-ai.md`를 확인한다.

## 기본 순서

1. `docs/ai/ENTRYPOINTS.md`에서 관련 진입점을 확인한다.
2. 관련 task 문서가 있으면 `docs/ai/tasks/{task-name}`을 확인한다.
3. 하네스 문서에 정보가 부족하면 필요한 코드 범위만 탐색한다.
4. 구현하려는 기능의 가치 기준을 먼저 정리한다.
5. 구현 중 제품 또는 기술 결정이 모호하면 사용자와 논의한다.
6. phase 단위 구현 계획을 작성한다.
7. 사용자 승인 후 파일을 수정한다.
8. 변경 범위에 맞는 검증 방법을 정한다.
9. 검증을 수행했으면 결과를 기록하고, 수행하지 않았으면 이유를 기록한다.
10. 새 구조, 새 파일, 새 기술 선택, 새 검증 흐름이 생겼으면 문서 지도를 갱신한다.
11. 반복 재사용될 구조, 진입점, 검증 명령, 기술 결정은 `docs/ai` 갱신 후보로 제안한다.
12. ADR 작성 기준에 해당하는 결정은 구현 전 또는 해당 phase 종료 전에 `docs/ai/ADR.md`에 기록한다.
13. 같은 명령이나 검증 흐름이 2~3회 이상 반복되면 `scripts/ai` 자동화 후보로 제안한다.
14. phase 종료 시 설계, 계획, 진행, 결정, 검증 기록이 각자 맞는 문서에 남았는지 확인한다. 긴 상세 기록은 `progress/{phase}.md`와 `decisions/{phase-or-domain}.md`로 분리하고, 인덱스 문서에는 현재 상태와 링크만 남긴다.
15. 변경한 하네스 문서의 크기와 책임 혼합 여부를 점검하고, 필요하면 압축 또는 인덱스/상세 문서 분리를 다음 phase 전에 제안한다.

## 상황별 상세 문서

- 구현 가치, 역할 관점, 미배포 앱 호환성, 테스트/QA 경계: `docs/ai/workflows/implementation/validation.md`
- 논의 필요 기준과 보고 형식: `docs/ai/workflows/implementation/discussion.md`
- 작업 문서 기준, 문서 지도 갱신 기준, 완료 보고 전 체크: `docs/ai/workflows/implementation/docs-map.md`
- 하네스 커밋 후보 분류와 커밋 안내 형식: `docs/ai/workflows/implementation/commits.md`
- 하네스 문서 크기 관리, 압축, 인덱스/상세 문서 분리 기준: `docs/ai/workflows/implementation/document-size.md`
- `scripts/ai` 자동화 후보와 제안 형식: `docs/ai/workflows/implementation/scripts-ai.md`

## 참조 원칙

- `IMPLEMENTATION.md`는 구현 workflow의 시작점과 문서 지도를 제공한다.
- 세부 기준은 하위 상세 문서에서 관리하고, 이 문서는 상세 내용을 반복하지 않는다.
- 상세 문서를 추가하거나 경로를 바꾸면 이 인덱스와 관련 entrypoint에서 발견 가능한지 확인한다.
