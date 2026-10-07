# 제품 룩북 대기열 — 세부 구현 계획 검토본

## 2026-10-07 최신 완료 — 합의한 Q7 서버 검증

[최종 결과·커밋](product-queue-q7-final-results.md): 정상A/B·A~J와K/L 실제종료/처음부터재시도·총5회소진/실패목록·수동새실행/성공제거를완료했다. K/L8접수·124JPEG·현재원장/hash/generation·종료후queue idle,서버필수6게이트와앱28개검사모두통과다. 실제장시간/24h삭제·관리자웹·목록운영지침은기존합의대로후속미검증이며원래active중신규도착시간조건도통과로바꾸지않는다. 서버/Worker/앱/검증커밋4개 생성·설계/결과67개문서 포함 범위 사용자 승인. 아래구현중·배포0·잔여표시는과거시점이다.

## 2026-10-07 최신 변경 — Q7 재시도·실패 목록 계약

이 절은 아래 기존 Q7의 중간 checkpoint 복원·inspect/resume 필수 확대안보다 우선한다. [확정 결정](season-failure-retry-decision.md): 종료 확인 뒤 해당 시즌을 처음부터 자동 재시도(최초 포함 총5회), 소진 시 최종 실패, 완료 시즌 유지, 맨뒤 새 수동 요청·새5회. 실패 목록 문서는 시즌별 하나로 유지·재실패 최신화·성공/명시적 재시도 안 함에 제거·무선택 유지다. 원본 실행 기록의 보관 정책은 유지한다.

실행 순서: **세부 변경 계약 최종화 → 종료 정산·처음부터 재시도·실패 목록 보완 → 로컬 필수 검사 → 짧은 실제 비정상 종료·재시도 검증 → 결과/하네스/최종 커밋**. [개정 단계·변경 후보·게이트](product-queue-q7-server-validation-plan.md)의 최신 절을 따른다. 실제12/14/15분 장시간 플랫폼 경계 실측은 후속 미검증이며 기존 안전장치·로컬 검사는 유지한다. 기존 A/B·A~J 결과와 과거 실패 원본을 보존한다.

D1 부분 산출물 정리·D2 같은5회 예산과 새 검토 추천은 사용자 확정·구현 승인됐다. 실패 identity/version+executionID·인가/멱등3개 API·종료 정산/새 추출/기간 정리를 로컬 구현했으며 현재 코드 필수 gate는 진행 중이다. 기존 코드나 과거 gate의 통과를 새 계약의 구현 완료로 간주하지 않는다. 새 실험의 대상·요청량·비용도 다시 산정한다.

2026-10-07 최신: [A~J 실제 제품 검증 결과](product-queue-q7-ten-brands-results.md) — 36접수·16시즌 저장·710JPEG와 현재 공개 원장 대조가 완료됐다. 두 100ms 예약 wave에서 실제 서버 순번과 브랜드 대기·실행 비중첩을 확인했다. 앞 run 시작 후 신규 접수는 없었으므로 A/B의 active 중 도착과 동일한 조건으로 표시하지 않는다. 메모리 최고 84.05%, 최대 표본 공백 380.7ms, 이미지 실패·시즌 재시도·중단 0회. 실행기 job 기록 누락은 원본 보존·별도 job index 대조로 정산했으며 이후 도구 기록 연결을 수정했다. 최종 client31/Worker359/Linux2 필수 검사 통과. 실제 장시간·플랫폼 종료 및 청구 전체는 별도 미검증이다. 전체 Q7 완료·커밋은 아직 아니다. 아래 실행 전/진행 중 문구는 과거 기록이다.

2026-10-06 Q7 최신 기준: [전체 계획](product-queue-q7-server-validation-plan.md)과 [P2 구현안](q7-verifier-p2-plan.md), [검증 행렬](q7-verification-matrix.md)을 따른다. Q0~Q6 결과는 보존한다. 과거 Q6 배포 전 문구는 당시 이력이며 Q7 readiness에 후속 배포 기록이 있다. P1 인가 변경은 미배포다. iPhone 관리자 UI 대신 최소 Google 로그인+기존 callable로 검증한다. FIFO는 브랜드 최종 저장 우선이 아니라 접수된 요청 묶음 sequence 기준이다.

2026-10-06. Q0~Q6 로컬 구현/필수 게이트 통과. Q7 순서(Development 소규모 → A~J 16시즌 제품 queue → 예외/앱 확인), A6/B2/C~J각1 입력, 고정 후보와 일치한 needsReview 항목의 정상 관리자 승인이 확정됐다. 실제 Development 배포/실행은 미시작이다. [Q7 readiness](product-queue-q7-readiness.md)에 상세 계획과 요청량, read-only 원격 상태, 로컬 사전 게이트를 기록한다.

## 1. 목표와 범위

Q1 추가 진행: 서버 adapter가 중복 판정한 기존 job의 참조 입력과 준비 처리를 구현했다. 기존 실행 이력은 보존하며 새 실행은 만들지 않는다. 실제 시즌 선택·직접 URL adapter 및 부분 저장 재시도 연결은 아직 미완료다. 기존 결과와 후속 검증은 [Q1 기록](product-queue-q1-results.md)을 따른다.

