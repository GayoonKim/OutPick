# OutPick Project Rules

## 기본 응답

- 모든 답변은 한국어로 작성한다.
- 핵심 문제를 먼저 정의하고, 선택한 구조나 기술의 이유와 해결 방식을 함께 설명한다.
- 잘 모르는 내용은 "잘 모르겠습니다"라고 말한다.
- 추측은 "추측입니다"라고 표시한다.
- 확실하지 않은 정보는 "확실하지 않음"으로 표시한다.
- 정책, 심사, 개인정보, 권한, 결제, UGC, AI, 외부 링크처럼 최신성이 중요한 내용은 기억 기반으로 단정하지 않는다. 가능한 Apple 공식 문서를 확인하고, 확인할 수 없으면 "확실하지 않음"으로 표시한다.

## 프로젝트 하네스

- 새 기능, 큰 수정, 리팩토링은 먼저 `docs/ai` 하위 문서에서 필요한 범위만 확인한다.
- 제품/사용자 흐름/화면/데이터/아키텍처/기술 결정은 `docs/ai` 문서를 기준으로 한다.
- 기능별 코드 진입점은 `docs/ai/ENTRYPOINTS.md`를 먼저 확인한다.
- OutPick 코드 구조의 세부 원칙은 `docs/ai/CODE_ARCHITECTURE.md`를 따른다.
- 중요한 기술 결정은 `docs/ai/ADR.md`에 기록하거나 갱신 후보로 제안한다.
- 현재 진행 중인 작업은 `HANDOFF.md`가 가리키는 `docs/ai/tasks/{task-name}/` 문서를 기준으로 확인한다.
- 하네스 문서에 필요한 정보가 없거나 오래됐다고 판단되면 관련 코드 범위만 탐색하고, 반복 재사용될 내용은 작업 후 하네스 갱신 후보로 정리한다.

## OutPick 아키텍처 원칙

- 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선 따른다.
- CompositionRoot는 앱, 탭, Feature 진입점 조립과 UIKit/SwiftUI 브릿지를 담당한다.
- Container는 Feature 내부 Repository, UseCase, Store, ViewModel, Coordinator, 화면 factory를 생성하고 보관한다.
- Coordinator는 push, sheet, fullScreenCover, UIKit present/dismiss 등 화면 전환과 사용자 흐름 제어를 담당한다.
- View는 화면 렌더링과 사용자 이벤트 전달에 집중하고, Repository, UseCase, Firebase, Cloud Functions, Firestore SDK를 직접 생성하지 않는다.
- ViewModel은 생성자 주입으로 UseCase, Repository, Store를 받고 외부 구현 세부사항을 직접 알지 않게 한다.
- 서버 상태 변경은 가능한 Repository 또는 Cloud Functions 계층을 통해 처리한다.
- 화면 이동 책임이 View, ViewModel, Container 클로저에 흩어지면 Coordinator로 모으는 방향을 우선 검토한다.
- 불필요한 추상화와 요청 범위 밖 리팩토링은 피한다.

## 작업 원칙

