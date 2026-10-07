# Lookbook Entrypoints

Q7 검증완료(2026-10-07): [최종결과·작업별 커밋](../tasks/lookbook-import-performance/product-queue-q7-final-results.md). 정상A/B·A~J와K/L실제종료/새파싱·자동총5회/실패목록·맨뒤수동새5회·성공제거를완료했다. 서버필수6게이트와앱·GRDB28개통과. 관리자웹/최근목록운영·실제장시간/24h삭제는후속이며정식웹없는현재는기존제품API/서버증거로검증했다. 서버/Worker/앱/검증커밋4개 생성·설계/결과67개문서 포함 범위 사용자 승인.

Q7 이어 실행 승인(2026-10-07): K·L 각 시나리오를 한 번 검증하며 접수/전달 상한은 반복 테스트 수가 아니다. 기존K3영수증/실행/원본OOM을 유지하고 K새승인1+L4=남은5접수만 진행한다. `q7-retry-runner.mjs`의 `--continue=true`는 새20분창·L전용faultcampaign·old/currentrevision별 자료를 기록한다. Swift/관리자웹/공개API 추가는 없다. 로컬 verifier40passed, 실제 K/L 완료 전이다. [확정 실행안](../tasks/lookbook-import-performance/q7-retry-development-continuation-plan.md).

**Q7 현재미완료(2026-10-07):** 새K는3접수·추출검토후실제OOM1회, L은미접수다. 자동정산을막은로그필터를수정했고기존K/원본부분파일12개를보존했다. 이어실행제안은새K/OOM을추가하지않고남은5접수·전체8을유지하며새20분창·새revision별증거를명시한다. [결과](../tasks/lookbook-import-performance/q7-retry-development-results.md)/[실행안](../tasks/lookbook-import-performance/q7-retry-development-continuation-plan.md).

**Q7 K/L 검증(2026-10-07):** `scripts/q7-retry-{runner,contract}.mjs`는 UNAFFECTED2026SS의 새K/L만 사용해 실제 종료 뒤 동일 execution 새 추출·재검토, 총5회 소진 뒤 실패 목록1개·맨뒤 수동 새5회·성공 제거를 검사한다. 제품 최대8접수·20분, 정상124JPEG를 현재 공개 원장과 대조한다. 기존A~J/Swift/관리자웹UI 범위는 유지한다. [실행안](../tasks/lookbook-import-performance/q7-retry-development-execution-plan.md).

**Q7-R1 최신(2026-10-07):** 실패 시즌 자동 처리는 중간 복원이 아닌 추출부터 총5회다. approval 저장 실패의 다음 추출은 새 검토 규칙을 적용하며 같은 예산을 사용한다. 실패 목록은 브랜드+sourceURL 문서1개, 재실패 최신화/성공·명시적 안 함 제거, 맨뒤 수동 새5회다. 서버 구현은 Functions queue failure-service와 Worker queue restart/termination-retry/job-write/failure-record; 관리자 웹 UI는 후속이며 이번 Swift/DI/GRDB 변경은 없다. [데이터/API·검증 계획](../tasks/lookbook-import-performance/q7-retry-contract-plan.md), [서버 진입점](FIREBASE.md).

2026-10-07 최신: [A~J 실제 제품 검증 결과](../tasks/lookbook-import-performance/product-queue-q7-ten-brands-results.md) — 36접수·16시즌 저장·710JPEG와 현재 공개 원장 대조가 완료됐다. 두 100ms 예약 wave에서 실제 서버 순번과 브랜드 대기·실행 비중첩을 확인했다. 앞 run 시작 후 신규 접수는 없었으므로 A/B의 active 중 도착과 동일한 조건으로 표시하지 않는다. 메모리 최고 84.05%, 최대 표본 공백 380.7ms, 이미지 실패·시즌 재시도·중단 0회. 실행기 job 기록 누락은 원본 보존·별도 job index 대조로 정산했으며 이후 도구 기록 연결을 수정했다. 최종 client31/Worker359/Linux2 필수 검사 통과. 실제 장시간·플랫폼 종료 및 청구 전체는 별도 미검증이다. 전체 Q7 완료·커밋은 아직 아니다. 아래 실행 전/진행 중 문구는 과거 기록이다.

Q7 A~J 실행기 준비 완료(2026-10-07): `scripts/q7-wave.mjs::runQ7Wave`는 응답 대기 없이 절대 100ms 간격으로 최대10건을 시작한다. `q7-journal.mjs`/runner는 동시 기록을 직렬·원자 저장하고, 실패하면 새 투입을 멈춘 뒤 시작한 요청을 모두 정리한다. `assertQ7WaveEvidence`는 두 wave 각10건의 예정/시작/HTTP 직전 기록·실제 서버 순번과 서로 다른 브랜드 대기를 검증한다. 실제 서버 도착 간격을100ms로 단정하지 않고 편차와 순서 변경을 기록한다. 승인된 A6/B2/C~J각1·16시즌·36접수·기존 비용/2시간 상한은 유지한다. 필수 verifier gate `1791303321801-54c50236-ead4-40c3-ad2d-f126a1131cbc` passed31; digest `e3da40995238821d1f710fe61930efb6057e14c69792897cc00aa61f155c9c66`. 원격 A~J는 아직 실행 전이다.

Q7 A/B 기능저장 완료:7접수/3시즌/126JPEG/60게시물·3cover 공개 확인. coverThumbPath가 없는현행schema는 published원장에서thumbPath를 확인한다. `q7-runner --verify-only=true`는이미끝난7건의결과만읽고추가접수하지않는다. [실측·원본·미검증조건](../tasks/lookbook-import-performance/product-queue-q7-smoke-results.md).

Q7 사용자 확정 저장 재개(2026-10-07): `q7-runner --resume-after-extraction=true`는 idle/동일released A2/검토대기2만 이어가며 기존 create/import를 재전송하지 않는다. 활성 중 B접수 관측 실패는 보존하고 대기 조건은 A~J100ms로 옮겼다. 이번 report는 functionalStorageSmoke/overlapObserved=false다. q7-resume 원본보존/계정/fixture 검증은 유지한다. 총7접수·2시간 상한도 유지한다.

Q7 완료 항목 이어 실행(2026-10-07): 복구 후 terminal item은 batch-runner에서 다시 begin하지 않는다. 최종 release transaction은 실제 execution/continuation 종료를 재검사하므로 checkpoint만 성공으로 표시된 손상은 recovery로 차단한다. candidate023의 NOTQUEUED 실패는 epoch3/종료확인0잔여 이력으로 보존한다. A2 import는 아직 preparing, 원본 접수2건 유지, 새 후보/같은 run observer 연결 전이다.

Q7 현재 접수 유지(2026-10-07): `scripts/q7-runner.mjs --resume=<runID>`→`q7-resume.mjs` 계약/원본 보존→기존 A 영수증 조회→active 관측 시 B 신규 접수다. 기존 createBrand/A2 import는 재전송하지 않으며 총7 mutation 범위를 유지한다. 기능 완료 시 기존 sample-gap 실패는 historicalFailurePreserved로 남기고 새 실행은 기존 FIFO/자원 기준을 통과해야 한다. 앱 코드/계약 변경은 없다.

Q7 receipt 준비 연결(2026-10-06): 실제 목록 성공 뒤 preparing receipt가 반환되므로 `q7-receipts.mjs::waitQ7Receipt`로 job ID 준비/최종release를 기다린다. discovery domain 성공만으로 import를 보내지 않는다. 실제 batch는 별도로 sample-gap922ms 복구 상태여서 원인을 분석 중이며 이미지jobs/Storage writes0. [현재 실행 증거와 계획](../tasks/lookbook-import-performance/product-queue-q7-server-validation-plan.md).

Q7 탐색 오탐 수정(2026-10-06): `src/season-discovery-controls.ts::inspectDiscoveryPageControls`가 가시 활성 more/실제 forward pagination을 DOM에서 확인한다. `season-discovery.ts::renderedDiscoveryExtraction`이 이를 최종 미완료 판정에 쓰며 문자열 힌트는 rendered fallback을 위해 유지한다. 정산된 A 원본은 correctionRequired 이력으로 보존했고 수정본 gate·배포·smoke는 후속이다. 실제 probe/정산 원본은 [readiness](../tasks/lookbook-import-performance/product-queue-q7-readiness.md).

Q7 다음 실행(2026-10-06): 본인 Google 계정 하나로 Development recovery SA를 사용하는 최소 IAM 안 확정. `src/queue/recovery-auth.ts`→복구 CLI→`/recovery/inspect`→조건 충족 시 `/recovery/settle-correction`. 배포/preflight는 recovery env를 검사하며 새 gate/candidate 확인 후에만 A 정산을 시도한다. 관리자 웹 복구 연결은 이번 범위에 추가하지 않는다. [1~6 통합 순서](../tasks/lookbook-import-performance/product-queue-q7-server-validation-plan.md).

**Q7 최신 진행(2026-10-06):** Worker gate `1791290297722-acd38c5e-89ae-442f-9a7e-cf88e2da3abb`(354 tests/lint/fixtures/deploy contract)와 product queue gate `1791289769511-4141e4a8-d6d9-4c08-9dc0-a49b5f414fcc`(72 emulator tests/build) 통과. Candidate `00020-yun`은 verified snapshot digest `91c937c1…733b` 및 Q7 관측 환경으로 Ready, Q7 tag 0%, base `00012-fih` 100%, queues RUNNING/0 tasks다. Q7 preflight 통과. 전용 recovery IAM이 없어 기존 A batch inspect/정산은 아직 실행하지 않았다. 현재 권한 선택 요청과 상세 status는 [Q7 readiness](../tasks/lookbook-import-performance/product-queue-q7-readiness.md)를 따른다.

**제품 FIFO Q7 Development 검증 이력(2026-10-06):** `q7-runner.mjs`가 승인된 Google platform admin 세션으로 A 브랜드 생성·최초 탐색을 접수했고 29개 후보를 기록했다. unresolved 더보기 신호로 discovery job은 `correctionRequired`이며 이전 Worker의 status mapping 오류 때문에 queue batch/head가 `recoveryRequired`로 남았다. 정상 제품 mapping은 `src/processor.ts::queueOutcomeForSeasonDiscovery`, `src/queue/coordinator.ts::isQueueExecutionTerminal`, `src/queue/checkpoint.ts`다. 조건부 correction settlement는 `src/queue/recovery.ts::inspectQueueRecovery`/`settleCorrectionQueueRecovery`, `/recovery/settle-correction` route로 연결한다. 종료 run, 단일 discovery item, exact run revision/epoch/head, terminal domain=`correctionRequired`, queue checkpoint=`recoveryRequired`, asset writes 0을 transaction에서 재검증하며 원본 discovery 결과/run evidence는 보존한다. 최신 candidate, gates와 recovery 권한 상태는 위 `Q7 최신 진행` 및 [Q7 readiness](../tasks/lookbook-import-performance/product-queue-q7-readiness.md)를 따른다.

