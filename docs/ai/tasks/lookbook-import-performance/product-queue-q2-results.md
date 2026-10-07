# 제품 룩북 대기열 Q2 — 묶음 실행권 구현 기록

2026-10-05 당시 Q2 구현 snapshot과 그 시점의 gate를 기록한다. 아래 “남은 Q2 작업”과 당시 최신 상태는 역사적 기록이다. discovery/continuation activation, Functions dispatch 연결, 14분 HTTP 응답 경계, 전체 최신 gate 통합은 Q6에서 후속 완료했다. 현행 통합 결과와 실제 남은 범위는 [Q6 결과](product-queue-q6-results.md)를 기준으로 한다. 실제 Development/Storage 호출이나 배포는 수행하지 않았다.

## 추가 — 구형 실행 경로의 큐 우회 차단

2026-10-05. 기존 Worker 진입점이 queue 소유 job을 batch 실행권 없이 claim/update하지 못하게 보호를 추가했다.

- `queue/ownership.ts::isQueueOwnedJob`은 `queueContractVersion`, `queueBatchID`, `queueExecutionID`, `dispatchMode=batchQueue`, `queueActivationRequired` 중 일부만 남은 문서도 큐 소유로 판정한다. `/wake`의 대상 검색에서 제외하고 import/discovery 단건 claim은 batch 실행권을 요구한다.
- `claimJob`의 큐 실행 분기는 실행권 확인과 같은 Firestore transaction에서 현재 queue head·batch owner/epoch/runID, batch item ordinal/jobID/executionID, active execution/runID, root job 식별자를 대조한다. 불일치면 root 상태를 쓰지 않는다. 최신 `processImportBatchTaskRequest`가 이 분기를 통해 기존 `processJob`를 실행한다.
- 기존 asset-failure retry와 discovery task도 큐 표식이 있는 job을 읽기 후 skip하거나 claim을 거절한다.
- Worker 단위검사 `PQ10` 두 개를 추가했다. 부분 표식 분류와 구형 개별 task의 queue-owned import claim/update 차단을 검사한다. Discovery claim 검사는 두 queue 표식 조건을 추가로 거절한다.

구형 경로는 queue-owned job을 단독 처리하지 않는다. 이 문단 작성 시 batch route는 있었지만 Functions Cloud Tasks 송신 함수는 export/trigger에 연결되지 않았다. 그 연결 상태는 뒤의 Q6 추가 기록이 갱신한다. 재시도 정책은 변경 없이 대기 없이 즉시, 최초 시도를 포함해 총5회다.

## 구현

`tools/lookbook-import-worker/src/queue/coordinator.ts`:

- `parseBatchDelivery`: batchID/dispatchGeneration/queueContractVersion만 허용한다. 클라이언트가 owner/epoch를 정하지 않는다.
- `claimBatch`: 현재 head, 준비 완료, 전달 세대, retry 예정 시각, 비어 있는 실행권을 transaction으로 확인한다. owner/bootID/증가 epoch와 runs 문서를 함께 저장한다. 같은 Worker ID의 중복 전달도 다시 실행권을 주지 않는다. 시간 경과는 owner를 빼앗는 근거가 아니다.
- `readOwnedBatch`: 이후 checkpoint와 공개 쓰기가 사용할 transaction 내부 실행권 검사다. 큐와 batch의 owner/epoch/runID, 프로세스 bootID 및 active/draining 상태를 대조한다. 별도 읽기 뒤 무조건 update하는 패턴을 사용하지 않는다.
- `heartbeatBatch`/`beginBatchDrain`: 실행권을 확인하며 갱신한다. heartbeat는 실제 진행 fingerprint에 포함하지 않는다.
- `writeBatchProgress`: 실행권으로 검증된 progress 문서에 영속 진행 값만 기록한다. 실제 processor의 phase/저장 checkpoint와 같은 동작 단위로 연결하는 일은 후속이다.
- `finishBatchRun`: draining 상태에서만 종료를 기록한다. 남은 작업이나 정리 미확인이 있으면 recoveryRequired로 유지하며 owner를 자동 해제하지 않는다. 정상 continue/retry는 같은 head와 새 전달 세대를 사용한다. 완료는 created 항목의 실행/continuation이 종료 또는 검토 대기 상태인지 추가로 확인한다. 영속 progress가 정상 두 구간 연속 바뀌지 않으면 복구 확인으로 멈춘다.
- `advanceReleasedHead`: released와 실행 run의 종료 확인을 대조한 뒤 정확히 다음 sequence로 이동한다. 전부 중복/접수 실패처럼 실행 run이 없는 released batch도 처리한다. 다음 순번이 비어 있는데 더 뒤 순번이 있으면 임의 추월하지 않는다.