- 구현 전 변경 파일 후보, 구현 계획, 테스트/검증 계획을 먼저 정리한다.
- 기능 범위, 완료 기준, 화면 이동, 데이터 구조, API/Firebase Functions 필요 여부, 정책 리스크, 아키텍처 변경처럼 제품 또는 기술 결정이 모호하면 임의로 확정하지 않고 사용자와 논의한다.
- 논의가 필요한 경우 무엇이 모호한지, 가능한 선택지, 각 선택지의 장단점, 추천안을 정리한 뒤 사용자 결정을 기다린다.
- 큰 작업은 phase 단위로 나누고, 각 phase가 끝나면 변경 파일, 핵심 결정, 검증 여부, 남은 위험을 짧게 정리한다.
- 새 기능, 큰 수정, 리팩토링처럼 여러 phase로 나뉘는 작업은 메인 스레드를 총괄 컨텍스트로 유지한다.
- 여러 phase 작업을 시작하거나 다음 phase로 넘어가기 전에는 다음 phase들의 예상 변경 파일, 의존성, DI/Container/Coordinator 영향, 데이터/API 계약, 충돌 가능성을 먼저 점검한다.
- 코드 수정이 필요 없는 조사, 중복 지점 탐색, 설계 쟁점 후보 발굴, 테스트 범위 조사는 서브 에이전트로 병렬화할 수 있다.
- 설계 쟁점의 최종 결정은 메인 스레드에서 사용자와 논의해 확정한다.
- 구현은 파일 충돌 가능성, service/protocol 경계 변경, 데이터/API 계약 의존성, DI/Container/Coordinator 영향 범위를 기준으로 순차 진행 또는 별도 스레드 병렬 진행을 결정한다.
- 같은 파일, 같은 service/protocol 경계, 같은 DI 조립부를 건드릴 가능성이 있거나 한 phase 결과가 다른 phase의 전제 조건이면 병렬 구현하지 않고 메인 스레드에서 순차 진행한다.
- 별도 스레드에서 구현한 작업은 메인 스레드에서 최종 통합, 검증, 문서 갱신 기준을 관리한다.
- 사용자가 "다음 단계로 넘어가지 말고 정리", "요약하고 넘어가자"라고 요청하면 단계 완료 후 멈추고 확인을 기다린다.
- 수동 파일 수정은 `apply_patch`를 사용한다.
- 사용자 변경사항을 임의로 되돌리지 않는다.
- 코드 주석이 필요하면 한글로 작성한다.
- 앱 실행으로 쉽게 확인 가능한 단순 happy path UI는 자동 테스트를 과하게 작성하지 않고 수동 QA를 우선한다.
- 서버 실패, 권한 실패, 일부 API 실패, 비동기, 중복 호출, 캐시, pagination, 상태 전이처럼 재현과 제어가 어려운 케이스는 fake repository/use case/spy 기반 자동 테스트를 우선한다.
- 테스트 실행은 사용자가 명시적으로 요청했거나, 결제/인증/데이터 삭제/보안 규칙/배포 전 검증처럼 실패 비용이 큰 변경에 한해 우선 수행한다.
- 테스트 코드를 작성하고 실행하지 않은 경우에는 작성한 테스트 파일/시나리오와 실행 보류 이유를 최종 보고에 정리한다.
- `scripts/ai` 실행 자동화는 같은 명령이나 검증 흐름이 2~3회 이상 반복될 때만 제안하거나 추가한다.

## Firebase/Firestore

- Firebase Functions 변경은 `.codex/skills/firebase-functions-workflow/SKILL.md` 절차를 확인한다.
- Firestore rules 또는 indexes 변경은 `.codex/skills/firestore-workflow/SKILL.md` 절차를 확인한다.
- Functions 변경 시 기본 배포 대상은 `firebase deploy --only functions --project outpick-664ae`다.
- Firestore rules 변경 시 기본 배포 대상은 `firebase deploy --only firestore:rules --project outpick-664ae`다.
- Firestore indexes 변경 시 기본 배포 대상은 `firebase deploy --only firestore:indexes --project outpick-664ae`다.
- 운영 함수 삭제처럼 되돌리기 어려운 작업은 사용자 명시 승인 없이 진행하지 않는다.
- 데이터 삭제, 마이그레이션, 보안 규칙 완화, 운영 배포 범위가 모호하면 진행 전에 사용자와 논의한다.

## 커밋 정리

- 하나의 큰 작업이 완전히 끝나기 전에는 임의로 커밋하지 않는다.
- 커밋 안내 전에는 `git status --short`를 확인한다. 필요하면 `git diff --name-only` 또는 `git diff --cached --name-only`도 확인한다.
- `git add .`는 기본 제안하지 않는다. 작업 단위별 파일 또는 디렉터리를 명시한다.
- 앱 Swift 코드, 테스트 코드, Firebase Functions/Firestore rules, 프로젝트 설정/문서 작업은 서로 다른 커밋 후보로 나눈다.
- `HANDOFF.md`, `.codex/`, 백업 폴더, 로컬 설정 파일은 사용자가 명시하지 않으면 커밋 후보에서 제외한다.

## 최종 보고

- 핵심 문제, 선택한 구조와 이유, 변경 파일, 검증 결과를 중심으로 정리한다.
- 검증을 수행하지 못했거나 보류했다면 이유를 밝힌다.
- 커밋 안내가 필요한 경우 한글 git commit 메시지 한 줄만 제안하지 않는다.
- 커밋 안내는 `git status --short` 확인 결과를 바탕으로 작업 단위별 `git add {file-or-dir}`와 `git commit -m "{message}"` 명령 전체를 제안한다.
- `git add .`는 제안하지 않는다. ignore/exclude 대상 파일을 커밋해야 하는 경우에는 사용자가 명시적으로 포함하길 원하는지 확인하거나, 필요한 파일만 `git add -f {file}` 형태로 분리해 안내한다.
