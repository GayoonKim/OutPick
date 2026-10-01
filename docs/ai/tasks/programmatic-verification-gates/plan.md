# 프로그램적 검증 — 간단한 도입 계획

2026-09-30 간소화 승인. **Node.js 공용 실행기 + 프로젝트별 설정을 사용자 확정했다.** 아래는 승인된 구현 계획이며 실제 완료/차단 결과는 [진행 기록](progress.md)에 남긴다. 기준: [운영 규칙](../../architecture/PROGRAMMATIC_VERIFICATION.md).

## 1. 규칙 반영

공통 AGENTS.md에는 사용자 수동 모델 선택, GPT-6.1 Sol High 설계·분석, GPT-6.1 Sol Light 구현, 승인된 필수 게이트 실행, 미실행/누락/실패를 통과시키지 않는 원칙을 둔다. 프로젝트에는 실제 게이트 진입점과 현재 연결 상태를 둔다.

완료 기준: 기존 선택적 테스트 실행 규칙과 충돌하지 않으며, 존재하지 않는 게이트를 작동 중이라고 안내하지 않는다.

## 2. 실제 게이트 연결

프로젝트별 승인된 검사 목록·명령·합격 기준을 읽고 기존 도구를 실행하는 공용 진입점을 만든다. 필요한 도구 연결만 작성하고 모델 실행·전달 기능을 넣지 않는다.

OutPick의 기존 진입점:
- Functions: functions/package.json, functions/scripts/run-tests.mjs.
- Socket: Socket/package.json, Socket/scripts/run-tests.mjs.
- Firestore/Storage: firestore-tests/package.json, firestore-tests/run-firestore-tests.mjs.
- 앱: Xcode 빌드·테스트, 기존 OutPickTests/OutPickUITests.
- 환경 검사: scripts/build/validate-and-copy-firebase-config.sh.

각 작업에 필요한 검사와 영향 범위를 명시한다. 모든 작업에 무관한 전체 검사를 일괄 요구하지 않는다. 명령·환경·시간 한도·개별 필수 테스트의 결과 확인 방법을 짧은 구현안에 담아 검토한 뒤 구현한다.

현재 셸의 Node는 22이고 Functions 설정은 24이며 Go는 발견하지 못했다. 실제 사용할 도구 버전을 맞추되 Go 설치·별도 저장소·3개 OS 배포를 선행 조건으로 삼지 않는다.

완료 기준: 명시한 검사 실행, 원본 결과 보존, 실제 검사 코드 상태 기록, 필수 누락 감지, 통과/실패/차단 반환.

## 3. 게이트 동작 확인

정상 통과, 의도적 테스트 실패, 필수 검사/테스트 누락·skip·0개, 잘못된 결과, 실행 불가·시간 초과, 코드 변경 후 오래된 결과를 각각 확인한다.

게이트 자체의 합성 오류 검사는 별도 테스트 코드로 작성한다. 기존 제품 테스트를 복제하거나 운영 데이터를 바꾸지 않는다. 실제 연결된 도구로 최소 한 번 확인한 후 해당 프로젝트의 게이트 상태를 연결 완료로 바꾼다.

이전 32개 Go 계약 테스트는 폐기된 연결 프로토콜에 종속된 미실행 초안이므로 삭제한다. 누락·중복·실패 보존 같은 검증 의도는 간소화 기준에 유지한다.

## Sol에 전달할 최소 구현안

### 구성과 파일

- 공용 원본: `tools/verification-gate/`. `install.mjs`로 `~/.codex/tools/verification-gate/`에 설치해 다른 프로젝트도 같은 실행기를 호출한다. 원본 저장 위치는 PR 준비 시 사용자가 확정했다.
- `gate.mjs`: 설정 확인 → 입력 식별 → 순차 실행 → 결과 대조 → 최종 판정. 새 패키지 빌드·자동 모델 호출은 필요 없다.
- `node-reporter.mjs`: Node 테스트의 구조화된 이벤트를 기록한다. 단순 로그 문자열·총개수로 실행 성공을 추정하지 않는다.
- `gate.test.mjs`: 아래 합격 기준을 실제 임시 파일·합성 명령·Node 테스트로 검증한다. 별도 테스트 전용 엔진이나 연결 실행 파일은 만들지 않는다.
- 프로젝트 설정: `verification/{gate,functions,firestore,ios}.json`. 검사 ID·실행 파일/인자·작업 폴더·필수 테스트 식별자·입력 경로·검사별/전체 시간 한도·결과 형식을 둔다. 작업의 합의된 검사 범위에 맞는 설정을 선택한다.
- 결과: 프로젝트의 `output/verification/<run-id>/`에 이번 실행의 요약 JSON과 원본 로그/결과만 저장한다. OutPick은 이미 `output/`이 Git 제외 대상이다. 새 프로젝트는 해당 경로의 취급을 연결 시 확인한다.
- 기존 Node runner에는 구조화된 결과 출력 인자를 전달하는 최소 연결만 추가한다. 기존 테스트 발견 목록·테스트 내용·판정 기준은 바꾸지 않는다.