Q3 최신 추가(2026-10-05): [결과·검증](product-queue-q3-results.md). queue-owned 이미지 저장에 실행별 경로/두 generation 조건부 공개, browser/image/hash 인스턴스 단일 gate, browser 전환 시 source buffer cache purge, 활성 업로드 원장의 삭제 차단을 구현했다. Q3 Linux Chromium 종료/메모리·실제 Storage 검증, legacy direct 경로 cutover, Q4 stale ledger 복구는 남았다. 제품 대기열은 아직 활성화하지 않았다.

Q4 최신 추가(2026-10-05): [구현·필수 게이트·미검증 범위](product-queue-q4-results.md). stale head 전달 회수, 정확한 Cloud Logging 증거를 요구하는 기본 비활성 복구 API/CLI, execution ledger 기반 24시간 generation 정리, 일일 24h/30d/90d 기록 만료를 구현했다. G-F/G-E/G-W/G-R/G-L은 현재 소스 digest로 통과했다. 실제 IAM·Development 종료 증거·Worker HTTP 강제 종료/14분 응답은 아직 검증하지 않았다.

Q5 최신 추가(2026-10-06): [앱 요청 기록·접수/복원·진행 UI·게이트](product-queue-q5-results.md). 계정별 GRDB migration 27과 계정 삭제, 전송 전 고정 ID 저장, 응답 유실 재조정, 브랜드 생성/탐색·수동 갱신·시즌 접수·검토·재시도·보수 요청의 queue envelope, 상태 polling/복원 연결을 완료했다. iOS 필수 G-I가 28개 테스트로 통과했다.

Q6 최신 추가(2026-10-06): [로컬 통합 결과와 원본](product-queue-q6-results.md). 모든 batch kind/continuation activation과 14분 HTTP 응답 경계를 연결하고 G-F/G-W/G-E/G-R/G-L/G-I를 현행 digest에서 통과했다. 재시도는 대기 없이 최초 시도 포함 총5회다. 실제 Development/Storage/Cloud Tasks 동작, IAM, 원격 legacy 경로, 수동 화면 QA는 Q7에 남았다.

앱의 한 번 선택을 닫힌 요청으로 받아 이미지 import와 목록 탐색을 서버 접수 순서대로 처리한다. 현재 묶음의 시즌은 최대6개, 다운로드4/변환1/업로드4·재사용128MiB를 공유한다. 브라우저는1개이며 이미지의 무거운 작업과 겹치지 않는다. 저장·정리 확인 뒤 다음 차례를 시작한다.

정상12/14/15분 분할은 같은 차례에서 이어간다. 종료 불명확·메모리 중단은 복구 확인으로 차단한다. 실행별 새 경로에 업로드한 뒤 현재 실행권으로만 앱 참조를 공개한다. 추가 선택/검토 승인/수동 재시도는 맨 뒤이며 수동 재시도에는 새 총5회 예산을 준다.

앱은 배포 전이므로 최신 계약 하나로 맞춘다. 구버전 앱 호환, 새 관리자 복구 화면, 자동 자원 증설, 공정성/동적 동시성 스케줄러, 영구 원본 캐시, 기존 성능 행렬 재실행은 제외한다. 기존 Development 잔여 task/revision의 실행 우회는 제거 대상이다. 실험용 remote runner를 제품 실행 경로로 그대로 승격하지 않는다.

## 2. 세부 상한·만료 처리 결정표

아래 세부 상한·만료 처리·추가 안전장치는 사용자가 추천안으로 모두 확정했다. 정책 확정은 코드 구현 승인과 구분한다. 파일명·함수 분리는 구현 계획의 제안이며 동등한 좁은 책임 분리는 가능하되 권한·완료 기준·정책을 임의 변경하지 않는다.

| 항목 | 기준 | 상태/근거 |
|---|---|---|
| 선택 수/시즌/단계 | 최대80시즌 접수,6시즌·4/1/4·128MiB | 기존 접수80/실험 유지 후보·사용자 설계 확정.80부하 성능 검증 완료라는 뜻 아님 |
| HTTP 시간 분할 |720초 신규 시작 중단,840초 정리/응답 목표,900초 외부 제한 | 확정. 진행 중 작업 종료 미확인은 차단 |
| 메모리 |85% 이상 표본상1초,100ms 표본,500ms 초과 공백 중단 | 확정. CPU 사용률만으로 중단하지 않음 |
| 조회/정리 | 앱3/10초, 점검5분, 파일 매시간, 기록 매일 | 확정. 이벤트 전달이 정상 시작 경로 |
| 기록 | 성공상세24시간, 최소완료30일, 해결된 장애30일, 복구감사90일 | 확정. 보호 조건 우선 |
| 회당 정리 | page100·최대5page, 실제 객체/문서500건 또는120초에 새 처리 중단 | 사용자 확정. 진행 중 요청 정리까지120초 안에 보장한다는 뜻 아님 |
| 조회 오류 backoff |10→20→40→60초, 성공/명시 새로고침 시 정상 복귀 | 사용자 확정. 중복 조회/백그라운드 조회 없음 |
| 신규 접수 시간 창 | 영수증 없을 때만 requestCreatedAt 기준24시간·미래5분 허용 | 사용자 확정. ID/생성시각을 재전송 때 변경하지 않음 |
| 로컬 기록 | 확정 결과30일 후 활성 시 정리, 진행/검토/복구/미확정 보호 | 사용자 확정. 계정 삭제 scrubber 별도 |
| 접수 준비 복구 | 최초 포함 총5회, 시즌 실행 예산과 별도 | 사용자 확정. 전달/claim 거절은 횟수 제외 |
| 무진행 감지 | 정상 재개2구간 연속으로 영속 진행이 전혀 없으면 복구 확인 | 사용자 확정. 의도적 retryWaiting/미시작 전달은 구간 아님 |
| 브라우저 전환 | 이미지 정리 확인 후 재사용 캐시 비우고 Chromium 실행 | 사용자 확정. 재다운로드 증가를 제품 검증에 기록 |