Q7 최신 흐름: [실제 제품 생성→목록→추출→승인→저장 계획](../tasks/lookbook-import-performance/product-queue-q7-server-validation-plan.md). iPhone 관리자 검증은 선행 조건에서 제외한다. 검토 대기에서 차례를 반환하며 승인은 새 FIFO 요청이므로 A 최종 저장 전 B 탐색이 가능하다. 아래 과거 배포 전/실기기 계획보다 최신 통합 계획을 우선한다.

**Q7 Development smoke 조건(2026-10-06):** [원격 설정 snapshot·URL/시즌 입력량·실행 순서와 비용 한계](../tasks/lookbook-import-performance/product-queue-q7-readiness.md). A 2시즌/B 1시즌 flow의 A 생성·목록 탐색은 실제 실행됐고 unresolved 동적 더보기로 `correctionRequired`가 됐다. 이전 Worker 상태 매핑 오류가 queue head를 `recoveryRequired`로 남겼으므로 A의 시즌 import와 B 접수는 미실행이다. Candidate `00020-yun` 배포 및 기본 traffic 보존은 완료됐다. Recovery 전용 IAM 연결·기존 batch settlement 뒤 smoke와 A~J를 재개한다.

**Q6 현행 제품 큐 실행 흐름(2026-10-06):** [구현/게이트 원본/잔여 확인](../tasks/lookbook-import-performance/product-queue-q6-results.md). Functions 접수·preparation → queue head delivery → Worker `src/queue/batch-runner.ts`의 단일 owner/epoch → `activation.ts`가 discovery/import/retry/review/repair를 1회 활성화 → 기존 import/discovery processor → checkpoint/조건부 asset publication 순이다. retryable 시즌 오류는 지연 없이 최초 시도 포함 총5회다. HTTP 14분 경계는 retryable 503 응답과 새 입장 차단 후 실행 중 promise drain을 기다린다. 실제 Development URL·Storage·Cloud Tasks·Cloud Run 종료와 IAM 동작은 미검증이다.

**Q5 앱 요청·복원 연결(2026-10-06):** migration27 `lookbookImportRequest`를 AppCompositionRoot의 GRDB store/UID provider에서 Lookbook queue adapters에 주입한다. createBrand+최초 탐색, 수동 discovery, 시즌/자산/검토/재시도/repair 접수는 전송 전 동일 요청 envelope를 저장한다. 응답의 contractVersion/requestID/brandID/kind 불일치 시 수락하지 않고 reconcile 상태로 보존한다. 후보 선택·시즌 관리 화면은 3/10초 polling, 오류 backoff, foreground 재개와 requestID 복원을 제공한다. Q5 G-I는 iOS 26.2 Simulator 28 tests 통과. Q7 Development 검증과 실기기 QA는 남았다. [Q5 결과](../tasks/lookbook-import-performance/product-queue-q5-results.md).

**Q4 제품 FIFO 최신 상태(2026-10-06):** stale head 전달은 5분 reconciliation에서 같은 generation만 재전달한다. Worker `/recovery/inspect`·`/recovery/resume`에 사용자가 승인한 제한적 `/recovery/settle-correction` 로컬 구현이 추가됐다. 대상 revision은 현재 serving revision과 분리해 run record의 revision과 정확히 대조한다. dedicated recovery OIDC 설정이 없으면 routes는 비활성이다. batch/brand receipt·recovery audit 보관과 미참조 JPEG exact-generation 정리가 Functions schedule로 연결됐다. Worker 및 product queue의 새 필수 로컬 gate는 통과했으며 실제 Development 정산은 아직 미실행이다. [Q7 readiness](../tasks/lookbook-import-performance/product-queue-q7-readiness.md).

**Q3 최신 상태(2026-10-05):** `queue/asset-paths.ts`·`asset-publication.ts`가 queue 실행별 Storage 경로와 두 변형 generation 확인 후 owner/epoch 조건부 공개를 연결했다. `queue/browser-gate.ts`는 이미지 저장/hash와 Chromium을 Worker 인스턴스 안에서 직렬 배타화하고, 대기 중 새 이미지 입력을 막은 뒤 브라우저 진입 전에 SourceBuffer 재사용 cache를 비운다. `deletion/assetWriteFence.ts`는 활성 asset ledger가 있는 대상 삭제를 차단한다. G-L Linux/amd64 1CPU·2GiB에서 Chromium gate/SIGTERM·cgroup 표본, 분리된 OOM container 검사가 통과했다. 실제 Worker HTTP/Cloud Run 복구, legacy direct 경로 cutover, Q4 stale ledger 복구, Development 검증은 남았다. [Q3 결과](../tasks/lookbook-import-performance/product-queue-q3-results.md)를 우선한다.

**Q2 최신 상태(2026-10-05):** `queue/batch-runner.ts`가 기본 `importSeasons` batch를 `processImportBatchTaskRequest`→기존 `processJob`로 연결한다. `/tasks/import-batch`는 OIDC로 보호되며 최초 포함 총5회 즉시 재시도, 시즌6·download4·transform1·upload4·path 제한 없음·128MiB shared runtime을 사용한다. 12분 admission stop/cgroup guard가 연결됐고 14분은 현재 drain 초과 기록만 하므로 응답 보장은 미완료다. 다른 kind와 Cloud Tasks sender/trigger는 미연결이다. [Q2 결과](../tasks/lookbook-import-performance/product-queue-q2-results.md).

**Q2 Worker 실행권(2026-10-05):** `tools/lookbook-import-worker/src/queue/{coordinator,checkpoint,runtime}.ts`가 claim/epoch, season attempt ledger, progress, retryAt와 묶음 자원 runtime을 제공한다. `queue/ownership.ts`와 `processor.ts`·`season-discovery-processor.ts`는 기존 `/wake`·단건 task가 queue-owned job을 실행권 없이 처리하지 못하게 한다. `claimJob`의 batch token 검증은 현재 runner에서 호출된다. 자동 재시도는 대기 없이 최초 포함 총5회다. 남은 연결은 [Q2 기록](../tasks/lookbook-import-performance/product-queue-q2-results.md).

**Q1 추가 연결(2026-10-05):** `reviewLookbookExtraction`의 승인 분기, `retryLookbookExtractionAfterFix`, `requestLookbookSeasonRepair`, `applyLookbookSeasonRepair` → `queue/followup-admission.ts`. insufficientImages는 새 실행 없이 기존 검토 기록만 갱신한다. `requestSeasonDiscovery`, `retrySeasonDiscovery`, `retrySeasonDiscoveryAfterExtractionFix`, 기존 `discoverSeasonCandidates` → `queue/discovery-admission.ts`. 준비 이벤트는 `preparation-functions.ts` → `preparation-runner.ts` → 기존 preparation이다. [Q1 결과](../tasks/lookbook-import-performance/product-queue-q1-results.md)에 Q2가 소비할 activation 입력과 남은 범위를 기록한다.

**브랜드 생성 자동 탐색(2026-10-05):** `brand/admin/functions.ts::createBrand` → `shared/lookbookQueue/admission.ts`로 같은 FIFO에 접수한다. `shared/seasonDiscoveryCreation.ts::initialSeasonDiscoveryData`가 timestamp 없는 frozen seed를 만들며 준비 단계가 결정적 discovery job을 생성한다. 기존 `lookbook/import/queue/{contracts,model,admission,projection}.ts`는 shared 구현을 re-export한다. 즉시 탐색/Cloud Tasks enqueue는 하지 않는다.

**Q1 실제 시즌 접수 연결(2026-10-05):** `import/functions.ts` 세 callable(URL·후보 선택·asset 재시도)이 `queue/season-admission.ts`를 사용한다. `asset-retry.ts`는 이전 root의 대상·post 목록·실행 ID를 digest로 고정하고 `preparation.ts`는 별도 executions 문서만 생성한다. Worker 활성화·앱 API 변경·승인/보수/탐색 연결은 후속이다. 자세한 계약은 [Firebase 진입점](FIREBASE.md), 결과는 [Q1 기록](../tasks/lookbook-import-performance/product-queue-q1-results.md)을 따른다.

**Q1 기존 job 참조 보강(2026-10-05):** `functions/src/lookbook/import/queue/model.ts`의 서버 전용 `existingJobID`를 `admission.ts`에서 검증하고 `preparation.ts`에서 중복으로 반영한다. 대상 삭제 시 `QUEUE_REFERENCE_NOT_FOUND`로 차단하며 기존 job과 source claim은 변경하지 않는다. 실제 callable의 중복 판정·부분 저장 재시도 연결은 아직 남아 있다.

**제품 큐 Q1 진행(2026-10-05):** [공통 접수 계층·변경 파일·검증·남은 adapter](../tasks/lookbook-import-performance/product-queue-q1-results.md). Functions `import/queue/{admission,preparation,dispatch,projection,authorization,functions,model}.ts`와 `import/taskService.ts`, 조회 callable `getSeasonImportBatch`를 추가했다. 기존 trigger/watchdog는 큐 소유 job을 제외한다. `verification/lookbook-product-queue.json`은 demo 프로젝트/8086의 실제 transaction·준비·전달/권한15개를 검증한다. 기존 실행 접수 callable 전체 연결과 Worker 실행은 아직 미완료이며 Q1 전체 완료가 아니다.

**제품 큐 Q0 구현(2026-10-05):** [변경·게이트 원본·남은 범위](../tasks/lookbook-import-performance/product-queue-q0-results.md). 사용자 구현 승인 후 공용 `contracts/lookbook-import-queue-v1.json`, Functions/Worker `queue/contracts.ts`, 앱 `Domains/Entities/LookbookImportQueueContract.swift`와 각5개 계약 검사를 연결했다. 정책/버전/공통 요청/시간 경계/상태 분류를 검사하며 기존 API·DI에는 아직 연결하지 않았다. Functions·Worker 기존 필수 검사를 유지하고 전용 iOS/자체 게이트를 추가했다. Q1 이후 접수/FIFO/실행/저장/복구 및 emulator/Linux 기능 검증은 후속이다. 아래 구현 승인 전 문구는 이전 이력이며 현재 결과는 링크를 따른다.

**제품 큐 단계별 구현 계획(2026-10-05):** [Q0~Q7·변경 파일·완료 기준·필수 게이트](../tasks/lookbook-import-performance/product-queue-implementation-plan.md). 계약/검증 연결 → 접수/FIFO → Worker 실행권/재개 → 저장/브라우저 → 복구/정리 → 앱 → 로컬 통합 → 승인된 Development 순서다. 정리100건/페이지·회당500건 또는120초 신규 투입 중단, 조회 오류10/20/40/60초, 신규 접수24시간/미래5분, 로컬 확정 기록30일, 접수 준비 총5회·무진행2구간·브라우저 전환 캐시 비우기를 사용자 확정했다. 아래 시점별 미확정 문구는 이 최신 결정으로 대체한다. 이번에는 계획 문서만 작성했으며 제품 코드·새 게이트·배포·IAM·삭제는 미실행이다. 코드 구현 승인 후 Q0부터 진행한다.

