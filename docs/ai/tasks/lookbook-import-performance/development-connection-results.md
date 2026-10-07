# Development 비교 연결 — D0~D3 구현·검증 기록

**현재 단계(2026-10-04):** 사용자가 다운로드4·변환1·업로드4를 유지한 다음 구현을 승인했다. [version2 네 구조20회+smoke1회 로컬 구현·검증 기록](development-network-implementation.md)과 [실행 대상·요청량·비용](development-network-comparison-plan.md)을 따른다. remote-contract/runner와 remote-campaign/report/target/CLI가 진입점이다. 이미지별 예약/R 연결은 보류했고 기존 결과는 보존한다. 배포·유료 실험은 미실행이다. 아래 ‘다음’과 AD2b 결정 대기는 이전 이력이다.

후속 방향 변경(2026-10-04): 사용자 지시로 [자원 기반 자동 조절 R 설계](adaptive-concurrency-design.md)를 추가했다. 아래 결과는 고정 P/S version1의 검증 이력이며 R 또는 새15회 행렬의 검증이 아니다. 다음은 R의 로컬 제어기 계획 검토다. 아래 D4 잔여 작업은 R 검토·연결 후 새 manifest로 갱신한다.

2026-10-04. **D0~D3 구현·필수 로컬 검증 완료.** 사용자가 P/S·128MiB·3부하·각5회 총30회 계약으로 로컬 구현과 필수 검사를 승인했다. [승인 계획](development-comparison-plan.md)을 따른다. Mac/Linux 각각278개·필수170개와 Firestore/Storage emulator4개가 통과했다. 실제 Cloud Run 배포·이미지 재다운로드·Storage/Firestore 원격 쓰기는 하지 않았다.

## 구현

| 책임 | 진입점 | 동작 |
| --- | --- | --- |
| 고정 계약 | `tools/lookbook-import-worker/src/performance/remote-contract.ts` | P/S 교차 30회, 개발 project/bucket, manifest digest, 허용 runID, 공유 단계 제한, 실행 timeout 범위 검증 |
| 고정 입력 | `tools/lookbook-import-worker/fixtures/performance-remote-input.json` | 기존 승인 로컬 자료에서 원격 URL·원본/출력 hash·bytes만 추출. 이미지 파일/자격증명 미포함. 파일 SHA-256 `307bdf7d1b90c04fbcc8ed16307aa7e2ed559cc008207eed8fd487cece676a10` 고정 |
| 공용 연결 | `performance/reuse-input.ts` | 기존 로컬 spy 유지, `ConnectedIO` 주입 시에만 실제 다운로드/저장 사용. 기존 dedupe·변환·커버 선준비·공유 scope와 같은 경로 |
| 원격 입출력 | `performance/remote-io.ts`, `remote-firebase.ts` | 공개 HTTP 검사와 중단 signal, 25MiB 입력 한도, 실제 원본 hash, 두 JPEG 저장 뒤 경로 기록, 실제 저장물 재조회. 객체 create-only·412 내용 대조, 임의 제품 경로 거부 |
| 실행권 | `performance/remote-store.ts` | Firestore transaction으로 한 회차만 claim. 고정 순서·중복·다른 owner 완료·입력 변경·만료 거부. 종료 미확인/중단은 자동 인계하지 않음 |
| 회차 실행 | `performance/remote-runner.ts` | 공유128MiB와 P4 정책, P/S 순서, 총5회 시도, 원격 오류 원인 기록, 실제 메모리 감독·정리·사후 검증·증거 저장. 입력 변경 같은 비재시도 오류는 모든 새 작업 및 다음 브랜드 시작 중단 |
| 서버 연결 | `config.ts`, `index.ts`, `server.ts` | `OUTPICK_IMPORT_REMOTE_CAMPAIGN` 미설정 시 기존 모드. 설정 시 개발 프로젝트/소스 일치 검증, `/experiments/lookbook-transfer`에 기존 Functions OIDC caller 요구. 실험 모드에서는 제품 wake/import/discovery/smoke route를 등록하지 않음 |
| 회귀·경합 | `performance/remote.test.ts`, `remote-fixture.ts`, `server.test.ts`, `config.test.ts`, `scripts/remote.emulator.mjs` | RC01~13 및 RD01~04. fake 원격 서비스+실제 JPEG, 실제 로컬 Firestore transaction·Storage/Firestore 규칙 검사 |