### 경계 해석

- 정리120초는 신규 I/O 투입 기한이다. 시작한 삭제/DB 작업을 취소했다고 완료 처리하지 않는다. 결과가 불명확하면 해당 정리 시도/객체를 재조정 대상으로 남기고 lease만 만료됐다고 성공으로 처리하지 않는다. 실행 전체 외부 timeout은 배포 시 SDK 정리 시간을 포함해 검증한다.
- 신규 접수 나이가 정확히24시간이면 허용, 초과하면 REQUEST_EXPIRED. 미래 정확히5분이면 허용, 초과하면 CLOCK_INVALID로 제안한다. 기존 영수증은 나이가 오래돼도 현재 권한·동일 digest로 먼저 조회한다. 삭제된 영수증의 옛 ID를 새 요청으로 자동 재사용하지 않는다.
- requestCreatedAt은 UTC epoch milliseconds 정수, GRDB와 payload digest에 고정한다. 시각 검사는 멱등성 시간 창이며 인증 수단이 아니다. 이미 접수된 요청의 서버 sequence는 서버 transaction으로만 정한다.
- preparation attempt는 준비 실행권을 얻고 미확정 항목을 실제 처리하기 시작할 때 증가한다. 성공한 item은 재생성하지 않는다.5회에도 준비가 미완료면 종료가 확인된 미확정 item을 접수 실패로 확정하고 성공한 item만 실행한다. 준비 중 쓰기 결과가 불명확하면 먼저 재조회하고 확정할 수 없으면 recoveryRequired로 둔다. 준비가 안 된 item을 성공으로 세지 않는다.
- 무진행 fingerprint는 phase/snapshot 고정·대상 매핑·공개 asset 집합·시즌 종료 전이처럼 **영속화된 실제 진행**으로 만든다. heartbeat/updatedAt/log 수 증가는 진행으로 세지 않는다. 진행이 있으면 연속 카운터를 초기화하고, 취소/실패한 요청을 정상 분할로 바꾸지 않는다.
- 메모리 시작 표본이 이미85% 이상이거나 무효이면 새 이미지 작업을 시작하지 않는 방어 조건을 검토본에 명시한다. 진행 중 guard와 별도이며 시작하지 않은 시즌의 실패 횟수를 증가시키지 않는다.

## 3. 단계와 의존성

`Q0 계약·검증 연결 → Q1 접수·순번 → Q2 실행권·재개 → Q3 저장·브라우저 → Q4 복구·정리 → Q5 앱 → Q6 통합·Development 준비 → Q7 승인된 Development·수동 QA`

서버와 Worker는 중간 상태에서 새 계약을 운영 활성화하지 않는다. Q1의 신규 접수 코드가 있다고 기존 per-job Worker로 요청을 흘리지 않는다. Q6까지 로컬/에뮬레이터로 통합하고 Q7 실행안 승인 후 배포한다. 단계 완료는 해당 범위의 검사 통과이며 전체 제품 검증 완료와 다르다.

### Q0 — 계약과 단계별 검증 연결

- **목표:** 앱/Functions/Worker가 같은 정책·DTO·상태 전이·실패 분류를 사용하도록 검토 가능한 기준을 고정한다.
- **변경 후보:** 신규 `contracts/lookbook-import-queue-v1.json`; 각 런타임의 계약 fixture test; 기존 `verification/{lookbook-import,functions,firestore}.json`; 신규 `verification/{lookbook-product-queue,lookbook-queue-linux,lookbook-queue-ios}.json`; `verification/README.md`.
- **구현:** 공용 JSON은 필드/정책/입출력 예제 fixture다. 별도 공용 TypeScript package·코드 생성기를 추가하지 않는다. Worker rootDir 밖의 Functions 코드를 직접 import하지 않는다. 단계별 필수 ID와 미구현 범위를 나누고 gate가0개/skip/미준비를 실패로 기록하는지 확인한다. 게이트 실행용 코드는 기존 runner/reporters를 재사용한다.
- **완료 기준:** 필드·기준값·계약 버전 불일치를 검출하는 각 런타임 검사가 연결된다. 아직 구현하지 않은 Q1~Q7을 통과로 선언하지 않는다.
- **검증:** 계약 정상/오류 fixture, 필수 검사 누락/0개/skip/실패 로그의 게이트 판정. 기존 테스트 ID를 제거해 통과시키지 않는다.
- **논의/의존:** §2 확정 정책을 계약 fixture와 대조. 현재 기본 iOS 게이트는 룩북 검사가 아니므로 전용 suite 선택 필수. 실제 코드 승인 전에는 설정 파일도 만들지 않는다.

