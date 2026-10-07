# 제품 룩북 대기열 Q1 — 공통 접수 계층 진행 기록

## 추가 구현 — 나머지 접수 경로와 준비 자동 실행 (2026-10-05)

사용자가 요청한 Q1의 주요 접수 연결과 준비 이벤트를 구현했다. 최신 실제 결과는 본 절을 우선하며 아래 이전의 ‘미연결’ 표시는 당시 이력이다. Q1의 접수·준비 동작과 Q2 이후 실제 실행/저장/복구를 구분한다. 배포하지 않았다.

| 변경 진입점 | 구현 |
|---|---|
| `queue/followup-admission.ts` | 검토 승인, 수정 후 수동 재시도, 보수 분석/적용을 최신 요청 envelope와 같은 FIFO 영수증으로 접수 |
| `queue/discovery-admission.ts` | 목록 탐색 두 진입점, 같은 탐색 job 재시도, 수정 후 재분석 접수. 기존 권한/runtime 조건 유지 |
| `shared/lookbookQueue/{model,admission}.ts` | continuation 입력/기존 execution 참조, 접수 transaction의 review/trust 기록 commit hook |
| `queue/preparation.ts` | 같은 승인 execution 이력 보존, 새 재시도 execution, source snapshot 비교, 준비 중 root/season/post 미변경 |
| `queue/preparation-runner.ts` | preparationSequence의 한 batch만 선점. 항목 반환 후 준비 회차/오류 기록, 총5회 한도·부분 성공 보존 |
| `queue/preparation-functions.ts`, index | preparing 이벤트와 준비 순번 변경 이벤트. 중복/불명확 owner 선점 금지. 신규 trigger2개 포함 export123개 |
| `functions.ts`, `seasonDiscoveryJobs.ts` | 기존 직접 재실행/보수 저장 대신 접수 adapter 연결. 부족 판정·후보 해석·보수 preview 등 새 실행이 없는 경로는 기존 흐름 유지 |

검토 승인은 같은 execution의 시도 이력을 유지한다. legacy job은 결정적 승인 execution으로 옮기되 root의 기존 시도 수를 보존한다. review에는 승인 executionID를 고정해 root가 이후 다른 실행을 가리켜도 중복 승인이 원래 실행을 참조한다. 준비가 소진됐어도 같은 승인 내용의 새 요청은 현재 동일 snapshot에서 준비를 다시 시도할 수 있다. 자동으로 새 요청 ID를 만들지는 않는다.

`executions/{id}/continuations/{batchID}`에 mode/input/expected/status를 저장한다. 수동 재시도/보수는 새 execution이며 import는5회, discovery는 기존3회를 유지한다. 실행권 획득·root 활성화·실제 쓰기는 Q2/Q3다. 준비 source claim은 pending continuation도 중복으로 판단한다. 준비 시나리오는 모든 시작한 item의 반환을 기다리며, 이전 owner가 남아 있으면 자동으로 교체하지 않는다. 프로세스 강제 종료 뒤 복구 상태 표시는 Q4의 누락 점검/복구에 연결해야 한다.

### Q2/Q3가 이어받아야 하는 계약

| 입력 | 자기 차례에서 수행할 작업 |
|---|---|
| reviewApproval | expected snapshot/권한을 다시 확인, 같은 execution·attemptCount 유지, 승인 keys로 materializing만 재개. continuation 완료 상태 갱신 |
| manualRetry | 새 execution과 예산 활성화, parsing 또는 discovery 재시작·기존 실패/검토 요약 초기화, 이전 실행 이력 보존 |
| repairAnalyze | season/job 연결 재확인 후 예약 repairGeneration으로 분석 시작 |
| repairApply | repair generation/hash·season/post 상태 재확인 후 고정 plan을 실행권으로 적용하고 조건부 공개. 접수/준비 단계는 게시물을 수정하지 않음 |
| 새 discovery seed | generation은 접수 때 예약됨. 중복 접수로 번호가 비어 있을 수 있으므로 연속 번호나 lastGeneration과의 단순 동등성을 실행 조건으로 사용하지 않음. 자기 차례의 active pointer/공개 snapshot 전환 필요 |
| reanalysisSource | 원본 job/generation/hash 재확인 뒤 superseded/resolvedByJobID와 기존 후보 보관 정책 반영. 접수 때는 이전 검토 자료를 유지 |