제품의 Swift 요청 API, Functions job 생성/trigger, 전역 브랜드 대기열, 제품 기본 저장 경로는 변경하지 않았다. 실험 데이터는 `lookbookImportPerformanceRuns`, `lookbookImportPerformanceCampaigns`, `lookbookImportPerformanceControl` 및 `lookbook-import-performance/` 객체 root로 분리한다. root가 분리됐다는 이유만으로 서버 권한이 제한됐다고 주장하지 않으며 adapter에서 project/bucket/path를 검사한다.

## 실행·관측 계약

- 단계 슬롯은 다운로드4·변환1·업로드4·경로저장 제한없음. 이미지 미완료4/시즌, 시즌 상한6, 재사용128MiB·커버 선준비. S의 합성3브랜드×2시즌 입력은 실제 최대2시즌 동시 실행이다.
- 시즌 실제 시도 총5회, 사이 대기1초. 이미지 내부 시도 최대3회, 사이400/800ms·각20초 timeout. 초기 비교 계약이며 최적값 판정이 아니다.
- Storage SDK 자동 재시도 off·쓰기/읽기20초. Firestore GAX RPC20초·GAX 자동 retry code 없음·transaction 최대5회. Firestore 상위 stream/transaction과 실제 RPC 수는 adapter 호출 수와 구분한다. 취소 불가능한 SDK 호출은 반환까지 기다리며 이 설정을 전체 프로세스 강제 종료 보장으로 해석하지 않는다.
- 캠페인2시간 및 manifest 만료 확인, 개별 run timeout은 실행안에서1~840초 범위로 지정한다. 현재 서비스900초보다 짧게 제한했다. 비용US$10 감독·정확한 배포 제한은 D4 실행안/외부 실행 제어에서 연결해야 한다. 코드만으로 청구 상한을 보장하지 않는다.
- 결과는 회차별 `result.json`에 성공/실패/중단/환경 미준비, 원인, 단계·브랜드 시각, 첫 시즌/첫 브랜드/전체 시간, 원격 호출/bytes, 메모리·scope·slot, 업로드 확인 파일·시도한 파일·DB 경로를 남긴다. 응답 유실로 결과 확인이 안 되면 같은 runID를 재실행하지 않는다.
- 해시·저장물 불일치와 재시도 소진을 포함해 비성공 회차는 캠페인을 멈춘다. 다음 회차를 새 캠페인으로 자동 우회하지 않으며 남은30회 계획의 미수행 분모는 후속 집계에서 보존한다. 실제 실험 실행기/비용 감독·최종 집계는 D4 범위다.
- 메모리 감독은 준비·측정·사후 파일/경로 검증 구간을 포함한다.100ms/500ms/85%1초 계약을 유지한다. 결과 JSON은8MiB로 제한해 측정 종료 뒤 기록한다. 결과 저장이나 최종 상태 반영 실패 시 실행권을 해제하지 않는다.
- CPU/메모리를 보고 동시성을 자동 증감하는 기능은 구현하지 않았다. 두 고정 구조의 원격 비교를 먼저 수행한다.

## 필수 검증

검사 코드 상태: HEAD `1d67d61faa04984783083971688a7c628df74748` + 현재 작업 트리. 각 게이트 입력 범위가 달라 digest는 서로 다르다.

| 검사 | 원본 summary | 상태·범위 |
| --- | --- | --- |
| Mac Worker | [1791061081185-a3837756-821f-4a32-b7ee-945ddbbbeba1](../../../../output/verification/1791061081185-a3837756-821f-4a32-b7ee-945ddbbbeba1/summary.json) | passed. lint·TypeScript build·전체278개/필수170개·추출 fixture. digest `cdc499c0dc42d15e2fa1ed5ca9170e1c36137deb7845867220966fdd5b2e135e`,173파일 |
| Firestore·Storage emulator | [1791061033545-2c04c1f1-b5fe-426c-906d-61d234642c7b](../../../../output/verification/1791061033545-2c04c1f1-b5fe-426c-906d-61d234642c7b/summary.json) | passed. build 및 RD01~04 전체4개/필수4개. digest `f9a44666896797ee5d8d531531588f21fa818396a95f924c3b4a4adf43399512`,177파일 |
| Linux Worker 최종 | [1791061149533-18f64e05-4855-4739-9499-b2c9e69e86cc](../../../../output/verification/1791061149533-18f64e05-4855-4739-9499-b2c9e69e86cc/summary.json) | passed. lint·TypeScript build·전체278개/필수170개·추출 fixture. digest `c546eaadc01db9cbaba0e6746f23802dc2a1edb2fbae821e677c60ece7d25749`,177파일 |