Q0 실제 연결: 공용 요청 envelope·시간 경계·정책/상태/오류 fixture와 세 런타임 검사부터 연결한다. 실제 작업별 접수/응답 DTO와 상태 전이 부수효과는 Q1~Q5 구현에서 확장한다. 기존 G-F/G-W 필수 ID를 유지하고 G-I에는 Q0 suite5개를 선택한다. 게이트 자체 검증은 `verification/lookbook-queue-contract.json`으로 실행한다. G-E/G-L은 Q1/Q2~3의 실제 emulator/Linux 검사와 함께 생성하며 아직 미구현인 동작을 검사하는 것처럼 빈 게이트를 만들지 않는다.

### Q1 — 접수·중복 방지·순번·전달 의도

진행: [공통 접수 계층 구현·검증](product-queue-q1-results.md). 공통 서비스/조회 callable/기존 trigger 보호를 먼저 구현했다. 아래 전체 완료 기준은 유지하며 기존 접수별 adapter·실제 snapshot/이력 승계 연결이 남아 있어 Q1은 아직 완료가 아니다.

- **목표:** requestID 단위의 닫힌 요청과 이미지/목록 탐색 공통 FIFO를 영속화한다.
- **기존 변경:** `functions/src/lookbook/import/{functions,seasonDiscoveryJobs,taskService}.ts`, `functions/src/index.ts`, `functions/src/index.contract.test.ts`, 관련 import/review/repair contract tests.
- **신규 후보:** `functions/src/lookbook/import/queue/{contracts,admission,dispatch,projection}.ts`와 각 test. `firestore-tests/lookbook-import-queue.emulator.test.mjs`.
- **구현:** 인증·기존 영수증·신규 입력 검증 순서, 결정적 batch/item/job identity, 부분 preparation 복구, 서버 sequence, durable dispatch intent, 새 상태 조회 callable. 목록 탐색은 기존 discovery job 참조를 같은 순번에 넣는다. 기존 모든 실행 접수 경로에 동일 admission을 연결한다. requestCreatedAt을 모든 새 실행 접수에 전달한다.
- **완료 기준:** 동시 동일ID 한 번 접수, 같은ID 다른payload 거절, 서로 겹치는 시즌의 활성 실행 중복0,80항목 부분 실패 집계 일치, 준비 중 뒤 요청 추월0, task 전달 유실 시 복구 가능. discovery 기다림이 기존 watchdog 시도 예산을 소모하지 않는다.
- **검증:** G-F/G-E의 PQ01~05/PQ12. 원본 입력 변조·snapshot 만료 후 기존 영수증 조회·전부 중복·DB성공/task실패 포함.
- **논의/의존:** Q0. Firestore query 경쟁 안전성을 입증하지 못하면 브랜드 하위 source/season claim 문서를 같은 transaction에 넣는다. 기존 brand 권한과 삭제 조건을 유지한다. iOS는 아직 연결하지 않는다.

### Q2 — 묶음 실행권·시도·시간 분할·중단

완료: [Q2 초기 기록](product-queue-q2-results.md)과 [Q6 통합 결과](product-queue-q6-results.md). Q2 시점에는 `importSeasons`만 연결됐지만 Q6에서 지원 batch kind 전부의 activation과 continuation, Functions delivery 경로, 실행권 경계를 연결했다. retryable 시즌 오류는 지연 없이 최초 포함 총5회 시도한다. 14분에는 retryable 503을 응답하며 기존 처리 promise의 drain을 기다린다. 실제 Cloud Run 15분 내 drain과 원격 전달은 Q7에서 검증한다.

- **목표:** 현재 차례 하나만 Worker에서 실행하고 정상 재개와 장애 복구를 구분한다.
- **기존 변경:** `tools/lookbook-import-worker/src/{index,server,processor,config,oidc-auth}.ts`, `season-discovery-processor.ts`, `pipeline/{resources,scheduling}.ts`, 해당 tests.
- **신규 후보:** Worker `src/queue/{contracts,coordinator,batch-runner,checkpoint}.ts`와 tests. 제품 메모리 supervisor는 검증된 실험 guard의 순수 로직을 좁게 분리/재사용하되 실험 campaign 관리에 의존하지 않는다.
- **구현:** owner/epoch transaction, 중복 전달 무거운 작업0, heartbeat와 차단, import5/discovery3 시도,12/14/15분 분할, noProgress fingerprint, 종료 영수증, 전체 공유 runtime 생성/주입. 기존 `/wake`와 task route 우회 제거. SIGTERM/연결 종료 시 취소 신호와 실제 drain을 분리한다.
- **완료 기준:** 두 Worker의 활성 차례 최대1, 이전 epoch의 상태 쓰기0, 정상 분할은 같은 차례/시도, 종료 증거 없는 다음 실행0. 메모리 표본/높은 사용량 조건에서 신규 투입0, 잔여 작업은 완료 확인 전0으로 세지 않는다.
- **검증:** G-W/G-E/G-L의 PQ03~07/PQ09. 단위 fake clock과 독립 프로세스 검증을 함께 사용한다.
- **논의/의존:** Q1. 이미지 저장 공개는 Q3 완료 전 실제 제품에 활성화하지 않는다. worker/functions가 함께 coordinator 계약을 쓰므로 병렬 구현하지 않는다.