`runs/{runID}`에는 owner/bootID/epoch, 시작/heartbeat/종료 시각, 종료 확인 여부, 남은 작업 수, 종료 disposition/fingerprint를 보관한다. `progress/{key}`는 phase/공개된 산출물 집합 등의 값이며 단순 timestamp를 진행으로 사용하지 않는다. Q4의 보관/복구 대상이다.

`queue/checkpoint.ts`는 시즌 execution의 `attempts/{00001...}` 원장과 batch item 진행 상태를 실행권 확인 transaction에 함께 쓴다. 활성 중복 호출은 두 번째 attempt를 시작하지 않는다. batch runner는 retryable 오류 직후 `retryWaiting`과 현재 시각을 기록하고 다음 attempt를 즉시 시작한다. 최초 포함 총5회에 도달하면 기존 processor가 최종 실패로 닫는다. 승인 continuation은 같은 execution의 attemptCount를 보존하고 별도 attempt를 만들지 않는다. `runtime.ts`는 묶음 하나의 PipelineRuntime을 만들며 시즌 동시성6, 다운로드4, 변환1, 업로드4, 경로 저장 제한 없음, 원본 재사용 예산128MiB를 주입한다. `runQueueBatchItems`는 한 묶음 최대80시즌, 최대6시즌 동시 실행을 보장하고 취소 후 새 시즌 투입을 멈추며 이미 시작한 promise가 끝날 때까지 기다린다.

`finishBatchRun`의 완료 검사도 강화했다. continuation과 원본 execution 문서가 둘 다 terminal이어야 차례를 넘긴다. continuation 하나만 succeeded여도 execution이 남아 있으면 종료를 거부한다.

## 검증 설계

- Worker 단위4개: 전달 입력 위조/세대 계약, 진행 fingerprint 안정성, 제품 runtime 자원 한도, 취소 후 실행 중 시즌 drain.
- 제품 큐 Emulator40개에8개 추가: 기존 독립 Admin SDK 클라이언트 동시 선점·시간만 지난 owner 유지·epoch 재개/쓰기 거절·drain·무진행·정확한 head 전환 5개와 attempt/retryAt 원장·승인 시도 보존/stale epoch 거절·continuation 단독 종료 차단 3개.
- 같은 프로세스의 독립 SDK 클라이언트로 실제 Firestore transaction 경합을 검사한다. Linux 독립 Worker 프로세스 실행이나 실제 이미지 업로드 검증은 아니다. 실행의 저장 완료 상태는 fixture로 명시했다.
- G-W는 기존 Worker lint/build/전체 테스트/추출 fixture를 유지하고 단위2개를 필수 목록에 추가했다. G-E는 Worker build를 추가하고 실제 queue 소스를 입력 digest에 포함했다.

## 당시 남은 Q2 작업 — Q6에서 연결 완료

1. Functions의 `deliverQueueHead`를 실제 Cloud Tasks 생성 어댑터/trigger에 연결하고, task deadline·retry policy와 전달 유실 복구를 검증한다. 아직 task는 송신하지 않는다.
2. `discoverSeasons`, 승인/수동 재시도, asset 재시도, repair batch 실행 입력을 각 기존 processor로 안전하게 연결한다. 현재 runner는 `importSeasons`만 지원하며 나머지는 claim 전에 거절한다.
3. 시간 경계의 강제 보장을 완성한다. 12분은 새 시즌 투입을 중단하지만 현재 실행 작업은 기다린다. 14분은 현재 drain 초과 evidence만 기록할 뿐 응답을 강제 종료하지 않는다. 따라서 14분 응답 완료와 15분 외부 제한을 아직 만족했다고 볼 수 없고, 단계별 취소/저장 경계와 최대 drain 시간 검증이 필요하다.
4. 메모리 표본 누락·85% 초과 시 새 시즌 유입 중단/복구 확인 동작을 실제 Linux1CPU/2GiB container에서 검증한다. 현재 실행 중 processor를 강제 취소하지 않고 drain하므로 종료 지연도 검사해야 한다.
5. Q3의 실행별 storage 경로·조건부 공개·미공개 asset 보존 및 브라우저 gate를 구현하기 전에는 batch route를 제품 전달에 연결하지 않는다.

Q3의 조건부 이미지 공개가 준비되기 전 새 큐를 실제 제품 경로에 활성화하지 않는다. 배포·Cloud Tasks 송신·실제 Storage 변경은 수행하지 않았다.

