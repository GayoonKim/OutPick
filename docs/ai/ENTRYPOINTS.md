# OutPick Entrypoints

Q7 합의한 검증 완료(2026-10-07): [최종 결과·커밋 기록·후속 미검증](tasks/lookbook-import-performance/product-queue-q7-final-results.md). K실제종료→같은execattempt2새파싱/재검토/저장, L총5회소진→실패목록→맨뒤수동새exec/새5회→성공제거를확인했다. K/L전체8접수·124JPEG·새task6/누적24·108.957초·queue/task둘다idle. 새26후보0%/base12 100%,서버필수6게이트와앱28개passed. 서버/Worker/앱/검증 커밋4개를 생성했고 설계·결과 문서67개 포함도 사용자 승인으로 확정했다. 실제장시간/24h삭제·관리자웹은후속미검증. 아래시점별구현중/미배포는과거이력이다.

Q7 이어 실행 구현(2026-10-07): 사용자 승인으로 기존 K3건·남은5접수·새20분창1회·추가OOM0을 고정했다. `tools/lookbook-import-worker/scripts/q7-retry-runner.mjs --continue=true --fault-campaign=<새UUID>`는 `q7-retry-contract.mjs`의 동일3영수증·oldrun 실제 증거·미공개 원장 검사를 통과해야 같은 K task1개를 전달한다. 원본은 배타적 `continuation-original.json`에 보존하며 새 장애 campaign은 L만 대상으로 한다. QV13/14 포함 verifier40개 통과(`1791350705468-a622bcfb-7122-4c77-83d2-b5f4cbfcc93a`). 새 Worker snapshot 필수 검사/배포와 실제 검증은 아직 전이다. [확정 실행안](tasks/lookbook-import-performance/q7-retry-development-continuation-plan.md).

Q7 K/L 실제 중단(2026-10-07): K3접수·실제OOM1회는확인했지만system logName 인코딩오류로자동정산이막혔다. `cloud-logging-evidence.ts`의exact필터/KR20은수정했고새candidate미배포다. [실제결과](tasks/lookbook-import-performance/q7-retry-development-results.md), [기존K유지·남은5접수이어실행제안](tasks/lookbook-import-performance/q7-retry-development-continuation-plan.md). 현재Q7미완료·최종커밋전이며원래20분창을임의연장하지않는다.

Q7 K/L 재시도 검증(2026-10-07): Worker `queue/development-retry-fault.ts`는 검증된 Development campaign에서만 고의OOM1회/다운로드 전5회 실패를 소비한다. `scripts/q7-retry-runner.mjs`·`q7-retry-contract.mjs`는 제품최대8접수·20분·미확정 재전송 금지·실제 플랫폼 종료/124JPEG·실패목록 제거를 연결한다. [실행안](tasks/lookbook-import-performance/q7-retry-development-execution-plan.md), [필수 결과](tasks/lookbook-import-performance/q7-retry-local-results.md), [서버](entrypoints/FIREBASE.md), [검사](entrypoints/TESTS.md).

Q7-R1/R2 구현·R3 로컬 검사 완료(2026-10-07): [현행 소스 게이트·원본·미검증](tasks/lookbook-import-performance/q7-retry-local-results.md) — 제품큐93/Functions324/Worker359/Firestore·Storage131/Q7 verifier31/Linux2 통과. [새 짧은 Development 실행안](tasks/lookbook-import-performance/q7-retry-development-execution-plan.md)은 K/L새2브랜드·실제 종료1회/제어 실패5회·수동 새 시작·최대8접수 제안이다. 새 장애 방법·유료 범위 확인 전 장치 구현/배포/실행은 하지 않았다. 아래 ‘검사 중/선택 대기’는 이전 이력이다.

2026-10-07 Q7-R1 최신: D1/D2 추천안 확정 후 종료 정산·처음부터 재시도·실패 목록을 구현 중이다. 아래 R0 결정 대기는 과거 기록이다. 서버 callable `getSeasonImportFailures/requestSeasonImportFailureRetry/dismissSeasonImportFailure`는 Functions `lookbook/import/queue/{failure-service,failure-functions}.ts`; Worker는 `queue/{failure-record,restart,job-write,termination-retry}.ts`와 processor/server/batch-runner에서 연결한다. 실패 목록의 CAS는 version+executionID이며 원본 실행 이력은 보존한다. 필수 검사는 `verification/{functions,lookbook-product-queue,lookbook-import,firestore}.json`과 KR01~11 테스트다. 새 종료 경로의 전체 검사·원격 검증은 아직 완료 전이다. [최신 계약·상태](tasks/lookbook-import-performance/q7-retry-contract-plan.md).

2026-10-07 Q7-R0 세부 계약안: [종료 정산·처음부터 재시도·실패 목록 API/데이터·변경 후보·필수 검사](tasks/lookbook-import-performance/q7-retry-contract-plan.md). 부분 저장은 현재 재사용되고 승인 저장은 추출 attempt 수를 유지함을 확인했다. 이번 등록의 부분 산출물 정리와 새 추출의 재검토 정책 D1/D2는 사용자 선택 대기다. 실패 identity/version·조회/수동재시도/명시적안함 callable 제안·원본 실행/완료 시즌 보호·시도5회와 실제 종료 증거 계약을 기록했다. 새 코드/실제 API/게이트 연결은 아직 없다.

2026-10-07 Q7 세부 구현 계획 개정: [Q7-R0~R5·변경 후보·필수 검사](tasks/lookbook-import-performance/product-queue-q7-server-validation-plan.md), [전체 계획의 최신 정정](tasks/lookbook-import-performance/product-queue-implementation-plan.md). 종료 정산·처음부터 재시도·실패 목록 생명주기를 기존 계획에 반영했다. 현재 부분 산출물 정리·검토 승인 후 실패의 시도 예산/재검토·실패 목록 API/키의 세부 계약은 R0 진행 중이며 코드 착수 가능/전체 계획 완료로 표시하지 않는다. 이후 로컬 필수→새 짧은 원격 실행안→검증→최종 정리 순서다.

2026-10-07 실패 목록 최종 확정: [문서 생명주기·재시도 결정](tasks/lookbook-import-performance/season-failure-retry-decision.md). 시즌별 목록 문서1개·재실패 최신화·성공 또는 명시적 ‘재시도 안 함’ 선택 시 제거·무선택 유지. 서버 실행 기록은 원래 보관 정책 유지. 이번은 설계 문서 반영이며 실제 데이터 삭제·코드 구현·새 게이트 실행은 없다.

2026-10-07 최신 Q7 정정: [시즌 실패 기록·처음부터 재시도 결정](tasks/lookbook-import-performance/season-failure-retry-decision.md). 추가하려던 중간 복원·미완료 실행 재연결은 제외한다. 비정상 종료 확인 뒤 해당 시즌을 처음부터 자동 재시도(최초 포함 총5회)하고, 소진하면 실패 결과/이력을 남긴다. 전체 선택 시즌 처리 뒤 실패 목록에서 맨뒤 새 수동 요청·새5회로 재시도하며 완료 시즌은 유지한다. 현재 상세 정리/시도/API 계약과 Q7 새 검증은 준비 전이며 기존 코드 통과·Q7 완료를 뜻하지 않는다. 아래 중간 복원 계획은 이전 이력이다.

2026-10-07 최신 확정: [Q7 집중 계획](tasks/lookbook-import-performance/product-queue-current-operations-plan.md). Q7은 기존 정상 A/B·A~J 결과와 짧은 실제 종료·복구 검증으로 마무리한다. 실제12/14/15분 플랫폼 경계 실측은 후속 미검증으로 분리하며 기존 안전장치·로컬 검사는 유지한다. 다음 핵심은 강제 종료 뒤 복구 상태 전환과 미완료 저장 재연결이다. [목록·운영 지침 후속 작업](tasks/admin-web-operations-migration/lookbook-list-operations-followup.md)은 관리자 웹으로 분리한다. 기존 snapshot을10개씩 조회하고 원본 사이트 순서를 유지하며 발매일 필드·미확인 표시를 추가하지 않는다. 이번 변경은 문서만이며 Q7 전체 완료·새 원격 실행을 뜻하지 않는다.

2026-10-07 룩북 운영 정책: [관리자 웹 결정](tasks/admin-web-operations-migration/decisions.md)의 ‘룩북 등록·운영 기준’. 처음10개·더보기10개·선택 자유·최근1~2년 중심, 콜라보 우선 없음. 최근 발매한 룩북부터 확인·등록하는 운영 지침과 원본 사이트 순서로 표시하는 목록 계약을 구분한다. 관리자 웹의 별도 후속 작업이며 Q7의 선행 조건이 아니다.

2026-10-07 잔여 검증 실행안 작성: [장시간·복구 최소 실행안](tasks/lookbook-import-performance/product-queue-q7-boundary-validation-plan.md). L/T/O각1회·11접수·90분·추가 관리예산3USD/기존누적10USD안이다. 정상6설정에서미시작항목을남기기위해2023SS를추가한7시즌안을준비했다(로컬30후보/HEAD6,704,829B). 강제종료시active/draining을조건부복구상태로정산하는경로와미완료execution/continuation재연결이현재없음을확인했다. 실제종료증거·완료/시도이력보존·전용Development고의지연/종료기능을추가하는방향은사용자확인전미확정이다. 원격변경/새접수/고의장애0,기존Q7미완료·커밋0. 승인순서대로실행안준비는진행했으며추가기술결정대기중이다.

2026-10-07 최신: [A~J 실제 제품 검증 결과](tasks/lookbook-import-performance/product-queue-q7-ten-brands-results.md) — 36접수·16시즌 저장·710JPEG와 현재 공개 원장 대조가 완료됐다. 두 100ms 예약 wave에서 실제 서버 순번과 브랜드 대기·실행 비중첩을 확인했다. 앞 run 시작 후 신규 접수는 없었으므로 A/B의 active 중 도착과 동일한 조건으로 표시하지 않는다. 메모리 최고 84.05%, 최대 표본 공백 380.7ms, 이미지 실패·시즌 재시도·중단 0회. 실행기 job 기록 누락은 원본 보존·별도 job index 대조로 정산했으며 이후 도구 기록 연결을 수정했다. 최종 client31/Worker359/Linux2 필수 검사 통과. 실제 장시간·플랫폼 종료 및 청구 전체는 별도 미검증이다. 전체 Q7 완료·커밋은 아직 아니다. 아래 실행 전/진행 중 문구는 과거 기록이다.

Q7 A~J 실행기 준비 완료(2026-10-07): `scripts/q7-wave.mjs::runQ7Wave`는 응답 대기 없이 절대 100ms 간격으로 최대10건을 시작한다. `q7-journal.mjs`/runner는 동시 기록을 직렬·원자 저장하고, 실패하면 새 투입을 멈춘 뒤 시작한 요청을 모두 정리한다. `assertQ7WaveEvidence`는 두 wave 각10건의 예정/시작/HTTP 직전 기록·실제 서버 순번과 서로 다른 브랜드 대기를 검증한다. 실제 서버 도착 간격을100ms로 단정하지 않고 편차와 순서 변경을 기록한다. 승인된 A6/B2/C~J각1·16시즌·36접수·기존 비용/2시간 상한은 유지한다. 필수 verifier gate `1791303321801-54c50236-ead4-40c3-ad2d-f126a1131cbc` passed31; digest `e3da40995238821d1f710fe61930efb6057e14c69792897cc00aa61f155c9c66`. 원격 A~J는 아직 실행 전이다.

Q7 A/B 기능 저장 완료(2026-10-07): [결과·전체원본·실패보존·한계](tasks/lookbook-import-performance/product-queue-q7-smoke-results.md).7accepted/3succeeded/126JPEG golden+generation/63공개원장 확인,queueidle. `q7-runner --verify-only=true --resume=<runID>`는 확정7건만 재검사하며 mutation하지 않는다. `q7-storage-evidence::q7PublishedCoverReference`가 현재cover 원장경로/generation을 확인한다. client gate26건 통과. A~J100ms wave 보완/검증은 다음이다.

Q7 기능 저장 smoke 전환 확정(2026-10-07): A2 추출44개/해시 완료, run 약3.2초로 active 구간을 관측하지 못해 original overlap smoke는 중단했다. 사용자 결정에 따라 같은 접수 유지·총7건 안의 저장 기능 완료를 이어가고 대기 조건은 A~J100ms에서 확인한다. `q7-runner --resume=<runID> --resume-after-extraction=true`→`q7-resume::assertQ7ExtractedContinuation`이 idle/동일released batch/검토대기2를 검사한다. report overlapObserved=false/functionalStorageSmoke/historicalFailurePreserved로 구분한다. Q7 gate24건 통과. 복구 해제 준비 이벤트도 Functions321/Emulator75건 뒤 Development handler1개 배포 완료.

Q7 복구 재개 오류 후속(2026-10-07): candidate023에서 이전 성공 item을 다시 begin하려 해 QUEUE_ITEM_NOTQUEUED로 종료됐다. `src/queue/batch-runner.ts`는 terminal processingStatus를 재실행하지 않고 `coordinator.ts::finishBatchRun`에서 실제 execution/continuation 종료를 재확인한다. 불일치 시 차례 반환을 막는다. PQ06 Emulator 필수2건 추가/제품큐74건 통과. 새 Worker gate/후보가 필요하며 기존 A2 import는 preparing/접수2건 그대로다.

Q7 현재 접수 이어 실행(2026-10-07): `scripts/q7-resume.mjs`가 확정 A 생성/A2 import의 payload digest·plan·선택 시즌 검사와 원본 중단 기록 보존을 담당한다. `q7-runner.mjs --stage=smoke --resume=<runID>`는 같은 계정·원격 snapshot·preparing 상태를 대조하고 OBSERVER_READY 후 기존 요청 조회로 기다린다. 새 후보의 conditional recovery는 별도 CLI로 적용한다. QV07 필수3건 포함 gate23건 통과. 기존 sample-gap 실패는 성능 통과로 바꾸지 않는다. [현행 계획/증거](tasks/lookbook-import-performance/product-queue-q7-server-validation-plan.md).

Q7 sample-gap 최소 수정(2026-10-06): Linux1CPU/2GiB에서 첫 Playwright JS 모듈 로딩503.670ms/표본공백604.259ms, warm0.357ms를 재현했다. `src/index.ts::main`은 모듈만 Ready 전에 준비하며 실제 browser launch는 작업 차례에 유지한다. 표본/메모리/동시성 기준은 바꾸지 않는다. 이 runtime 수정은 새 gate·local bootstrap·Development 확인 전 미검증이며 현재 `92ad4778` batch는 복구 재개 전이다.

Q7 실제 smoke 중단 분석(2026-10-06): `00022-zic`에서 목록 탐색 succeeded, 접수2회 후 실행기 preparing/jobID-null 처리 오류. 서버는 별도로 sample-gap922ms로 recoveryRequired이며 이미지job 미생성·import preparing다. 원본/로그/inspect는 run `92ad4778-f90e-408a-b062-8afc46383952/evidence/`에 보존했다. `scripts/q7-receipts.mjs::waitQ7Receipt`로 접수 준비와 discovery batch release를 조회로 확인하도록 도구를 수정하며 QV06 필수 검사2건 추가. 자원 측정 원인 확인 전 복구 재개/추가 접수는 하지 않는다.

Q7 1~2 원격 완료·3 수정 검증 중(2026-10-06): recovery candidate `00021-kup`·최소 IAM·실제 ID token·preflight 통과 후 A를 조건부 정산했다. queue idle/batch released/stateRevision11, 원본 job correctionRequired·종료증거·90일 audit 보존. 실제 현재 UNAFFECTED는29후보/활성 more0/1page이며 paginate 문자열 오탐을 확인했다. `season-discovery-controls.ts`가 rendered 최종 활성 컨트롤·앞 pagination 판정과 가시 more 클릭 진입점이다. Worker 변경본은 새 gate 전이며 원격 수정본 적용·제품 smoke/A~J는 아직 미검증이다.

Q7 복구 권한 방향 확정(2026-10-06): 본인 Google 운영 계정 하나→Development 전용 recovery SA→기존 조건부 복구 API. `src/queue/recovery-auth.ts`는 사용자 access token으로 `generateIdToken`만 요청하고, 배포 스크립트/Q7 preflight는 recovery env를 고정·검사한다. IAM 적용·새 gate·candidate·정산은 진행 중이며 아래 이전 gate 결과는 변경된 소스의 통과를 의미하지 않는다. 정확한 권한과 1~6 순서는 [통합 계획](tasks/lookbook-import-performance/product-queue-q7-server-validation-plan.md)의 확정 절을 따른다.

이전 candidate 진행(2026-10-06): verified Worker-only Development snapshot 절차가 추가됐고 Worker gate `1791290297722-acd38c5e-89ae-442f-9a7e-cf88e2da3abb`(354 tests/lint/fixtures/deploy contract), product queue gate `1791289769511-4141e4a8-d6d9-4c08-9dc0-a49b5f414fcc`(72 emulator tests + Worker/Functions build)가 통과했다. Candidate `00020-yun`은 Q7 0% tag, digest `91c937c1…733b`, 성능 계측 enabled, 1 CPU/2GiB/concurrency2/900s로 Ready이며 base `00012-fih` 100%를 보존한다. 현재 Q7 preflight 통과, queues RUNNING/0 tasks. Recovery endpoint는 전용 Development IAM identity가 없어 아직 꺼져 있고 A head는 정산 전 상태다. [Q7 readiness](tasks/lookbook-import-performance/product-queue-q7-readiness.md)에서 권한 선택·상세 증거와 다음 순서를 확인한다.

