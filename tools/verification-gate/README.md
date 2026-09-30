# 공용 프로그램적 검증 게이트

Node.js 22 이상과 Git이 필요하다. 현재 검증한 실행 환경은 macOS이며 프로세스 그룹 정리는 POSIX 환경을 사용한다. Windows 지원은 아직 확인하지 않았다. 실행기는 OutPick에 종속된 코드 없이 다른 Git 프로젝트의 JSON 설정도 처리한다. 원본은 이 디렉터리에서 리뷰·버전 관리하고 공용 위치에 설치해 재사용한다.

```sh
node tools/verification-gate/install.mjs
node tools/verification-gate/gate.mjs --project . --config verification/gate.json
node ~/.codex/tools/verification-gate/gate.mjs --project /path/to/project --config verification/gate.json
```

설치는 공용 위치의 실행기·reporter·자체 테스트 세 파일을 현재 원본으로 갱신한다. 다른 프로젝트는 각자의 설정·검사를 먼저 연결해야 한다. 공용 실행기만 설치해도 요구사항과 필수 검사가 자동 결정되는 것은 아니다.

설정에는 `version: 1`, `runTimeoutMs`, `inputs`, `checks`를 둔다. 각 검사는 고유 `id`, `command`, 문자열 배열 `args`, 프로젝트 상대 `cwd`, `timeoutMs`, `kind`를 갖는다. `kind`는 빌드·정적 검사용 `command`, Node 테스트용 `node`, Xcode 테스트용 `xcresult`다. 필요하면 `nodeMajor`로 실행 환경을 제한한다. 설정의 모든 검사는 필수다.

테스트 검사는 `requiredTests`에 필수 ID를 명시한다. Node ID는 `프로젝트 상대 테스트 파일::테스트 이름`이며 중복 이름은 차단한다. Node runner는 게이트가 제공하는 `OUTPICK_GATE_REPORTER_PATH`와 `OUTPICK_GATE_RESULT_PATH`를 Node의 `--test-reporter`와 `--test-reporter-destination`에 전달한다. 여러 결과가 있으면 `OUTPICK_GATE_RESULT_BASE` 아래 `node-result-<이름>.jsonl`로 저장하고 `reportNames`에 이름을 선언한다. 기본 이름 `main`은 `node-result.jsonl`이다. Xcode는 `nodeIdentifier`를 사용하고 실행기가 새 `-resultBundlePath`를 추가한다. 테스트를 단순 `command`로 등록해서 ID 검사를 생략하지 않는다. 초기 구축용 자체 테스트·기존 shell 환경 검사만 명령의 종료 상태를 사용한다.

Node reporter는 테스트 판정과 assertion 오류·표준출력·표준오류를 보존한다. 결과는 `output/verification/<실행 ID>/`에 기록한다. 프로젝트에서 이 출력 경로와 빌드 산출물을 Git 제외해야 한다. 입력 범위는 코드뿐 아니라 테스트·설정·실행 연결부 및 의존 코드를 포함하도록 합의한다. 정상적인 파일 삭제도 입력 상태에 기록한다. 실행 전후 입력 내용, Git HEAD 및 게이트 원본이 달라지면 차단한다. 중간 변경 후 원상복구나 의도적인 우회까지 막는 격리 장치는 아니다.

종료 코드 `0`/`1`/`2`는 `passed`/`failed`/`blocked`다. 누락·skip·todo·0개·결과 손상·중복·환경 불일치·시간 초과는 차단한다. 실패와 차단이 함께 있으면 차단으로 보고하며 실패도 요약에 남긴다. 요구사항을 충분히 검증하는지는 사용자와 계획 검토에서 결정한다.

자체 회귀 검사는 `node --test tools/verification-gate/gate.test.mjs`로 실행한다. OutPick별 사용법과 연결 범위는 [검사 설정 안내](../../verification/README.md)를 따른다.