## 검증 결과

초기 G-W `1791192467667-b618679e-0a75-4eec-8980-56409eaf9ac9`는 lint5건과 기존 HTTP 테스트5개의 로컬 listen EPERM으로 실패했다. 신규 코드 형식을 수정하고 승인된 로컬 서버 검사 권한으로 동일 게이트를 다시 실행했다. 실패 로그는 보존하며 테스트를 제거하거나 skip하지 않는다.

| 게이트 | 실제 결과 | 원본 결과 |
| --- | --- | --- |
| G-W `verification/lookbook-import.json` | passed: lint/build, 테스트327개, fixture. 실패·취소·skip0, 기존 lint 경고70개 | [이번 결과](../../../../output/verification/1791195491312-64f3c793-f52f-4a50-ab58-008a39ec2503/summary.json) |
| G-E `verification/lookbook-product-queue.json` | passed: Worker/Functions build, Emulator 테스트48개. 실패·차단0 | [이번 결과](../../../../output/verification/1791195628640-36db0d30-fc6d-4400-877d-e941f3f3cb13/summary.json) |

검사 HEAD는 `1d67d61faa04984783083971688a7c628df74748`이며 미커밋 변경을 포함한다. 이번 G-W 입력 digest는 `194a7b0ab4b4b4ddc58374d2be5386e7451178468d0bb90f9bac19306f529bc4`, fileCount210이고, G-E는 `49021bafafad49649d88e11246fe353d5e0383b5331fd2ec201c938aecc52d5a`, fileCount254다. 검사 범위가 달라 digest도 다르다. 원본 로그는 실행 디렉터리에 보존했다. 이전 snapshot G-W 325/G-E 48은 [Worker](../../../../output/verification/1791194046657-c2cd2164-659d-45b9-9864-e565339d6e9a/summary.json), [Emulator](../../../../output/verification/1791194183548-105a6aab-e57c-43a7-8f21-5361e80a2052/summary.json)에 남아 있다. 이번 G-W를 처음 실행한 기본 셸 시도는 Node24를 찾지 못해 필수 검사 미실행으로 blocked 됐고, [원본 결과](../../../../output/verification/1791195474743-cc9dabbc-2522-4e23-b43e-6761f4c1ca87/summary.json)를 보존했다. Node24 경로를 지정한 실행은 위처럼 통과했다.

이전 결과 표는 batch runner/supervisor 전 단계의 이력이다. 최신 코드의 필수 게이트 결과는 아래 최신 추가 절에 기록한다. Linux 프로세스 종료·OOM, 실제 Storage 전송, Cloud Tasks 송신, Development 동작은 로컬 게이트에 포함되지 않는다. 이전 통과를 최신 코드나 제품 end-to-end 통과로 재사용하지 않는다.

## 당시 추가 — 기존 import processor 연결·즉시 재시도·감독

- `queue/batch-runner.ts::processImportSeasonsBatch`는 지원 kind를 claim 전에 확인한 뒤 현재 FIFO head 실행권을 얻고 `importSeasons`의 created 항목만 최대6개 병렬 투입한다. 항목 준비 상태/ID/최대80개 계약이 손상되면 완료로 건너뛰지 않고 `recoveryRequired`로 멈춘다. 중복·실패·skip 항목은 새 processor를 시작하지 않는다.
- `processor.ts::processImportBatchTaskRequest`가 root job의 dispatch generation과 queue execution token을 기존 `processJob`로 넘긴다. 각 시즌의 shared runtime은 다운로드4·변환1·업로드4·경로 무제한·128MiB를 사용한다. item attempt와 root claim은 현재 epoch에 fence된다.
- 자동 재시도는 최초 시도를 포함해 총5회이며 재시도 대기시간은 두지 않는다. retryable 오류 후 `retryAt=현재 시각`을 원장에 기록하고 같은 묶음 실행에서 바로 다음 시도를 시작한다. 정상 12분 분할은 retry attempt를 늘리지 않는다.
- `/tasks/import-batch`는 Cloud Tasks OIDC로 보호되며 SIGTERM/연결 종료 신호는 새 시즌 투입을 멈춘 뒤 실행 중 promise를 기다린다. 다른 batch kind는 HTTP 503으로 돌려보내고 claim하지 않는다. Functions `deliverQueueHead` helper의 payload 이름은 `queueContractVersion`으로 Worker 계약과 맞췄지만 실제 Cloud Tasks sender/trigger는 연결하지 않았다.
- `queue/supervisor.ts`는 Linux cgroup의 작은 파일을 동기 표본으로 100ms마다 읽는다. 85% 이상 1초 지속, 시작 표본 85% 이상, 표본 공백 500ms 초과/환경 불명확은 새 시즌 투입을 중단하고 복구 확인으로 남긴다. 12분에는 새 시즌 투입을 멈춘다. 14분 drain 목표는 현재 초과 evidence만 기록하며 강제 응답 마감은 보장하지 않는다. Cloud Tasks helper에 900초 전달 deadline 값은 있지만 실제 queue/Cloud Run 배포 설정은 확인하지 않았다.
- 메모리/시간 중단 외에는 현재 시즌을 끝까지 기다린다. 확인된 drain이 없으면 owner를 해제하지 않는다. 따라서 in-flight SDK 요청 취소, 14분 안의 drain 보장, Cloud Run 15분 종료 경계는 Linux 필수 게이트와 후속 Q2 수정 대상이다.
- 제품 전달/배포/실제 URL·Storage 요청은 하지 않았다. 이 코드는 일반 season import의 로컬 실행 연결이며 discovery, continuation, conditional asset publication이 포함된 전체 제품 FIFO가 아니다.