취소는 기존 협조적 상태 전이를 유지하며 Q2가 활성화/종료 때 취소 상태를 확인해야 한다. 진단 경로의 브라우저 자원 통제는 Q3 범위로 남는다. Cloud Tasks sender/intent는 구현돼 있으나 새 Worker route가 없는 현재 제품 자동 전달은 활성화하지 않았다. 준비 trigger를 실제 배포한 것도 아니다.

### 필수 검사 범위와 중간 기록

기존28개에 준비 이벤트/총5회/owner, 승인 같은 실행/원본 참조/snapshot 변경/준비 소진 재접수, 수동 재시도 권한, 보수 불변, 탐색 두 진입점/3회/재분석 원본 보존 등12개를 추가해40개를 필수 목록에 연결했다. 실제 callable `.run`, event handler `.run`, Firestore Emulator transaction을 사용한다. Worker가 완료한 상태는 해당 검사에서 명시적으로 fixture로 만들었으며 Worker 실행을 검증했다고 주장하지 않는다.

중간 실패 로그는 보존했다. `1791190383647-09394a70-b7d8-401a-9ada-729ecd200a4c`는 lint 형식5건과 신규 trigger를 callable 목록에 넣은 메타데이터 오류, `1791190438626-454f55bb-0d1f-48d7-be66-52e4cd1d7b65`는 새 expected 타입의 memory 필드 누락으로 build/테스트0 차단, `1791190456106-944a0205-5690-4b6b-89a5-21eba6b861d0`와 `1791190480872-ec3460c8-bf73-4b4e-8ea2-029c97a098d3`는 신규 trigger 기본 memory 및 static document filter 표현 차이였다. 기존 trigger 기대값은 유지하고 신규 trigger를 올바른 Firestore 목록/정확한 SDK 필터 위치로 연결했다. `1791190856611-19e3c151-68e3-4bf6-84a4-ce9dc2b62e10`의 추가 lint1건도 수정했다. 기준 완화나 기존 테스트 제거는 하지 않았다.

최종 원본은 다음과 같다. HEAD `1d67d61faa04984783083971688a7c628df74748`의 미커밋 작업 트리를 검사했으며 정확한 입력 digest·실행 로그는 각 summary.source와 실행 디렉터리에 보존했다. 이전36개/39개 통과는 변경 전 중간 기록이며 최종 코드 통과로 재사용하지 않는다.

| 최종 게이트 | 결과 | 원본 |
|---|---|---|
| Functions | lint/build·307개, 실패/차단0 | [summary](../../../../output/verification/1791190909995-1c0923e2-b071-4647-af07-a2429aef0247/summary.json) |
| 제품 큐 Emulator | build·필수40개, 실패/차단0 | [summary](../../../../output/verification/1791190961880-34bec12b-2d90-4741-a7fd-0a72cfd5dece/summary.json) |

git diff 공백 검사 통과. 새 테스트 skip/0개 실행을 통과로 처리하지 않았다. 이 결과는 로컬 접수·준비 경계의 검증이며 실제 Worker FIFO 활성화, Storage 쓰기, Linux 프로세스 drain, iOS UI, 배포 검증은 포함하지 않는다. 이 범위는 Q2 이후 필수 게이트로 이어간다.

## 추가 구현 — 브랜드 생성·최초 탐색 단일 요청 (2026-10-05)

사용자가 단일 요청을 확정했다. 이전 절의 해당 질문은 해결됐으며 추가 결정 대기 항목이 아니다. 브랜드 생성 요청은 공통 envelope를 요구한다. 같은 transaction에서 현재 총 관리자 권한, 기존 생성 영수증/digest, 신규 요청 시각, 브랜드명·mood 검사를 수행한 뒤 브랜드/이름 인덱스/탐색 접수/영수증을 확정한다. URL이 없으면 탐색 큐를 사용하지 않는다.

변경 파일:

- `brand/admin/functions.ts::createBrand`: 요청자별 `brandCreationRequests`와 결정적 brandID, 최초 discoveryJobID/batchID 반환. 같은 입력 재전송은 기존 결과, 다른 입력은 충돌로 처리한다. 생성 실패 때 큐 순번이나 일부 브랜드를 남기지 않는다.
- `shared/lookbookQueue/{contracts,model,admission,projection,errors}.ts`: 브랜드와 룩북의 공통 계층. `admitQueueRequestInTransaction`은 외부 transaction에 접수를 포함한다. 기존 룩북 경로는 re-export로 보존했다.
- `shared/seasonDiscoveryCreation.ts::initialSeasonDiscoveryData`: timestamp 없는 큐 입력 생성. 실제 job은 준비 단계에 만들며 기존 legacy initializer는 기존 호출/회귀용으로 보존한다.
- Emulator 테스트/필수 게이트5개 추가, 총28개. 현재 코드 상태와 원본 로그는 다음 summary.source/실행 디렉터리에 보관한다.