공용 실행기의 첫 실제 검증 환경은 현재 macOS/Node 22이며 프로젝트 도구는 별도다. Functions 검사는 선언된 Node 24 환경을 확보한 뒤 실행하고, 없으면 환경 차단으로 보고한다. 별도 Go 설치·저장소 생성·3개 OS 배포는 하지 않는다.

### 실행·판정 계약

진입점: `node tools/verification-gate/gate.mjs --project . --config <승인된 설정 경로>`. 다른 프로젝트는 설치된 `~/.codex/tools/verification-gate/gate.mjs`를 사용한다.

- 설정의 모든 검사를 필수로 실행한다. 작업별 필요한 검사·영향 범위는 GPT-6.1 Sol High와 사용자 검토로 설정한다. 이번 버전에는 자동 의존 그래프 추론·검사 선택 서버를 넣지 않는다.
- 설정에 없는 검사, 중복 ID/JSON 키, 잘못된 경로/형식, 시간값 누락은 명령 실행 전에 거절한다. 빈 검사 목록을 통과로 처리하지 않는다.
- 명령은 실행 파일·인자 배열로 전달한다. 기존 npm/script 실행은 명시적으로 호출하며 결과의 문자열을 명령으로 해석하지 않는다.
- 단순 명령 검사에는 실제 시작·종료 상태·로그를 요구한다. 테스트 검사는 추가로 승인된 필수 ID와 실제 결과를 대조한다. 선택한 검사에서 실행된 추가 테스트의 실패도 보존한다.
- Node는 `TestsStream` 이벤트를 공용 reporter로 기록한다. XCTest/Swift Testing은 `xcresulttool get test-results tests/summary`로 원본 `.xcresult`를 해석한다. 다른 도구를 연결하면 결과 해석기를 추가하며 미지원 결과는 차단한다.
- 검사마다 새 결과 위치를 만들고 이전 파일을 통과 근거로 재사용하지 않는다. 필수 테스트 ID 누락·skip·todo·중단·0개·중복/해석 불가 상태는 차단한다.
- 승인된 입력 경로, 검사 설정, 실행기/연결부를 시작·종료 시 내용으로 식별한다. 입력에는 검사 대상뿐 아니라 필요한 의존 코드·테스트·설정도 포함한다. 변경되면 결과를 차단한다. 중간에 바꿨다가 되돌리는 의도적 조작까지 증명하는 격리 장치는 아니다.
- 독립 검사는 실패 후에도 정한 한도 안에서 계속한다. 필수 준비 실패나 전체 시간 초과 시 추가 실행을 중단한다. 취소 시 해당 실행의 프로세스·자손 정리를 확인하며 다른 작업 프로세스를 종료하지 않는다.
- 최종 결과는 `passed / failed / blocked`, 종료 코드는 각각 `0 / 1 / 2`로 제안한다. 누락·환경 문제와 실패가 섞이면 `blocked`를 대표로 하고 확인된 실패도 함께 기록한다.
- 자동 재시도·자동 수정 루프는 이번 버전에 넣지 않는다. GPT-6.1 Sol Light가 결과를 보고하면 사용자가 GPT-6.1 Sol High로 바꿔 분석한다.

### OutPick 연결 순서와 실행 범위