### Q3 — 이미지별 저장·조건부 공개·브라우저 분리

- **목표:** 늦은 실행이 현재 이미지를 덮어쓰지 못하고, 브라우저와 이미지 처리 자원이 겹치지 않게 한다.
- **기존 변경:** Worker `processor.ts`, `season-discovery.ts`, `season-discovery-processor.ts`, `pipeline/{asset-pipeline,source-buffer-store,resources}.ts`, `extraction/dedupe.ts`; `functions/src/lookbook/deletion/functions.ts`; `storage.rules`, 필요한 `firestore.rules`/indexes.
- **신규 후보:** Worker `src/queue/{asset-checkpoint,asset-publication,browser-gate}.ts`와 tests; `firestore-tests/lookbook-import-storage.rules.test.mjs`.
- **구현:** write 의도/고유 경로/두 JPEG generation, 앱 참조와 완료 기록의 조건부 transaction, 비연속 완료 이미지 skip, cover 이름 관계 유지, 삭제 중 늦은 쓰기 방지. browser 대기 시 신규 image/hash 투입 닫기→진행 이미지 정리→캐시 반환→browser 실행/close 확인→이미지 재개. 진단/repair preview도 자원 통제를 우회하지 않는다.
- **완료 기준:** 오래된 epoch 공개0, 부분 JPEG를 ready로 표시0, 현재 참조 삭제0, browser 활성 최대1·browser/image 중첩0, 미종료 browser permit 반환0. 이미지 입력/출력 Buffer 누수와 미공개 산출물 추적 누락0.
- **검증:** G-W/G-E/G-R/G-L의 PQ06/PQ08~10. emulator transaction/Storage와 실제 Linux Chromium 종료를 함께 확인한다. 로컬 fixture는 테스트 경계에서 주입하며 제품 SSRF 정책을 완화하지 않는다.
- **논의/의존:** Q2. 현재 `brands/{brandID}/{assetPath=**}`의 넓은 쓰기 허용과 새 서버 전용 경로를 함께 검토한다. 좁은 하위 match 추가만으로 기존 allow를 무효화했다고 하지 않는다. 공개 읽기 정책은 새 비공개 미디어 기능으로 확대하지 않는다.

**2026-10-05 구현 기록:** `asset-paths.ts`·`asset-publication.ts`는 queue-owned write를 실행별 path/ledger로 만들고 generation 검증 뒤 현재 owner/epoch에서 공개한다. `browser-gate.ts`는 import/discovery Chromium과 hashing/image 저장을 인스턴스 단위로 배타 처리하며 browser 진입 직전 등록된 `SourceBufferStore` cache를 비운다. Functions purge는 uploading ledger가 남은 대상의 post/season/brand 삭제를 차단한다. 해당 날짜 검사와 현재 구현의 최종 gate digest는 구분하며 최신 수치는 [Q6 결과](product-queue-q6-results.md)를 따른다.

### Q4 — 복구 도구·정기 점검·기록/파일 정리

**상태(2026-10-05): 로컬 구현 및 G-F/G-E/G-W/G-R/G-L 통과.** 상세 코드 경계와 source digest는 [Q4 결과](product-queue-q4-results.md)에 기록했다. 기본 off 복구 route의 실제 IAM·Cloud Logging 형식은 Q7 Development 검증 대상이다.

- **목표:** 누락 전달을 회수하고, 안전하게 복구하며, 필요 없는 파일/기록만 정리한다.
- **변경:** Functions `lookbook/import/queue/{maintenance-functions,dispatch,asset-retention,record-retention}.ts`, brand creation receipt, `functions/src/index.ts`; Worker `src/queue/{recovery,cloud-logging-evidence,recovery-cli}.ts`, `server.ts`, `oidc-auth.ts`, `config.ts`; Firestore indexes와 emulator/Worker tests.
- **CLI:** `tools/lookbook-import-worker/scripts/lookbook-import-recovery.mjs`. 별도 `recovery` OIDC identity만 받고 전용 환경 설정이 없으면 route는 비활성이다. 범용 운영 자동화는 만들지 않는다.
- **구현:**5분 누락 점검·시간 파일 정리·일일 기록 정리, page/cursor/상한,24h/30d/90d/보호 조건, requestCreatedAt 만료 검사, 최소 영수증 압축, 삭제 중 공개 fencing. inspect/resume 전용 인증·동일 결정 멱등성·보고서 위조 거절. 앱 브랜드 관리자와 복구 호출 주체 분리.
- **완료 기준:** 보호 기록/현재 이미지 오삭제0, 회당 최대500 기록 변경·120초 이후 신규 처리0, 만료ID 자동 신규 실행0, inspect DB mutation0, 증거 없는 resume0, 같은결정 중복효과0. 복구 차단을 시간 경과로 해제하지 않는다.
- **검증 결과:** G-F/G-W/G-E/G-R/G-L의 PQ09/PQ12~15는 [Q4 기록](product-queue-q4-results.md)에 원본·digest와 함께 기록했다. 실제 IAM·Cloud Logging/Run 로그 경계는 Q7에서만 확인한다.
- **논의/의존:** Q3. 도구 구현 승인은 클라우드 IAM 부여·실제 복구·데이터 삭제 승인이 아니다. 기존 추출 증거7일/Cloud Logging/백업 정책은 유지한다.