Q7 초기 실행 상태 이력(2026-10-06): [전체 단계](tasks/lookbook-import-performance/product-queue-q7-server-validation-plan.md), [P2 최소 연결 구현·검증](tasks/lookbook-import-performance/q7-verifier-p2-plan.md), [실행 조건·비용·Development 준비](tasks/lookbook-import-performance/product-queue-q7-readiness.md), [검증 행렬](tasks/lookbook-import-performance/q7-verification-matrix.md). Development Google 계정의 platform admin 확인 뒤 A 브랜드 생성과 최초 탐색을 접수했다. 29개 후보를 찾았으나 동적 더보기 잔여 신호로 job이 `correctionRequired`가 됐고, 이전 Worker의 도메인 상태 매핑 오류가 대기열을 `recoveryRequired`에 남겼다. 원본 evidence, settlement 구현 및 PQ14 emulator 계약은 readiness의 최신 상태를 따른다.

**Q7 실행 진입점:** `tools/lookbook-import-worker/scripts/q7-runner.mjs` (`--stage=smoke|tenBrands`)가 Google 로그인 세션, active `platformAdmins` 확인, Deployment/task queue preflight, 기존 제품 callable, read-only Firestore/Storage 증거 수집을 연결한다. 로그인 페이지·journal·스토리지 판정·preflight는 같은 scripts 디렉터리의 `q7-session.mjs`, `q7-login.html`/`.js`, `q7-journal.mjs`, `q7-storage-evidence.mjs`, `q7-development-preflight.mjs`다. 필수 로컬 gate는 `verification/lookbook-q7-verifier.json`이다. uncertain mutation이 남은 run은 자동 재전송하지 않고 후속 실행을 차단한다.

Q7 platformAdmins P1 구현·로컬 게이트 완료(2026-10-06): `createBrand`와 queue admission/status, extraction review/repair preview, discovery cancel/candidate resolution은 `platformAdmins/{uid}` 활성/비회수 권한을 확인한다. `queue/preparation.ts`는 접수 뒤 권한 회수를 배치 진행 중단으로 바꾸지 않도록 브랜드 활성 상태만 검사한다. Functions gate 320 tests와 제품 큐 Emulator gate 69 tests가 통과했다. 기존 공용 `brandAuthorization` 및 비 Q7 API·Firestore Rules는 이번 범위에서 유지한다. [설계/변경/검증](tasks/lookbook-import-performance/platform-admin-transition-plan.md).
Q7 Development 도구 P2 구현: `outpick-test` 전용 Firebase Web app을 생성하고 public config는 ignore/mode 600으로 저장했다. 인증·journal·runner·실제 Storage bytes/hash/JPEG 검사·원격 preflight가 구현됐다. live smoke에서 A brand/discovery job이 생성됐고, 현재 queue head가 복구 확인 상태라 추가 요청은 차단돼 있다.

Q7 권한 범위 확정: Q7 필수 경로 우선 전환(A), P1 로컬 구현·검증 완료. [최종 계획](tasks/lookbook-import-performance/platform-admin-transition-plan.md).

Q7 플랫폼 관리자 전환 초기 설계 기록(2026-10-06): [권한 계약·호출부·P0~P3·필수 검증](tasks/lookbook-import-performance/platform-admin-transition-plan.md). 현재는 P1 완료, P2 검증 도구가 후속이다.

Q7 실기기 테스트(2026-10-06): `LookbookImportQ7DevelopmentUITests.swift`는 기본 오픈채팅 화면에서 `룩북` 탭을 선택한 뒤 관리자 진입을 검사한다. 실제 XCTest 연결은 재실행으로 성공했고, 최초 테스트의 탭 전환 누락을 수정해 재검증한다. 최신 결과는 Q7 readiness를 따른다.

**Q7 실행 순서(2026-10-06):** P2 최소 연결 → 로컬 필수 검사 → Development 준비 → 3시즌 smoke → 통과 시 A~J 16시즌 검증. smoke는 A 생성·최초 탐색까지 실행됐고 29개 후보를 찾았으나 동적 더보기 분류 및 큐 종료 상태 오류가 확인되어 중단됐다. A~J는 아직 시작하지 않았다. 최신 로컬 검증 ID와 Development 증거는 Q7 readiness를 따른다.

**Q7 최신 local gates/Development:** Worker gate `1791281635620-7e62e5e7-a635-4676-ba50-bad7f96a3e09` passed(354 tests/lint/fixtures, digest `f5aef99a0b65da550e44598a23732be5794e4511446c4c9ac0ff6ded4eaf8f92`); product queue gate `1791281754202-5d0ebb8f-c857-4843-9a8a-889243b4b5b1` passed(72 emulator tests + Worker/Functions build, digest `f473851733e9f4a14d3e42b072d8896e01eaeb1a71010c80bc9e4b44a07f0ad0`). Development A batch는 여전히 복구 차단 상태이고 settlement candidate는 미배포다.

**제품 큐 Q6 로컬 통합(2026-10-06):** [현행 구현·G-F/G-W/G-E/G-R/G-L/G-I 원본·미검증 범위](tasks/lookbook-import-performance/product-queue-q6-results.md). `functions/src/lookbook/import/queue/preparation.ts` → Functions queue dispatch → Worker `src/queue/{batch-runner,activation,checkpoint}.ts` → `processor.ts`/`season-discovery-processor.ts`가 모든 지원 batch kind의 활성화와 owner/epoch 실행권을 연결한다. `/tasks/import-batch`의 14분 retryable 503 및 처리 promise drain 경계는 `queue/http-deadline.ts`와 `server.ts`다. 즉시 재시도는 최초 포함 총5회다. 실제 Development URL/Storage 동작은 미검증이다.

**Q5 앱 요청·복원 연결(2026-10-06):** [구현·iOS 게이트·결과](tasks/lookbook-import-performance/product-queue-q5-results.md). migration27의 `lookbookImportRequest`를 `AppCompositionRoot → LookbookRepositoryProvider → queue adapters/UseCase`에 주입한다. 접수 요청은 전송 전 같은 requestID/digest를 저장하고 서버 영수증의 requestID/brand/kind를 확인한다. 진행 화면은 requestID로 복원하며 대기·실행·검토·실패·복구 상태를 표시한다. G-I 28 tests/8 suites 통과. Q7 Development 검증은 미완료다.

**Q4 제품 룩북 FIFO 최신 상태(2026-10-05):** `functions/src/lookbook/import/queue/maintenance-functions.ts`가 head 전달·5분 reconciliation을, `record-retention.ts`와 `asset-retention.ts`가 일일 기록·시간당 exact-generation 정리를 담당한다. Worker `src/queue/{recovery,cloud-logging-evidence,recovery-cli}.ts`와 `/recovery/{inspect,resume}`는 dedicated OIDC 설정이 없으면 비활성이다. Q4 시점의 G-F/G-E/G-W/G-R/G-L 및 정리 경계는 [Q4 결과](tasks/lookbook-import-performance/product-queue-q4-results.md), 최신 통합 gate는 [Q6 결과](tasks/lookbook-import-performance/product-queue-q6-results.md)를 따른다. Development 증거는 남았다.

**Q3 최신 저장·브라우저 연결(2026-10-05):** `tools/lookbook-import-worker/src/queue/{asset-paths,asset-publication,browser-gate}.ts`가 queue-owned 이미지 저장의 실행별 경로·두 JPEG generation 확인 뒤 조건부 공개와, 이미지/hash 대 Chromium의 인스턴스별 상호 배제를 구현한다. 브라우저 실행 직전 실행 중 SourceBuffer 재사용 cache도 비운다. `functions/src/lookbook/deletion/assetWriteFence.ts`는 `uploading` 원장이 남은 post/season/brand purge를 차단하며 관련 복합 인덱스는 `firestore.indexes.json`에 추가했다. 최신 G-W Worker342개, G-E Emulator59개, G-L Linux 시나리오2개가 통과했다. 실제 URL/Storage/Worker HTTP 복구·배포/Development 검증은 미실행이다. 상세·미완료 범위는 [Q3 결과](tasks/lookbook-import-performance/product-queue-q3-results.md).

**Q2 최신 Worker batch 연결(2026-10-05):** `tools/lookbook-import-worker/src/queue/{batch-runner,supervisor,runtime}.ts`가 지원된 `importSeasons` batch를 기존 `processJob`에 연결한다. `/tasks/import-batch`는 Cloud Tasks OIDC로 보호되고 retryable 오류는 대기 간격 없이 최초 포함 총5회 즉시 재시도한다. 100ms cgroup 표본·85%/1초·500ms gap·12분 admission stop이 포함되며 14분은 초과 기록만 남겨 응답 deadline은 미보장이다. Cloud Tasks sender/trigger와 discovery/continuation, Development 검증은 미완료다. Q3 Linux gate는 통과했다. 상세는 [Q2 기록](tasks/lookbook-import-performance/product-queue-q2-results.md)을 따른다.

**Q2 묶음 실행권 진행(2026-10-05):** Worker `src/queue/{coordinator,checkpoint,runtime}.ts`는 owner/epoch·attempt 원장·retryAt·shared pipeline 상한·취소 후 drain을 제공한다. `queue/ownership.ts`와 processor/discovery claim은 구형 `/wake`·단건 task가 queue-owned job을 실행권 없이 가져가지 못하게 한다. 기본 `importSeasons` batch는 `processJob`와 연결됐고 retryable 오류는 대기 없이 최초 포함 총5회 재시도한다. 최신 결과는 위 Q2/Q3 항목 및 [Q2 기록](tasks/lookbook-import-performance/product-queue-q2-results.md)을 따른다.

**Q1 나머지 접수·준비 이벤트 연결(2026-10-05):** `queue/followup-admission.ts`(승인/수동 재시도/보수), `discovery-admission.ts`(탐색/재시도/수정 후 재분석), `preparation-runner.ts`와 `preparation-functions.ts`(순번별 준비 이벤트)가 진입점이다. 실행은 root를 바로 변경하지 않고 executions/continuations에 고정한다. 신규 trigger2개 포함 export123개. 실제 Worker 활성화·전달 및 저장은 Q2/Q3이며 배포하지 않았다. [범위·검증·후속 계약](tasks/lookbook-import-performance/product-queue-q1-results.md).

**Q1 브랜드 생성·최초 탐색 원자 접수(2026-10-05):** `brand/admin/functions.ts::createBrand`가 `shared/lookbookQueue/admission.ts::admitQueueRequestInTransaction`을 사용한다. 브랜드/이름 인덱스/탐색 입력/순번/`brandCreationRequests` 영수증을 함께 저장한다. 계약/model/projection/error도 shared로 이동해 기능 간 직접 의존을 없앴다. [Q1 기록](tasks/lookbook-import-performance/product-queue-q1-results.md). 앱 연결·배포 전이다.

**Q1 실제 시즌 접수 연결(2026-10-05):** `import/functions.ts`의 `requestSeasonImport`, `requestSeasonCandidateImportJobs`, `requestSeasonAssetRetry` → `queue/season-admission.ts` → 공통 admission. 기존 job 조회와 후보 snapshot 고정, `asset-retry.ts`의 입력 digest·별도 실행 이력을 연결했다. 최신 요청 envelope/통일 영수증을 사용하며 아직 배포하지 않았다. Functions307개·Emulator23개 결과와 남은 연결은 [Q1 기록](tasks/lookbook-import-performance/product-queue-q1-results.md)에 보존한다.

**Q1 기존 job 참조 보강(2026-10-05):** `queue/model.ts::AdmissionTarget.existingJobID` → `admission.ts` 식별자 검증 → `preparation.ts` 중복 영수증 반영. 기존 job·실행권·이력을 변경하지 않고 참조만 남긴다. 실제 접수 callable의 중복 판정 연결은 후속이며 상세 결과는 [Q1 기록](tasks/lookbook-import-performance/product-queue-q1-results.md)을 따른다.

**제품 큐 Q1 진행(2026-10-05):** [공통 접수 계층·변경 파일·검증·남은 adapter](tasks/lookbook-import-performance/product-queue-q1-results.md). Functions `import/queue/{admission,preparation,dispatch,projection,authorization,functions,model}.ts`와 `import/taskService.ts`, 조회 callable `getSeasonImportBatch`를 추가했다. 기존 trigger/watchdog는 큐 소유 job을 제외한다. `verification/lookbook-product-queue.json`은 demo 프로젝트/8086의 실제 transaction·준비·전달/권한15개를 검증한다. 기존 실행 접수 callable 전체 연결과 Worker 실행은 아직 미완료이며 Q1 전체 완료가 아니다.

**제품 큐 Q0 구현(2026-10-05):** [변경·게이트 원본·남은 범위](tasks/lookbook-import-performance/product-queue-q0-results.md). 사용자 구현 승인 후 공용 `contracts/lookbook-import-queue-v1.json`, Functions/Worker `queue/contracts.ts`, 앱 `Domains/Entities/LookbookImportQueueContract.swift`와 각5개 계약 검사를 연결했다. 정책/버전/공통 요청/시간 경계/상태 분류를 검사하며 기존 API·DI에는 아직 연결하지 않았다. Functions·Worker 기존 필수 검사를 유지하고 전용 iOS/자체 게이트를 추가했다. Q1 이후 접수/FIFO/실행/저장/복구 및 emulator/Linux 기능 검증은 후속이다. 아래 구현 승인 전 문구는 이전 이력이며 현재 결과는 링크를 따른다.

**제품 큐 단계별 구현 계획(2026-10-05):** [Q0~Q7·변경 파일·완료 기준·필수 게이트](tasks/lookbook-import-performance/product-queue-implementation-plan.md). 계약/검증 연결 → 접수/FIFO → Worker 실행권/재개 → 저장/브라우저 → 복구/정리 → 앱 → 로컬 통합 → 승인된 Development 순서다. 정리100건/페이지·회당500건 또는120초 신규 투입 중단, 조회 오류10/20/40/60초, 신규 접수24시간/미래5분, 로컬 확정 기록30일, 접수 준비 총5회·무진행2구간·브라우저 전환 캐시 비우기를 사용자 확정했다. 아래 시점별 미확정 문구는 이 최신 결정으로 대체한다. 이번에는 계획 문서만 작성했으며 제품 코드·새 게이트·배포·IAM·삭제는 미실행이다. 코드 구현 승인 후 Q0부터 진행한다.

**제품 큐 운영·검증 기준(2026-10-05):** [설계 §16~19](tasks/lookbook-import-performance/product-queue-design.md). 조회3/10초, 점검5분·파일 정리1시간·기록 정리일1회, 성공 상세24시간/최소 완료30일/장애 해결 후30일/복구 감사90일, 본인1인 조건부 복구 확정. PQ01~15의 필수 게이트 연결안·만료 요청 방지·보호 예외를 기록했다. 현재 iOS 게이트는 룩북을 선택하지 않는다. 문서만 변경했으며 새 검사 연결/실행·IAM·삭제는 미실행이다.

**제품 큐 데이터/API·복구·브라우저·앱 연결(2026-10-05):** [설계 §12~15](tasks/lookbook-import-performance/product-queue-design.md). 최신 계약 통일(구버전 앱 호환 제외), Chromium1개·이미지와 분리, 목록 탐색도 같은 FIFO, GRDB 복원을 확정했다. batch/items/runs/산출물·진행 조회, bootID와 플랫폼 instance 증거의 구분, inspect/resume 제안, AppCompositionRoot→Container·GRDB migration/계정 삭제 진입점을 기록했다. 설계만 수행했으며 필수 게이트/운영 복구 도구는 아직 미구현이다.

**시간·메모리·앱 정책 확정(2026-10-05):** [제품 큐 설계 §6·7·9·10](tasks/lookbook-import-performance/product-queue-design.md).12/14/15분 정상 분할·같은 차례 재개, 메모리85%1초/100ms측정/500ms초과 공백 중단 후 복구 확인, 기존 화면 상태 구분·요청 ID 재시작 복원을 확정했다. 제품 초기 검증 기준이며 구현·배포·제품 테스트는 미실행이다.

**제품 import 대기열 세부 설계(2026-10-05):** [최신 검토본](tasks/lookbook-import-performance/product-queue-design.md). 닫힌요청/추가선택·검토승인·수동재시도 맨뒤/수동새5회/종료불명확 차단/묶음 Worker/실행별 경로·조건부 공개/미참조 파일24시간 후 정리 확정. 이미지별 재개와 Storage 삭제·공개 경합, callable→task→실행권→pipeline 및 iOS 변경 경계를 정리했다. PQ01~11은 검증 설계이며 제품 구현·실행·배포·삭제는 아직 하지 않았다.

**A~J 실측 종료·T2 중단(2026-10-05):** [결과·검증·남은 범위](tasks/lookbook-import-performance/ten-brand-results.md). 실제 Development6성공/변환2메모리중단1/업로드8미실행1. 완주 게이트failed, 중단정리drained=true·후속차단 유지. 원본·분석·배포·게이트는 `output/lookbook-import-performance/ten-brand-live/`. 제품 반영·추가 실험 없음.