**제품 큐 운영·검증 기준(2026-10-05):** [설계 §16~19](../tasks/lookbook-import-performance/product-queue-design.md). 조회3/10초, 점검5분·파일 정리1시간·기록 정리일1회, 성공 상세24시간/최소 완료30일/장애 해결 후30일/복구 감사90일, 본인1인 조건부 복구 확정. PQ01~15의 필수 게이트 연결안·만료 요청 방지·보호 예외를 기록했다. 현재 iOS 게이트는 룩북을 선택하지 않는다. 문서만 변경했으며 새 검사 연결/실행·IAM·삭제는 미실행이다.

**제품 큐 데이터/API·복구·브라우저·앱 연결(2026-10-05):** [설계 §12~15](../tasks/lookbook-import-performance/product-queue-design.md). 최신 계약 통일(구버전 앱 호환 제외), Chromium1개·이미지와 분리, 목록 탐색도 같은 FIFO, GRDB 복원을 확정했다. batch/items/runs/산출물·진행 조회, bootID와 플랫폼 instance 증거의 구분, inspect/resume 제안, AppCompositionRoot→Container·GRDB migration/계정 삭제 진입점을 기록했다. 설계만 수행했으며 필수 게이트/운영 복구 도구는 아직 미구현이다.

**시간·메모리·앱 정책 확정(2026-10-05):** [제품 큐 설계 §6·7·9·10](../tasks/lookbook-import-performance/product-queue-design.md).12/14/15분 정상 분할·같은 차례 재개, 메모리85%1초/100ms측정/500ms초과 공백 중단 후 복구 확인, 기존 화면 상태 구분·요청 ID 재시작 복원을 확정했다. 제품 초기 검증 기준이며 구현·배포·제품 테스트는 미실행이다.

**제품 import 대기열 세부 설계(2026-10-05):** [최신 검토본](../tasks/lookbook-import-performance/product-queue-design.md). 닫힌요청/추가선택·검토승인·수동재시도 맨뒤/수동새5회/종료불명확 차단/묶음 Worker/실행별 경로·조건부 공개/미참조 파일24시간 후 정리 확정. 이미지별 재개와 Storage 삭제·공개 경합, callable→task→실행권→pipeline 및 iOS 변경 경계를 정리했다. PQ01~11은 검증 설계이며 제품 구현·실행·배포·삭제는 아직 하지 않았다.

**A~J 실측 종료·T2 중단(2026-10-05):** [결과·검증·남은 범위](../tasks/lookbook-import-performance/ten-brand-results.md). 실제 Development6성공/변환2메모리중단1/업로드8미실행1. 완주 게이트failed, 중단정리drained=true·후속차단 유지. 원본·분석·배포·게이트는 `output/lookbook-import-performance/ten-brand-live/`. 제품 반영·추가 실험 없음.

**A~J 배포 전 확인(2026-10-05):** [대상·입력·비용 분석](../tasks/lookbook-import-performance/ten-brand-readiness.md). 원본138개·Development 설정·OIDC/실행권·version5/8회/100ms 계약·검사한 소스 해시 대조 통과. 원본 증거와 비용 산술은 `output/lookbook-import-performance/ten-brand-readiness/`. 이번 push/배포/Worker 호출0, 다음은 새 revision 대상 대조 후 smoke와 본 비교다.

**A~J 원격 version5 연결(2026-10-05):** [구현·검증 기록](../tasks/lookbook-import-performance/ten-brand-connection-results.md). `remote-input.ts`가18시즌을 독립 ID로 매핑하고 `remote-contract.ts`가100ms 접수·고정8회·단계 증량을 묶는다. `remote-runner.ts`→`arrival-runner.ts` 실행, `remote-arrivals.ts`/`remote-report.ts`의 도착·정책·저장 증거 재검사와 variant별 집계가 진입점이다. Mac/Linux 각각 전체316개·필수208개, emulator5개, 테스트/runtime 이미지 대조를 모두 통과했다. 배포·실제 네트워크 비교는 이번 범위에서 미실행이다.

**100ms 접수 로컬 검증 완료(2026-10-05):** Mac/Linux AMD64 각각313개·필수205개 통과, 실패·취소·skip0. Linux1CPU/2GiB에서 검사했고 기존 lint70경고는 남아 있다. 원본 로그·소스 해시·이미지 대조는 아래 A~J 검증 기록5절에 보존한다. 다음은 원격18시즌·8회 계약 연결이며, Firebase 실측은 이번에 실행하지 않았다.

**A~J 실험 조건 확정(2026-10-05):** [입력·최소 행렬·요청량·비용·연결 계획](../tasks/lookbook-import-performance/ten-brand-execution-proposal.md). 총18시즌(A8/B2/C~J각1), 접수 간격100ms(A0~J900ms), Worker 합산 시즌6/해제 비교, 준비 포함8회로 확정했다. 접수 간격 외 추천 조건은 유지한다. 새 계약 연결·필수 검증·승인된 유료 실행은 아직 미완료다.

**최신 작업(2026-10-05) — A~J 로컬 최종 검사:** [검증 범위·결과·미구현 경계](../tasks/lookbook-import-performance/ten-brand-validation.md). `performance/arrival-runner.ts`가100ms 접수를 재현하고 `season-runner.ts::beforeStart`가 도착 전 실행을 막는다. `arrival-runner.test.ts` TB03~06 및 기존 TB01/02를 `verification/lookbook-import.json` 필수 목록에 연결했다. 원격18시즌·8회 계약 연결과 유료 실행은 아직 미완료다. 제품 FIFO 방향과 기존 실측 증거는 보존한다.

**최신 결정(2026-10-05) — 브랜드 요청 FIFO 확정:** [확정 사항·제품 연결 설계·남은 결정](../tasks/lookbook-import-performance/phase-4-brand-dispatch-design.md). 현재 브랜드 안에서 시즌을 병렬 처리하고 저장·종료·정리 후 접수 순서대로 다음 요청을 진행한다. 뒤 요청 대기를 수용하고 단순성·순서 예측 가능성을 우선한다. 실측에 의한 큰 속도 개선 주장이 아니다. 다음은 요청 묶음/API·실행권·재시도/복구·공용 pipeline의 최소 설계 및 구현 계획이다. 제품 구현·추가 실험·배포는 아직 진행하지 않았으며 아래 기록은 이력이다.

**검증 이력 — Development 역순3회 완료:** [계약·구현 계획·요청량·검증](../tasks/lookbook-import-performance/development-reverse-comparison.md). version4는 준비→SP→PP만 허용한다. `remote-contract.ts`/`remote-report.ts`와 관련 필수 게이트가 진입점이며 이전5회 결과는 보존한다. Mac/Linux307개·emulator5개·실제3회·원본 재검사 게이트 모두 통과했다. 이번 SP 전체0.61%/첫 브랜드4.24% 단축으로 큰 처리량 개선 근거는 부족하다. 추가 성능 실험은 실행하지 않는다. 당시 제품 도입 보류 권고는 이후 FIFO 제품 결정으로 대체됐으며 세부 구현은 후속이다.

**최신 — Development 실제 약식5회 완료:** [실측 결과·원본·게이트·비용 추정](../tasks/lookbook-import-performance/development-screening-results.md). 준비1회와 PP/SP/PS/SS 각1회가 모두 성공했고 실제 실행·원본 재검사 게이트를 통과했다. 전체 처리100~104초, 브랜드 순차 후보의 첫 브랜드 완료는 약10% 빨랐으나 각1회·동일 인스턴스·고정 순서이므로 채택은 미판정이다. 추가 실행/운영 반영/삭제는 하지 않았다. 아래 승인 대기·미실행 문구는 실행 전 이력이다.

실행 전 기록: **배포 전 준비:** [약식5회 실행안·현재 대상·비용·검증](../tasks/lookbook-import-performance/development-screening-execution.md). 로컬 원 사이트 HTML7개/원본138개 검사가 통과했고 현재 설정·기존 OIDC와 서울 단가를 재확인했다. 준비 게이트2개 통과, Worker 소스 변경 없음. push/배포/Worker 실험 요청/Firebase 실험 쓰기는 아직 하지 않았다.

**최신 — 약식5회(version3) 로컬 구현·검증 완료:** [확정 조건·구현·검사·요청량](../tasks/lookbook-import-performance/development-screening.md). 준비1회+PP/SP/PS/SS 각1회로 축소한다. 다운로드4·변환1·업로드4·재사용128MiB는 유지한다. `remote-contract.ts`의5회 계약과 `remote-report.ts`의 단일 관측 집계가 현재 기준이며, 채택/반복악화/실패율 개선 판정은 하지 않는다. Mac/AMD64 각각307개·필수199개, emulator5개와 요청량/이미지 대조 게이트를 통과했다. 실제 배포·유료 실험은 미실행이다. 아래21회 실행안·version2·과거 ‘현재/다음’ 문구는 이전 이력이며 추가 실행 권한이 아니다.

- **AMD64 golden 분리:** [구현·증거](../tasks/lookbook-import-performance/development-amd64-golden.md). `remote-contract.ts`가 별도 AMD64 fixture/digest/profile을 읽고, `index.ts` → `remote-golden-profile.ts`가 실행 환경을 확인한다. runner의 인코더/profile 증거는 `remote-report.ts`에서 재검사한다. 기존 ARM fixture와 변환 함수는 보존했다.

- **최신 배포 전 준비:** [AMD64·OIDC·실행안·차단 사항](../tasks/lookbook-import-performance/development-amd64-readiness.md). `performance/remote-auth.ts`는 기존 gcloud 사용자 자격으로 지정 계정의 `generateIdToken`을 호출하며 `remote-campaign-cli.ts`에서 사용한다. RN11~12가 인증 경계를 검사한다. AMD64 JPEG golden 불일치 때문에 배포는 아직 진행하지 않는다.

**현재 단계(2026-10-04):** 사용자가 다운로드4·변환1·업로드4를 유지한 다음 구현을 승인했다. [version2 네 구조20회+smoke1회 로컬 구현·검증 기록](../tasks/lookbook-import-performance/development-network-implementation.md)과 [실행 대상·요청량·비용](../tasks/lookbook-import-performance/development-network-comparison-plan.md)을 따른다. remote-contract/runner와 remote-campaign/report/target/CLI가 진입점이다. 이미지별 예약/R 연결은 보류했고 기존 결과는 보존한다. 배포·유료 실험은 미실행이다. 아래 ‘다음’과 AD2b 결정 대기는 이전 이력이다.

- **AD2b 연결 설계 검토:** [후보 파일·소유권·제동·필수 검사](../tasks/lookbook-import-performance/adaptive-ad2b-plan.md). 새 admission과 runtime은 아직 미구현이다. 초기 예약량·커버 방식 결정 대기이며 실제 R 성능 비교·원격 실행은 별도다.

- **AD2a 계측·준비 측정 완료:** [코드·원본·18회 결과](../tasks/lookbook-import-performance/adaptive-ad2a-results.md). `resource-feed.ts::ResourceFeed/OperationEvents`, `memory-preparation.ts::measurePreparation/validatePreparationResult`, `memory-preparation-host.ts::runPreparationCampaign`이 진입점이다. Mac/Linux292개·필수184개,18/18회·JPEG42개 통과. 예약 E와 실제 R 연결은 AD2b에 남아 있다.