| 최종 게이트 | 결과 | 원본 |
|---|---|---|
| Functions | lint/build·307개 통과 | [summary](../../../../output/verification/1791189418832-236ed565-3388-4478-874f-81ace0435660/summary.json) |
| 제품 큐 Emulator | build·필수28개 통과 | [summary](../../../../output/verification/1791189443892-659233d1-e170-4703-8419-75ff071d14d0/summary.json) |

[초기 게이트 실패](../../../../output/verification/1791189339685-23dd1ba5-a9e0-4876-9d49-e7b722c5b1d6/summary.json)는 feature 간 직접 import 아키텍처 검사였다. 검사를 변경하지 않고 공유 구현을 shared 계층으로 이동해 해결했다. 최종 실패/차단0. git diff 공백 검사도 통과했다.

준비 자동 실행·나머지 승인/재시도/보수/탐색 경로와 Q2 Worker 실행은 남아 있다. 앱의 브랜드 생성 payload/GRDB 복원은 Q5, 생성 영수증30일 정리는 Q4에 명시했다. 이번에 배포·유료 실행·실제 데이터 삭제는 수행하지 않았다. Q1 전체 완료나 실제 앱 동작 완료를 뜻하지 않는다.

## 추가 구현 — 실제 시즌 접수 API (2026-10-05)

사용자는 추가로 모호한 사항만 논의하고 승인 계획을 계속 진행하도록 지시했다. `requestSeasonImport`, `requestSeasonCandidateImportJobs`, `requestSeasonAssetRetry`를 실제 공통 admission에 연결했다. `queue/season-admission.ts`와 `asset-retry.ts`를 추가하고 `model/admission/preparation.ts`를 확장했다. 이전 직접 생성·asset task enqueue 전용 helper는 제거했으며 진단/승인/보수/legacy trigger의 후속 연결은 남아 있다. 기존 함수 region/timeout/memory 메타데이터는 유지했다.

- 최신 requestID/생성 시각을 요구하고 batch 영수증을 반환한다. 앱 연결 전이며 배포하지 않았다.
- 후보 snapshot/공개 세대/hash, candidate resolution/URL을 transaction에서 고정한다. 같은 ID 재전송은 snapshot 재검사 전에 기존 영수증을 반환한다. 누락/잘못된 후보는 항목 실패로 남기고 같은 URL은 준비 claim으로 중복 처리한다.
- 기존 sourceURL/sourceCandidateID job을 조회해 중복 참조 또는 부분 저장 재시도로 연결한다. 재시도는 같은 job 하위 새 execution, 총5회 예산을 가지며 이전 root/이력은 불변이다. source digest가 준비 전에 달라지면 실행을 만들지 않는다. 동일 원본의 pending 실행이 있으면 같은 실행을 참조한다.
- 실제 callable `.run`과 Firestore Emulator를 사용한5개를 필수 게이트에 추가했다. 인증 context를 주입한 로컬 검사이며 배포된 인증·실제 Worker/Storage·앱 화면 검증은 아니다.

| 최종 게이트 | 결과 | 원본 |
|---|---|---|
| Functions | lint/build·307개 통과 | [summary](../../../../output/verification/1791188372568-3cc096b0-9792-4be9-bd7c-e769b459d30a/summary.json) |
| 제품 큐 Emulator | build·필수23개 통과 | [summary](../../../../output/verification/1791188405095-330b54f1-eaff-404b-bcd5-ec2ef4c274d9/summary.json) |

최종 실패/차단0. 코드 상태·source digest·원본 로그는 각 디렉터리에 보존했다. [초기 실패](../../../../output/verification/1791188327716-c4a60e6a-14bb-40d3-91f4-2d7814b6317f/summary.json)는 lint 형식7건과 callable metadata 회귀1건이었다. 형식을 수정하고 URL/asset callable의 기존 runtime 설정을 복원한 뒤 같은 게이트를 재실행했다. 기존 테스트를 제거하거나 기준을 완화하지 않았다.