Linux 최종 검증 이미지: `sha256:9da9eda38eaeea0a9664c4aa370f87e394b409eb7fc91f78e952f9604bc88705`. 기존 로컬 고정 이미지를 바탕으로 `--network=none` 빌드했다. 검사 컨테이너는1CPU/2GiB·추가 swap 없음·네트워크 없음이며 실험 속도 측정 컨테이너와 구분한다. 실제 Cloud Run 배포용 이미지 검증/원격 성능 통과를 의미하지 않는다.

명령:

```sh
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-remote.json
node tools/verification-gate/gate.mjs --project . --config output/lookbook-import-performance/remote-linux-gate.json
```

Node24 PATH 및 Mac의 로컬 포트/Docker 접근이 필요하다. 에뮬레이터는 `firebase.lookbook-performance.json`과 `scripts/run-remote-emulator.mjs`로 `demo-lookbook-performance`의127.0.0.1:8085/9195만 사용한다. 필수 테스트는 skip/0개/원본 결과 누락을 통과시키지 않는다.

확인한 핵심 실패 경계: 부분 업로드 실패 시 형제 종료 대기와 경로 미기록, 응답 유실 후 create-only 충돌 검증, 저장물 손상 거부, 실제 fetch 취소, 원본 변동 시 다음 브랜드 차단, 중복 요청 경합, 이전 owner 종료 거부, 미확인 실행의 만료 자동 인계 금지, 인증된 클라이언트의 실험 데이터 접근 거부.

## 실패·수정 이력

- 초기 Worker 게이트 `1791060249697-41b16708-63a9-4ebb-ac01-23569a3839ed`:275개 테스트는 통과했으나 lint 줄 길이2곳 실패. 해당 줄을 수정했고 실패 기록은 보존했다.
- 초기 emulator 게이트 `1791060397745-93539c5b-2e83-4440-ac8f-7803a531b66c`: Firebase CLI가 설정 디렉터리 밖 rules 경로를 거부했다. 테스트0개·결과 누락을 blocked로 기록하고 설정을 프로젝트 루트로 이동했다.
- 중간 Mac/Linux277개 통과 뒤, 원본 변동을 일반 시즌 실패로 취급하면 S의 다음 브랜드까지 시작할 수 있는 경계를 보완했다. RC13을 추가하고 최종278개 코드의 게이트를 다시 실행했다. 중간277개 결과를 최종 코드의 통과로 재사용하지 않는다.
- 외부 사이트 재요청·원격 Cloud Run/Storage/Firestore 쓰기 없이 코드 수정·가짜 원격 adapter·로컬 emulator로 검증했다.

## D4에서 남은 일

1. 최종 코드/검사 결과 분석, 정확한 Development 후보 리비전·이미지·인증 호출자·버킷 위치·기존 트래픽 격리·CPU/메모리/인스턴스 설정 확인.
2. 고정 입력의 실제 URL 품질 확인과30회 연결 전송 비교를 분리한 실행 manifest, 준비를 포함한 최대45회·2시간·추정US$10 감독, 예상 작업/bytes/비용·중단·복구 절차 제시.
3. 실제 Cloud Run cgroup·표본 간격·원본 변화·OIDC/Storage/Firestore 권한 준비 확인. CPU 아키텍처/라이브러리 차이로 출력이 달라지면 원인 검토 전 기대값을 갱신하지 않는다.
4. 배포·실험 실행안 사용자 확인 후 원격 검증. 무응답 Worker의 실행 종료가 확인되지 않으면 캠페인을 중단하며, 남은 회차를 자동 재실행하지 않는다.
5. 결과로 제품의 P/S 구조와 대기열 계약을 확정한다. 현재 구현은 제품 글로벌 FIFO나 관리자 검토 이후 자동 복구의 검증을 대신하지 않는다. 데이터 삭제와 운영 배포는 별도 승인이다.