### Q5 — 앱 GRDB·요청/진행 API·화면 연결 — 구현 및 G-I 통과

- **목표:** 응답 유실/재시작에도 같은 요청을 확인하고 대기·검토·복구를 정확히 표시한다.
- **구현:** `OutPick/DB/GRDB/Core/AppDatabase.swift`, `Migrations/GRDBMigrationRegistry.swift`, `Records/LookbookImportRequestRecord.swift`, `Stores/GRDBLookbookImportRequestStore.swift`; `App/AppCompositionRoot.swift`, `Features/Lookbook/LookbookContainer.swift`, `Repositories/LookbookRepositoryProvider.swift`; 큐 요청/영수증 Entity·coordinator·Repository·UseCase·ViewModel·화면을 연결했다.
- **화면/흐름 변경:** StartSeasonImportExtractionUseCase/ManageSeasonImportJobsUseCase, CreateBrandDiscoveryViewModel/SeasonImportManagementViewModel, CreateBrandFlowView/CreateBrandCandidateSelectionView/SeasonImportManagementView, 승인/재시도/보수 Repository. UI fixture provider와 두 곳의 UseCase 조립을 같이 갱신한다.
- **요청 경로:** 브랜드 생성과 최초 탐색은 기존 원자적 `createBrand` callable 한 요청으로 묶어 같은 ID를 유지한다. 시즌 묶음·URL 접수, 수동 목록 탐색/재시도, asset 재시도, 검토 승인, 수동 재시도, 보수 요청은 전송 전 GRDB 기록 후 동일 envelope를 보낸다. 응답은 requestID/brandID/kind/contractVersion이 요청과 일치해야 수락한다. insufficientImages는 새 실행이 아닌 검토 결과 갱신이므로 큐에서 제외한다.
- **저장/화면:** 전송 전 DB 저장, ID/시각 고정, 응답 유실 시 같은 ID 조회/재전송, 계정 격리/계정 삭제, 확정 결과30일 정리, 3/10초 조회·오류 backoff·foreground 재개, batch item 상태 표시를 연결했다. View가 DB/Functions를 직접 접근하지 않는다.
- **완료 기준:** DB 실패 시 HTTP0, 재시작 중복접수0, 타계정 응답 혼입0,6시즌3성공/2검토/1실패 표시 일치, 조회 겹침/백그라운드 조회0, 닫기로 서버 취소0. 검토/복구를 성공으로 표시하지 않는다.
- **검증:** `verification/lookbook-queue-ios.json`의 G-I는 iPhone 17 Pro / iOS 26.2 Simulator에서 28개 테스트·8개 suite가 통과했다. 임시 GRDB·migration27·계정 삭제·같은 ID 복원·계약 응답 검증·create/discovery/review/retry/repair adapter·자산 재시도 polling 회귀를 검사한다. 실제 화면 QA는 Q7에 남긴다.
- **결과:** 전체 원본·소스 digest·실패/복구 실행 내역은 [Q5 기록](product-queue-q5-results.md).
- **논의/의존:** Q5에는 추가 설계 결정을 남기지 않았다. Q6은 앱/Functions/Worker/Emulator/Linux gate와 legacy 경로를 한 revision 상태로 통합한다. Q7은 별도 승인된 Development 입력·요청량·비용 조건에서 실행한다.

### Q6 — 로컬 최종 통합과 Development 실행안 — 완료

**완료(2026-10-06):** 모든 batch kind의 실행 activation, retry child job/source claim, 14분 HTTP 응답 경계와 drain 대기, 앱·Functions·Worker 계약을 연결하고 로컬 필수 게이트를 현행 입력에서 통과했다. 코드 변경·source digest·실행 ID·원본은 [Q6 결과](product-queue-q6-results.md)에 기록했다. Development의 현재 revision/resource/IAM 읽기 전용 대조와 3시즌 FIFO smoke 설계는 [Q7 readiness](product-queue-q7-readiness.md)에 기록했다. Q6 source가 remote에 배포되지 않았고, 실행은 별도 승인 전까지 시작하지 않는다.

- **목표:** 최신 앱/서버/Worker 계약과 필수 게이트를 같은 코드 상태에서 묶어 검증하고 실제 실행 범위를 제시한다.
- **변경 후보:** 각 신규 게이트 설정/필수ID, emulator·Linux·iOS fixtures, runbook, ENTRYPOINTS/LOOKBOOK/TESTS/DATA 또는 FIREBASE 하네스, ADR 후보, 제품 큐 검증 결과 문서.
- **완료 기준:** G-F/G-W/G-E/G-R/G-L/G-I가 필요한 현 코드 입력에 대해 모두 통과한다. contract fixture/설정 digest 일치, 필수 항목 누락·skip·0개·미준비가 없어야 한다. 이 기준을 충족했고 실제 플랫폼 증거/IAM/화면 QA는 Q7 잔여 항목으로 기록했다.
- **검증:** A8/B2/C~J와 목록 탐색 혼합100ms 접수,80선택 최악 입력, 재개/중복/종료 불명확/정리 경합/계정 전환 등. 현재 코드가 달라졌으면 과거 코드의 통과를 재사용하지 않는다. 이미 통과한 변경 없는 부분을 이유 없이 반복 실행하지 않는다.
- **실행안 산출:** project/service/revision/image digest, 현재 CPU·memory·instance·timeout·Cloud Tasks retry, task/recovery identity와 IAM을 read-only로 확인한다. 그 뒤 실험 전용 brand/Storage 경로·요청 수·산출량·최대 비용·복구 identity·원상복구/정리 범위를 구체화한다. 성능 campaign의 중단 상태를 임의 해제하지 않는다.
- **논의/의존:** Q5. 실제 배포·유료 네트워크·IAM 변경·삭제는 구체 Q7 실행안을 확인한 뒤 별도 범위로 승인받는다. 문서와 로컬 검증은 실제 실행 승인을 포함하지 않는다.