**A~J 배포 전 확인(2026-10-05):** [대상·입력·비용 분석](tasks/lookbook-import-performance/ten-brand-readiness.md). 원본138개·Development 설정·OIDC/실행권·version5/8회/100ms 계약·검사한 소스 해시 대조 통과. 원본 증거와 비용 산술은 `output/lookbook-import-performance/ten-brand-readiness/`. 이번 push/배포/Worker 호출0, 다음은 새 revision 대상 대조 후 smoke와 본 비교다.

**A~J 원격 version5 연결(2026-10-05):** [구현·검증 기록](tasks/lookbook-import-performance/ten-brand-connection-results.md). `remote-input.ts`가18시즌을 독립 ID로 매핑하고 `remote-contract.ts`가100ms 접수·고정8회·단계 증량을 묶는다. `remote-runner.ts`→`arrival-runner.ts` 실행, `remote-arrivals.ts`/`remote-report.ts`의 도착·정책·저장 증거 재검사와 variant별 집계가 진입점이다. Mac/Linux 각각 전체316개·필수208개, emulator5개, 테스트/runtime 이미지 대조를 모두 통과했다. 배포·실제 네트워크 비교는 이번 범위에서 미실행이다.

**100ms 접수 로컬 검증 완료(2026-10-05):** Mac/Linux AMD64 각각313개·필수205개 통과, 실패·취소·skip0. Linux1CPU/2GiB에서 검사했고 기존 lint70경고는 남아 있다. 원본 로그·소스 해시·이미지 대조는 아래 A~J 검증 기록5절에 보존한다. 다음은 원격18시즌·8회 계약 연결이며, Firebase 실측은 이번에 실행하지 않았다.

**A~J 실험 조건 확정(2026-10-05):** [입력·최소 행렬·요청량·비용·연결 계획](tasks/lookbook-import-performance/ten-brand-execution-proposal.md). 총18시즌(A8/B2/C~J각1), 접수 간격100ms(A0~J900ms), Worker 합산 시즌6/해제 비교, 준비 포함8회로 확정했다. 접수 간격 외 추천 조건은 유지한다. 새 계약 연결·필수 검증·승인된 유료 실행은 아직 미완료다.

**최신 작업(2026-10-05) — A~J 로컬 최종 검사:** [검증 범위·결과·미구현 경계](tasks/lookbook-import-performance/ten-brand-validation.md). `performance/arrival-runner.ts`가100ms 접수를 재현하고 `season-runner.ts::beforeStart`가 도착 전 실행을 막는다. `arrival-runner.test.ts` TB03~06 및 기존 TB01/02를 `verification/lookbook-import.json` 필수 목록에 연결했다. 원격18시즌·8회 계약 연결과 유료 실행은 아직 미완료다. 제품 FIFO 방향과 기존 실측 증거는 보존한다.

**최신 결정(2026-10-05) — 브랜드 요청 FIFO 확정:** [확정 사항·제품 연결 설계·남은 결정](tasks/lookbook-import-performance/phase-4-brand-dispatch-design.md). 현재 브랜드 안에서 시즌을 병렬 처리하고 저장·종료·정리 후 접수 순서대로 다음 요청을 진행한다. 뒤 요청 대기를 수용하고 단순성·순서 예측 가능성을 우선한다. 실측에 의한 큰 속도 개선 주장이 아니다. 다음은 요청 묶음/API·실행권·재시도/복구·공용 pipeline의 최소 설계 및 구현 계획이다. 제품 구현·추가 실험·배포는 아직 진행하지 않았으며 아래 기록은 이력이다.

**검증 이력 — Development 역순3회 완료:** [계약·구현 계획·요청량·검증](tasks/lookbook-import-performance/development-reverse-comparison.md). version4는 준비→SP→PP만 허용한다. `remote-contract.ts`/`remote-report.ts`와 관련 필수 게이트가 진입점이며 이전5회 결과는 보존한다. Mac/Linux307개·emulator5개·실제3회·원본 재검사 게이트 모두 통과했다. 이번 SP 전체0.61%/첫 브랜드4.24% 단축으로 큰 처리량 개선 근거는 부족하다. 추가 성능 실험은 실행하지 않는다. 당시 제품 도입 보류 권고는 이후 FIFO 제품 결정으로 대체됐으며 세부 구현은 후속이다.

**최신 — Development 실제 약식5회 완료:** [실측 결과·원본·게이트·비용 추정](tasks/lookbook-import-performance/development-screening-results.md). 준비1회와 PP/SP/PS/SS 각1회가 모두 성공했고 실제 실행·원본 재검사 게이트를 통과했다. 전체 처리100~104초, 브랜드 순차 후보의 첫 브랜드 완료는 약10% 빨랐으나 각1회·동일 인스턴스·고정 순서이므로 채택은 미판정이다. 추가 실행/운영 반영/삭제는 하지 않았다. 아래 승인 대기·미실행 문구는 실행 전 이력이다.

실행 전 기록: **배포 전 준비:** [약식5회 실행안·현재 대상·비용·검증](tasks/lookbook-import-performance/development-screening-execution.md). 로컬 원 사이트 HTML7개/원본138개 검사가 통과했고 현재 설정·기존 OIDC와 서울 단가를 재확인했다. 준비 게이트2개 통과, Worker 소스 변경 없음. push/배포/Worker 실험 요청/Firebase 실험 쓰기는 아직 하지 않았다.

**최신 — 약식5회(version3) 로컬 구현·검증 완료:** [확정 조건·구현·검사·요청량](tasks/lookbook-import-performance/development-screening.md). 준비1회+PP/SP/PS/SS 각1회로 축소한다. 다운로드4·변환1·업로드4·재사용128MiB는 유지한다. `remote-contract.ts`의5회 계약과 `remote-report.ts`의 단일 관측 집계가 현재 기준이며, 채택/반복악화/실패율 개선 판정은 하지 않는다. Mac/AMD64 각각307개·필수199개, emulator5개와 요청량/이미지 대조 게이트를 통과했다. 실제 배포·유료 실험은 미실행이다. 아래21회 실행안·version2·과거 ‘현재/다음’ 문구는 이전 이력이며 추가 실행 권한이 아니다.

- **AMD64 기준 분리 완료:** [새 기준·최종 이미지·원본](tasks/lookbook-import-performance/development-amd64-golden.md). `performance-remote-input-amd64.json`, `remote-golden-profile.ts`, `remote-golden.test.ts`가 새 진입점이다. 기존 ARM 자료 보존, 독립2회274개 재현과 최종 runtime274개 exact 검사, Mac/AMD64 각각307개·emulator5개를 통과했다. 실제 배포·원격21회는 미실행이다.

- **최신 배포 전 준비:** [AMD64 검증·인증 수정·실행안·golden 차단](tasks/lookbook-import-performance/development-amd64-readiness.md). `remote-auth.ts`/`remote-auth.test.ts`가 기존 OIDC 전용 권한을 사용하는 CLI 인증 진입점이다. 원본138개 일치, AMD64 JPEG274개 중152개가 ARM golden과 달라 기준 분리 결정 전 배포·실험을 보류한다.

**현재 단계(2026-10-04):** 사용자가 다운로드4·변환1·업로드4를 유지한 다음 구현을 승인했다. [version2 네 구조20회+smoke1회 로컬 구현·검증 기록](tasks/lookbook-import-performance/development-network-implementation.md)과 [실행 대상·요청량·비용](tasks/lookbook-import-performance/development-network-comparison-plan.md)을 따른다. remote-contract/runner와 remote-campaign/report/target/CLI가 진입점이다. 이미지별 예약/R 연결은 보류했고 기존 결과는 보존한다. 배포·유료 실험은 미실행이다. 아래 ‘다음’과 AD2b 결정 대기는 이전 이력이다.

- **룩북 AD2b 설계 검토:** [예약·실제 연결·AB01~12](tasks/lookbook-import-performance/adaptive-ad2b-plan.md). `dedupe` 예약 위치, 커버 원본 토큰 확대, CPU 준비 상태, 표본 확인 뒤 예약 반환 경계를 정리했다. 초기 예약량과 커버 방식 답변 후 구현하며 아래 AD2a 결과는 그대로 보존한다.

- **룩북 AD2a 완료:** [구현·검사·18회 실측](tasks/lookbook-import-performance/adaptive-ad2a-results.md). `resource-feed.ts` → `memory-preparation.ts` → `memory-preparation-host.ts`가 공통 cgroup 계측·실제JPEG·외부 종료 검증 진입점이다. Mac/Linux292개·필수184개,18/18회·42변환 통과. 예약 E·기예약 제동 예외·실제 R 연결은 AD2b 후속이다.

- **룩북 자동 동시성 AD1 구현:** [설계](tasks/lookbook-import-performance/adaptive-concurrency-design.md), [변경·필수 검사](tasks/lookbook-import-performance/adaptive-ad1-results.md). `adaptive-controller.ts`의 주입 표본 판단, `PipelineRuntime.setStageLimit`과 `ReadySeasonQueue.setLimit`의 명시적 실험 모드가 진입점이다. 실제 cgroup·메모리 예약·Worker 연결은 AD2에 남아 있다.

- **룩북 Development 연결 D0~D3 완료(2026-10-04):** [승인 계획](tasks/lookbook-import-performance/development-comparison-plan.md), [변경·검증·남은 D4](tasks/lookbook-import-performance/development-connection-results.md). `performance/remote-{contract,io,firebase,store,runner}.ts`와 `reuse-input.ts::ConnectedIO`가 P/S30회·개발 전용 저장·실행권·취소/정리·증거를 담당한다. `OUTPICK_IMPORT_REMOTE_CAMPAIGN` 기본 off, 켜면 인증된 실험 route만 제공하고 제품 작업 route를 닫는다. Mac/Linux278개·필수170개 및 emulator4개 통과. 실제 배포·다운로드·Storage/Firestore 원격 실험과 제품 전역 FIFO는 미실행이다.

- **룩북 브랜드 순차 비교 구현(2026-10-04):** [세부 설계·구현 계획](tasks/lookbook-import-performance/phase-3-brand-fifo-design.md), [실행·검증 기록](tasks/lookbook-import-performance/phase-3-brand-fifo-results.md). 현재 배포 인스턴스당1CPU/2GiB를 유지하며128MiB/두부하/3브랜드×2시즌/각5회로 비교한다. `performance/season-runner.ts`의 `serial-brands`, `brand-comparison.ts`의20회계획, `brand-metrics.ts`/`brand-statistics.ts`/`brand-report.ts`의대기포함지표·분모, `brand-progress.ts`의OOM경계기록이 진입점이다. 신규BF01~12 포함 Mac/Linux265개·필수157개 및20/20 실측·독립집계·정리를 통과했다. 대용량 전체0.86%단축/최고메모리93.37→83.36%/읽기22.29%감소로 S를 후속후보로 추천하되10%속도목표는 미달이다. 실제 근거는 실행 기록을 따르며 제품API/분산claim/클라우드설정은 미변경이다. 아래 결과는 이전 단계 이력이다.

- **룩북 P4 15회 확인 완료(2026-10-04):** [고정 조건·게이트·원본·판정](tasks/lookbook-import-performance/phase-3-p4-confirmation.md). Mac/Linux253개·필수145개 통과. off3/5·128MiB5/5·256MiB3/5 성공, 감독 중단3회·실제OOM1회다.128 전체 중앙값219.582초/최고메모리94.048%, off대조 완주3쌍으로 속도채택 미판정. `large-comparison.ts::makeLargeConfirmationPlan`은15회계획, `large-statistics.ts`는 실패분모·5쌍판정 진입점이다. 성공JPEG17,424개/경로8,712건·원본재집계 일치, 내부반환14회 확인/OOM1회 미확인, 잔여컨테이너0. 다음 추천은 메모리 원인 진단 설계이며 제품/원격환경은 미변경이다. 아래 단계 요약은 각 당시의 이력이다.

- **룩북 P4 비재사용 대조군 완료:** [조건·원본·결과](tasks/lookbook-import-performance/phase-3-p4-off-control.md). Mac/Linux250개·필수142개 통과, P4/off(커버 선준비 유지)1회219.558초 성공·최고86.55%·지속 중단 없음. JPEG1,584개/경로792건·재집계/반환 확인. `large-comparison.ts::makeLargeControlPlan`/독립 집계, `reuse-contract.ts`의 arm별커버 검사, `large-input.test.ts` 신규3개가 진입점이다. 다음 추천은P4/off·128·256 각5회 후보확정 비교이며 아직 미실행이다.

- **룩북 대용량 준비7회 완료:** [승인·구현·게이트·실측](tasks/lookbook-import-performance/phase-3-large-input-design.md). Mac/Linux247개·필수139개 통과, 실측2성공(P4/128·256)·5메모리 중단(U4조건·P4/512). `performance/large-input.ts`/`large-comparison.ts`/`large-input.test.ts`가 입력·7회 집계·회귀 진입점이다. 원본/재집계/반환 대조 완료. 다음 추천은 P4/off 유효 대조군 확인이며 새 회차·제품 채택·Development는 미실행이다.

- **룩북 제출 순서45회 완료:** [코드·게이트·원본·판정](tasks/lookbook-import-performance/phase-3-submission-design.md). Mac/Linux240개·필수132개 및45/45 성공. R4/B4는 첫 시즌 반복 악화로 채택 보류, P4는16MiB에서 U 대비 첫 시즌12.50% 단축·전체0.025% 단축으로 종료 지연 완화 후보 유지다. `performance/submission-comparison.ts`의 정책·행렬·trace 검사, `submission-runtime.ts`의 실험 전용 준비된 변환 우선 큐, `submission.test.ts`가 진입점이다. 최고 메모리89.32% 관측(지속 중단 없음), 다음은 대용량 입력·예산 압박 설계이며 제품 정책은 미변경이다.

- **룩북 다른 부하·작은 예산 압박45회 완료:** [구현·게이트·원본·판정](tasks/lookbook-import-performance/phase-3-load-pressure-proposal.md). Mac/Linux232개·필수124개 통과, 실측45/45 성공·JPEG10,210개 정합성 확인. 16/32MiB는 첫 시즌 반복 악화로 채택 보류, 128MiB는 전체1.07% 단축으로 후속 후보 유지다. `reuse-comparison.ts`의 makeLoadPressurePlan/5쌍 집계, `reuse-contract.ts`의 입력 계약/읽기·cache 교차 검증, `load-pressure.test.ts`가 진입점이다. 다음은 부분 재사용 시 본문 제출 순서 설계이며 제품 API/기본값은 유지한다. 아래는 이전 단계 이력이다.

- **룩북 커버 선준비 15회 완료:** [설계·코드·게이트·결과](tasks/lookbook-import-performance/phase-3-cover-preparation.md). Mac/Linux 전체226개·필수118개, 실측15/15 성공. 첫 시즌 current34.393초→prepared13.630초, 전체 off 대비1.04% 단축·반복 악화 없음. `reuse-input.ts`의 prepareCover, `reuse-trace.ts`의 prepare 사건, `reuse-comparison.ts`의 makeCoverPreparationPlan/5쌍 집계가 진입점이다. 다른 부하·예산 압박·실제 네트워크 검증이 남아 있으며 제품 API·기본값은 유지한다. 아래 기록은 이전 단계 이력이다.

- **룩북 재사용 지연 진단 완료:** [2회 증거·다음 수정 후보](tasks/lookbook-import-performance/phase-3-reuse-diagnosis.md). Mac/Linux 222개·필수 114개 통과, 2/2 성공. on 첫 시즌 본문 13.342초 완료지만 커버는 다른 시즌 본문 변환 214건 뒤에서 대기해 36.681초 완료했다. `performance/reuse-trace.ts`와 `makeReuseDiagnosticPlan`이 계측/검증 진입점이다. 다음은 커버 원본 선준비 등 제출 순서 개선안 구체화이며 제품 정책 미변경이다.

- **룩북 재사용 15회 완료:** [계약·검증·원본·지연 결과](tasks/lookbook-import-performance/phase-3-reuse-comparison.md). Mac/Linux 218개·필수 110개 통과, 15/15 성공. 읽기 약 49% 감소지만 전체 시간 개선 1% 미만·첫 시즌 약 2.44배 지연으로 현재 조합 채택 미추천이다. `performance/reuse-comparison.ts`가 계획/실행/집계, `reuse-input.ts`가 해시/같은 scope 저장, `reuse-entry.ts`가 진입점, `reuse-comparison.test.ts`가 5개 회귀다. 다음은 본문/커버 단계 시각 진단이며 제품 기본값 미변경이다.

- **룩북 C 변환 30회 완료:** [실행 계약·원본·결과](tasks/lookbook-import-performance/phase-3-transform-confirmation.md). Mac/Linux 전체 213개/필수 105개 통과, 1·2 × 3부하 × 5쌍 모두 성공·전체/첫 시즌 반복 악화 없음. 시간 차이 0.36~2.38%로 작고 다중 시즌 메모리 여유가 더 큰 1을 우선 후보로 유지한다. `performance/comparison.ts`의 `makeTransformConfirmationPlan`, `transform-confirmation-report.ts`, `transform-confirmation.test.ts`가 진입점이다. 제품 기본값은 미변경이며 다음은 재사용 비교 입력·회차 검토다.