- **자동 조절 AD1 구현:** [실제 코드·검사·한계](../tasks/lookbook-import-performance/adaptive-ad1-results.md). `adaptive-controller.ts::observe/checkTime/snapshot/decisions` → 명시적 `adjustableLimits`의 `PipelineRuntime.setStageLimit` 및 가변 `ReadySeasonQueue`가 진입점이다. 실제 Worker 연결/시즌당4 대체/메모리 예약/성능 실험은 AD2 이후다. 기존 P/S 계약은 유지한다.

- **Development 연결 D0~D3 완료(2026-10-04):** [구현·게이트·한계](../tasks/lookbook-import-performance/development-connection-results.md). `config.ts`의 개발 전용 캠페인 → `index.ts`의 공용 입력/adapter → `server.ts`의 `/experiments/lookbook-transfer` → `performance/remote-runner.ts`의 메모리·P/S → `reuse-input.ts::ConnectedIO` → `remote-io.ts`/`remote-firebase.ts`의 실제 I/O와 재검사 순서다. `remote-store.ts`는 실험 한 회차 실행권과 종료 미확인 차단을 담당한다. 제품 큐/Swift API를 바꾸지 않았고 실험 모드는 기본 off다. Mac/Linux278개·필수170개, emulator4개 통과. 실제 원격 배포·실험은 D4 실행안 확인 후 진행한다.

- **브랜드 사이 순차 비교 구현(2026-10-04):** [설계·20회·필수 검사](../tasks/lookbook-import-performance/phase-3-brand-fifo-design.md), [실제 검증·실측 상태](../tasks/lookbook-import-performance/phase-3-brand-fifo-results.md). `season-runner.ts::runSeasons`의 `serial-brands`는 같은브랜드 시즌을 병렬로 시작하고 저장/review/최종실패·정리 후 다음브랜드로 넘긴다. `brand-comparison.ts`는3×2매핑/20회/digest, `brand-metrics.ts`는등록순서별입장/정리/대기포함완료, `brand-statistics.ts`/`brand-report.ts`는5쌍·실패분모 검증, `brand-progress.ts`는256KiB경계기록을 담당한다. `reuse-comparison.ts`/`reuse-entry.ts`는새marker에만 연결하고 `container-runner.ts`는증거출력실패를실패로남긴다. Mac/Linux265개·필수157개 및20/20 실측·재집계·정리 완료. 대용량은 S가 전체0.86%단축/최고메모리93.37→83.36%/읽기22.29%감소로 후속후보지만 속도10%목표는 미달이다. 제품API/DI/분산claim·클라우드설정은 미변경이다.

- **P4 다섯 쌍 확인 완료(2026-10-04):** [조건·순서·검증·실측](../tasks/lookbook-import-performance/phase-3-p4-confirmation.md). Mac/Linux253개·필수145개 통과,15회 중11성공/4메모리중단(실제OOM1포함).128만5/5 성공이나 최고94.048%여서 후속 진단 후보로 유지한다. off/256은각3/5, 완주3쌍으로 속도채택 미판정이다. `large-comparison.ts::makeLargeConfirmationPlan`/`reuse-comparison.ts`의 `largeConfirmation`은 전용계획·준비분리, `large-statistics.ts`는 실패분모·5쌍판정 진입점이다. 원본/독립집계/정리 증거와 OOM 관측 한계를 기록했다. 다음 추천은 메모리 원인 진단 설계이며 실행Pipeline/제품API/DI 변경 없음.

- **P4/off 준비 대조군 완료:** [입력·승인·게이트·실측](../tasks/lookbook-import-performance/phase-3-p4-off-control.md). Mac/Linux250개·필수142개, 실측1회219.558초 성공. `performance/large-comparison.ts::makeLargeControlPlan`은 커버 선준비/P4를 유지하고 source cache만 끈다. `reuse-comparison.ts`의 `largeControl` marker로 기존7회와 구분하고 `reuse-contract.ts`는 cache 설정과 커버 준비를 독립 검사한다. 제품 API/DI 변경 없음.

- **대용량 준비7회 완료:** [635MiB 합성 수요·원본·판정](../tasks/lookbook-import-performance/phase-3-large-input-design.md). Mac/Linux247개·필수139개 통과. P4/128·256만 완주하고 U4조건·P4/512는 메모리 중단됐다. `performance/large-input.ts`/`large-comparison.ts`/`large-input.test.ts`가 입력·7회 집계·회귀 진입점이다. 독립scope/새digest/trace상한과 실패 분모를 유지하며 다음은P4/off 기준선 확인 추천이다. 제품 API/DI 변경은 없다.

- **제출 순서45회 완료:** [설계·코드·실측·판정](../tasks/lookbook-import-performance/phase-3-submission-design.md). `performance/submission-comparison.ts`는 U/R4/B4/P4 및16/128MiB·공유 off 행렬을 만든다. `submission-runtime.ts`는 P4에 한해 준비된 변환을 입력 시즌 순위로 선택하고 나머지는 기존 FIFO를 사용한다. `reuse-comparison.ts`와 `reuse-entry.ts`가 연결·입력 계약·시즌별 완료 시각·5쌍 판정을 담당한다.45/45 성공·R4/B4 채택 보류·P4 후속 후보 유지이며 메모리 여유/대용량/원격 효과는 미확정이다. 공용 제품 pipeline/API/DI 변경은 없다.

- **후속 부하·압박45회 완료:** [구현·원본·판정·다음 설계](../tasks/lookbook-import-performance/phase-3-load-pressure-proposal.md). `performance/reuse-contract.ts`가 고정 입력별 대상/원본·출력 바이트를 산출하고 trace/cache/읽기를 교차 검사한다. `reuse-comparison.ts`의 makeLoadPressurePlan과 summarizeReuse가20회 부하 확인+25회 예산 압박 및5쌍·압박 성립을 구분한다. `reuse-entry.ts`는 입력 계약을 사전 확인·결과 보존하고 `load-pressure.test.ts`는6개 필수 회귀다. 45/45 성공이지만16/32MiB는 첫 시즌 반복 악화로 채택 보류다. 부분 재사용 시 늦게 제출되는 본문과 다른 시즌의 큐 순서를 다음 설계에서 다룬다. 앱/제품 API/DI 변경은 없다. 아래는 이전 단계 이력이다.

- **커버 선준비 15회 완료:** [계약·게이트·원본·판정](../tasks/lookbook-import-performance/phase-3-cover-preparation.md). `performance/reuse-input.ts`의 prepareCover는 해시/중복 제거 후 커버를 공용 다운로드 슬롯으로 준비하고 해당 시즌 asset 제출을 시작한다. `reuse-trace.ts`는 준비 사건과 asset 시작 경계를 검사한다. `reuse-comparison.ts`의 makeCoverPreparationPlan/summarizeReuse와 `reuse-entry.ts`가 off/current/prepared 각5회에 연결한다. 15/15 성공·첫 시즌 지연 해소·전체 off 대비1.04% 단축이며 다른 부하·예산 압박·Development는 후속이다. API/데이터/제품 processor/DI 변경은 없다. 아래는 이전 단계 이력이다.

- **재사용 지연 진단 완료:** [계약·검증·원본·큐 대기 증거](../tasks/lookbook-import-performance/phase-3-reuse-diagnosis.md). `performance/reuse-trace.ts`의 ReuseTrace/TracedPipeline/analyzeReuseTrace, `reuse-comparison.ts`의 makeReuseDiagnosticPlan, `reuse-input.ts`의 논리 대상·source-ready·season-end가 진입점이다. 2/2 성공, 커버 변환이 다른 시즌 본문 뒤로 밀려 첫 시즌 종료를 지연함을 확인했다. 진단 marker가 있을 때만 연결하며 제품 슬롯·우선순위는 유지한다.

- **재사용 15회 완료:** [계약·검증·원본·지연 결과](../tasks/lookbook-import-performance/phase-3-reuse-comparison.md). `performance/reuse-{comparison,input,entry}.ts`와 `reuse-comparison.test.ts`가 전용 계획/연결/결과/회귀다. `frozen-input.ts`의 무결성 확인 자료, 실제 해시·JPEG, `pipeline/source-buffer-store.ts`의 scope·공용 예산을 연결한다. `container-runner.ts`의 reuse 종류는 단일 구간 결과를 검증한다. Mac/Linux 218개·필수 110개 및 15/15회 정합성 통과지만 첫 시즌 약 2.44배 지연으로 현재 조합 채택 미추천이다. 예산 최적값 미확정, 다음 본문/커버 단계 시각 진단 권고다.

- **C 변환 30회 완료:** [계약·검증·원본·결과](../tasks/lookbook-import-performance/phase-3-transform-confirmation.md). `performance/comparison.ts`의 `makeTransformConfirmationPlan`/validator는 1·2 × 3부하 × 5쌍과 교차 순서를 고정한다. `comparison-report.ts`가 5회씩 집계하고 `transform-confirmation-report.ts`가 같은 부하/반복 번호의 전체·첫 시즌 저장 완료를 판정한다. 불완전한 쌍을 악화 없음으로 처리하지 않는다. 30/30 성공·반복 악화 없음, 변환 1 우선 후보 유지, 제품 정책은 미변경이다.

- **로컬 54회 완료:** [결과·원본·후속 추천](../tasks/lookbook-import-performance/phase-3-comparison.md). 48성공/6메모리 중단, C/E 각 9회 통과, C 우선 후속 후보. Mac/Linux 필수 99개/전체 207개 통과. `tools/lookbook-import-worker/src/performance/{overhead,overhead-entry}.ts`는 off/on 12회와 준비 제외 5쌍 검증, `container-runner.ts`는 Linux volume/결과 종류 검증, `resources.ts`는 승인된 작은 cgroup 동기 읽기를 담당한다. 제품 기본값·실제 클라우드 업로드·분산 재시도 계약은 아직 별도다.

- PR 리뷰의 선로딩 경로 갱신: `AvatarViewportObserver.onChange(of: items)` → `update(items:)`에 콜백의 최신 배열을 전달한다. 행 ID/좌표가 그대로인 프로필 경로 변경도 스크롤 없이 요청한다. 재현 테스트는 `AvatarNestedViewportTests.testSwiftUIViewportPrefetchesChangedPathWithoutScrolling`, 근거는 [리뷰 기록](../tasks/avatar-image-loading/review.md).

- 댓글 빠른 스크롤 표시: `CommentSafetyAvatarView.displayedImage`는 현재 표시 이미지가 없을 때 보호된 기존 메모리 캐시를 첫 body에서 즉시 확인한다. `AvatarImagePresentationState.configure(initialImage:)`도 UIKit/SwiftUI에 즉시 이미지를 전달하되 기존 async loader는 유지해 disk promotion을 생략하지 않는다. 서비스/메모리 용량을 추가하지 않는다.

