# 프로그램적 검증 — 현재 상태

## 2026-09-30 간소화 적용

사용자가 복잡한 구성을 제거하고 직접 모델을 변경하는 운영을 선택했다.

- 설계·세부 계획·테스트 설계·결과 분석: GPT-6.1 Sol High (2026-10-01 사용자 갱신).
- 구현·필수 게이트 실행·결과 보고: GPT-6.1 Sol Light.
- 모델 변경: 사용자 직접 수행.
- 검증 실행·판정: 프로젝트에 연결할 프로그램적 게이트.
- 자동 전달·별도 OS 계정·GitHub App·격리/승인 인프라 구축: 이번 범위에서 제외.
- 독립 Go 제품·3개 OS 배포를 도입 선행 조건으로 하는 계획: 제외.

## 정리 범위

이 작업에서 만든 과도한 설계·조사·계약 문서와 미실행 Go 테스트/Schema 초안을 제거했다. [운영 기준](../../architecture/PROGRAMMATIC_VERIFICATION.md), [작업 설계](design.md), [간단한 계획](plan.md)으로 통합했다.

기존 OutPick 제품 코드·테스트·개인 설정·보안 설정과 다른 작업의 HANDOFF/미커밋 변경은 보존한다. 계정·App·저장소·엔진을 만들었던 상태가 아니므로 이를 제거하는 외부 작업은 없다. Git ignore/exclude도 변경하지 않는다.

## 실제 구현 상태

공용 원본은 사용자 결정에 따라 `tools/verification-gate/`에서 버전 관리하고 `install.mjs`로 `~/.codex/tools/verification-gate/`에 설치한다. OutPick은 저장소의 원본을 직접 실행하므로 개인 홈 경로가 없는 clone에서도 환경을 준비해 사용할 수 있다.

사용자가 선택한 **Node.js 공용 실행기 + 프로젝트별 설정**을 구현했다. 공용 `gate.mjs`는 JSON 설정·검사 목록·시간 한도·Node 주 버전을 확인하고, Git 입력과 설정 및 실행기 내용을 식별한 뒤 명령을 순차 실행한다. Node `TestsStream` reporter의 JSONL과 Xcode `.xcresult`를 대조해 필수 테스트 ID, 추가 테스트의 실패, skip/todo/0개/결과 손상/중복을 검사한다. 원본 로그와 요약은 매 실행의 `output/verification/<실행 ID>/`에 저장한다. 실행 중 입력이 달라지면 결과를 차단하며, 변경 후 이전 통과 결과를 재사용하지 않는다.

OutPick은 `verification/gate.json`(자체·Firebase 설정·Socket), `functions.json`(Node 24), `firestore.json`(Firestore/Storage Emulator), `ios.json`(AppRuntimeConfigurationTests 13개)을 연결했다. 합의된 작업 범위에 맞는 설정을 선택한다. 이것은 다른 프로젝트 자동 연결, 모든 OutPick 기능/실기기/운영 검증 완료를 뜻하지 않는다.

공통 `/Users/gy/.codex/AGENTS.md`에 수동 모델 변경·역할·프로그램적 검증 원칙을 반영했다. OutPick `AGENTS.md`, 검증 workflow, 테스트 설계 skill의 선택적 실행 기준과 승인된 필수 게이트 실행 기준도 구분했다. 규칙 적용과 실제 게이트 연결 완료는 별개다.

실행기 자체 테스트는 정상/실패/누락/skip/0개/손상/중복/버전 불일치/시간 초과/입력 변경을 다루는 9개가 통과했다. Firestore/Storage는 샌드박스의 localhost 제한으로 첫 실행이 차단됐고, 다음 실행에서는 `ios.json` 추가로 입력 변경 차단이 발생했다. 이 두 차단은 통과로 취급하지 않았다. 최종 설정과 실행기를 고정한 후 네 설정을 다시 실행해 모두 통과했다.

아래는 다른 미커밋 기능이 포함된 기존 작업 폴더에서 수행한 초기 연결 검증 기록이다. 게이트만 분리한 PR 코드의 검증 결과는 PR 설명에 별도로 남긴다.