### Q7 — 승인된 Development 검증과 수동 QA

- **2026-10-06 입력 확정:** 제품 sourceURL 중복 규칙을 지켜 A6/B2/C~J각1 총16시즌. 후보 URL/순서/개수/커버/hash가 fixture와 일치하는 검토 필요 QA 시즌은 서버의 generation/snapshot으로 정상 관리자 승인 API를 호출한 뒤 FIFO 저장을 확인한다.
- **목표:** 제품의 실제 URL/Storage/Firestore·Chromium·플랫폼 종료 증거·복구 권한을 확인한다.
- **변경/실행 범위:** [Q7 readiness의 원격 증거·입력량·단계](product-queue-q7-readiness.md)를 따른다. Worker traffic 0% candidate, 필요한 Functions와 indexes를 Development에 적용한다. 최초 smoke는 A 2시즌→정상 review 저장, 처리 중 B 최초 탐색, B 1시즌 review 저장까지 7 mutation calls/7 queue batches다. 제품 QA 원본과 로컬 준비 gate를 연결한다.
- **서버 검증 진입점(2026-10-06 사용자 승인):** iPhone 관리자 UI는 Q7 선행 gate에서 제외한다. Development 전용 검증 도구에서 Firebase 사용자 인증과 실제 callable 인가를 거쳐 createBrand/최초 discovery → 후보 대조 → import → 정상 review → FIFO 저장을 검증한다. DB 직접 접수·Worker 직접 호출로 제품 API를 우회하지 않는다. 관리자 웹 화면 검증은 웹 구현 task로 이관한다. 상세 준비와 권한 결정은 `product-queue-q7-server-validation-plan.md`를 따른다.
- **필수:** 정상 FIFO(탐색 포함), 정상 checkpoint 재개, 검토 승인/수동재시도 차례, 실제 다운로드·JPEG·공개 경로, browser/image 비중첩, exact instance 종료 증거, 권한 거절·inspect/resume, 승인된 테스트 산출물만 정리. 데이터 보관기간 검증을 위해 운영 시계를 조작하거나 무관한 실제 데이터를 삭제하지 않는다.
- **완료 기준:** 승인된 모든 필수 시나리오가 증거와 함께 통과하고 사람 확인 항목도 확인된다. 종료 증거를 확보하지 못하면 해당 복구는 미검증/차단이며 전체 완료로 처리하지 않는다. 메모리/동시성 값을 테스트 통과 목적으로 임의 완화하지 않는다.
- **논의/의존:** Q7의 Development 배포·실제 URL/Firestore/Storage 쓰기 전 범위를 사용자 검토 후 시작한다. QA 산출물 삭제는 별도 승인이다. 운영 배포는 자동 수행하지 않는다.

## 4. 필수 게이트와 책임

모든 명령은 프로젝트 루트에서 `node tools/verification-gate/gate.mjs --project . --config <설정>` 형태다. Node24·Java·Docker·Xcode 등 실제 준비 조건을 검사한다. 최종 필수 게이트와 실행 원본은 [Q6 결과](product-queue-q6-results.md)에 기록했다.

| 이름 | 설정 | 필수 범위 |
|---|---|---|
| G-F | 기존 `verification/functions.json` 보강 | lint·build·Node tests·최신 export/API/접수/retention |
| G-W | 기존 `verification/lookbook-import.json` 보강 | Worker lint·build·tests·추출 fixture, 제품 queue/pipeline/브라우저/복구 |
| G-E | 신규 `verification/lookbook-product-queue.json` | 로컬 Firestore/Storage emulator, 독립 claim·transaction·입력/산출물/정리 경합 |
| G-R | 기존 `verification/firestore.json` 보강 | 서버 원본·새 경로 접근 거절/기존 권한 회귀·indexes 검사 |
| G-L | 신규 `verification/lookbook-queue-linux.json` | Linux1CPU/2GiB Chromium·cgroup guard·실제 프로세스 취소/OOM·drain |
| G-I | 신규 `verification/lookbook-queue-ios.json` | Development build/룩북·GRDB·조회/계정 경계 xcresult 필수 ID |
| G-D | Q7 실행안에서 구체화 | 실제 Development revision·IAM·플랫폼 증거·요청/산출물/정리 대조 |
| QA | 실기기·운영자 확인표 | 화면 문구/닫기/재시작/백그라운드·복구 보고서 이해 가능성 |