### 실제 발견한 추가 결정

`brand/admin/functions.ts::createBrand` → `shared/seasonDiscoveryCreation.ts::initialSeasonDiscoveryJob`은 브랜드 생성 transaction에서 최초 탐색 job도 즉시 만든다. 기존 설계에는 생성 응답 유실 시 브랜드와 탐색 접수의 멱등성 경계가 없었다. 사용자에게 두 선택지를 질문했다: (추천) 생성+최초 탐색을 한 요청 ID/transaction으로 확정하고 같은 결과 재조회, 또는 브랜드 생성 후 탐색 별도 접수와 누락 복원. 전자는 생성 API/앱 저장 범위를 확장하고 후자는 두 요청 사이 종료 복구가 필요하다. 결정 전 해당 경로는 변경하지 않았다.

Q1은 전체 완료가 아니다. 준비 자동 실행·승인/수동 재시도/보수/탐색과 브랜드 생성 연결이 남아 있으며 Q2 이후 실행 활성화도 아직 하지 않았다. 다음 작업자가 이 문서 아래의 이전 미연결 설명을 최신 상태로 오해하지 않도록 본 절을 우선한다.

## 추가 구현 — 기존 job 참조 (2026-10-05)

이번에는 접수 adapter 연결의 선행 작업인 기존 job 참조 처리를 구현했다. 실제 시즌 선택·직접 URL callable을 교체한 것은 아니다. 아래 이전15개 결과 대신 이번 변경의 검증은 다음 원본을 따른다.

- `queue/model.ts`: 서버 전용 `AdmissionTarget.existingJobID` 추가.
- `queue/admission.ts`: 기존 job ID가 잘못되면 접수·순번 할당 전 거절.
- `queue/preparation.ts`: 기존 job 참조는 duplicate 항목으로 확정하며 job/root 상태·실행권·이력·source claim을 변경하지 않는다. 기존 execution ID가 없는 legacy job은 null을 반환한다. 대상 삭제 시 새 job을 대신 만들지 않고 `QUEUE_REFERENCE_NOT_FOUND`로 차단한다. 이 오류의 준비 재시도/최종 집계 연결은 기존 Q1 준비 orchestration 후속 범위다.
- 기존 claim의 execution ID가 없을 때 문자열 `undefined`로 반환하지 않도록 보완했다.
- Emulator 필수3개를 추가해 기존15개를 포함한18개를 실행했다. 기존 job 불변·새 execution 없음·삭제 후 재시도·동일 준비 재실행·잘못된 ID의 순번 미소비를 확인했다.

검사 상태는 HEAD `1d67d61faa04984783083971688a7c628df74748`의 미커밋 작업 트리이며 각 summary.source에 입력 digest를 보관한다.

| 게이트 | 결과 | 원본 |
|---|---|---|
| Functions | lint/build·307개 통과 | [summary](../../../../output/verification/1791187501160-279db837-f47f-4227-8c57-a281e5834fea/summary.json) |
| 제품 큐 Emulator | build·필수18개 통과 | [summary](../../../../output/verification/1791187530233-ec0cc78d-0b43-43ca-a346-effafba6ff45/summary.json) |

실패·차단 없음. 원본 로그는 각 실행 디렉터리에 보존했다. 클라우드 배포·Worker 호출·실제 데이터 삭제는 수행하지 않았다. 실제 중복 판정 adapter, 부분 저장 재시도, 승인/재시도/탐색 및 준비 이벤트 연결은 남아 있으므로 Q1 완료로 보지 않는다.

## 이전 공통 접수 구현 기록

2026-10-05. 사용자가 Q0 이후 다음 구현 진행을 승인했다. Q1의 영속 접수·준비·전달 계층과 조회 callable을 구현했다. **Q1 전체는 아직 진행 중**이다. 기존 실행 접수 callable별 adapter, 실제 snapshot 검증 연결, 기존 job 중복 승계, 승인/수동 재시도 실행 이력 연결은 남아 있다. 새 큐는 제품 실행 경로에 활성화하지 않았다.

## 구현 범위