- **룩북 로컬 구조 탐색 완료:** [54회 결과·자원 분석·후속 추천](tasks/lookbook-import-performance/phase-3-comparison.md). Mac/Linux 각각 207개/필수 99개 통과, 준비 18회와 본 54회 완료. 본 결과 48성공/6메모리 중단, C/E 각 9회 통과·약 45~46% 시간 단축. C 우선 후속 후보이며 최적값/제품 기본값/클라우드 배포는 미확정이다. `performance/{overhead,overhead-entry}.ts`는 off/on 준비 2회+교차 5쌍, `resources.ts`는 승인된 작은 cgroup 동기 읽기, `comparison-report.ts`는 실패 분모/54회 검증 진입점이다. 아래 201개 기록은 직전 단계다.

- **룩북 URL 추출 성능 개선 Phase 0~3 진행(2026-10-03):** [설계](architecture/LOOKBOOK_IMPORT_PERFORMANCE_DESIGN.md), [계획](tasks/lookbook-import-performance/plan.md), [최신 A~F 연결·컨테이너 검증](tasks/lookbook-import-performance/phase-3-comparison.md). Worker `src/performance/{comparison,frozen-input,buffer-inventory,container-runner,local-entry,comparison-report}.ts`가 고정 입력·A~F 정책·바이트 보유량·컨테이너 종료·54회 집계/5쌍 판정의 진입점이다. 필수 테스트 93개를 연결해 전체 201개를 검사한다. 초기 정책/부하/표본 간격은 승인됐고 Docker 설치·Linux 이미지 빌드를 진행했다. 54회 본 비교·클라우드 배포·최적값 채택과 제품 분산 재시도는 별도다. [시즌/중단](tasks/lookbook-import-performance/phase-3-runner.md), [재사용](tasks/lookbook-import-performance/phase-2-reuse.md)도 참조한다.

- **채팅 검색·차단 목록 구현 및 DEV QA 완료(2026-10-02):** [최종 계약·검증·배포 경계](architecture/CHAT_MESSAGE_SEARCH.md). 포함 검색, 최초/계속 찾기 최대 500후보, 사용자 과거 이동 후 잔여 10개 이하에서 1페이지 선로딩, 현재 순번/확보 개수를 표시한다. 계정 전환·미읽음·방 종료까지 확인하고 전용 QA 자료를 정리했다. [채팅 진입점](entrypoints/CHAT.md), [차단 목록](entrypoints/PROFILE.md), [검증](entrypoints/TESTS.md). 운영 배포는 별도다.

- **채팅 전송 버튼·키보드 수정 완료:** 한 번 탭으로 전송·입력 비움·키보드 유지, 연속 전송·배경 dismiss를 iPhone 14에서 사용자 확인했고 iOS 게이트 17개가 통과했다. `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`의 공통 제스처 → `ChatUIView`의 버튼 callback → `ChatViewController.handleSendButtonTap`이 진입점이다. 공통 dismiss는 입력창과 `UIControl` 하위 터치를 제외한다. [CHAT](entrypoints/CHAT.md), [회귀 테스트·수동 QA](entrypoints/TESTS.md)를 참고한다.

- **채팅 미디어 7일 만료 구현·개발 QA 완료:** [최종 계약·검증·운영 주의사항](architecture/CHAT_MEDIA_RETENTION.md). 서버 확정 시각+168시간, 모든 채팅 미디어의 서명 URL, 시간당 generation 지정 정리, 캐시·화면·Photos 경계를 적용했다. 운영 배포와 실제 1시간 대기·개인정보처리방침 원문 대조는 별도 후속이다.
- **코드 지도:** [CHAT](entrypoints/CHAT.md) → [DATA](entrypoints/DATA.md) → [FIREBASE](entrypoints/FIREBASE.md) → [TESTS](entrypoints/TESTS.md).
- **프로그램적 검증:** [운영 기준](architecture/PROGRAMMATIC_VERIFICATION.md), `verification/{gate,functions,firestore,ios,chat-media-retention}.json`. 원본·설치는 [tools/verification-gate](../../tools/verification-gate/README.md), 환경 준비는 [verification](../../verification/README.md)를 따른다. 공용 설치본의 로컬 실행이며 GitHub CI 연결을 의미하지 않는다.

- **영상 저장 중 닫기 검증:** `OutPickTests/VideoSaveLifetimeTests.swift`가 실제 UIKit present/dismiss와 지연 resolver/saver를 사용해 두 영상 VC의 준비 중 닫기·제출 후 성공/실패·늦은 UI 차단·재생 링크/저장 파일 해제를 확인한다. 사용자 영상/Photos/서버 자료 없이 전용 임시 파일만 사용.

- **영상 저장 결과 UX:** `Infra/Media/MediaSaveToast`를 두 영상 VC가 사용한다. 사진과 같은 하단 위치/여백/1.2초 유지 후 사라지는 토스트에 “저장 완료”/“저장 실패”만 표시. 중앙 결과 alert와 localizedDescription 노출 제거. 저장 중 진행 UI는 기존 유지.

- **저장 이후 영상 캐시 재생:** `DefaultChatVideoPlaybackResolver.cachedPlaybackAsset`는 bin 캐시를 MP4/MOV 확장자 hardlink(불가 시 사본)로 제공하고 래핑 lease가 재생 링크와 원본 pin을 함께 해제한다. `PhotoLibraryOriginalIntegrationTests`에서 합성 MP4/MOV의 AVURLAsset 재생 가능·Photos 저장·링크 정리/원본 보존 검증.

- **영상 Photos 저장 보완:** `PhotoLibraryOriginalResource.videoType`가 최상위 ftyp major brand로 MP4/MOV를 구분하고 `PhotoLibraryPreparedResource`로 확장자 사본을 제출한다. Photos 실제 합성 MP4/MOV 통합은 `PhotoLibraryOriginalIntegrationTests`, 바이트/잘못된 확장자/손상 헤더는 `PhotoLibraryOriginalResourceTests`. 원본 변환 없음.

- **확대 로딩 표시:** `SimpleImageViewerVC.renderLoadStatus`는 이미지가 보이면 로딩 문구 없이 원본으로 교체한다. 이미지가 없는 로딩은 스피너, 실패는 재시도 버튼을 유지한다. 저장 상태 안내는 별도 기존 흐름 유지.

- **현재 원본 우선:** `SimpleImageViewerVC.scheduleProgressiveLoads`는 현재 lease 확보 전 인접 신규 요청을 보류한다. `startOriginalFileLoad`에서 파일 확보 후 현재 decode와 인접 다운로드를 겹친다. 페이지 전환 시 다른 미확보 요청 취소, 확보 파일 유지. `ImageViewerOriginalFileTests`에 보류/페이지 전환/닫기 회귀 추가.

- **원본 첫 로딩 계측:** `ChatOriginalFileStore`의 `original.cache/transfer/fileGate/networkGate/download/downloadBytes`, `SimpleImageViewerVC`의 `original.viewer/viewerRole/acquire/decode`를 기존 `ImageCacheMetrics`로 수집한다. DEBUG `OUTPICK_IMAGE_BASELINE=1`일 때만 출력하며 key는 해시다. viewer 종료는 이미지 할당·로딩 상태 갱신까지이며 실제 화면 프레임 표시 완료는 아니다.

- **Photos3302 실제 재현/보완:** `PhotoLibraryPreparedResource`가 원본 캐시를 올바른 확장자 고유 임시 사본으로 복사하고 Photos callback 후 정리한다. 형식 옵션만으로는 `.bin` 직접 제출 실패를 해결하지 못했다. 실제 Simulator Photos 검증은 `PhotoLibraryOriginalIntegrationTests`, [결과](tasks/chat-media-first-view-loading/original-media-results.md).

- **원본 Photos 포맷 보완:** `Infra/Media/PhotoLibraryOriginalResource.creationOptions`가 `.bin`/확장자 없는 사진도 ImageIO 실제 타입과 올바른 파일명을 전달한다. `DefaultPhotoLibrarySaver.saveOriginal`에서 사용하며 재인코딩하지 않는다. [실기기 저장 실패·재검증](tasks/chat-media-first-view-loading/original-media-results.md).

- **③ 원본 Phase3·4:** `Chat/Services/OriginalMedia/{ChatOriginalFile,ChatOriginalFileStore,ChatOriginalFileDisk,ChatOriginalFileTransport}` → Container 계정별 service → 뷰어/영상/삭제. 계정별 보관·합산512MiB·lease/SDK 취소 수명, 사진 현재±1/GIF 활성만·원본 파일 저장·영상 스트리밍. `AppCoordinator.ensureChatContainer` 계정 교체와 탈퇴 scrub 연결. [구현·검증/QA 잔여](tasks/chat-media-first-view-loading/original-media-results.md).