- 답글 시트 높이: `PostCommentsSheetView.repliesSheet`는 iOS16+에서 62%와 large 두 detent를 제공해 상단 손잡이로 확장 가능하다. 사용자 실기기 QA의 작은 답글 영역 불편을 반영했으며 원댓글/입력창 구성은 유지한다.

- 댓글 아바타 경로 갱신: `CommentSafetyAvatarView.onChange(of: identity)`는 콜백의 새 identity를 `configure(_:)`에 직접 전달한다. 이전 View의 빈 path 재적용으로 상단 초기 행이 스크롤 전까지 기본 사진에 머물던 실기기 QA 결함 수정이며, 재진입 검증 기록은 Phase5 문서를 참조한다.

- 2026-09-20 재진입 상단 아바타 미표시 수정은 사용자 실기기 정상 및 상단4행 새 identity→start→loaded 로그로 확인했다. 조사용 `avatarSwiftUI.*`/`avatarPresentation.*` 임시 로그는 제거했다. 상세는 avatar-image-loading/progress/phase-5.md.


- 아바타 Phase4: `Views/Shared/AvatarViewportObserver.swift`의 row preference·미배치 행 추정·viewport 수요 → PostCommentsSheetView/PostCommentRepliesSheetView/PostDetailView. 기존 PostComments/PostCommentReplies/PostDetailViewModel의 일괄 선로딩·영구 prefetchedAvatarPaths 제거; 앞의 두 VM 이미지 DI도 LookbookContainer에서 제거. 명시 refresh는 서비스 실패 경로를 한 번 해제한 뒤 환경 refreshID로 보이는 avatar와 선로딩을 재시도한다. [구현·제약](../tasks/avatar-image-loading/progress/phase-4.md).

- 댓글·답글·안전 sheet 아바타는 `Views/PostDetail/CommentSafetyAvatarView.swift`로 통일했다. PostCommentCardView와 CommentBlock/Delete/ReportSheet가 사용자ID·경로를 전달하며, StateObject의 AvatarImagePresentationState가 완료/실패와 취소를 관리한다. 요청 전 loadedPath 마킹 없음. 출발 memoryOnly 정책은 Phase2 DI 유지. [Phase3](../tasks/avatar-image-loading/progress/phase-3.md).

- 이미지 로딩 최종 구조·실기기 비교는 [공개 검증 요약](../qa-image-loading-concurrency-2026-09-16.md) 참조. HTTP 디스크 히트도 본문 읽기 전에 디코딩 바이트를 예약한다. 예약 대기 중 캐시 제거는 `LookbookHTTPImageCacheTests.diskBodyWaitsForDecodeBudgetBeforeReadingAndHandlesEviction`에서 검증한다.

- Phase 5 재시도 QA: Debug `LookbookUITestFixtureRepositoryProvider.swift`의 `--uitest-lookbook-image-fail-once`가 브랜드/시즌/포스트 각 Storage 경로의 첫 로드만 실패시킨다. 해당 fixture의 prefetch는 no-op으로 유지해 표시 요청 실패가 확정적으로 보인다. `LookbookSmokeUITests.testImageRetryDoesNotOpenCardDetail`은 재시도가 카드 이동 없이 복구되는지 확인한다. 일반 서버·화면 로딩 정책은 변경하지 않았다. [실행 결과](../tasks/image-loading-stage-concurrency/phase-5-validation.md).

- 이미지 Phase 4: `Views/Shared/LookbookViewportObserver.swift`가 세 화면의 카드 frame·화면 높이·스크롤 방향을 받아 미배치 행 위치를 추정한다. `LookbookHomeView`/`BrandDetailView`/`SeasonDetailView` → 각 ViewModel `updateViewport` → `Services/ImageLoading/LookbookImagePrefetchController.swift`가 이미지 수요를 추가/300ms 후 해제한다. 홈은 끝 카드 표시 전 page 요청, 시즌은 기존 page24/cursor 계약 유지. `BrandRowView.swift`와 `Views/Shared/LookbookAssetImageView.swift`가 이미지 실패 재시도와 이전 응답 차단을 소유한다. DI/Coordinator·서버 API 변경 없음. [시작값·QA](../tasks/image-loading-stage-concurrency/phase-4-lookbook-screens.md).


- 이미지 Phase 3: `Services/ImageLoading/LookbookAssetImageRequest.swift`가 primary/secondary Storage·remoteURL·Referer 후보를 정규화하고 `BrandDetailViewModel`/`SeasonDetailViewModel` 프리패치 및 `Views/Shared/LookbookAssetImageView.swift` 표시가 공유한다. `BrandImageCacheProtocol`/`BrandImageCache.swift`는 prefetchAssets와 HTTP 갱신 API 경계다. `LookbookHTTPImageCache.swift`가 URL·Referer·maxBytes identity, memory/disk body+metadata, max-age/no-cache/no-store, ETag/Last-Modified 304/200, 일시/영구 오류와 중복 검증·취소를 소유한다. `ImagePipelineResources.shared`의 network/decode/I/O·바이트 예산을 공유한다. 좋아요/시즌·포스트 카드/포스트 상세는 공용 View를 통해 적용된다. [구현 정책과 한계](../tasks/image-loading-stage-concurrency/phase-3-http-cache.md). 화면 viewport/목록 선표시는 Phase4.


- 아모멘토 cold QA: 예약8/8→8/16→16/16MiB 비교, 마지막값을 후속 시작값으로 유지. 시즌목록 initial prefetch 대기는 아직 Phase4 대상. 사용자 체감 차이 없음. [비교 결과](../tasks/image-loading-stage-concurrency/phase-2-qa.md).

- Cold QA: BrandDetailViewModel의 metadata→initial prefetch await→seasons 공개 순서가 남아 있다(Phase4 목록 선표시 대상). ImagePipelineProcessor에 성공 body 바이트 계측을 보완했다. [삭제·재설치 관찰과 연결 상태](../tasks/image-loading-stage-concurrency/phase-2-qa.md).

- 2026-09-16 이미지 Phase 2: LookbookRepositoryProvider/BrandImageCache의 Data/file fetcher → LookbookStorageService → FirebaseImageDownload. 작은 썸네일은 byte 예약·네트워크·준비 gate, 큰 허용 크기는 임시 파일. 공용 저장은 표시와 분리. 관리자 LookbookRemotePreviewImageLoader도 파일 전송 지원. 외부 URL 폴백 TTL/통합·화면 프리패치는 Phase3/4. [구현·초기값·QA](../tasks/image-loading-stage-concurrency/phase-2-implementation.md).

- 확대 화면: `Views/PostDetail/PostImagePreviewView.swift`의 `LookbookImageViewerView` → 공용 `SimpleImageViewerVC`/`ImageViewerChromeView`. 패션 매거진 컨트롤·로딩/실패/저장 상태 공유, 한 장이면 번호 숨김, 기존 원본 loader와 onClose 유지. 검증은 `tasks/shared-image-viewer-editorial/implementation-plan.md`.

## 목적과 탐색 순서

Lookbook 변경 시 필요한 코드만 찾기 위한 인덱스다.

1. 화면/사용자 흐름 변경: 이 문서의 화면 표
2. 데이터/API 변경: `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`
3. 장기 기술 결정: `docs/ai/ADR.md`
4. 완료 상태·QA: 관련 task의 `progress.md`, `qa-checklist.md`

## 공통 조립

| 책임 | 진입점 |
| --- | --- |
| 앱 탭 조립 | `OutPick/Features/Lookbook/LookbookCompositionRoot.swift` |
| Feature DI/factory | `OutPick/Features/Lookbook/LookbookContainer.swift` |
| 화면 전환 | `OutPick/Features/Lookbook/Coordinators/LookbookCoordinator.swift` |
| 댓글 전환 | `OutPick/Features/Lookbook/Coordinators/PostCommentCoordinator.swift` |
| Repository 조립 | `OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift` |
| SwiftUI environment | `OutPick/Features/Lookbook/Environment` |
| 공용 store | `OutPick/Features/Lookbook/Domains/Stores` |
| DTO/mapper | `OutPick/Features/Lookbook/Models` |
| 이미지/미디어 | `OutPick/Features/Lookbook/Services` |

- Lookbook/Liked root는 UIKit navigation stack 위 SwiftUI Hosting 구조다.
- 상세 push/pop은 SwiftUI hidden route가 아니라 `LookbookCoordinator`가 소유한다.
- Lookbook/Liked root navigation stack은 `LookbookNavigationController`가 소유한다. Coordinator가 push하는 SwiftUI 화면은 화면별 `LookbookInteractivePopState`를 가진 `LookbookHostingController`로 감싼다.
- browse route는 edge/content pop을 허용하고, 작성 초안·관리자 내부 단계·mutation 상태는 `lookbookInteractivePopDisabled(_:)`로 동적으로 차단한다.
- 브랜드 요청, 삭제 관리, extraction 검토, 시즌 보수와 `AdminBrandManagementView`가 stateful 정책 대상이다. `AdminBrandManagementView` 내부 메뉴의 실제 push route 전환은 후속 작업이다.
- extraction 부족 이미지 보고가 저장되어 `correctionRequired`로 전환된 뒤에는 입력 폼이 더 이상 초안이 아니므로 interactive-pop 차단을 해제한다.
- `DefaultAppContentRouter`의 룩북 상세·브랜드 요청 내역 진입도 HostingController를 직접 만들지 않고 `LookbookCoordinator` push를 사용한다.
- View는 Repository/Firebase를 직접 만들지 않고 Container가 주입한다.
- SwiftUI 입력 화면 키보드 dismiss는 `KeyboardDismissSupport.outpickDismissKeyboardOnTap()`을 사용한다.
- Firestore 기본 identity는 ADR-020에 따라 문서 경로 ID를 사용한다. 앱의 Season DTO/Repository는 read-only이며 생성은 import worker의 Admin SDK materialization만 사용한다.

## Firestore 문서 ID 경계

| 확인할 내용 | 코드 진입점 |
| --- | --- |
| read schema와 DTO→Domain mapping | `OutPick/Features/Lookbook/Models/DTOs/`; identity가 필요한 mapper의 `toDomain(documentID:)` |
| snapshot 경로 ID 전달 | `OutPick/Features/Lookbook/Repositories/Implementations/Firestore*Repository.swift` |
| 브랜드·시즌·포스트 기본 identity | `BrandDTO.swift`, `SeasonDTO.swift`, `PostDTO.swift`와 각 Firestore Repository |
| 댓글·replacement 기본 identity | `CommentDTO.swift`, `ReplacementDTO.swift`와 `FirestoreCommentRepository.swift`, `FirestoreReplacementRepository.swift` |
| 태그 기본 identity | `TagDTO.swift`, `FirestoreTagRepository.swift` |
| import job·candidate 기본 identity | `SeasonImportJobDTO.swift`, `SeasonCandidateDTO.swift`와 각 Firestore Repository |
| Season 생성·무드 수정 | worker `processor.ts`의 create, `updateSeasonMoods` callable의 기존 문서 patch |
| 경계 회귀 테스트 | `OutPickTests/FirestoreDocumentIDBoundaryTests.swift` |