| 초기 연결 실행 | 판정·실제 테스트 수 | 원본 요약 |
| --- | --- | --- |
| 기본·Firebase 설정·Socket | 통과, Socket 117개 | `output/verification/1790769603908-8c426f67-58cf-495a-9b2c-ff2e50b8be59/summary.json` |
| Functions(Node 24) | lint·테스트 통과, 테스트 283개 | `output/verification/1790769603889-ae456d57-efe1-41c3-b797-387555efe439/summary.json` |
| Firestore/Storage Emulator(Node 24) | 통과, 테스트 126개 | `output/verification/1790769652586-711c739b-ae67-461e-973e-36829131f35b/summary.json` |
| iPhone 17 Pro(iOS 26.2) Simulator | 통과, AppRuntimeConfigurationTests 13개 | `output/verification/1790769651586-20bc72dc-0cc6-4584-98b6-2e5a89d3f79f/summary.json` |

모든 최종 요약은 `failures=[]`, `blockers=[]`, 검사 종료 코드 0을 기록했다. `git diff --check`와 변경한 `.mjs` 문법 검사도 통과했다. 이 실행 결과는 각 설정에 기록된 입력 상태와 검사 범위에 한정된다.

## 실행 방법과 범위

프로젝트 루트에서 `node tools/verification-gate/gate.mjs --project . --config verification/gate.json` 형식으로 실행한다. 다른 설정은 끝 인자를 `verification/functions.json`, `verification/firestore.json`, `verification/ios.json`으로 바꾼다. Functions와 Emulator는 Node 24를 `PATH` 맨 앞에 준비한다. Firestore/Storage는 로컬 Emulator 포트 접근이 필요하고, iOS는 CoreSimulator 접근이 필요하다. 격리된 환경에서 불가하면 게이트가 차단 결과를 반환한다.

프로젝트별 필수 검사와 테스트 ID의 충분성은 사용자·GPT-6.1 Sol High가 작업 계획에서 검토한다. 초기 연결 이후 채팅 미디어 만료용 필수 검사를 확장했고 [최종 범위](../../architecture/CHAT_MEDIA_RETENTION.md)를 따른다. `OutPickUITests`, 운영 배포, 다른 프로젝트의 검사는 별도 연결 전까지 미검증이다. 실기기 QA는 사용자 관찰 결과와 별도로 기록하며 모델 전환·자동 전달은 포함하지 않는다.

## PR 준비와 리뷰 보완

- 다른 채팅 미디어 변경을 제외하고 `main` 기준 전용 작업 폴더에서 게이트 변경만 분리했다. Functions 필수 export 계약은 해당 코드의 117개 이름을 따른다. 초기 작업 폴더의 119개 계약은 별도 미커밋 기능에 속하며 그 기능 반영 시 설정도 함께 갱신한다.
- 원본·설치기·사용 설명을 저장소에 추가해 게이트 구현이 PR에서 누락되는 문제를 해결했다. 개인 홈 절대 경로와 Simulator UUID는 실행 설정에서 제거했다.
- Node reporter가 assertion 오류와 stdout/stderr/diagnostic을 보존하도록 수정했다. 불완전한 요약 수치도 통과시키지 않는다.
- 정상적인 추적 파일 삭제를 입력 상태로 식별하고, 명시한 ignored 설정 파일도 내용 해시에 반영한다. 비밀 파일 내용은 결과에 출력하지 않는다. iOS 입력에 xcconfig·빌드 스크립트·Development plist를, Emulator 입력에 추가 Storage rules·indexes를 포함했다.
- 시간 초과/취소 시 강제 종료 대기가 조기에 사라지지 않도록 수정했다. SIGTERM을 무시하는 자손 프로세스 정리를 포함한 회귀 검사를 추가했다. Xcode 필수 테스트의 assertion 실패는 `failed`, 누락·skip은 `blocked`로 구분하는 검사까지 자체 회귀 13개를 실행한다.
- 운영 기준·ADR·검증 workflow에 남아 있던 미구현 표시를 정정했다. PR 검증은 이 변경들을 커밋한 후 네 설정으로 실행하고 원본 요약 위치와 코드 버전을 PR에 기록한다.
