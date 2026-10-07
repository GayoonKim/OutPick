# 시즌 실행·중단 감독 구현 상태

2026-10-03. 사용자 ‘진행해도 문제 없으면 진행’에 따라 승인된 로컬 비교의 시즌 순서와 메모리 중단 감독을 구현했다. **54회 실험 실행과 A~F 전체 측정 도구의 완성은 아직 아니다.** 컨테이너 실행 환경은 사용자가 ‘로컬 Linux 컨테이너 실행안을 먼저 제시’를 선택해 [별도 검토안](local-container-proposal.md)으로 정리했다.

## 구현과 연결

- `tools/lookbook-import-worker/src/performance/season-runner.ts`: 시즌 병렬 또는 브랜드 내 입력 순서 유지·브랜드 간 병렬. 전체 실행 폭은 호출자가 명시한다. 검토 대기·최종 실패이면 다음 시즌으로 넘어가고, retryable일 때만 최초 포함 총 5회까지 호출한다. 재시도 대기 중에는 해당 브랜드 순서를 유지한다. 대기 시간은 실행 결과의 `retryAfterMs`로 받으며 임의 5분 한도는 없다.
- 결과는 입력 순서로 유지한다. 실제 호출마다 시도 번호·시작/종료·반환 상태를 기록한다. 미시작/대기 중 취소는 시도를 추가하지 않는다. 중단 때 모든 시즌 결과를 보존하며 실행 중 작업이 뒤늦게 성공했어도 실험 시즌 결과는 aborted이고 해당 시도 기록은 succeeded로 구분한다. 알려지지 않은 예외·잘못된 결과는 자동 재시도 대상으로 만들지 않는다.
- `performance/memory-supervisor.ts`: 컨테이너 전체 사용량/한도를 100ms 주기로 읽는다. 유효 표본에서 비율 85% 이상이 1초 유지되면 공용 AbortSignal을 중단한다. 최초 표본 미지원/오류는 작업을 시작하지 않는 unavailable, 도중 표본 누락·읽기 지연·한도/소스 변경·역행 시계는 environment 중단이다. `maxSampleGapMs`는 필수 인자이며 제품 기본값은 없다. 테스트의 500ms는 실험 채택값이 아니다.
- 메모리 읽기는 겹치지 않는다. 읽기가 멈추어도 주기 감독이 간격 초과를 판정한다. 늦은 표본은 중단 결과를 바꾸지 않는다. 완료 직전에도 표본을 확인한다. 이미 실행 중인 작업을 Promise.race로 버리지 않고 실제 종료 후 결과를 확정한다.
- `pipeline/scheduling.ts`의 선택적 signal은 다음 묶음/빈자리 작업 시작을 막는다. `PipelineRuntime.signal`은 모든 단계 슬롯에 전달되고 개별 호출 signal과 함께 적용된다. 대기 permit은 취소하며 실행 중 permit은 실제 Promise 종료까지 유지한다.
- `extraction/dedupe.ts`, `processor.ts`의 실험 실행 정책 경로가 위 signal을 전달한다. 기본 runtime 미설정 경로와 제품 API/Firestore 필드는 유지한다. index/HTTP 설정에서 감독기나 새 runtime을 켜는 경로는 추가하지 않았다.

## 한계

이 실행기는 로컬 callback 호출을 센다. 실제 Cloud Tasks 재배달, claim/stale, 관리자 검토 재개/수동 재시도/asset 재시도의 제품 횟수 계약과 분산 브랜드 순서를 구현한 것이 아니다. Phase 4에 남긴다.

메모리 감독은 표본 기반이다. 표본 사이의 모든 순간이나 정지된 Node 이벤트 루프에서 즉시 취소를 보장하지 않는다. 이미 시작한 sharp/SDK 요청은 강제 종료하지 않는다. 급격한 OOM/프로세스 강제 종료를 누락하지 않으려면 컨테이너 밖 실행기가 종료 코드·OOMKilled·누락 결과를 기록해야 한다. 외부 감독기는 아직 미구현이다. 메모리 안전 표본과 작업 종료 대기는 별도 개념이다.

## 검증

테스트 설계: 시즌 순서·재시도·취소는 제어 가능한 Promise/wait, 메모리 지속 시간·누락·지연은 fake 시계/표본, 저장 중단은 실제 runSyncTargets/JPEG와 fake Storage/Firestore로 재현했다. 실제 컨테이너 제한과 클라우드 연동은 이 테스트가 대신하지 않는다.

Node 24.19.0에서 `node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json` 실행. 결과: **passed**, lint·build·전체 테스트 **184개**, 필수 ID **76개**, 추출 fixture 통과. 이번 신규 필수 18개는 시즌 실행 7, 메모리 감독 8, 묶음/슬롯 중단 2, 실제 저장 중단 1이다. 최초 lint 실행의 긴 줄 오류 1건을 수정한 뒤 전체 게이트를 실행했다.

- 원본: `output/verification/1791003698641-db9c1e94-013e-4808-a142-874d4e0794e8/summary.json` 및 같은 디렉터리 검사 로그.
- HEAD: `1d67d61faa04984783083971688a7c628df74748` + 작업 트리.
- source digest: `6674541e7b420ce8870c60c31f756c37a7f57823786cfe8b6ba01cadc187e644`, 121파일.
- 위 실행 이후 Worker 코드·검사 설정을 바꾸지 않았다. 문서 갱신은 게이트 입력에 포함되지 않는다.

실제 저장 중단 검사는 두 JPEG 업로드가 실행 중인 시점에 취소한다. 업로드 2개의 종료를 기다리고 경로 쓰기 0, ready 미설정, 활성 슬롯 0, scope 종료 보관 0을 확인했다. Memory supervisor→season runner 연결 검사는 시작한 시즌과 미시작 시즌을 모두 aborted로 남기고 미시작 시도 0회를 보존한다.

## 다음 범위

1. 컨테이너 실행안·초기 manifest 검토. 설치/실행은 아직 하지 않았다.
2. A~F 정책과 실제 추출→검토/승인 후 저장의 분리 측정 연결, 중간 Buffer/JPEG 보유량 관측, 외부 컨테이너 종료 감독, 회차 manifest/집계/판정 연결.
3. 동일 Linux 이미지에서 필수 게이트·입력 hash/JPEG 정합성·환경 preflight. 준비 실행과 계측 오버헤드 회차를 별도 기록한다.
4. 위 조건을 갖춘 뒤 54회 탐색. 현재 Mac의 기존 준비 측정을 해당 실험이나 새 코드의 오버헤드 검증으로 재사용하지 않는다.