Repository가 `DocumentSnapshot.documentID`를 같은 snapshot에서 decode한 DTO와 함께 mapper에 전달한다. 자기 문서 ID는 DTO 필드로 중복 저장하지 않으며, `brandID`, `postID`, `userID`처럼 부모 경로나 별도 query 계약을 나타내는 ID는 해당 데이터 계약대로 유지한다.

## 화면별 진입점

| 변경 목적 | View | ViewModel/상태 |
| --- | --- | --- |
| 홈·검색 | `Views/LookbookHome/LookbookHomeView.swift` | `ViewModels/LookbookHomeViewModel.swift` |
| 관심 스타일 브랜드 전체 보기 | `Views/LookbookHome/InterestedStyleBrandListView.swift` | `ViewModels/InterestedStyleBrandListViewModel.swift` |
| 브랜드 요청 | `Views/BrandRequest` | `BrandRequestViewModel.swift`, `MyBrandRequestsViewModel.swift` |
| 브랜드 상세 | `Views/BrandDetail/BrandDetailView.swift` | `BrandDetailViewModel.swift` |
| 시즌 상세 | `Views/SeasonDetail/SeasonDetailView.swift` | `SeasonDetailViewModel.swift` |
| 포스트·댓글 | `Views/PostDetail` | `PostDetailViewModel.swift`, `PostCommentsViewModel.swift` |
| 좋아요 | `Views/Liked` | `LikedViewModel.swift` |
| 브랜드 생성 | `Views/CreateBrand/brand` | `CreateBrandViewModel.swift`, `CreateBrandFlowView.swift` |
| 관리자 홈 | `Views/Admin/LookbookAdminHomeView.swift` | `BrandAdminSessionStore` |
| 스타일 무드 관리 | `Features/StyleMood/Views/StyleMoodManagementView.swift` | `StyleMoodManagementViewModel.swift` |
| 브랜드 요청 관리 | `Views/Admin/AdminBrandRequestGroupsView.swift` | `AdminBrandRequestGroupsViewModel.swift` |
| 브랜드 관리 | `Views/Admin/AdminBrandManagementView.swift` | `AdminBrandManagementViewModel.swift` |
| 삭제 관리 | `Views/Admin/AdminLookbookDeletionManagementView.swift` | `AdminLookbookDeletionManagementViewModel.swift` |
| 시즌 discovery·import 통합 현황 | `Views/BrandDetail/SeasonImportManagementView.swift` | `SeasonImportManagementViewModel.swift` |
| 시즌 동일성 후보 검토 | `Views/BrandDetail/SeasonDiscoveryReviewView.swift` | `SeasonDiscoveryReviewViewModel.swift` |
| extraction 검토 | `Views/BrandDetail/LookbookExtractionReviewView.swift` | `LookbookExtractionReviewViewModel.swift` |
| 기존 시즌 보수 | `Views/BrandDetail/LookbookSeasonRepairView.swift` | `LookbookSeasonRepairViewModel.swift` |

경로 prefix는 `OutPick/Features/Lookbook/`이다.

- Phase 6 댓글·답글 생성 경로는 ViewModel이 본문별 pending UUID를 소유하고 `CreatePostCommentUseCase`/`CreateCommentReplyUseCase` → `CommentWritingRepositoryProtocol` → `CloudFunctionsCommentWritingRepository`로 전달한다. 같은 본문 네트워크 재시도는 UUID를 유지하고 입력 변경·성공·화면 종료 뒤 새 작성은 새 UUID를 쓴다.
- 댓글 입력은 trim 후 UTF-16 1,000 code unit 상한이며 `PostCommentInputBarView`가 길이 표시 없이 초과 입력을 막는다. 서버의 최종 상한·멱등·분당 20회 합산 quota는 `functions/src/lookbook/comments/{contracts,service}.ts`가 소유한다.
- 댓글·답글 텍스트 의미 자동 필터는 두지 않고 기존 신고·차단·운영자 검수 흐름을 유지한다. 현재 comment attachment는 빈 배열인 텍스트 전용이다.

- 시즌 후보 카드의 대표 이미지는 기존 nullable `coverImageURL`과 placeholder를 그대로 사용한다. Phase 7 backend는 목록 이미지 우선, 시즌 상세 콘텐츠 영역의 최상단 첫 유효 이미지 차선으로 URL을 채우며 SwiftUI 화면·Coordinator·DI는 변경하지 않는다. Worker 진입점은 `extraction/{image-candidates,season-cover}.ts`와 `season-discovery.ts`이고 상세 계약은 task의 `phase-7-season-cover-enrichment.md`다.

### 좋아요 탭

- 화면 조립: `LookbookCompositionRoot.makeLikedRoot` → `LookbookContainer.makeLikedView` → `Views/Liked/LikedView.swift`
- 카드: `LikedBrandCardView.swift`, `LikedSeasonCardView.swift`, `LikedPostCardView.swift`
- 표현 계약: `SAVED EDITS` 헤더, serif 섹션 제목, monospaced 인덱스·카운트, hairline 구분선과 작은 모서리를 사용한다. 브랜드는 정방형 가로 카드, 시즌은 세로형 가로 카드, 포스트는 2열 타이트 그리드다.
- 상태 계약: `LikedViewModel`의 브랜드·시즌·포스트 `SectionState`를 독립 렌더링한다. 부분 실패가 다른 섹션을 가리지 않으며 섹션 패널에서 전체 reload를 재시도한다.
- 동작 계약: pull-to-refresh, 섹션별 pagination, 좋아요 취소, 상세 push는 기존 ViewModel/UseCase/Repository/Coordinator 경계를 유지한다.

### 브랜드 생성과 로고

- 흐름: `CreateBrandFlowView` → `CreateBrandView` → `CreateBrandViewModel.saveBrand()` → `CloudFunctionsBrandStore.createBrand` → `LookbookStorageService` → `CloudFunctionsBrandStore.updateLogoPaths`.
- 완료 기준: 로고를 선택한 경우 `brands/{brandID}/logo/thumb.jpg`, `detail.jpg` 업로드와 두 경로의 단일 패치가 모두 성공해야 생성 완료 단계로 이동한다.
- 실패 기준: 업로드 또는 경로 패치 실패 시 성공한 업로드 객체를 rollback하고, 생성된 브랜드 ID를 `createdBrandDocument`로 유지해 같은 문서에 재시도한다. 재시도 중 브랜드 기본 입력은 잠근다.
- 브랜드 생성과 관리자 편집의 로고 실패 문구는 내부 Storage error/path를 노출하지 않고 `로고 저장에 실패했습니다. 다시 시도해주세요.`로 고정한다.
- Storage 권한: `storage.rules`의 브랜드 쓰기는 계정 문서와 총 관리자/브랜드 관리자 문서만 조회해 Storage rules의 Firestore 교차 조회 2문서 한도를 지킨다. 총 관리자는 신뢰된 운영 주체이므로 별도 브랜드 존재 조회를 하지 않으며, 클라이언트 경로는 생성된 brandID로 고정한다. 실행 프로젝트의 Storage service agent에는 교차 조회용 `roles/firebaserules.firestoreServiceAgent`가 반드시 필요하다.

## 자주 수정하는 흐름

### 관심 스타일 브랜드

읽기 순서:

1. `App/Session/CurrentUserStylePreferenceStore.swift`
2. `Domains/UseCases/LoadInterestedStyleBrandsUseCase.swift`
3. `Repositories/Protocols/BrandRepositoryProtocol.swift`, `Repositories/Implementations/FirestoreBrandRepository.swift`
4. `ViewModels/LookbookHomeViewModel.swift`, `ViewModels/InterestedStyleBrandListViewModel.swift`
5. `Views/LookbookHome/InterestedStyleBrandSectionView.swift`, `InterestedStyleBrandListView.swift`
6. `LookbookContainer.swift`, `Coordinators/LookbookCoordinator.swift`

현재 계약:

- 비공개 `users.selectedMoodIDs`와 공개 `brands.moodIDs`의 교집합을 `array-contains-any`로 조회한다.
- 정렬은 `likeCount DESC`, 문서 ID ASC이며 홈은 10개, 전체 보기는 첫 결과를 이어받아 이후 20개 단위로 조회한다.
- 커서는 `(likeCount, brandID)` field-value keyset이다. append는 브랜드 ID를 중복 제거하고 동일 커서 동시 호출을 막는다.
- `deletionStatus`가 없는 기존 활성 브랜드도 보존하기 위해 query 조건에는 넣지 않고 Domain의 `isVisibleToUsers`로 비노출 문서를 거른다.
- 검색 중에는 섹션을 표시하지 않으며, 조회 실패는 기존 전체 브랜드 목록과 분리해 재시도한다.
- 활성 계정은 관심 스타일을 1~5개 유지하므로 룩북에 편집 CTA를 두지 않는다. 방어적으로 관심 스타일이 0개면 개인화 섹션을 숨기고, 매칭 브랜드가 0개면 중앙 정렬한 안내만 표시하며 요청 CTA는 노출하지 않는다. 관심 스타일 섹션과 세로 목록 사이는 divider와 `전체 브랜드` 헤더로 구분한다.
- `CurrentUserStylePreferenceStore`는 bootstrap·온보딩 완료·마이페이지 저장·로그아웃에 맞춰 갱신되며 홈과 전체 보기의 첫 페이지를 다시 구성한다.
- `popularScore`는 계산·갱신 경로가 없어 Phase 6 정렬에 사용하지 않는다.

### 일반 사용자 브랜드 요청

읽기 순서:

1. `LookbookHomeView.swift`
2. `BrandRequestView.swift`, `MyBrandRequestsView.swift`
3. `LookbookCoordinator.swift`, `LookbookContainer.swift`
4. `MyPageViewController.swift`, `MyPageCoordinator.swift`
5. `AppContentRouting.swift`, `DefaultAppContentRouter.swift`

현재 계약:

- 일반 사용자의 새 브랜드 요청은 룩북 검색 결과가 없을 때만 노출하며, 정규화한 검색어를 요청 화면의 초기 브랜드명으로 전달한다.
- 룩북 홈 상단과 관심 스타일 빈 상태에는 요청 진입점을 두지 않는다. 홈 상단의 관리자 버튼은 총 관리자에게만 유지한다.
- `MyBrandRequestsView`는 진행 중/이전 요청 조회에 집중하며 새 요청 `+` 버튼을 제공하지 않는다.
- 요청 제출 성공 시 기존처럼 현재 요청 화면을 본인 요청 상황 화면으로 교체한다.
- 이후 재진입은 마이페이지 `ACTIVITY > 브랜드 요청 내역`에서 시작하며, `DefaultAppContentRouter.openMyBrandRequests()`가 MyPage navigation stack에 Lookbook 요청 상황 화면을 push한다.
- 총 관리자의 전체 요청 처리 화면은 관리자 콘솔의 브랜드 요청 메뉴로 분리하며 일반 사용자 본인 요청 내역과 혼동하지 않는다.

### 브랜드 상세

읽기 순서:

1. `BrandDetailView.swift`
2. `BrandDetailViewModel.swift`
3. `BrandRepositoryProtocol.swift`, `SeasonRepositoryProtocol.swift`
4. 관련 repository implementation
5. `LookbookContainer.swift`, `LookbookCoordinator.swift`

현재 계약:

- 초기 `Brand` snapshot으로 빠르게 표시한 뒤 단건 브랜드와 시즌 목록을 최신화한다.
- pull-to-refresh는 브랜드, interaction state, 시즌을 함께 갱신한다.
- 삭제 요청 등 사용자 비노출 상태면 상세 상태를 비우고 unavailable을 표시한다.
- 관리자 수정 결과는 `applyUpdatedBrand(_:)`로 상세 상태에 반영한다.
- 이미지 확대는 공용 `LookbookImageViewerView`/Infra UIKit viewer를 사용한다. 선택 이유는 ADR-017.

### 관리자 브랜드 요청

읽기 순서:

1. `AdminBrandRequestGroupsView.swift`
2. `AdminBrandRequestGroupsViewModel.swift`
3. `Domains/Entities/BrandRequest.swift`
4. `ListBrandRequestGroupsUseCase.swift`
5. `BrandRequestRepositoryProtocol.swift`
6. `CloudFunctionsBrandRequestRepository.swift`

현재 계약:

- segment는 `새 요청/처리 중/보류/완료`다.
- `보류/완료`는 최근 14일을 기본 표시하고 이전 기록은 별도 pagination한다.
- 브랜드 생성과 검수 완료는 분리한다.
- 삭제 요청 목록의 `active/failed` 정책과 혼동하지 않는다.

### 관리자 브랜드·시즌 관리

읽기 순서:

1. `AdminBrandManagementView.swift`
2. `AdminBrandManagementViewModel.swift`
3. `Domains/Entities/BrandManagement.swift`
4. 관련 repository/use case
5. `LookbookContainer.swift`

현재 계약:

- 총 관리자와 브랜드 owner/admin 권한을 분리한다.
- 메뉴는 정보, 관리자, `브랜드 스타일`, 시즌 가져오기, 삭제 흐름으로 구성한다. 브랜드 스타일 메뉴는 총 관리자에게만 보인다.
- 총 관리자는 정보 화면에서 브랜드 스타일 0~5개, 브랜드 스타일 메뉴의 시즌 목록에서 시즌 스타일 0~5개를 편집한다.
- 관리자 taxonomy 화면명은 `스타일 키워드 관리`이며 이름·alias 로컬 검색과 빈 그룹 숨김을 지원한다.
- 시즌 목록 검색은 `displayTitle`·`sourceTitle`·`year`·`term`을 대상으로 하고, 시즌 스타일 picker는 키워드 이름·alias를 검색해도 기존 선택 Set을 유지한다.
- 브랜드 생성·편집 picker의 `새 스타일 키워드 추가`는 생성 성공한 키워드를 현재 선택에 즉시 포함한다.
- 브랜드 생성·편집 picker는 전체 키워드를 기본 노출하지 않는다. 검색어가 있을 때만 이름·alias가 일치하는 active 키워드를 표시하고, 선택값은 별도 칩으로 유지하며, 결과가 없고 5개 미만일 때만 새 키워드 추가를 표시한다.
- 표시 용어만 변경하며 내부 `StyleMood` 타입, callable 이름, `styleMoods`·`moodIDs` 데이터 계약은 유지한다.
- 시즌 가져오기는 별도 segment 없이 한 화면에서 위쪽 discovery 상태 카드와 아래쪽 시즌 이미지 import job 목록을 함께 표시한다.
- discovery 요청은 즉시 job receipt를 반환하고, 화면은 브랜드의 최신 job을 Firestore stream으로 관찰한다. 화면 종료는 관찰만 끝내며 서버 job을 취소하지 않는다.
- 상태 카드는 queued/dispatching/running, succeeded, awaitingReview, correctionRequired, failed, cancelled, superseded를 구분하고 각 상태에 맞는 취소·재시도·URL 수정·후보 선택·동일성 검토 진입점만 제공한다. active 본문은 `ProgressView + 주 문구 + 보조 문구` 묶음 전체를 카드 본문 중앙에 두고 취소 action은 하단에 분리한다.
- Phase 3A 구현은 `SeasonImportManagementView.activeDiscoveryContent`와 `discoveryPhaseText`에서 확인한다. 카드 본문 최소 높이 안에서 묶음 전체를 중앙 정렬하며 dispatching/fetching/rendering/parsing/matching/publishing을 사용자 문구로 변환한다.
- `correctionRequired`는 job projection의 issue status를 `개선 대기 중`, `개선 처리 중`, `다시 가져오기 가능`, `추가 작업 필요`로 표시한다. 앱은 issue 목록·fingerprint·fixture·PR·배포 정보를 노출하지 않는다.
- issue 상태 설명은 내부 용어인 `추출 로직/개선된 방식`을 노출하지 않는다. 시즌 목록은 `가져오지 못했어요/다시 가져올 수 있도록 확인하고 있어요/다시 가져올 수 있어요`, 이미지는 같은 어조의 짧은 문구를 사용하며 상태 chip은 기존 값을 유지한다.
- 시즌 목록과 이미지 재시도는 총 관리자에게만 보이며 `fixed`와 상위 동일-stage runtime이 모두 있어야 한다. 앱 ViewModel과 callable 서버가 이 조건을 각각 검사하며 기존 개선 요청 버튼과 동일-version 즉시 재분석 경로는 제거했다.
- 시즌 목록 fix 재시도는 새 discovery job을 만들 때 원본의 서버 검증 fingerprint와 runtime projection을 승계한다. 그래야 contract 2 이상의 실제 성공 job이 cluster를 `verified`로 닫을 수 있다. 2026-08-05 AMOMENTO Development 재시도에서 후보 15개와 해당 전이를 확인했다.
- `wontFix` 중 원본 부재·접근 제한인 시즌 목록 문제는 기존 룩북 목록 URL 수정 action만 제공한다. 상세 구현 기준은 `docs/ai/tasks/lookbook-extraction-issue-operations/`다.
- `awaitingReview` 후보는 `SeasonDiscoveryReviewView`에서 신규 유지, 제외, 기존 시즌 연결 중 하나로 결정한다. 기존 시즌 연결 대상은 시즌명으로 표시하며 job ID는 운영 화면에 노출하지 않는다.
- `awaitingReview`여도 안전하게 `newSeason`으로 분류된 후보는 검토 완료를 기다리지 않고 별도 선택할 수 있다.
- 이미지 import job 행의 기본 식별값은 `SeasonImportJob.displayTitle`이다. `seasonTitle`을 우선하고 `sourceTitle`을 보조로 사용하며 내부 import job ID를 제목으로 표시하지 않는다.
- 신규 시즌 선택 화면은 published snapshot만 읽고, 화면 진입 자체로 discovery를 중복 시작하지 않는다.
- 실제 worker 구조는 `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`를 먼저 본다.

### 삭제 관리 화면

읽기 순서:

1. `Views/Admin/AdminLookbookDeletionManagementView.swift`
2. `ViewModels/AdminLookbookDeletionManagementViewModel.swift`
3. `Domains/Entities/LookbookDeletionRequest.swift`
4. `Repositories/Protocols/LookbookDeletionRepositoryProtocol.swift`
5. `Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
6. `Repositories/Implementations/CloudFunctionsMappers/LookbookDeletionCloudFunctionsMapper.swift`
7. `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
8. `docs/ai/entrypoints/FIREBASE.md`의 삭제 lifecycle

현재 계약:

- 앱 목록은 `active/failed`만 표시한다. 완료/history picker는 없다.
- 총 관리자 전역 목록은 브랜드별로 묶고, 브랜드 관리 내부는 해당 브랜드로 scope한다.
- 총 관리자만 브랜드 삭제 요청/복구와 failed manual retry를 수행한다.
- 브랜드 owner/admin은 해당 브랜드의 시즌·포스트 삭제/복구만 수행한다.
- owner/admin failed 문구는 실행 중/자동 재시도와 최종 실패를 구분한다.
- 다음 page는 목록 전체 하단 sentinel이 요청하며 `requestID`로 중복 제거한다.
- 상세 정책과 검증: `docs/ai/tasks/lookbook-deletion-request-list-simplification/`.

## Domain·Repository 지도

| 영역 | Entity/Store | Repository/UseCase |
| --- | --- | --- |
| 브랜드 | `Brand.swift`, `BrandUserState.swift`, `BrandInteractionStore` | `BrandRepositoryProtocol`, brand use cases |
| 시즌 | `Season.swift`, `SeasonUserState.swift`, `SeasonInteractionStore` | `SeasonRepositoryProtocol`, season use cases |
| 포스트 | `LookbookPost.swift`, `PostUserState.swift`, `PostInteractionStore` | `PostRepositoryProtocol`, post use cases |
| 댓글 | `Comment.swift`, `CommentUserState.swift`, `CommentInteractionStore` | comment repository/use cases |
| 관리자 | `BrandManagement.swift`, `BrandRequest.swift` | brand admin/request repository/use cases |
| 스타일 무드 | `Features/StyleMood/Domain/StyleMood.swift` | read/admin/season mood repository |
| 삭제 | `LookbookDeletionRequest.swift` | `LookbookDeletionRepositoryProtocol` |
| import | `SeasonImportJob.swift`, `SeasonCandidate.swift`, `LookbookExtractionDiagnostic.swift` | import/discovery repositories |
| extraction review | `LookbookExtractionReview.swift` | `LookbookExtractionReviewRepositoryProtocol`, `ManageLookbookExtractionReviewUseCase` |
| existing-season repair | `LookbookSeasonRepair.swift` | `LookbookSeasonRepairRepositoryProtocol`, `ManageLookbookSeasonRepairUseCase` |

- protocol은 `Domains/UseCases`, `Repositories/Protocols`에서 찾는다.
- 댓글 작성자 표시값은 `Domains/Stores/CommentAuthorProfileStore.swift`가 `UserPublicProfile`로 해석한다. 최초·pagination은 누락 작성자만 조회하고, 댓글 목록·답글·포스트 상세의 명시적 refresh는 이미 캐시된 작성자도 강제 재조회한다. 조회 실패는 기존 표시값을 보존하며 `.unknown`을 cache entry로 저장하지 않아 다음 refresh에서 재시도할 수 있다.
- 외부 구현은 `Repositories/Implementations`, DTO는 `Models/DTOs`, 변환은 `Models/Mapper`에서 찾는다.
- 기본 identity가 필요한 DTO mapper는 `documentID`를 명시적으로 받고, Repository가 `DocumentSnapshot.documentID`를 전달한다.
- `SeasonDTO`와 `FirestoreSeasonRepository`는 read-only다. 앱 client create/update는 rules에서 거부하고 기존 시즌 무드는 총 관리자 callable로만 수정한다.
- 상호작용 정합성은 `LookbookInteractionStore`와 대상별 store를 먼저 확인한다.

## 이미지·공유·Navigation

### 이미지