## Q2 당시 필수 게이트 결과(2026-10-05)

| 게이트 | 결과 | 원본 |
| --- | --- | --- |
| G-W `verification/lookbook-import.json` | passed. lint/build/fixture 성공, 전체 Worker 테스트332개, 실패·취소·skip0. 기존 lint 경고70개 | [summary.json](../../../../output/verification/1791198150647-0f15e6f2-d818-49c2-ab7b-b2ec8423b7a4/summary.json) |
| G-E `verification/lookbook-product-queue.json` | passed. Worker/Functions build, Firestore Emulator52개, 실패·차단0 | [summary.json](../../../../output/verification/1791198279396-73ac1726-eae9-4ede-98ac-890760e2fc16/summary.json) |
| G-F `verification/functions.json` | passed. lint/build, Functions307개. 이 실행 뒤 Functions source/config는 수정하지 않았고 이번 G-E에서도 최신 Functions build가 통과 | [summary.json](../../../../output/verification/1791196784149-926d2a92-fa13-43cd-941d-dd70faae15ba/summary.json) |

최종 G-W source digest `87e4612eae07e998917ac2cce62c2f17cf4d59329316201b97f40e365d8e6fb5`/213 files, G-E digest `0ec32be3058a918b70c97d1556291b1b6c0702ab67d23245bca8aab1a347af60`/264 files다. G-F digest는 `8e87c5b40536b19a4c98080d4ea09d0df9fb084c614bd57b8dadb6825475ddb7`/259 files다. G-W의 앞선 실행은 초과 표본 테스트가 경계 100ms 부족으로 1개 실패(331/332)했고, 테스트 표본을 11회로 맞춘 재실행에서 모두 통과했다. 실패 원본도 `output/verification/1791198004231-a799d488-343b-4820-bf57-5ca409805aa9/summary.json`에 보존했다. Emulator의 권한 거절 로그는 rules negative test의 예상 출력이며 필수52개는 모두 통과했다.

실제 HTTP·Storage 다운로드/업로드, Cloud Tasks 송신, Linux1CPU/2GiB의 OOM·SIGTERM·14분 강제 drain, Cloud Run의 실제 15분 설정, Development 동작은 아직 실행하지 않았다. 이번 성공은 로컬 필수 게이트 통과이며 Q2 전체 또는 제품 FIFO 활성화 완료를 뜻하지 않는다.

## 후속 통합 상태 — Q6 (2026-10-06)

Q6에서 `discoverSeasons`, `assetRetry`, `reviewApproval`, `manualRetry`, `repair`를 포함한 queue batch activation을 연결하고 continuation의 최초 활성화만 도메인 변경을 수행하도록 했다. Asset retry는 child job 실행/source claim을 사용한다. `/tasks/import-batch`의 14분 경계는 retryable 503 응답과 abort/admission stop을 적용하고 processor promise가 drain될 때까지 handler 실행을 기다린다. Functions queue dispatch 경로와 batch-kind activation은 Emulator에서 검증했다. 전체 최신 G-F/G-W/G-E/G-R/G-L/G-I gate IDs/digests와 실제 미검증 범위는 [Q6 통합 결과](product-queue-q6-results.md)에 있다. Cloud Run 15분 실제 종료, 원격 Cloud Tasks 재전달, Development URL/Storage 및 IAM은 확인하지 않았다.