- **실제 스피너 추적:** ChatImagePreviewCell.spinner span/state/imageAssigned/종료이유↔collection.loadingResolution/Delivery. 전송확인/최신이동/공용overlay 별도계측. 동일hash key+span+seq/time으로연결,전체캐시hit만으로원인확정금지. [진단계획](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **전환/이탈 픽셀 유지:** ChatViewController.viewWillAppear부터viewport활성, applyInitialWindowSnapshotAndWait 완료콜백에서첫위치즉시조정. ChatImagePreviewCell.render(.idle)는픽셀유지,reset/reuse/remote경로교체는제거. chatEntry 전환시점 및cellIdle 계측. [검증/한계](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **로컬 단계 준비/셀 즉시 표시:** ChatInitialLoadUseCase.prepareLocalMedia→VM 세대검사→VC 별도 준비(서버확인 전 렌더없음). VC cachedMemoryImageImmediately→ChatMessageCell.configureWithImage→ChatImagePreviewCollectionView의 최초configure/loading 캐시조회. chatEntry.localMedia/renderWindow 및 chatPreview.cellCache 계측. [검증](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 디스크 준비 제한 해제:** `ChatMediaViewportController` maxConcurrent:nil / `ChatAttachmentImageService` remote pipeline bypassDirectDiskLimits:true를 일반 실행·Release에 동일 적용. 환경변수 의존 제거, 재실행 유지. processor directDiskValue/readLease에서 decode/IO 게이트 우회. 실제 decode/CPU·메모리 계측은 ImageCacheMetrics/ChatMediaQAMetrics. [계약](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **먼 디스크 준비 동시성:** ChatMediaViewportController→ChatDiskPreparationController(maxConcurrent:nil), 경로별 Task 취소·병합, 메모리 여유 검사·무퇴거 삽입 유지. [최신 근거](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 진입 초기 준비:** `ChatViewController.setMessageWindow`→snapshot 전 `+MediaViewport.prepareInitialDiskImages`→policy.initialDiskPreparationPaths→viewport.prepareDiskBeforeLayout. 최신/unread 메시지 순서로 먼저 시작, 초기 위치 안정화 후 실제 프레임 순서로 전환. willAppear/willDisappear와 활성 guard로 수명 관리. [검증](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **방 전체 디스크 준비:** `ChatMediaViewportPolicy.diskPreparationPaths`→`ChatMediaViewportController` 내부 `ChatDiskPreparationController`→Container 주입 service→pipeline.prepareDiskImage. 현재 snapshot 전체 거리순으로 동시 제출, cache-only/최저 우선순위, LRU 여유·압박 검사와 setIfRoom 무퇴거 삽입. 기존 주변 다운로드는 유지. [진행/QA](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **빠른스크롤 예측선로딩:** ChatMediaViewportPolicy의속도기반최대4화면+UIKit예상도착/0.35초구간,near/destination교대선택24상한. ChatViewController delegate→+MediaViewport의속도/target수명관리→controller.cancelOutsideImmediately. 빠른범위밖300ms유예제거/캐시유지. 자동30통과,기기체감QA전. [상세](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 disk 직접준비:** `ImageCachePipeline`/`ImagePipelineProcessor.usesDirectDiskFileDecoding` opt-in→`ImageCacheDiskStore.readLease`→`ImageCacheReadLease` hardlink→ImageIO fileDecoder. 채팅 remote는 Data예산/파일내용복사 및 decode/IO 게이트 대기 없이 처리. 교체/삭제중 파일 보호·세대 차단·실패 legacy 복구 유지. [검증/후속선로딩](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **채팅 표시 1GiB QA:** `ChatAttachmentImageService.makePipelines` remote 메모리1GiB/LRU, 디스크1GiB/trim900MiB. `ImageCacheMemoryStore` opt-in→`ImageLRUMemoryStore` 최근사용정리·stride비용·압박warning/critical/normal. 다른기능NSCache 기본유지, 파일규격동일. [계획·검증](tasks/chat-media-first-view-loading/display-readiness-plan.md).

- **③ Phase1·2 완료:** 자동89개 및 기기근접재방문QA 통과, memoryImmediate140회/저장282success/관측gate종료0. 일반DEV복원. 첫진입대기·용량퇴거 및 원본분리(Phase3~5)는 잔여. [결과·검증한계](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- **③ Phase2 저장 재사용:** `ImageCachePersistence.wait(forKey:revision:)`→coordinator.waitForPendingWrite→pipeline.cachedValue의 같은키 pending 합류. `storeImageData`는 beginPreparedStore 세대확보 후 storePrepared로 독립 persistence에 payload/lease 인계. 준비 중 삭제는 거절. [검증·기준선](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- **③ Phase2 첫 개선:** `ChatAttachmentImageLoading.cachedMemoryImageImmediately`→service remote 메모리 조회→`ChatContainer.makeChatMediaViewportController` 주입. viewport는 memory hit일 때 loading 없이 image 전달. 로컬 파일 읽기는 제외. 기준선 반복28건 중27건 용량퇴거 연결, pending 저장합류는 다음. [결과](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- **2026-09-23 최신:③ Phase1 계측 착수.** `ImageCacheMetrics.linkCacheKey`가 resource/storage/file hash를 연결하고 memory.lookup/store·disk.lookup/eviction·diskWrite.total·persistence.pending·chatPreview.presentation/load/preserveLocal을 기록한다. 정책/재사용 행동은 아직 유지, Phase2 전 기준선 QA. [실행 기록](tasks/chat-media-first-view-loading/cache-reuse-results.md).

- 다운로드② SDK 취소 경합: Firebase12.3.0→12.17.0 공식 상태 보호 적용(`project.pbxproj`, `Package.resolved`), SDK 직접 재현 포함87개 회귀 통과. 구버전 비교와 실기기 최종QA 진행,③ 미착수. [근거·의존성 영향](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 2026-09-22 다운로드② QA **잔여 발견**: 저장 실패 suite7개 통과·실제 병렬6 유지, 대량 반복 후 신규 임시 파일3개 잔존. Firebase cancel callback의 완전 종료 가정을 재검토해야 한다. [최신 판정](tasks/chat-media-first-view-loading/download-bottleneck-results.md),③ 구현 보류.

- 2026-09-22 다운로드② 저장 실패 자동 검증7개 통과. `FirebaseImageDownload.file` opt-in SDK 취소/callback 계측 추가, 실기기 QA 진행 중. [검증 진입점](entrypoints/TESTS.md), [진행·한계](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 2026-09-22 채팅 미디어: [③ 캐시 재사용 구현 계획](tasks/chat-media-first-view-loading/cache-reuse-implementation-plan.md) 작성·구현 전. 닫기 저장 취소·영상 즉시 재생, 수치/표시 파일 정책은 QA 결정. 현재 [② 병렬 다운로드 재점검](tasks/chat-media-first-view-loading/download-bottleneck-plan.md)으로 복귀했다.

- 채팅 미디어③ [표시 캐시/원본 설계 초안](tasks/chat-media-first-view-loading/display-original-cache-design.md): 앱 캐시 분리 우선 사용자 확정. `ChatAttachmentImageService`의 원문 저장·1024px decode, `ChatViewController`의 확대 원본 선로딩, `SimpleImageViewerVC.saveTapped`의 표시 이미지 우선 저장이 주요 경계. 구현 전 설계 논의 중이다.

- 다운로드② 실기기 결과: 파일 전송 최대6개 동시 확인, 자동75개 통과. 기존 캐시 QA에서 반복 완료53건/캐시 정리5회 관찰; 표시 속도 전체 해결 아님. 원인별 한계·일반 DEV 복원·③ 잔여는 [실행 기록](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 다운로드② 구현: `ImagePipelineProcessor.downloadFile`은 network/files로 SDK 파일 전송을 제한하고 앱 io(write)를 전송 동안 점유하지 않는다. 기본 수치 유지. `ImageFileDownloadSchedulingTests`6개 및 관련75개 회귀 통과, 실제 기기 계측 QA 진행. [결과·한계](tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 채팅 미디어② [세부 구현 계획](tasks/chat-media-first-view-loading/download-bottleneck-plan.md) 작성 완료·구현 전: ImagePipelineProcessor의 파일 전송을 앱 io(write)에서 분리, 기존 network/files 상한 및 취소/저장 소유권 유지.4개 Phase·자동 경계/실기기 비교·공용 경로 영향 명시. 최신 상태는 [진행](tasks/chat-media-first-view-loading/progress.md).

- 채팅 회전 지연 수정: `ChatMessageCell.configureWithImage`는 미디어 폭을 contentView의70%, 높이를 공유 배열 비율 제약으로 연결해 reconfigure 전의 고정 크기를 없앤다. `ChatMediaViewportSurfaceTests`의1장/30장 폭 왕복·이미지 보존 회귀 및 실기기 회전 재검증 통과. 누적95개/UI3개, 체감 QA 대기. [최신 기록](tasks/chat-media-first-view-loading/qa-results.md).

- 채팅 미디어 화면 수명 QA: 단위/컴포넌트 누적94개·UI3개 통과. 키보드/검색 종료/설정/사진 선택 취소/세로 복귀 확인, 가로 캡처와 실제 화면 대조 대기. 테스트 확장은 `ChatMediaViewportDevelopmentUITests`; [실행 기록](tasks/chat-media-first-view-loading/qa-results.md)이 아래 이전 상태보다 우선한다.

- 채팅 미디어① 검증: iPhone14 단위/컴포넌트89개＋기존 미디어 방 UI1개 통과. 공유 카드56pt 좌표 보정. 신규 사진·영상·GIF 전송/스크롤 복귀/방 재진입/확대·재생 사용자 QA 통과. 키보드/설정 등 잔여 검증이 있으며② 미착수. [실행 근거와 잔여](tasks/chat-media-first-view-loading/qa-results.md), [테스트 진입점](entrypoints/TESTS.md).

- 채팅 과거 미디어 첫 표시 ① 로컬 구현: `ChatMediaViewportPolicy`/`ChatMediaViewportController`→`ChatViewController+MediaViewport`→사진·공유 카드 표시 연결. 초기/수신/최신 이동/스크롤 전체 warmup을 제거했다. 실제 frame·재등장 재시도·취소·DI/QA 진입점은 [채팅](entrypoints/CHAT.md), 구현/검증 한계는 [진행](tasks/chat-media-first-view-loading/progress.md).②다운로드 병목·③캐시/원본 관리는 후속이다.

- 아바타 PR 리뷰 보완: `AvatarViewportObserver`는 items 변경 콜백의 최신 경로를 선로딩에 직접 전달한다. `AvatarNestedViewportTests.testSwiftUIViewportPrefetchesChangedPathWithoutScrolling`이 스크롤 없는 nil→사진→다른 사진 변경을 검증한다. [리뷰 기록](tasks/avatar-image-loading/review.md).

- 아바타 Phase0~5 완료(2026-09-21, VoiceOver사용자제외): 구현·QA·임시자료정리·일반DEV복구완료. 최종 iPhone14 16개검증의 범위/기존112개회귀와중복 여부는 [Phase5](tasks/avatar-image-loading/progress/phase-5.md), 다음작업 진입점은 [현재 상태](tasks/avatar-image-loading/progress.md) 참조.

- 잔여 QA2~4: `AvatarRouteContractTests`의 원본only 상세/확대2회, `AvatarNestedViewportTests`의 중첩 참여자50 UIKit 요청계측, `AvatarImageServiceTests`의 연속 아바타뷰 메모리승격/디스크재사용. 실기기 실행 여부와 결과는 [Phase5](tasks/avatar-image-loading/progress/phase-5.md)에서 구분한다. 서버 fixture 추가와 제품 코드 변경은 없다.

- 아바타 잔여 QA1 자동 경계: `OutPickTests/AvatarRouteContractTests.swift`는 실제 UserProfileDetailCompositionRoot→화면→주입 로더 요청의 정책 유지와 기존 scope의 참여 상태 변경 후 read/load/prefetch 정책 재평가를 검증한다. 상위 AppCoordinator/ChatCoordinator 조립은 코드 대조로 구분하며 앱 구조 변경은 없다. 실행 결과는 [Phase5](tasks/avatar-image-loading/progress/phase-5.md) 참조.

- 2026-09-21 아바타 후속 QA: 위임 후보·미참여 방·실패 후 스크롤/새 메시지 재시도·다른 계정 왕복 확인. 임시 오류/메시지 주입 및 정리 코드는 제거했고 서버183문서/20이미지·기기QA174행/3이미지를 정리했다. 검증 범위와 미검증 항목은 [Phase5](tasks/avatar-image-loading/progress/phase-5.md), [체크리스트](tasks/avatar-image-loading/qa-checklist.md) 참조.


- 프로필 확대 원본 30초 제한: `AvatarImageService.loadRemoteAvatar`에서 원본 소비자만 제한하고 기존 공용 pipeline 취소에 연결한다. 썸네일/로컬 파일·SDK 전역 설정은 유지. 테스트와 실제 오프라인 QA는 [프로필 진입점](entrypoints/PROFILE.md), [Phase5](tasks/avatar-image-loading/progress/phase-5.md) 참조.

- 아바타 즉시 메모리 표시: `AvatarImageManaging.cachedAvatarImmediately` → `AvatarImageService` → `AvatarImageSessionController.immediateReads` → 기존 `ImageCachePipeline` NSCache. 추가 이미지 캐시 없이 첫 렌더를 보완하며 전환/경로 무효화는 동기 read gate로 차단. 검증은 `AvatarImageSessionTests`/`AvatarImageServiceTests`/`AvatarImagePresentationStateTests`, 진행은 아바타 Phase5.

- 방 설정 스크롤: `ChatRoomSettingViewController`의 초기 상단 위치 유지와 `actionsSection/actionsItem`(참여자 뒤 나가기·차단 사용자·알림). [채팅 진입점](entrypoints/CHAT.md), 실제 QA는 아바타 Phase5 기록 참조.

- 답글 창 확장: `PostCommentsSheetView.repliesSheet`의 detent `[.fraction(0.62), .large]`. 상단 드래그로 최대 높이 확장, iOS16+ 적용. [룩북 진입점](entrypoints/LOOKBOOK.md).

- 2026-09-20 댓글 재진입 상단 사진 수정: `CommentSafetyAvatarView.onChange(of: identity)`에서 콜백의 최신 identity를 `configure(_:)`에 직접 전달한다. 실기기 사용자 정상 및 상단4행 loaded 확인, 원인 조사용 로그 제거. [검증](tasks/avatar-image-loading/progress/phase-5.md).

- 아바타 Phase5 통합 QA: [진행 기록](tasks/avatar-image-loading/progress/phase-5.md). `AvatarImagePrefetchController.loadingPaths`는 진행 상태를 읽는 내부 진단 값이며 `AvatarViewportPrefetchTests`가 고정 yield 횟수 대신 실제 실패 처리를 기다리는 데 사용한다. 기기 서명 복구와 실기기 QA 상태는 진행 기록에서 확인한다.

- 아바타 Phase4: `AvatarViewportPrefetchPolicy`/`AvatarCollectionViewport`/`AvatarImagePrefetchController`와 SwiftUI `AvatarViewportObserver`가 방향1.5/0.5·고유24·이탈300ms 수요를 관리한다. UIKit 메시지/방 목록/중첩 참여자/위임 후보, SwiftUI 댓글/답글/대표 댓글의 일괄 선로딩을 교체했다. 새 visible 메시지·재등장·수동 갱신의 재시도 및 session unavailable 경로 차단. [구현·검증·QA 잔여](tasks/avatar-image-loading/progress/phase-4.md).

- 아바타 Phase3 표시 수명 구현: `AvatarImagePresentationState`/`AvatarImageView` → UIKit 프로필/채팅 셀·SwiftUI CommentSafetyAvatarView. 같은 사진 유지, 재사용/화면 이탈 취소, 늦은 성공·실패 차단, SimpleImageViewerVC의 프로필 transient 종료 정리. [구현·검증](tasks/avatar-image-loading/progress/phase-3.md). Phase4 viewport/추가 표시 계기와 Phase5 실기기 QA는 남음.

- 아바타 Phase2 완료: `AvatarImageRequest`/`ScopedAvatarImageManager`/`AvatarImageSessionController` → 단일 `AvatarImageService` → App/Chat DI와 `AvatarObservingPublicProfileRepository`·`UpdatePublicProfileUseCase`. 댓글 memory-only·참여방/내 프로필 disk100/75MiB·원본 transient·세션/사진 무효화 연결. JPEG0.8 실제 사진 비교, 최종48개/10suite 통과. [구현·검증·남은 범위](tasks/avatar-image-loading/progress/phase-2.md). Phase3 화면 수명·Phase4 viewport/retry·Phase5 실기기 QA는 남아 있다.

- 아바타 Phase1 공용 기반: `Infra/Cache/ImageCache/ImageCachePipeline.swift`의 `.transient`/`promotionEncoding` → `ImageLoadCoordinator.swift`의 비저장 완료·메모리 hit 승격/세대 → `ImageCachePromotionEncoding.swift`의 준비/출력 예산. `OutPickTests/ImageCacheStorePolicyTests.swift`. [검증](tasks/avatar-image-loading/progress/phase-1.md).

- 아바타 전체 작업: [설계](tasks/avatar-image-loading/design.md) → [Phase0~5 계획](tasks/avatar-image-loading/plan.md) → [현재 상태](tasks/avatar-image-loading/progress.md). 서비스 기반과 화면 적용의 완료 범위를 구분한다. 상세 출발점은 [PROFILE](entrypoints/PROFILE.md).

- 이미지 로딩 최종 공개 검증 요약: [구조·설정·자동/실기기 QA·성능 한계](qa-image-loading-concurrency-2026-09-16.md). 머지 전 리뷰 보완은 `LookbookHTTPImageCache.cachedImage`의 디스크 크기 확인→바이트 예약→본문 읽기 순서와 `LookbookHTTPImageCacheTests.diskBodyWaitsForDecodeBudgetBeforeReadingAndHandlesEviction`에서 확인한다.

- 이미지 Phase 0~5 완료(2026-09-16): 자동90개/UI1개·룩북 기능 실기기 QA·Phase0 CPU/메모리/프레임 비교 후 사용자가 현 D07 값 채택과 Phase5 완료를 승인했다. 설정은 `ImagePipelineLimits.swift`, 화면 수요는 `LookbookImagePrefetchController.swift`; 최종 수치·표본 한계·로그는 [Phase 5](tasks/image-loading-stage-concurrency/phase-5-validation.md). 실패 fixture는 `LookbookUITestFixtureRepositoryProvider.swift`의 `--uitest-lookbook-image-fail-once`, 테스트는 `LookbookSmokeUITests.testImageRetryDoesNotOpenCardDetail`. 채팅 과거 사진 첫 표시 개선은 별도 작업이다. 아래 phase별 미착수/진행 문구는 당시 이력이다.

- 이미지 Phase 4: `Views/Shared/LookbookViewportObserver.swift`(frame·방향·미배치 행 추정) → 홈/브랜드 상세/시즌 상세 View → 각 ViewModel의 `updateViewport` → `Services/ImageLoading/LookbookImagePrefetchController.swift`(희망 집합·300ms 해제) → 공용 캐시. 목록 데이터 선표시·앞선 page 트리거·카드 실패 재시도 연결. [시작값·실기기 QA 잔여](tasks/image-loading-stage-concurrency/phase-4-lookbook-screens.md).


- 이미지 Phase 3: `LookbookAssetImageRequest`가 공용 카드 표시와 브랜드 상세/시즌 상세 프리패치의 Storage→외부 URL 후보를 통일. `BrandImageCacheProtocol` → `LookbookHTTPImageCache`가 URL·Referer·maxBytes별 메모리/디스크 캐시, HTTP TTL/304/200, shared 네트워크·준비·I/O 예산, stale→fresh UI 교체를 소유. [정책·구현 범위](tasks/image-loading-stage-concurrency/phase-3-http-cache.md), [테스트](entrypoints/TESTS.md). 관리자 검토 preview/확대 원본은 별도 경로 유지, Phase4 목록·viewport 미구현.


- 이미지 QA 최종: ImagePipelineLimits decodeBytes/writeBytes 각16MiB 유지, network6/decode2/I/O2(write1). 성공body 계측 추가. A/B/C 체감 차이 미확인, network6/예약회수는 확인. [실측·한계](tasks/image-loading-stage-concurrency/phase-2-qa.md).

- 이미지 QA 비교 진행: ImagePipelineLimits.writeBytes8→16MiB 후보, 나머지 한도 유지. 실제 cold 로그의 저장 예약 대기 최대2.3초를 근거로 비교 중이며 최적값 확정 아님. [비교 결과](tasks/image-loading-stage-concurrency/phase-2-qa.md).

- 이미지 cold QA 계측: ImagePipelineProcessor의 network.body.received는 성공한 이미지 body 바이트만 기록(전체 회선 사용량 아님). [QA 진행·Instruments 연결 문제](tasks/image-loading-stage-concurrency/phase-2-qa.md). 사용자 DEV 삭제/재설치 승인, USB 연결 대기.

- 이미지 Phase2 실기기 QA: 테스트 이미지 배율 보정 후26개 함수 전체 통과. [측정 기록·상태](tasks/image-loading-stage-concurrency/phase-2-qa.md). 아모멘토 화면 계측과 초기값 튜닝은 자동 fake 회귀와 별개로 진행.

- 2026-09-16 이미지 Phase 2: Infra/Cache/ImageCache의 ImagePipelineLimits(QA 초기값) → ImagePipelineResources/ImageStageGate(공유 단계 gate) → ImagePipelineProcessor(예약·Data/파일·준비) → ImageCachePersistence/ImageCacheDiskStore(비동기 저장·세대). DB/Firebase/DatabaseManager/Repositories/FirebaseImageDownload.swift는 SDK 취소 adapter. [실제 범위·제한·QA](tasks/image-loading-stage-concurrency/phase-2-implementation.md). 기존 서비스 fileFetcher 조립 변경, Container/화면 이동/서버 계약 유지. Phase3 외부 URL 폴백 통합·Phase4 viewport 미구현.

- 2026-09-16 이미지 로딩 Phase 1 구현: `Infra/Cache/ImageCache/ImageRequest.swift` → `ImageLoadCoordinator.swift`(원자 요청 통합·소비자별 취소·세대) → `ImageCachePipeline.swift`(캐시/기존 permit·disk 세대 검사), `ImagePipelineResources.shared`(기능별 캐시/공용 합산6). 룩북 카드 취소 후 fallback 차단. [실제 계약·제한](tasks/image-loading-stage-concurrency/phase-1-implementation.md). 최종 앱/테스트 대상 compile 통과, 새14개 시나리오 실행·실기기 QA는 보류. Phase 0 비교 소스 별도 보존. 큐 우선순위·단계 예산은 Phase 2.

- 2026-09-16 이미지 로딩 Phase 0 계측 구현: `Infra/Cache/ImageCache/ImageCacheMetrics.swift` → 기존 pipeline/cache/permit/fetch/decoder와 룩북 ViewModel/카드. Debug opt-in `OUTPICK_IMAGE_BASELINE=1` 또는 `-ImageLoadingBaseline`, 기본 꺼짐. 정책6/프리패치 유지·앱 Simulator build 통과·실기기 미측정. [사용·한계](tasks/image-loading-stage-concurrency/baseline-instrumentation.md), [진행](tasks/image-loading-stage-concurrency/progress.md). 테스트 실행 보류, 다음 측정 대상 OutPick-DEV 아모멘토.

- 2026-09-16 이미지 로딩 단계 분리 **계획 작성/미구현**: [설계](tasks/image-loading-stage-concurrency/design.md) → [Phase 0~5 계획](tasks/image-loading-stage-concurrency/implementation-plan.md) → [검증 계획](tasks/image-loading-stage-concurrency/qa-checklist.md). 공용 `ImageCachePipeline`·`BrandImageCache`·룩북 세 화면 적용과 다른 소비자 회귀 범위다. 현 코드의 제한/우회와 계획을 구분하며 구체 미정은 설계 D01~D08 참조. 코드·테스트·성능 측정은 미수행.

- 2026-09-14 동시성 적용·Development QA 완료: 원본4/준비전체/PUT4/FIFO1, 계약3 서버조회·서명·취소정리전체. iPhone41개/Socket124개와3장/70장/실패재전송 확인, 계측해제. [진행·증거](tasks/chat-media-concurrency-qa-rollout/progress.md). 커밋/PR 및 Production은 미수행.

- 2026-09-14 최종 동시성 로컬 구현: `ChatMediaPipelineLimits` 기본 원본4/준비전체/PUT4, QA 미지정 값은 기본값 보존. 계약3 `directMediaUploadService`의 조회·서명·취소 정리는 요청 대상 전체 실행, `createProductionDependencies`에서 계약3 폭 주입 제거. [진행·검증](tasks/chat-media-concurrency-qa-rollout/progress.md), [계획](tasks/chat-media-concurrency-qa-rollout/plan.md). Development 서버 미배포, 결합 QA 대기.

- 2026-09-14 원본 확보 비교 완료:4/all/4/all 각각1.630/0.411/0.505/0.437초,280장 앱 성공·사용자 조작 확인. QA 해제/기본4 복원, 최종 정책 논의 대기. [측정과 한계](tasks/chat-media-preview-continuity/acquisition-diagnosis.md).

- 2026-09-14 원본 확보 동시성 비교 준비: DEBUG Development QA의 `OUTPICK_MEDIA_QA_ACQUISITION=4|all`로 원본 확보만 비교한다. 기본4 유지. `ChatMediaSelectionUseCaseTests`의 확보 완료/실패 정리를 두 폭으로 검증하며, 실제 비교 상태는 [원본 확보 진단](tasks/chat-media-preview-continuity/acquisition-diagnosis.md) 참조.

- 2026-09-12 준비·업로드·metadata 실기기 개별 비교 완료: [측정 결과](qa-media-upload-concurrency-2026-09-12.md). 8회560장 정상 저장. 업로드4 유지, 준비all 및metadata60은 속도 개선 후보. 결합 조합·다중 사용자 부하는 미검증. 실험 후 기본4 복원.

- 2026-09-12 동시성 비교 QA: `ChatMediaPipelineLimits.forCurrentProcess`가 DEBUG Development에서만 `OUTPICK_MEDIA_QA=1`, `OUTPICK_MEDIA_QA_UPLOADS=4|all`, `OUTPICK_MEDIA_QA_PREPARATION=4|all`을 적용한다. `ChatMediaQAMetrics`가 메모리200ms 표본/1초 로그를 기록한다. 공용 FIFO1은 유지하며 서버 metadata 설정은 별도로 확인한다. 상세 CHAT 진입점 참조.

- 채팅 캐시 동기화 완료(2026-09-11): 합의된 QA 및 PR 리뷰 보완 후 핵심 48개 회귀 통과. Development iOS 빌드·연결 iPhone 14 설치/실행 확인. 앱 코드·테스트·하네스 커밋으로 정리하며 서버 배포 대상 변경은 없다. VoiceOver 제외·실기기 장시간 보류 범위 유지.

- 참여 완료 UI QA: `ChatViewController.joinRoomBtnTapped` 성공 경로는 이전 참여 버튼을 숨긴다. 캐시 동기화 progress의 2026-09-11 19:18 실제 재참여·재진입 검증 및 QA fixture 관리자 상태 보완 기록 참조.

- 오픈채팅 목록 삭제 원문 재노출 방지: `RoomListUseCase.cachedTopRooms()`는 비동기 로컬 삭제 마커 적용 후 미리보기를 반환한다. `ChatContainer`의 GRDB sanitizer 주입 → `RoomListsViewModel`의 복귀 시 이전 본문 제거·조회 세대 검사 → `RoomListsViewModelDeletionTests`를 참조한다. 서버 조회 추가 없음.

- 삭제 조회 도중 Socket revision 상승 경합 검증은 [TESTS](entrypoints/TESTS.md)의 `GRDBChatDeletionSyncStoreTests`를 참조한다. 실제 계정 간 QA와 제외·보류 범위는 캐시 동기화 task progress의 최신 상태를 따른다.

- 채팅 캐시 동기화 구현: 실제 seq 검사·혼합 범위 복구·공용 저장5회·삭제 transaction 보호·페이지 세대. [코드](entrypoints/CHAT.md), [진행·검증](tasks/chat-message-cache-sync/progress.md).

- 공용 이미지 확대 화면: `Infra/Media/ImageViewer/ImageViewerChromeView.swift`(왼쪽 상단 닫기·하단 저장/번호/신고) → `SimpleImageViewerVC.swift`(제스처·페이지별 요청 식별/실패 재시도·저장 중복 방지). 채팅/갤러리/룩북/프로필 공용, 생성자·loader·저장 주입 계약 유지. [구현 계획·검증](tasks/shared-image-viewer-editorial/implementation-plan.md).

- 사진300MB·실패 사진 복구: `ChatPhotoSizePolicy` → `ChatImageTransportSourceNormalizer`/`ChatMediaSelectionChunker` → `ChatMediaSelectionUseCase.failedImages`/`preserveFailedImages` → `ChatViewController+MediaSelection` 기존 선택 원장 복원·재시도·삭제. 서버 `Socket/src/media/directMediaUploadService.js`. [계약·구현·검증](tasks/chat-media-preview-continuity/photo-size-failure-recovery.md).

- 원본 확보 지연 계측(2026-09-11): `ChatMediaSelectionUseCase`의 사진별 slot 대기 → `ChatMediaSourceAcquisition`의 provider 대기/파일 복사 → VC의 취소 사유. [분석 방법·재현 상태](tasks/chat-media-preview-continuity/acquisition-diagnosis.md).

- 미디어 버블 이미지 깜빡임 개선: `ChatMessageCell` → `ChatImagePreviewItem.stableID` → `ChatImagePreviewCollectionView`의 ID snapshot/최신 payload 분리 → `ChatImagePreviewCell`의 동일 첨부 이미지·로딩 유지. [구현·검증 기록](tasks/chat-media-preview-continuity/implementation.md), 상세 CHAT/TESTS 진입점 참조. 직접 업로드는 Development 배포/3장·70장 전송 확인 완료, Production 미배포다.

- 실제 직접 업로드 QA의 동시 초기화 회귀: `ChatMediaForegroundUploadService.swift`에서 URLSession 최초 접근/작업 생성을 stateQueue로 직렬화한다. `ChatMediaForegroundUploaderTests.swift`가 URLProtocol fake로 동시 첫 업로드 30개의 완료를 검증한다.

- 최신 직접 업로드 구현(미배포): `ChatImageTransportSourceNormalizer`/`ChatGIFMetadataStripper` → 파일 기반 `ProcessedImage`/`PreparedVideo` → `ChatMediaUploadUseCase` 첨부당 display/thumbnail → `RealtimeSocketService` 계약3 → `Socket/src/media/directMediaUploadService.js` 최종 경로 signed PUT·metadata 확인·메시지 원자 확정. `functions/src/chat/media/directUploadCleanup.ts` 취소/만료 정리. 상세 구현·QA는 CHAT와 `tasks/chat-media-bounded-parallel-upload/direct-upload-detailed-design.md` 참조.

- 최신 순차 묶음 전송: CHAT의 「최신: 묶음 순차 전송」. `ChatViewController+MediaSelection` 최종버블 선표시 → Container FIFO1 → UploadUseCase 묶음내 PUT4 → VC 메시지 UI 반영/실패후 반환. `ChatMediaBatchProgress` 합산진행률, PendingStore/Cell/ProgressView 고정원형+장수. [승인 설계](tasks/chat-media-bounded-parallel-upload/design.md).

- 원본 확보 중복콜백 크래시: `ChatMediaSourceAcquisition.swift` 최초callback gate, `OutPickTests/ChatMediaSourceAcquisitionTests.swift` 오류→취소/중복성공/동시콜백 회귀. CHAT 진입점과 서버pipeline QA 보고서 최신항목 참조.

- 사진 선택 후 버블 없음 진단: CHAT의 원본 확보 DEBUG 항목. `ChatViewController+MediaSelection.swift` → `ChatMediaSelectionUseCase.swift` → `ChatMediaSourceAcquisition.swift`에서 대기열/원장/파일 provider/복사 단계와 오류 domain·code만 기록한다.

- 정상 이미지 처리 후30초재시도 제거: FIREBASE의 dispatcher 완료 barrier 항목. `functions/src/chat/media/{functions,orchestrationService,readyService}.ts`가 worker 완료→ready/slot반환→Task응답 순서를 연결한다. 상세 QA/설계는 `tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md`.

- 미디어 finalize 통합·서버 제한 병렬: `tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md`. 앱 복구 계약은 CHAT, Socket/worker 설정·측정은 FIREBASE, 자동 회귀는 TESTS 진입점 참조. 실측 최적값 미확정.

- 미디어 전송 진행 표시: `OutPick/Features/Chat/Views/ChatMediaUploadProgressView.swift` → `ChatMessageCell.applyMediaUploadRecoveryState` → `ChatViewController.pendingRecoveryState`/`updateVisibleRecoveryIfPossible`. 원본 확보 후 사진 덮개·원형 진행, 서버 확인 중 회전, 성공 제거, 실패 회전 제거/기존 복구 버튼. 상태·재사용·렌더링 테스트 `OutPickTests/ChatMediaUploadProgressViewTests.swift`.

- 실제 미디어 전송 QA·방 내부 사진 보기 취소 결함: `docs/ai/tasks/chat-media-bounded-parallel-upload/qa/iphone14-live-transmission.md` → `ChatViewController.viewDidDisappear`/`finishRouteLifecycleForCoordinator`, `ChatRoomRouteLifecycleStateTests`. 최초70장 전송은 실패이며 사용자 최초 성공 답변은 정정됐다. 최신 수정·재검증 상태는 task progress 최상단을 따른다.

## 목적

기능 수정이나 새 기능 추가 시 AI 에이전트가 어디부터 봐야 하는지 빠르게 확인하기 위한 인덱스 문서다.

루트 문서는 공통 진입점과 세부 문서 링크만 유지한다. 기능별 상세 진입점은 필요한 문서만 추가로 읽는다.

## 공통 진입점

- iPhone 14 미디어 성능 QA: `OutPickTests/ChatMediaDevicePerformanceTests.swift` → `docs/ai/tasks/chat-media-bounded-parallel-upload/qa/iphone14-performance.md`. synthetic17회는 참고 자료이며 현재 `ChatMediaPipelineLimits.imagePreparation=4`는 실제 전송·스크롤 비교 후보다. 사용자가 실제 picker로 전송하고 Instruments Animation Hitches + Activity Monitor로 기록한다. ‘미디어 QA 방’ 실제 사진3장 ready/첨부3 확정 확인,70장 및2/4비교 진행 상태는 task progress 최상단. 영상은 후속, XCUITest 조작은 미검증.

- 미디어 제한 병렬 전송(2026-09-10 로컬 구현): `ChatViewController+MediaSelection.swift` → `ChatMediaSelectionUseCase`/`ChatMediaSelectionRepository` → `ChatMediaUploadTurnQueue`/`ChatMediaUploadUseCase` → `ChatOutgoingOutboxUseCase`. 전체 원본 확보 barrier, 준비·업로드 제한, queued 직후 실행권 반환, 중단 후 대표 실패 복원은 `entrypoints/CHAT.md`와 `tasks/chat-media-bounded-parallel-upload/`를 따른다. 서버 배포·실기기 QA는 별도다.

- 방별 자동 승계 50초 제한·부분 성공·실패 방 재처리: `functions/src/chat/moderation/{roomSuccessionPolicy,roomSuccessionJobs,roomMembershipSweep,roomMembershipSweepFunctions}.ts` → `firestore-tests/room-succession-deadline.emulator.test.mjs`; 상세는 `entrypoints/FIREBASE.md`와 `DATA_SCHEMA.md`
- 부모 승계 작업 장애 격리: `roomSuccessionJobs.ts`의 `parentFailurePatch/drainFailedParentRooms/terminalRoom`과 `roomMembershipSweepFunctions.ts` 예약 → 동일 deadline Emulator suite의 부모 실패·claim 경쟁·watchdog·replay 회귀. 실패한 부모의 진단은 자식 성공과 독립 보존한다.
- 채팅 역할 receipt·outbox TTL 배포 계약: `firestore.indexes.json` → `firestore-tests/room-role-indexes.contract.test.mjs`; 원격 배포 확인은 `entrypoints/FIREBASE.md` 참조
- 채팅 역할·읽음 최종 리뷰 회귀: `ChatMessage.init(from:)`, `ChatRoomRoleSession` → `OutPickTests/{RoomRoleEventPayloadTests,ChatRoomRoleSessionTests}.swift`; 세부 계약은 `entrypoints/{CHAT,TESTS}.md` 참조

- 앱 시작/루트 라우팅: `OutPick/App/AppCoordinator.swift`
- iOS Development/Production 빌드 환경: `Configurations/` → `OutPick.xcodeproj/xcshareddata/xcschemes/` → `scripts/build/validate-and-copy-firebase-config.sh` → `OutPick/Info.plist`
- Scene 연결/초기 DI와 bootstrap 실패 복구: `OutPick/App/SceneDelegate.swift`, `OutPick/App/Bootstrap/`
- 탭 조립: `OutPick/App/TabBarController/Composition`
- 기능 코드: `OutPick/Features`
- 공통 인프라: `OutPick/Infra`
- iOS Cloud Functions 공통 transport: `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift`
- iOS Cloud Functions 기능 adapter: `OutPick/Features/*`의 `CloudFunctions*Repository/Client`와 Lookbook `CloudFunctionsMappers/`
- iOS local database bootstrap/Store: `OutPick/DB/GRDB/Core/AppDatabase.swift`, `OutPick/DB/GRDB/Stores/` (`AppDatabase.live()`는 `throws`)
- Chat persistence 계약/조립: `OutPick/Features/Chat/Persistence/`
- Firestore 문서 ID 경계: `docs/ai/tasks/firestore-document-id-boundary-cleanup/`, ADR-020
- 공통 키보드 dismiss helper: `OutPick/Infra/Utility/Support/KeyboardDismissSupport.swift`
- 로컬 DB/데이터 schema: `docs/ai/entrypoints/DATA.md`
- Firebase Functions flat export: `functions/src/index.ts`
- Firebase Functions 공통 runtime/callable: `functions/src/core/`
- Firebase Functions 기능 구현: `functions/src/{auth,brand,chat,lookbook,moderation,profile,styleMoods}/`
- 채팅 메시지 신고 evidence 계약·transaction·copy/cleanup: `functions/src/moderation/messageEvidence/{contracts,service,evidenceCopy,evidenceStorage,evidenceCleanup,evidenceFunctions,evidenceRuntime}.ts` → `functions/src/index.ts` → `functions/scripts/qa-message-evidence-development.mjs` → `firestore.indexes.json` → `functions/src/moderation/reports/contracts.ts` → `contracts/chat-moderation-v1.json` → `functions/src/moderation/messageEvidence/{contracts,evidenceCopy}.test.ts` / `firestore-tests/moderation-reports.emulator.test.mjs`; Phase 7.4C-2/C-3은 Development bucket/IAM/세 Function/필수 인덱스 3개와 30장·350MiB E2E까지 완료했고 Rules·TTL·관리자 조회·Production은 후속 승인 gate다.
- Kakao custom-token 함수·전용 runtime identity: `functions/src/auth/{functions,kakaoService,runtime}.ts`
- 계정·공개 프로필 서버 경계: `functions/src/profile/`, `functions/src/shared/accountStatus.ts`
- 계정 삭제 서버 상태 머신·정리 worker: `functions/src/accountDeletion/` → `firestore.rules`/`storage.rules`/`firestore.indexes.json`
- 계정 capability·삭제 차단: `functions/src/shared/accountStatus.ts`/`functions/src/accountDeletion/repository.ts` → `moderationAccounts/{uid}` schema v2 → `firestore.rules`/`storage.rules`와 `Socket/src/auth/socketAuthMiddleware.js`/`Socket/src/handlers/connectionHandlers.js`
- 스타일 무드 서버·seed·할당: `functions/src/styleMoods/`, `functions/src/shared/styleMoodAssignmentPolicy.ts`, `functions/src/lookbook/admin/seasonMoodFunctions.ts`, `functions/seeds/style-moods.v1.json`
- 브랜드·채팅 개발 데이터 선택 초기화: `functions/src/developmentReset/brandChatManifest.ts` → `functions/scripts/audit-brand-chat-reset.mjs` → 승인 후 `functions/scripts/reset-brand-chat-data.mjs`
- iOS 스타일 키워드 관리자·검색: `LookbookAdminHomeView.swift` → `LookbookCoordinator.pushStyleMoodManagement()` → `StyleMoodManagementViewModel.swift` / `StyleMoodManagementView.swift`
- iOS 브랜드·시즌 스타일 검색/선택: `AdminBrandManagementViewModel.swift` / `AdminBrandManagementView.swift` → `SeasonMoodManagementView.swift` / `StyleMoodSelectionSection.swift`
- iOS 브랜드 search-first picker 정책: `StyleMood.swift`의 `StyleMoodPickerPolicy` → `StyleMoodSelectionSection.swift` → `CreateBrandView.swift` / `AdminBrandManagementView.swift`
- Phase 5.1 스타일 관리 UX 구현·QA: `StyleMoodEditorView.swift` / `StyleMoodSelectionSection.swift` / `SeasonMoodManagementView.swift` → `docs/ai/tasks/style-mood-personalization-account-privacy/plan.md`의 Phase 5.1 → `decisions.md` D62~D64 → `qa-checklist.md`
- iOS 계정 bootstrap·새 온보딩: `AppCoordinator.swift` → `LoadCurrentUserBootstrapUseCase.swift` → `ProfileCoordinator.swift` → `ProfileSetupViewController.swift` → `StyleMoodOnboardingViewController.swift`
- iOS 계정/공개 프로필 read·mutation: `FirestoreCurrentUserAccountRepository.swift`, `FirestoreUserPublicProfileRepository.swift`, `CloudFunctionsProfileMutationRepository.swift`
- iOS 마이페이지 프로필·관심 스타일 편집: `MyPageCompositionRoot.swift` → `MyPageCoordinator.swift` → `ProfileEditViewController.swift` / `StylePreferenceEditViewController.swift` → `UpdatePublicProfileUseCase.swift` / `UpdateStylePreferencesUseCase.swift`
- iOS 일반 사용자 브랜드 요청·내역: `LookbookHomeView.swift` 검색 빈 결과 → `BrandRequestView.swift` → 제출 후 `MyBrandRequestsView.swift`; 재진입은 `MyPageViewController.swift`의 `ACTIVITY` → `MyPageCoordinator.swift` → `DefaultAppContentRouter.openMyBrandRequests()`
- iOS 계정 삭제·취소·로컬 scrub: `MyPageCoordinator.swift` → `AccountDeletionConfirmationViewController.swift` / `AccountDeletionPendingViewController.swift` → `RequestAccountDeletionUseCase.swift` / `CancelAccountDeletionUseCase.swift` → `AccountDeletionReceiptStore.swift` / `AccountDeletionLocalDataScrubber.swift` → `AppCoordinator.swift`
- iOS 환경/Firebase bootstrap: `AppRuntimeConfiguration.swift` → `AppDelegate.configureFirebaseApp(runtimeConfiguration:)` → `OutPickAppCheckProviderFactory.swift` → Debug 구성·Simulator Debug Provider / Release 실기기 App Attest → `OutPick.Debug.entitlements` / `OutPick.entitlements`
- 계정 삭제 provider 재인증: `DefaultSocialAuthRepository.swift` → Google pending sign-in/동일 세션 reauthenticate 또는 Kakao 강제 login prompt → callable
- iOS 관심 스타일 브랜드 홈·전체 보기: `CurrentUserStylePreferenceStore.swift` → `LoadInterestedStyleBrandsUseCase.swift` → `LookbookHomeViewModel.swift` / `InterestedStyleBrandListViewModel.swift` → `LookbookCoordinator.swift`
- iOS 좋아요 에디토리얼 화면·독립 섹션 상태: `LikedView.swift` → `LikedBrandCardView.swift` / `LikedSeasonCardView.swift` / `LikedPostCardView.swift` → `LikedViewModel.swift` → `LookbookCoordinator.swift`
- iOS 브랜드 생성·로고 업로드 재시도: `CreateBrandView.swift` → `CreateBrandViewModel.saveBrand()` → `CloudFunctionsBrandStore.createBrand/updateLogoPaths` + `LookbookStorageService` → `CreateBrandFlowView`
- Lookbook import extraction core/evidence/version: `tools/lookbook-import-worker/src/extraction/`, `processor.ts`, `season-discovery.ts`
- 시즌 목록 durable discovery: `functions/src/lookbook/import/seasonDiscoveryJobs.ts` → `tools/lookbook-import-worker/src/season-discovery-processor.ts` → `brands/{brandID}/seasonDiscoveryJobs/{jobID}`. 생성 흐름 상태 owner는 `CreateBrandDiscoveryViewModel.swift`이며 infrastructure 오류 원문은 내부 로그로만 남기고 브랜드 등록 화면에는 안정된 사용자 문구를 전달한다. 관리자 issue projection/fixed 재시도 상태 owner는 `SeasonImportManagementViewModel.swift`와 `SeasonCandidateDiscoveryResult.extractionIssueUserState`다.
- 시즌 대표 이미지 보강 Phase 7: `tools/lookbook-import-worker/src/extraction/{image-candidates,season-cover}.ts` → `season-discovery.ts` → `season-discovery-processor.ts`. 상세 계약은 `docs/ai/tasks/lookbook-extraction-issue-operations/phase-7-season-cover-enrichment.md`이며 기존 iOS nullable `coverImageURL` 표시 계약은 유지한다.
- Lookbook import worker HTTP/OIDC 경계와 배포 계약: `tools/lookbook-import-worker/src/server.ts`, `config.ts`, `oidc-auth.ts` → `scripts/ai/deploy-lookbook-import-worker.sh` → `docs/ai/runbooks/LOOKBOOK_IMPORT_WORKER_DEPLOYMENT.md`
- Chat media Phase 7.0 feasibility worker: `tools/chat-media-processing-worker/src/index.ts` → `imageProcessor.ts`의 sharp/libvips JPEG·PNG·GIF 정규화와 raw HEIC/HEIF 거부, `videoProcessor.ts`의 ffprobe/ffmpeg stream-copy remux. animated GIF 출력은 `keepDuplicateFrames: true`로 연속 중복 frame까지 frame 수·delay·loop를 보존하며 `imageProcessor.integration.test.ts`가 회귀를 막는다. `runtimeVerification.ts`와 `benchmark.ts`가 codec·resource gate다. 사용자 HEIC 선택은 Phase 7.3 iOS가 고품질 JPEG로 준비한다.
- Chat media Phase 7.1 로컬 구현: Socket `mediaHandlers.js`/`mediaUploadService.js`의 v2 preflight·finalize·status·cancel → `Rooms/{roomID}/MediaUploads/{uploadID}` 단일 원장 → `functions/src/chat/media/`의 queue trigger·private dispatcher·고정 execution slot·watchdog → `tools/chat-media-processing-worker/src/cloudJob.ts`의 Quarantine download·정규화·ready staging manifest 기록. 전용 upload Rules는 `storage.chat-media-quarantine.rules`, client deny와 watchdog query/TTL은 `firestore.rules`/`firestore.indexes.json`이다. Phase 7.2 전에는 message·seq·broadcast를 만들지 않는다.
- Chat media Phase 7.2 로컬 구현: `functions/src/chat/media/readyService.ts`와 worker-completed trigger가 room seq transaction으로 message·media index·preview·delivery job·ready 상태를 원자 생성하고, 검증된 `actualFormat`·`frameCount`·`animated`를 attachment의 `mediaFormat`·`animated`로 투영한다 → `Socket/src/media/mediaDeliveryWatcher.js`가 job lease 후 기존 media event/FCM을 at-least-once 전달 → `reconcileChatMediaObjectCleanup`이 source·고아 ready cleanup을 재시도한다. 새 ready Storage read gate는 `storage.rules`, 전용 bucket deploy config는 `firebase.chat-media.json`, server-only job deny와 cleanup/TTL index는 `firestore.rules`/`firestore.indexes.json`이다.
- Chat media Phase 7.3 iOS 구현: `ChatImageTransportSourceNormalizer.swift`/`ChatMediaSelectionChunker.swift`가 metadata 제거·HEIC→JPEG·GIF 보존과 30장/150 MiB 분할 → `ChatMediaUploadTurnQueue.swift`/`ChatMediaUploadUseCase.swift`가 image/video 독립 FIFO, kind별 로컬 1건 실행, Socket `active_upload_limit` 동일 identity backoff와 relaunch `uploading` status-only 2·4·8초 reconciliation을 적용 → `ChatMediaForegroundUploadService.swift`가 이미지와 영상을 attachment당 하나의 V4 signed PUT으로 foreground direct upload·응답 유실 1회 서버 reconciliation·finalize/status 처리 → `ChatOutgoingOutboxUseCase.swift`/GRDB가 보호된 local source와 실패 후 재시도/삭제 계약을 보존하되 signed PUT URL·필수 header는 영속화하지 않음 → `ChatAttachmentImageService.swift`가 같은 이미지 upload source를 최대 1024px로 메모리 다운샘플링하고 animated viewer에 원본 data를 공급 → `ChatImagePreviewCell.swift`가 확정 GIF만 정적 thumbnail 우하단 `GIF` badge로 표시 → `SimpleImageViewerVC.swift`의 Kingfisher `AnimatedImageView`가 탭한 원본 GIF를 전체 frame 선로딩 없이 현재 page에서만 재생한다. `ChatPendingMediaUploadStore.swift`/`ChatViewController{,Extension}.swift`/`ChatMessageCell.swift`는 대기·활성·재실행 pending의 무표시 로컬 버블, failed/expired의 시간 위치 소형 재시도·삭제 아이콘과 ready delivery reconciliation을 담당한다. 일반 이미지·영상 실패는 전역 팝업 없이 버블 액션만 사용하고 ban 중단 안내만 유지한다. 미디어 실패 overlay, 전송 중 진행률·취소 UI와 background `URLSession`/자동 PUT 복원은 사용하지 않는다.
- Lookbook extraction adapter registry: `tools/lookbook-import-worker/src/extraction/adapters/{registry,cafe24,types}.ts`
- Lookbook extraction review/trust/resume: worker `src/extraction/review.ts`, Functions `src/lookbook/import/{functions,reviewContract}.ts`, iOS `LookbookExtractionReview*`
- Lookbook extraction count-based review gate/UI: worker `src/extraction/{quality,review}.ts`, iOS `LookbookExtractionReview.swift`, `LookbookExtractionReviewViewModel.swift`, `LookbookExtractionReviewView.swift`
- Lookbook expected-count 활성 gallery scope: worker `src/extraction/expected-count.ts`, YOUTH incident fixture/test
- Lookbook 시즌 상세 pagination·이미지 prefetch: `LoadSeasonDetailUseCase.swift`, `SeasonDetailViewModel.swift`, `SeasonDetailView.swift`, 공용 `BrandImageCache`→`ImageCachePipeline`
- Lookbook extraction evidence/issue 자동 기록(Phase 2 완료): worker `src/extraction/{retained-evidence,issue-policy,issue-recorder}.ts`, `processor.ts`, `season-discovery-processor.ts` → Functions `src/lookbook/import/evidenceCleanup.ts`. 배포 경합의 구형 occurrence 지연 도착은 `issue-recorder.ts`가 cluster blocked runtime을 단조 증가시키고 fixed/verified runtime의 job 재시도 projection을 복원한다.
- Lookbook extraction issue 공통 계약: `contracts/lookbook-extraction-issue-v1.json` → Functions `extractionIssueContract.ts` → Worker `extraction/issue-contract.ts` → `docs/ai/tasks/lookbook-extraction-issue-operations/`
- Lookbook extraction issue 내부 운영: Functions `src/lookbook/issueOperations/{contract,auth,service,functions}.ts` → CLI `tools/lookbook-extraction-issue-ops/src/{config,gcloud,index}.js`의 exact operator IAM Credentials `generateIdToken` → `docs/ai/runbooks/LOOKBOOK_EXTRACTION_ISSUE_OPERATIONS.md`
- Lookbook extraction fix 검증: Worker `src/{runtime-contract,server,processor}.ts`의 `/runtime-contract`, `/smoke/extraction` → Functions `src/lookbook/issueOperations/{releaseContract,releaseExternal,releaseService,releaseFunctions}.ts` → CLI `verify-fix`
- Lookbook extraction fixed-only iOS 재시도: `SeasonCandidateDiscoveryResult.swift` / `SeasonImportJob.swift` / `LookbookExtractionReview.swift` → 각 Cloud Functions Repository → `SeasonImportManagementViewModel.swift` / `LookbookExtractionReviewViewModel.swift` → 관리자 두 화면. 서버 entrypoint는 `retrySeasonDiscoveryAfterExtractionFix`, `retryLookbookExtractionAfterFix`다.
- Lookbook existing-season reconcile: worker `src/extraction/reconcile.ts`, Functions `src/lookbook/import/{functions,repairContract}.ts`, iOS `LookbookSeasonRepair*`
- Lookbook 관리자 remote preview 이미지: `Services/ImageLoading/LookbookRemotePreviewImage{Loading,Loader}.swift`, `Views/Shared/LookbookRemotePreviewImageView.swift`
- Lookbook extraction fixture/differential gate: `tools/lookbook-import-worker/src/fixture/`, `tools/lookbook-import-worker/fixtures/`, `npm run test:fixtures`
- Lookbook Cafe24 underscore-detail discovery 회귀: `tools/lookbook-import-worker/src/season-discovery.ts`, `fixtures/discovery/platform/cafe24-underscore-detail-list/`
- Socket bootstrap/application: `Socket/index.js`, `Socket/src/app/`
- Socket 기능 경계: `Socket/src/{auth,handlers,rooms,messages,media,lifecycle,runtime}/`
- Socket message idempotency 공통 경계: `Socket/src/messages/messageDeliverySingleFlight.js`, `Socket/src/messages/sequenceStore.js`
- iOS Socket 단일 ingress/admission/routing/reconnect: `OutPick/Infra/Realtime/RealtimeSocketListenerBinder.swift`의 `RealtimeSocketMessageIngressQueue`, `OutPick/Infra/Realtime/RealtimeSocketService.swift`의 `RealtimeSocketAdmissionState`·`RealtimeRoomRoutingState`·`RealtimeRoomJoinState`·Socket generation·visible strict suspend/rejoin, `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `OutPickTests/RealtimeSocketListenerBinderTests.swift`, `OutPickTests/RealtimeChatIngressOrderingTests.swift`
- iOS Chat route·비동기 진입 경쟁·edge-pop/방 생성 차단 정책: `OutPick/Features/Chat/ChatNavigationController.swift`, `OutPick/Features/Chat/ChatNavigationStackPolicy.swift`, `OutPick/Features/Chat/ChatOpenRoomRequestState.swift`, `OutPick/Features/Chat/ChatOpenRoomRequestRegistry.swift`, `OutPick/Features/Chat/ChatRoomRouteLifecycleState.swift`, `OutPick/Features/Chat/Controllers/{ChatViewController,RoomCreateViewController}.swift`, `OutPick/Features/Chat/ChatCoordinator.swift`, `OutPickTests/{ChatNavigationControllerTests,ChatNavigationStackPolicyTests,ChatOpenRoomRequestStateTests,ChatOpenRoomRequestRegistryTests,ChatRoomRouteLifecycleStateTests}.swift`
- iOS Chat background tap·native message context menu·announcement long press·cell action gesture 책임: `OutPick/Features/Chat/Controllers/{ChatViewController,ChatViewControllerExtension}.swift`, `OutPick/Features/Chat/Domain/Policies/ChatMessageActionPolicy.swift`, `OutPick/Features/Chat/Views/Cell/ChatMessageCell.swift`
- iOS Profile modal edge-swipe dismiss: `OutPick/Features/Profile/Views/UserProfileDetailViewController.swift`, `OutPick/Features/Profile/UserProfileDetailCoordinator.swift`, `OutPick/Infra/Utility/Transitions/ChatModalTransitionManager.swift`
- iOS visible Chat strict ordering/recovery: `OutPick/Infra/Realtime/RealtimeChatIngressOrdering.swift`, `OutPick/Infra/Realtime/FirebaseChatRealtimeGapRecoveryLoader.swift`, `OutPickTests/RealtimeChatIngressOrderingTests.swift`
- iOS lightweight Banner presentation/retry: `OutPick/Infra/Banner/BannerManager.swift`의 `RealtimeBackgroundRoomSessionOpening`·`BannerSubscriptionRetryPolicy`, `BannerPresentationQueueState.swift`, `OutPickTests/BannerPresentationQueueStateTests.swift`
- iOS 방별 fan-out 최종 dedupe: `OutPick/Infra/Realtime/RealtimeSocketService.swift`의 `ChatRoomSessionActor`, `OutPickTests/ChatRoomSessionActorTests.swift`
- Chat moderator delegation Phase 1 호환 데이터 기반: Room owner canonical/fallback은 `ChatRoom.swift` → `ChatRoomFirestoreDTO.swift` → `ChatRoomFirestoreMapper.swift`, role/read projection은 `JoinedRoomListItem.swift`, 공개 역할 이벤트 계약은 `ChatMessageType.swift`/`ChatMessage.swift`, 로컬 보존은 `ChatMessageRecord.swift` → `ChatMessageRecordMapper.swift` → `GRDBMigrationRegistry.addRoomRoleEventToChatMessage`다. 집중 검증은 `ChatRoomFirestoreMapperTests`, `JoinedRoomProjectionTests`, `RoomRoleEventPayloadTests`, GRDB mapper/migration tests다.
- Chat moderator delegation Phase 2 서버 권한 코어: `functions/src/chat/moderation/roomRoleService.ts`의 transaction resolver·임명/회수/사임/퇴장/이전·24시간 receipt·role event/outbox → `roomBanService.ts`/`service.ts`의 owner/moderator 제재 matrix → `functions.ts`/`functions/src/index.ts` callable export → `firestore.rules` private state·role mutation deny → iOS `ChatModerationLifecycleRepository.swift` access/mutation mapping. 검증은 `contracts.test.ts`, `index.contract.test.ts`, `firestore-tests/{chat-moderation.emulator,moderation-capabilities.rules.test}.mjs`, `CloudFunctionsChatModerationLifecycleRepositoryTests.swift`다.
- Chat moderator delegation Phase 5 자동 승계·계정 정리: 영구 정지/계정 삭제 transaction → `roomOwnershipSuccessionJobs` → `roomSuccessionJobs.ts`의 부모/방별 상태·계정 fence → `roomMembershipSweep.ts`의 관리자 전용 후보·no-candidate 종료 → `roomMembershipSweepFunctions.ts`의 방별 50초·실패 후 5/15/20초 예약과 5분 watchdog → account deletion `cleanup.ts`/`drain.ts` finalizer gate·role event 익명화 → iOS 동일 ID privacy 갱신. 수동 복구는 `functions/scripts/replay-room-ownership-succession.mjs --room ...`, 검증은 `room-succession-deadline.emulator.test.mjs`와 관련 suite다.
- Chat moderator delegation Phase 6 migration·rollout gate: `functions/scripts/migrate-room-moderator-cutover.mjs`가 dry-run/apply orchestration을, `room-moderator-cutover-plan.mjs`가 ownerUID·dual frontier·owner role·moderatorCount 보정 계획과 conflict/blocker·exact-count/hash gate를 소유한다. 앱 시작 gate는 `OutPick/App/Rollout/` → `AppCompositionRoot.swift` → `AppCoordinator.swift`, 채팅 화면 feature snapshot은 `ChatContainer` → `ChatCoordinator` → `ChatRoomSettingViewModel`, 서버 신규 권한 생성 gate는 `functions/src/chat/moderation/rollout.ts` → `functions.ts`다. fixture·gate 검증은 `room-moderator-cutover-plan.test.mjs`, `rollout.test.ts`, `AppRolloutGateTests.swift`, 운영 절차는 task `migration-runbook.md`다. 실제 Firebase migration·배포·설정 변경은 수행하지 않았다.
- Chat moderator delegation Phase 3 timeline/unread: Socket 일반 message는 `Socket/src/messages/sequenceStore.js`, media ready는 `functions/src/chat/media/readyService.ts`에서 `seq + unreadMessageSeq`를 원자 증가한다. 역할 outbox는 `Socket/src/roles/roleEventDeliveryWatcher.js` → `createProductionDependencies.js` → iOS `RealtimeSocketListenerBinder.swift`/`RealtimeSocketService.swift` 공통 ingress로 전달되고 Messages pagination이 복구 원장이다. iOS dual read frontier는 `ChatReadStateStore.swift`/`ChatRoomReadStateStore.swift`/`ChatRoomViewModel.swift` → `UserProfileRepository.updateReadFrontier`, 표시·제외 정책은 `RoomRoleEventCollectionViewCell.swift`, `ChatMessageActionPolicy.swift`, `BannerManager.swift`, `GRDBChatMessageStore.swift`가 소유한다.
- Chat moderator delegation Phase 4 iOS 역할 화면: 현재 방 단일 listener는 `ChatRoomRoleRepository.swift` → `ChatRoomRoleUseCase.swift` → `ChatRoomRoleSession.swift`이며 `ChatContainer`가 같은 세션을 `ChatRoomViewModel`과 `ChatRoomSettingViewModel`에 주입한다. 참여자 pinned pagination·정렬은 `FirebaseChatRoomRepository.fetchPinnedRoomMembers` → `LoadChatRoomParticipantsUseCase`, 임명·회수·사임·이전 UI는 `ChatRoomSettingViewController`, 메시지 작성자 현재 역할 지연 판정은 `ChatRoomViewModel.resolvedMessageActionPolicy` → `ChatMessageActionPolicy`다. 검증은 `ChatRoomRoleSessionTests`, `ChatRoomParticipantRolePolicyTests`, `ChatMessageActionPolicyTests`, `ChatRoomExitUseCaseTests`다.
- 현재 Socket ingress 순서 보장 task: `docs/ai/tasks/socket-ingress-ordering-hardening/`
- iOS Socket candidate QA: `RealtimeSocketService.swift`의 DEBUG 전용 `SocketDebugQAConfiguration`, `OutPickTests/SocketDebugQAConfigurationTests.swift`
- iOS 발신 ACK 수렴: `ChatMessageSendReceipt.swift`, `ChatViewController.reconcileServerConfirmedOutgoingMessage`, `LookbookChatShareViewModel`의 동일 ID retry
- Socket room summary 단일 소유권: `Socket/src/messages/sequenceStore.js`가 seq transaction 안에서 `Rooms.lastMessage*`를 갱신하며, iOS `RealtimeSocketService`의 ACK 경로는 room summary를 직접 쓰지 않는다.
- Socket 자동 검증: `Socket/test/`, `Socket/scripts/run-tests.mjs`
- Phase 6 텍스트 전송 보호: Socket `src/utils/rateLimit.js`와 text/Lookbook/media handler가 canonical moderation principal·room·kind별 2초 bucket을 공유하고, Functions `src/lookbook/comments/{contracts,service,functions}.ts`가 댓글·답글 합산 분당 20회 Firestore transaction quota와 UUID 멱등 문서 ID를 소유한다. iOS 입력 상한/재시도 ID는 `ChatRoomMessageUseCase.swift`, `ChatUIView.swift`, `Create{PostComment,CommentReply}UseCase.swift`, 댓글 ViewModel/InputBar가 담당한다.
- Phase 6 메시지 개인정보 최소화: 신규 메시지의 `senderEmail`은 Socket/FCM/iOS `ChatMessage`/GRDB에서 제외하며 `GRDBMigrationRegistry.removeSenderEmailFromChatMessage`가 기존 로컬 column을 제거한다.
- Chat UGC safety/moderation v1 계약: `contracts/chat-moderation-v1.json` → ADR-024 → `docs/ai/tasks/chat-ugc-safety-room-moderation/{decisions,plan,phase-7-implementation-plan,progress,qa-checklist}.md`
- Chat moderation Phase 1 구현·Development rollout: iOS `CloudFunctionsCurrentUserModerationRepository`/`LoadCurrentUserBootstrapUseCase`/`AppCoordinator`/`ModerationNoticeViewController`, Functions `src/moderation/`와 `scripts/backfill-moderation-principals.mjs`, Socket `src/moderation/capabilities.js`, `firestore.rules`/`storage.rules` → 상세 `entrypoints/APP.md`, `entrypoints/CHAT.md`, `entrypoints/FIREBASE.md`, `entrypoints/TESTS.md`
- Chat moderation Phase 2 신고·관리자 API: iOS `ChatModerationReport.swift` → `ChatModerationReportingRepository.swift` → `SubmitChatModerationReportUseCase.swift`; Functions `src/moderation/{reports,admin,audit}/`; Rules/index/transaction QA `firestore.rules`, `firestore.indexes.json`, `firestore-tests/moderation-{capabilities.rules,reports.emulator}.test.mjs`
- Chat deletion revision legacy 감사·cutover: `functions/scripts/audit-chat-deletion-revisions.mjs`가 revision·cleanup·reply/media 잔존을 읽기 전용·비식별 집계한다. `apply-chat-deletion-field-index.mjs`는 Development 단일 field index를 exact patch하고, `repair-chat-deletion-cutover.mjs`는 expected hash/count/head와 confirmation fence 아래 cleanup 재개·revision backfill을 분리 수행한다. 순수 gate/정렬은 `chat-deletion-cutover-plan.mjs`와 test가 소유한다.
- Chat moderation Phase 3 삭제·Phase 3.1 공용 종료 tombstone: iOS `FirebaseChatRoomRepository.fetchJoinedRoomList`/`ChatModerationLifecycleRepository.swift` → `ChatRoomClosureAcknowledgementUseCase`/`JoinedRoomsViewModel`/`ChatCoordinator.handleRoomClosure`; 실시간·오프라인 확인 직후 목록 제거와 같은 세션 stale fetch 차단은 `ChatRoomClosureListUpdating`, `JoinedRoomsViewModel.removeRoomAfterRealtimeClosure`/`acknowledgeClosedRoom`; Functions `src/chat/{moderation,cleanup}/`의 `acknowledgeRoomClosure`와 `content → retention` cleanup; Socket `roomClosureWatcher.js`; Rules/transaction QA `firestore-tests/{moderation-capabilities.rules,chat-moderation.emulator}.test.mjs`
- Chat moderation Phase 4 전역 차단: `OutPick/Features/Moderation/{UserBlockVisibilityStore,UserBlockSnapshotStore,UserBlockSessionController}.swift` → `AppCompositionRoot`/`AppCoordinator` bootstrap → Chat·Lookbook·Profile·MyPage 공용 UseCase/Store; Functions `src/lookbook/safety/{blockContracts,functions}.ts`의 `blockUser`/`unblockUser`; Socket `src/push/chatPushService.js`의 수신자별 차단 push 억제 → 상세 `entrypoints/{APP,CHAT,FIREBASE,TESTS}.md`
- Chat moderation Phase 7.4D 관리자 queue/current-revision Evidence: Functions `src/moderation/admin/{contracts,service,functions,messageResolution,evidenceAccess}.ts`, Evidence retention drain `src/moderation/messageEvidence/{evidenceCleanup,evidenceFunctions}.ts`, Firestore deny/index/TTL `firestore.{rules,indexes.json}`, 전용 Storage target/rules `.firebaserc`·`firebase.chat-media.json`·`storage.moderation-evidence.rules`, 자동 검증 `functions/src/moderation/admin/*.test.ts`·`firestore-tests/{moderation-reports.emulator,moderation-evidence-storage.rules.test}.mjs` → 상세 `entrypoints/{FIREBASE,TESTS}.md`
- Chat moderation Phase 7.5E 사용자 메시지 신고: `ChatViewController.handleReport`와 `SimpleImageViewerVC.onReport` → `ChatCoordinator.presentMessageReport` → `ChatMessageReportViewController`/`ChatMessageReportViewModel` → `SubmitChatModerationReportUseCase.submitMessageReport` → `CloudFunctionsChatModerationReportingRepository` → callable `submitMessageReport`/`submitMessageReportService`. 중복 판정은 서버 transaction이 소유하고 iOS는 별도 GRDB·신고 캐시 없이 현재 신고 화면의 네트워크 재시도 동안만 UUID와 입력을 유지한다. 신고 화면은 OutPick editorial token을 사용하며 상세 입력 밖 tap과 scroll drag로 키보드를 닫는다. `신고` CTA는 사유 선택 전 비활성이고 선택 직후 활성화되며 ViewModel도 사유 누락을 재검증한다. reason title·symbol, multiline 안내·placeholder와 가변 높이 CTA는 Dynamic Type에 맞춰 재구성되고 선택·제출 상태는 글자 크기 변경 중에도 유지한다.
- Chat moderation Phase 7.5A~D queue-only·공통 deletion mutation·Socket fast path·iOS reconciliation: 서버는 `functions/src/chat/deletion/mutation.ts`, Socket은 `Socket/src/deletion/deletionDeliveryWatcher.js`, iOS는 `ChatDeletionSyncUseCase.swift` → `ChatDeletionSyncRepository.swift` → `GRDBChatDeletionSyncStore.swift` → `ChatMessageRecordMapper.swift`를 진입점으로 사용한다. 최초 삭제만 tombstone·Room revision·cleanup/outbox를 원자 생성하며 iOS는 account+room cursor·방 수명 삭제 마커·durable cleanup queue로 누락을 복구한다. 서버가 직접 반환한 같은/더 최신 tombstone은 legacy marker의 sender 익명화 정책을 교정하고, 오래된 visible payload에는 marker가 계속 우선한다. 기존 Firestore 삭제 listener는 제거됐다.
- Chat moderation Phase 5 room ban UX 보정: `ChatMessageActionPolicy`/`ChatViewController`의 방장 메시지 `내보내기`, `ChatRoomSettingViewController`의 방장 전용 `차단 사용자` 버튼 → `ChatRoomBannedUsersViewController` 독립 관리 화면, 참여자 프로필·별도 관리 버튼, `ChatModerationLifecycleRepository.fetchMyRoomAccess` → Functions `getMyRoomAccess`의 서버 권위 `member | joinable | banned | closed` 판정.
- Chat account capability v2·Storage reservation 보정: `functions/scripts/backfill-account-capabilities.mjs`, `functions/scripts/audit-{firebase-rules,firestore-indexes}.mjs`; Rules 회귀 `firestore-tests/chat-media-storage.rules.test.mjs`
- Platform admin 운영: `functions/scripts/manage-platform-admin.mjs` → `functions/src/moderation/admin/platformAdminOperations.ts` → `docs/ai/runbooks/PLATFORM_ADMIN_OPERATIONS.md`
- Phase 6 통합 회귀/배포 gate: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`, `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`
- Firestore rules: `firestore.rules`
- Firestore indexes: `firestore.indexes.json`
- Firebase/Storage 운영 권한 확인: `docs/ai/entrypoints/FIREBASE.md`
- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`
- Q7 Development 실기기 UI 진입점: `OutPickUITests/LookbookImportQ7DevelopmentUITests.swift`. 명시적 opt-in과 고유 run ID가 있어야 실행하며 총 관리자 확인 뒤 QA 브랜드 1개 생성·UNAFFECTED 후보 탐색을 확인한다. 제목/순서가 고정 fixture와 다르면 즉시 실패하고 시즌 선택·이미지 import는 하지 않는다. 실행 전제와 증거는 `docs/ai/tasks/lookbook-import-performance/product-queue-q7-readiness.md`를 따른다.

## 세부 진입점

- 앱 조립, 탭, 주요 Feature: `docs/ai/entrypoints/APP.md`
- Chat 앱 화면/검색/채팅방 흐름: `docs/ai/entrypoints/CHAT.md`
- Lookbook 앱 화면/도메인: `docs/ai/entrypoints/LOOKBOOK.md`
- Profile 생성/수정/상세: `docs/ai/entrypoints/PROFILE.md`
- Data/GRDB/Repository boundary: `docs/ai/entrypoints/DATA.md`
- Firebase Functions/Firestore: `docs/ai/entrypoints/FIREBASE.md`
- 테스트: `docs/ai/entrypoints/TESTS.md`

## 작업별 진입점

| 포인터 | 문서 |
| --- | --- |
| 현재 작업과 최근 완료 상태 | `docs/ai/tasks/active.md` |
| 세션 복원 | `HANDOFF.md` |
| 장기 결정 | `docs/ai/ADR.md` |
| 데이터 계약 | `docs/ai/DATA_SCHEMA.md` |

최근 작업은 `active.md`에서 관련 task의 `decisions.md`와 `progress.md`로 들어간다. phase 전체 이력은 루트 인덱스에 복사하지 않는다.

## 변경 목적별 빠른 경로

| 변경 목적 | 읽기 순서 |
| --- | --- |
| 핵심 인프라 모듈화 | `tasks/core-infrastructure-modularization/design.md` → `contracts/README.md` → `active.md`가 가리키는 현재 phase 결정/계획/테스트 → decisions/plan/progress → ADR-019 → 네 현재 대형 진입점 |
| 삭제 purge queue/장애 | task decisions/progress → ADR-018 → `lookbook/deletion/purgeDrain.ts` → `lookbook/deletion/functions.ts` scheduler/query → `purgeLease.ts` → test |
| 삭제 요청 앱 목록/retry | task progress → `LOOKBOOK.md` 삭제 관리 → `FIREBASE.md` 삭제 lifecycle → iOS/Functions 구현 |
| 룩북 import/진단 | task progress → `architecture/LOOKBOOK_IMPORT_WORKER.md` → `FIREBASE.md` URL import → worker/앱 구현 |
| 브랜드 요청/관리 | `LOOKBOOK.md` 관리자 흐름 → `FIREBASE.md` 권한·요청 → 관련 task progress |
| 관심 스타일 브랜드 | 현재 task Phase 6 decisions/data contract → `LOOKBOOK.md` 관심 스타일 브랜드 → `FirestoreBrandRepository.swift` → 관련 ViewModel/View/테스트 |
| 계정 삭제 iOS | 현재 task Phase 8 decisions/plan → `PROFILE.md` 계정 삭제 iOS 흐름 → MyPage 화면/UseCase/Repository → `AppCoordinator.swift` → `TESTS.md` Phase 8 |
| 스타일 무드/seed | 현재 task decisions/seed spec → `DATA_SCHEMA.md` 스타일 무드 계약 → `functions/src/styleMoods/` → `firestore.rules`/indexes → rules test |
| 새 사용자 온보딩/프로필 | 현재 task progress → `PROFILE.md` → `AppCoordinator.swift` → Profile UseCase/Repository → Functions profile module/rules |
| Chat membership/cache | `CHAT.md` → `DATA_SCHEMA.md` Chat 계약 → 관련 task decisions/progress |
| Chat 신고·차단·삭제·room ban·계정 제재·미디어 격리/evidence | `tasks/chat-ugc-safety-room-moderation/decisions.md` → Phase 7.5 신고 UX·Deletion Sync `phase-7-5-design.md` → `phase-7-implementation-plan.md` → `contracts/chat-moderation-v1.json` → ADR-024 → `CHAT.md`/`FIREBASE.md`/`TESTS.md` → task plan/progress/QA |
| Chat route/lifecycle/gesture 완료 변경 | `CHAT.md`의 `Route/lifecycle/gesture 변경 파일 빠른 지도` → `tasks/chat-route-lifecycle-hardening/progress.md` → `TESTS.md`의 Chat route lifecycle hardening tests → task QA checklist |
| Firestore 문서 identity | ADR-020 → `DATA_SCHEMA.md` → `CHAT.md`/`LOOKBOOK.md` 문서 ID 경계 → `DATA.md` Repository boundary → `FIREBASE.md` rules → `TESTS.md` 경계 테스트 → task progress/QA |
| Chat 대규모 unread/read frontier | `tasks/active.md` → `tasks/socket-ingress-ordering-hardening/phase-6-unread-catch-up-read-frontier.md` → `CHAT.md` read frontier/realtime-only 3초 preview·즉시 persistence 및 진단 계측 진입점 → `TESTS.md` Phase 6-A~C 회귀·Phase 6-D QA |

작업 시작 시 이 문서와 `docs/ai/tasks/active.md`만 먼저 읽고, 표가 가리키는 세부 문서만 추가로 확인한다.
# 2026-09-22 다운로드② 최종 검증

취소·파일 수명 필수 잔여 완료: Firebase12.17.0 공식수정, 구SDK 취소 후 재시작/파일생성 재현 및 수정SDK 통과, 공용87개 회귀. 실기기 취소87건·임시파일90개정리·신규잔여0, 사용자 지속빈화면아닌 빠른스크롤직전 로딩으로 확인. 진단 없는 일반DEV 복원 성공. `docs/ai/tasks/chat-media-first-view-loading/download-bottleneck-results.md`에 근거와 한계, 다음③은 `cache-reuse-implementation-plan.md`에 있으며 구현 전.