- 2026-09-16 Phase 1: `BrandImageCache` 기존 API → pipeline의 `ImageLoadCoordinator`. 같은 path/maxBytes load의 공용 작업, cache-only 디스크 조회 공유, 소비자별 취소, store/remove/전체 삭제 세대 검사. `LookbookAssetImageView`는 CancellationError/Task 취소에서 다음 후보 요청을 멈추고, BrandRow/InterestedStyleBrandCard/Header도 취소를 일반 실패로 표시하지 않는다. [실제 구현](../tasks/image-loading-stage-concurrency/phase-1-implementation.md). 기존 public protocol/Provider·Container 연결 유지. app/test target compile 통과, 실행·실기기 회귀 미수행. 이전 아래 in-flight 경합 설명은 Phase 0 기준이며 공용 작업 등록은 이번에 보완했다. ViewModel path set/viewport는 Phase 4 대상이다.

- 2026-09-16 Phase 0 계측 코드 적용: `ImageCacheMetrics` → pipeline 단계/세 ViewModel의 metadata·list 공개 → 카드 `ui.*.assigned`/이미지 분기 onAppear. 기존 로딩 정책은 유지한다. [계측 사용법](../tasks/image-loading-stage-concurrency/baseline-instrumentation.md). 앱 build 통과, 실기기 기준선은 미측정이며 아모멘토를 대상으로 준비한다. 아래 계획 미구현 기록 중 Phase 0 상태는 이 기록으로 갱신한다.

- 2026-09-16 단계별 자원 관리 설계·구현 계획: [image-loading-stage-concurrency](../tasks/image-loading-stage-concurrency/implementation-plan.md). 현재는 문서 작성만 완료했고 아래 코드 동작은 아직 변경하지 않았다. 공용 pipeline/외부 URL 캐시 통합과 홈·브랜드 상세·시즌 상세의 데이터 선표시/방향 기반 프리패치를 계획한다.

- 공용 로딩/캐시: `Services/ImageLoading`.
- extraction review와 existing-season repair의 외부 이미지 preview는 `LookbookRemotePreviewImageLoader` 단일 인스턴스를 Container에서 공유한다. 메모리·디스크 캐시, 동일 요청 in-flight 병합, 중복 제거된 8개 window prefetch와 최대 동시 4개 다운로드를 사용한다.
- 공용 렌더링은 `Views/Shared/LookbookRemotePreviewImageView.swift`다. extraction review는 순번·제외 상태가 있는 가로 단일 행 `LazyHStack`, repair는 keep/add/reorder/remove-candidate 구역별 2열 `LazyVGrid`로 표시한다.
- 확대 viewer: `Views/PostDetail/PostImagePreviewView.swift`에 정의된 `LookbookImageViewerView`와 Infra viewer.
- 같은 Storage path 덮어쓰기 시 `updatedAt` 기반 cache invalidation을 확인한다.

시즌 상세 목록 계약:

- `LoadSeasonDetailUseCase`는 source order 포스트를 첫 24개와 `PageCursor`로 반환하고, ViewModel이 cursor를 보존한다.
- 마지막 12개 카드 영역에서 다음 24개를 요청하며 `PostID` 중복 제거, 동일 cursor 동시 호출 차단, refresh generation 이전 결과 폐기를 적용한다.
- Firestore visibility filter로 빈 page가 반환돼도 `nextCursor`가 있으면 다음 page까지 이어서 조회한다.
- 첫 12개와 현재 위치 앞 32개 이미지를 prefetch하고, 다음 page가 append되면 새 이미지 최대 24개를 카드 노출 전에 즉시 큐에 등록한다.
- prefetch concurrency 4는 호출 한 번의 작업 수다. 여러 호출이 겹칠 수 있으므로 공용6 중 visible용2 확보를 보장하지 않는다. 현재 공용 permit은 다운로드뿐 아니라 디코딩·디스크 저장까지 포함한다. 저장은 `.memoryAndDisk`이며 기존 in-flight는 조회/등록이 별도 actor 호출이어서 최초 동시 미스 경합이 가능하다. ViewModel path set은 예약 시 기록하므로 실패·취소·eviction 후 재요청 정책을 보장하지 않는다. 개선 계획은 위 task를 참조한다.
- load-more 실패는 기존 포스트를 유지하고 화면 하단 재시도를 제공한다.

### Chat 공유

- Lookbook 쪽 payload/bridge: `OutPick/Features/Lookbook/`의 share 관련 View/Navigation.
- Chat 접합부: `docs/ai/entrypoints/CHAT.md`.
- snapshot/상세 최신화 결정: ADR-011~013.
- 공유 완료 확인 UI: `Views/Shared/LookbookShareConfirmationBar.swift`와 `BrandDetailView.swift`, `SeasonDetailView.swift`, `PostDetailView.swift`.
- `채팅방으로 이동` 처리 중에는 로딩을 표시하고 이동·계속 보기 버튼과 interactive sheet dismiss를 모두 잠근다. 성공하면 확인 sheet를 닫고, 최신 유효 요청의 실제 실패만 오류 toast와 재시도를 허용한다.

### URL 기반 시즌 import

- **A~F 비교 연결(2026-10-03):** [최신 코드·검증·Docker 준비](../tasks/lookbook-import-performance/phase-3-comparison.md). `performance/comparison.ts` → `season-runner`/`memory-supervisor`와 `frozen-input`의 실제 추출·JPEG/저장 spy; `buffer-inventory`는 논리 바이트 보유량, `container-runner`/`local-entry`는 고정 이미지/cgroup/종료 증거, `comparison-report`는 54회 분모·중앙값과 별도 5쌍 반복 악화를 담당한다. 초기 batch 8, C/E 공용 4/2/4/전체, 재사용 off, 3부하, 표본 간격 500ms를 사용자가 승인했다. 기본 서버 동시성·API 계약 변경은 없다. 아래 184개 검증은 직전 단계 기록이며 최신 필수 ID는 93개/전체 테스트 201개다.

- **성능 개선 Phase 0~3 진행(2026-10-03):** [최신 시즌 실행·중단 감독](../tasks/lookbook-import-performance/phase-3-runner.md), [실행안](../tasks/lookbook-import-performance/local-container-proposal.md), [계획](../tasks/lookbook-import-performance/plan.md). `performance/season-runner.ts`는 로컬 시즌 순서·총 5회, `memory-supervisor.ts`는 컨테이너 표본/중단을 담당한다. `pipeline/{resources,scheduling}.ts`의 선택적 공용 signal이 `processor`와 `extraction/dedupe`에서 신규 실행/대기 슬롯을 막고 실행 중 작업 종료를 기다린다. `sourceBufferBudgetBytes` 미설정은 재사용 off, 각 processJob scope는 독립이며 종료/검토 대기 후 복구하지 않는다. index/환경변수/HTTP로 새 runtime을 켜지 않는다. 게이트 184개·필수 ID 76개 통과. 제품 retry/분산 계약·54회 비교는 미완료이며 기본 동시성·품질·JPEG·API/Firestore 계약 유지.

- 앱: `CreateBrandCandidateSelectionView.swift`, `AdminBrandManagementView.swift`, `SeasonImportManagementView.swift`.
- discovery 상태 owner: `CreateBrandDiscoveryViewModel.swift`. View가 사라질 때는 Firestore 관찰만 끝내고 서버 job은 취소하지 않는다.
- repository: `CloudFunctionsSeasonCandidateDiscoveryRepository.swift`가 최초 `discoveryJobID` 또는 브랜드 published pointer를 관찰하고, `FirestoreSeasonCandidateRepository.swift`가 `newSeason` nested candidate만 로드한다.
- `BrandStoringRepository.createBrand`는 `BrandCreationReceipt(brandID, discoveryJobID)`를 반환해 브랜드 생성 transaction에서 함께 만들어진 최초 job을 그대로 이어받는다.
- 이미지 import 요청은 `discoveryJobID`, `generation`, `candidateSnapshotHash`를 전달한다. 새 discovery generation이 시작되면 브랜드의 published pointer를 같은 transaction에서 즉시 비우며, 서버는 각 import job 생성 또는 asset retry transaction 안에서 브랜드 pointer·job·candidate의 generation/hash, 만료, `newSeason` resolution과 URL을 다시 검증한다.
- review: `LookbookExtractionReviewView.swift`, `LookbookExtractionReviewViewModel.swift`, `CloudFunctionsLookbookExtractionReviewRepository.swift`.
- import 현황의 검토 action은 `LookbookCoordinator`가 상세 화면을 push하고 `LookbookContainer`가 Repository/UseCase/ViewModel을 조립한다.
- review 화면은 예상/발견 수량 방향을 기준으로 동작한다. 초과·예상 수 미확인은 불필요 후보 제외와 `승인`, 미달은 승인 없이 `누락된 이미지 알리기`, content hash 미완료는 승인 차단을 제공한다. correctionRequired 재분석은 총 관리자에게만 노출한다.
- review 초기 로딩 화면은 안내 문구 아래에 accent 색상의 큰 진행 표시를 배치한다.
- 두 review 화면의 외부 후보 이미지는 같은 remote preview loader/cache를 공유하며 URL별 중복 네트워크 요청을 병합한다.
- `원본과 다시 비교` 진행 화면은 설명 아래 accent `ProgressView`를 표시한다. diff가 없으면 상세 화면을 자동 종료하고 목록의 `원본과 다시 비교` 상태로 복귀하며, 실제 변경이 있을 때만 `변경 검토`로 전환한다.
- Functions/worker: `docs/ai/entrypoints/FIREBASE.md`, `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`.
- Cafe24 목록의 `collection_detail.html`처럼 section과 detail을 underscore로 연결한 상세 경로도 공통 discovery 후보로 인정한다. 이미지 링크와 제목 링크가 같은 URL로 분리된 목록은 URL 기준 병합으로 한 시즌 후보에 수렴한다.

## 변경 시 함께 갱신할 문서

- 화면·DI·Coordinator 위치: 이 문서와 `docs/ai/ENTRYPOINTS.md`.
- 데이터/API: `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`.
- 장기 선택: 새 ADR 또는 기존 ADR.
- phase 상태와 QA: 관련 task의 `progress.md`, `qa-checklist.md`.
# 대용량 로컬 준비 실험 진입점(2026-10-03)

- [설계·승인·247개 게이트·7회 실행 기록](../tasks/lookbook-import-performance/phase-3-large-input-design.md).
- `tools/lookbook-import-worker/src/performance/large-input.ts`: 기존 frozen 자료에서6개 독립 synthetic job을 구성, 원본 순서/cover/golden/derived digest/고정 계약 확인. metadata fixture는 `fixtures/performance-large-base.json`.
- `large-comparison.ts`:7회 계획과 분모/압박 성립/중단·미수행 집계. `reuse-entry.ts`→`runReuse`의 `large-input-v1`→기존 `SubmissionRuntime` U/P4→`connectedExecutor`. 실제 API·앱 DI 변경 없음.
- `reuse-trace.ts`: 새 profile의 대상·시도 수에서 유한 상한을 산출, 기존 소규모 검증 경계 유지. `reuse-contract.ts`는 입력별 계약으로 읽기/JPEG/경로/cache를 교차 확인한다.