| 파일 | 책임 |
|---|---|
| `functions/src/lookbook/import/queue/model.ts` | 요청/항목/영수증 타입, UID+requestID 결정적 식별자, 객체 키 정렬·선택 순서 보존 digest |
| `queue/admission.ts` | 인증/현재 권한 → 기존 영수증·동일 payload → 신규 시간 창 → transaction 내 snapshot 고정 hook → 서버 sequence·입력·preparing 원자 기록 |
| `queue/preparation.ts` | 준비 순번·owner, 총5회 예산, item/job/execution/source claim 원자 기록, 중복/부분 실패 집계. 실제 작업 시도 횟수는0 유지 |
| `queue/dispatch.ts`, `import/taskService.ts` | head의 영속 intent, 동일 taskID 재전송,15분 deadline·OIDC 송신 adapter. 실제 송신 호출 연결은 미활성 |
| `queue/projection.ts`, `queue/authorization.ts` | 최소 영수증, 현재 브랜드 권한/삭제 재검사, 큐 소유 job 판별 |
| `queue/functions.ts`, `functions/src/index.ts` | `getSeasonImportBatch` 조회 callable. requestID/batchID 하나만 입력, 자기 요청·현재 권한 확인 |
| `import/functions.ts`, `import/seasonDiscoveryJobs.ts` | 기존 trigger/watchdog에서 큐 소유 job 제외. 큐 대기를 기존 discovery 자동 재시도로 처리하지 않음 |

`taskService.ts`는 계획 당시 후보였으며 기존 실파일은 없었다. 기존 task ID 검사 파일 `taskService.test.ts`는 있었으므로 기존2개와 신규1개를 함께 유지한다. 배포 export는 기존120개를 보존하고 조회 callable1개를 추가해121개다.

## 경합·준비 계약

- 준비도 서버 sequence 순서를 지킨다. 앞 요청 준비가 끝나기 전에 뒤 요청이 같은 source를 먼저 선점하지 못한다. 준비 완료와 실제 Worker 실행은 별개이며, 뒤 요청의 준비 완료가 실행권을 부여하지 않는다.
- `lookbookImportQueue/main`의 `nextSequence`/`preparationSequence`/`headBatchID`, `lookbookImportBatches/{batchID}`와 서버 전용 `inputs/{ordinal}`, 브랜드 하위 `queueSourceClaims/{hash}`를 사용한다.
- 새 준비 작업은 고유 owner로 시작한다. item 처리와 batch 결과를 같은 transaction에 기록하므로 재호출이 job을 복제하지 않는다. 중단 후 owner의 종료가 불명확한 자동 인계는 제공하지 않는다. `finishQueuePreparation` 호출자는 시작한 모든 item promise 종료를 확인해야 한다.
- 준비5회가 소진되면 아직 pending인 항목만 실패로 남기고 생성된 항목은 유지한다. 준비 시도와 실행5회/탐색3회는 분리한다.
- 새 job의 기존 공통 createdAt/updatedAt은 Firestore Timestamp를 사용한다. 큐 내부 시간값은 epoch milliseconds이며 향후 Worker/정리 계층에서 구분한다.
- 일반 생성 준비는 importSeasons/discoverSeasons만 지원한다. 승인/수동 재시도/보수는 기존 이력·snapshot을 이어야 하므로 adapter 구현 전 일반 새 job으로 생성하지 않고 차단한다.
- Cloud Tasks 호출은 주입된 sender가 호출될 때만 발생한다. 제품 trigger에 새 sender를 연결하지 않았다. 송신 성공 후에만 delivered를 기록하며 이전 head/세대의 늦은 응답은 현재 상태를 덮어쓰지 않는다. 실제 task의 실행권 검사는 Q2다.

## 검증

최종 코드에서 두 게이트 모두 passed. Functions와 emulator 게이트는 같은 lib를 사용하므로 순차 실행했다. HEAD `1d67d61faa04984783083971688a7c628df74748`의 기존 미커밋 변경을 포함한 실제 작업 트리를 검사했다.

| 게이트 | 결과 | 원본 |
|---|---|---|
| Functions | lint·build·전체307개, 필수19개, 누락/skip/실패0 | [summary](../../../../output/verification/1791186377551-d2e9d6a4-f6d5-46e3-a50e-0b6e1662fc46/summary.json) |
| 제품 큐 emulator | build·15개/필수15개, 누락/skip/실패0 | [summary](../../../../output/verification/1791186485245-e09c0658-8c85-4a6d-9682-49f4ecbf6cb5/summary.json) |