| 순서 | 검사 | 명령·결과 연결 | 완료 기준 |
| --- | --- | --- | --- |
| 1 | 게이트 자체·환경 검사 | `node --test gate.test.mjs`, `sh scripts/build/test-validate-and-copy-firebase-config.sh` | 합성 정상/오류 경로와 기존 환경 검사 모두 실제 확인 |
| 2 | Socket | `npm --prefix Socket run check`, `npm --prefix Socket test` | 필수 테스트를 검토·등록하고 실제 ID·상태 확인 |
| 3 | Functions | Node 24에서 `npm --prefix functions run lint`, `npm --prefix functions test` | lint/컴파일/테스트 결과 구분, 필수 테스트 확인 |
| 4 | Firestore/Storage | `npm --prefix firestore-tests test` | 기존 `outpick-rules-test` Emulator 흐름 유지, 각각의 테스트 묶음·seed 검증 결과가 모두 존재 |
| 5 | 앱 | `OutPick-Development` Simulator build/test에 고유 `-resultBundlePath` 사용 | 먼저 `AppRuntimeConfigurationTests` 13개로 XCTest/Swift Testing 결과 연결 확인. 다른 앱 기능 검증 완료로 확대하지 않음 |

모든 작업에 이 표 전체를 무조건 실행한다는 뜻은 아니다. 이 표는 도구 연결의 구현·확인 범위다. 앱의 실제 대상 Simulator는 구현 시 설치된 가용 기기를 조회해 기록한다. 외부 인증·Development 배포·사용자 실기기/운영 데이터 변경은 이번 연결 검증에 포함하지 않는다. 해당 항목이 필수인 작업은 별도로 연결·실행하기 전까지 미검증이다.

초기 시간 예산 제안: 자체/환경 각 2분, Socket 각 5분, Functions lint 5분·test 10분, Emulator 20분, 앱 30분, 전체 연결 확인 90분. 성능 합격 수치가 아니라 무제한 실행 방지 한도이며 실측치는 아니다. 최종 구현 승인 시 함께 검토하고, 초과 시 임의 연장하거나 통과시키지 않는다.

### 게이트 자체의 필수 합격 기준

| 사례 | 합격 기준 |
| --- | --- |
| 정상 명령·정상 테스트 | 실제로 실행됐고 모든 필수 결과가 유효하면 통과 |
| assertion 실패·추가 테스트 실패 | 실패로 반환하고 원본 실패 보존 |
| 종료 0이나 필수 ID가 다름 | 차단. 총개수만 맞춰도 통과 불가 |
| 필수 skip/todo/0개·중단 | 차단. 실행한 것으로 간주하지 않음 |
| 결과 없음·손상·중복 ID·오래된 결과 | 차단. 파일 존재만으로 통과 불가 |
| 실행 파일/환경 없음·timeout | 차단·원인 보존·대상 프로세스 정리 |
| 실행 중 검사 입력/설정 변경 | 해당 실행 결과 차단 |
| 잘못된 설정 | 외부 검사 명령을 시작하지 않음 |
| 독립 검사 일부 실패 | 다른 독립 결과와 실패/차단 사유를 함께 보고 |
| 다른 임시 프로젝트 사용 | 동일 공용 실행기가 프로젝트 경로·설정만 바꿔 동작 |

각 사례를 `gate.test.mjs`에 작성하고 실제 공용 실행기를 호출해 검증한다. 앱 제품 테스트를 복제하거나 별도 대형 테스트 프로토콜을 추가하지 않는다. 초기에는 게이트 자체를 기존 Node 테스트 runner로 확인하고, 실제 연결이 완료된 범위만 게이트 적용 완료로 보고한다.

### 승인과 역할 경계

이 문서는 완료된 구현의 계획 기록이다. Node 방식 선택과 실제 파일 생성·기존 runner 변경·Node 24 환경 준비·위 범위 검사 실행을 승인받아 수행했다. 현재 역할은 GPT-6.1 Sol High 설계·분석 / GPT-6.1 Sol Light 구현·게이트 실행이며, 모델 설정을 추정하거나 자동 전환하지 않는다. 결과는 progress와 기능별 최종 검증 기록을 따른다.

기술 근거: [Node 공식 문서](https://nodejs.org/download/release/v22.23.1/docs/api/test.html#test-reporters)는 프로그램적 판독에 기본 reporter의 가변 텍스트 대신 `TestsStream` 이벤트를 사용하도록 안내한다. Xcode 결과 명령은 설치된 Xcode 26.6의 `xcresulttool help`에서 확인했다. 이번 조사에서 빌드·제품 테스트·패키지 설치는 실행하지 않았다.