PQ01~15의 필수 시나리오는 [설계 §19](product-queue-design.md)를 그대로 추적한다. gate config의 requiredTests에는 실제 reporter가 내보내는 `파일::테스트명`/xcresult ID를 등록한다. Q0는 테스트 식별/runner 연결을 구축하고, 기능 단계는 해당 구현과 필수 tests를 같이 추가한다. 미래 단계 ID를 없는 테스트로 등록해 조용히 제외하거나 상위 전체 테스트 개수만 보고 통과시키지 않는다.

권장 test 파일 후보: Functions queue 아래 모듈별 `.test.ts`, Worker queue 아래 모듈별 `.test.ts`, `firestore-tests/lookbook-import-queue.emulator.test.mjs`/`lookbook-import-storage.rules.test.mjs`, `OutPickTests/GRDB/GRDBLookbookImportRequestStoreTests.swift`, `OutPickTests/StartSeasonImportExtractionUseCaseTests.swift`, `OutPickTests/LookbookImportProgressTests.swift`. 현재 존재하는 `AppDatabaseMigrationTests`, `AccountDeletionLocalDataCleanupTests`, `CloudFunctionsSeasonImportRepositoryTests`, `SeasonDiscoveryManagementViewModelTests`, `LookbookSeasonRepairViewModelTests`도 변경 영향에 맞춰 포함한다.

Functions와 rules 게이트는 같은 빌드 산출물, iOS 게이트는 같은 derived data를 공유할 수 있으므로 순차 실행한다. 독립 경계 검사만 필요시 병렬 명령으로 묶고 제품 구현 파일은 순차 편집한다. 새 `scripts/ai` 자동 실행 체계나 하위 에이전트를 추가하지 않는다.

## 5. 결과 기록·완료 기준

단계마다 변경 파일/계약 버전/소스 digest/필수 검사 목록/실제 결과/원본 경로/미검증 범위를 기록한다. `output/verification/<runID>/summary.json`과 원본 로그를 근거로 판정하고 누락·skip·0개·환경 미준비·timeout은 통과가 아니다. Q7 외부 증거는 별도 원본 manifest로 연결한다. 단위테스트가 실기기 화면을 검증했다고 기록하지 않는다.

각 코드 단계 완료 때 `docs/ai/ENTRYPOINTS.md`, `docs/ai/entrypoints/LOOKBOOK.md` 및 관련 데이터/API/TESTS 하네스를 갱신한다. 단계별 긴 경과를 공용 문서에 계속 복제하기보다 최종 진입점·계약·검증 위치를 남긴다. 기존 실험 이력/원본은 보존한다. HANDOFF·사용자 변경·기존 dirty 코드·실험 제어 상태를 임의 초기화하지 않는다.

전체 완료는 Q0~Q7 필수 검증과 수동 QA가 모두 충족된 상태다. 일부 단계 통과·문서 완성·플랫폼 증거 미확보를 전체 완료로 보고하지 않는다. 구현 중 사용자가 범위를 바꾸면 남은 계획/필수 검사에 반영하며 실패를 감추려고 기준을 바꾸지 않는다. 커밋·PR·운영 배포는 별도 사용자 요청을 따른다.

## 6. 현재 상태

**완료된 로컬 단계:** Q0 공통 계약, Q1 접수/FIFO/준비 adapter, Q2 지원 batch kind activation·실행권·지연 없는 최초 포함 총5회 재시도, Q3 queue-owned 저장·조건부 공개·browser gate·삭제 fence, Q4 reconciliation·증거 기반 복구 route/CLI·asset/record retention, Q5 앱 GRDB/API/UI 복원, Q6 전체 로컬 통합이다. 최종 G-F/G-W/G-E/G-R/G-L/G-I 실행 IDs·digest·원본은 [Q6 결과](product-queue-q6-results.md)를 따른다.

**아직 미완료:** Q6 Worker candidate/Functions/index 배포, Cloud Tasks 재전달 및 Cloud Run 종료/15분 내 drain의 원격 증거, 실제 URL 다운로드/Storage 업로드, 원격 legacy 경로 차단 확인, 수동 화면 QA다. 읽기 전용 기준 대조에서 100% traffic은 구 Worker revision이고, 새 queue triggers/callable은 Development에 없으며 `requestSeasonImport`은 기본 Worker URI를 가리킨다. 현재 queue는 비어 있었고 local `writes` 복합 index 4개는 remote 목록에 없다. 14분 retryable HTTP 응답과 local handler drain은 구현했지만 플랫폼 동작은 확인하지 않았다.

**다음 단계는 Q7 live 연결**이다. 소규모 3시즌 smoke는 추출 검토·정상승인을 포함해 재시도 제외 image GET127/55.69MB, JPEG126 writes/15.61MB, verification GET 최대126이다. A~J 실제품력은 A6/B2/C~J각1이다. 생성+탐색 10건을100ms 간격으로 먼저 넣고, 후보 선택 후 import 10건을 별도100ms wave로 접수하며 review 최대16건이 FIFO 뒤에 이어진다. 요청량·원격 설정·잔여 위험·실험 제약은 [Q7 readiness](product-queue-q7-readiness.md) 참조.

Q6 로컬 통합 및 Q7 준비 문서는 완료했다. Q7 remote 실행에는 Worker tag 배포, queue Functions/index 적용, Development URL/Firestore/Storage 쓰기가 필요하다. 이번 로컬 구현 승인은 그 원격 변경을 포함하지 않는다. 별도 범위 승인 전에 deploy/write를 실행하지 않는다.