Functions source digest: `11d7a2ad723a415441b34a22b81c827f36832752e16bbf55d3c8337d3ef9a133`. emulator의 입력 범위/digest는 해당 summary.source에 보존한다. 출력 디렉터리의 stderr/stdout/reporter 원본을 함께 보관했다. 문서 링크·신규 파일 공백·git diff 공백 검사도 수행했다.

중간 결과:

- 초기 lint에서 신규 코드 형식10건을 발견해 수정했다. 기준을 완화하지 않았다.
- [초기 Functions305개 passed](../../../../output/verification/1791186064711-05da8746-9fd7-48ba-bb90-950648112195/summary.json)는 최종 통과로 사용하지 않는다. 변경 대조에서 기존 task ID 회귀2개가 새 파일 작성 중 빠진 것을 발견했고 원래 내용을 복원했다. 해당2개도 필수 ID로 추가한 최종307개 결과를 기준으로 한다.
- [초기 emulator12개 passed](../../../../output/verification/1791186113537-da950e1c-7e1e-4dfb-aa1a-4d474e7a91dc/summary.json)는 조회 callable·권한 변경·미연결 작업 차단 추가 전 기록이다. 최종15개 결과로 대체한다.

- `verification/functions.json`: lint·build·전체 테스트, 필수19개. 기존 필수14개+새3개+기존 task ID 회귀2개 명시. export120 검사는 기존 목록을 보존한121 검사로 갱신했다.
- `verification/lookbook-product-queue.json`: 빌드 후 실제 Firestore 에뮬레이터15개. 독립 SDK 클라이언트 동일ID 경합, payload 충돌·snapshot 만료 후 영수증 조회, 권한 회수, 준비 순번·동일 source 중복,80항목 부분 실패, 준비5회·이전 owner 거절, 송신 실패·동일ID 재전송, 목록 탐색 같은 순번, 최소 projection, 기존 trigger/watchdog 제외, 늦은 전달 응답, 신규 입력 경계, 내부 원본 접근 거절, 조회 callable, 미연결 승인 준비 차단.
- 환경은 `firebase.lookbook-queue.json`, `demo-lookbook-queue`, `127.0.0.1:8086`로 고정한다. 실행 스크립트와 테스트가 환경을 대조하며 demo 외 원격 Firestore를 대상으로 실행하지 않는다.
- 기존 rules를 그대로 로드해 큐 원본/inputs/claims/executions의 직접 접근 거절을 확인한다. rules/indexes 변경 없음. 전체 Firestore 회귀 게이트를 실행했다고 주장하지 않는다.
- Worker/iOS 소스는 이번에 수정하지 않아 Q0 결과를 새 제품 실행 검증으로 재사용하지 않는다. 새 제품 Worker route·iOS 접수 계약 연결은 미검증이다.

## 남은 Q1 작업과 완료 조건

1. `requestSeasonCandidateImportJobs`의 실제 공개 snapshot·후보 검증을 freezeTargets에 연결하고 기존 job 중복/부분 저장 재시도 승계를 구현한다. 현재 새 서비스는 기존 job 전체를 쿼리해 승계하지 않으므로 기존 callable을 바로 바꾸지 않았다.
2. 직접 URL·asset retry·검토 승인·수동 재시도·보수·목록 탐색/재탐색 및 브랜드 생성 시 탐색 접수 경로를 같은 admission에 연결한다. 승인 거절처럼 새 실행을 만들지 않는 변경은 분리한다.
3. 새 실행을 만드는 요청은 requestID/requestCreatedAt을 요구하고, 기존 상태 변경 및 snapshot/권한 조건을 보존한다. 승인 storage-only 및 수동 재시도 새5회/이전 이력 보존은 실제 adapter 검사로 입증한다.
4. 준비 orchestration/이벤트 및 전달 intent 회수 연결을 완료하되 Q2~Q3 이전에는 새 요청을 기존 per-job Worker에 전달하지 않는다. 실제 다음 head 선택/해제·Worker fencing은 Q2다.
5. 해당 callable/adapter 경계 테스트·emulator 필수 ID를 추가한 뒤 Q1 완료를 판정한다. Q1 완료 전 Q2로 넘어가지 않는다.

배포·IAM·실제 Cloud Tasks/Worker 호출·Storage 업로드·원격 데이터 삭제·커밋은 수행하지 않았다. 초기 기존 테스트 누락을 포함한 중간 결과도 아래에 보존하고 최종 결과와 구분한다.
