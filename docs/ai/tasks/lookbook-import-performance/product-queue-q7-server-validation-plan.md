# Q7 전체 검증 세부 구현 계획

## 2026-10-07 최종 — 합의한 서버 검증 완료

[최종 결과/커밋/원본](product-queue-q7-final-results.md)이 이전 진행중 절보다 우선한다. R0계약/R1종료정산/R2실패목록/R3서버필수6게이트/R4실제K/L검증을 완료했다. 같은K의attempt2/5·L원래5회소진/수동새5/성공제거·원장124JPEG·현재참조·대기열종료를 확인했다. R5의 앱28개 검사와 하네스 정리도 완료했고 서버/Worker/앱/검증커밋4개를 생성했다. 설계·결과67개문서를 포함하는 최종문서커밋은 사용자 승인 범위다. 추가유료검증/고의종료는 수행하지 않는다. 장시간경계/24h삭제·관리자웹·실제청구미확정은 분리보존한다.

## 2026-10-07 최신 개정 — 중간 복원 제외·처음부터 재시도·실패 목록

[Q7-R0 세부 계약/API·검증안](q7-retry-contract-plan.md)의 D1 부분 산출물 정리·D2 같은5회 예산/새 검토 추천을 사용자 확정·구현 승인했다. R1/R2 서버 구현 및 KR01~14 검사 연결을 진행했고 현재 소스의 전체 필수 gate를 실행 중이다. 새 원격 배포·삭제·접수·종료·커밋은 아직0이다.

[확정 결정](season-failure-retry-decision.md)이 아래 과거 복구 재개 설계보다 우선한다. 종료 확인 뒤 해당 시즌을 처음부터 자동 재시도하며 최초 포함 총5회 소진 시 최종 실패다. 완료 시즌은 유지하고, 수동 재시도는 맨뒤 새 요청/새 실행/새5회다. 시즌별 실패 목록 문서는 하나 유지·재실패 최신화·성공 또는 명시적 재시도 안 함에 제거·무선택 유지다. 원본 실행 기록은 기존 정책대로 보관한다. 관리자 웹 UI·목록10개/최근 운영 지침은 별도 작업이며 Q7에 새 iOS 관리자 UI를 추가하지 않는다.

### 개정 단계·변경 후보·완료 기준

| 단계 | 목표·변경 후보 | 완료 기준·필수 검사 | 의존/미결정 |
|---|---|---|---|
| Q7-R0 |종료 정산·처음부터 재시도의 데이터/API 상세 계약, 현재 문서·design·DATA_SCHEMA/ENTRYPOINTS |부분 저장 정리/보호, 승인 뒤 재시도의 시도 계산/재검토, 실패 목록 식별키/인가/멱등·최신 실행 조건을 문서로 고정 |진행 중. 확정 방향과 상세 계약 완료를 구분 |
| Q7-R1 |Worker `src/queue/{recovery,checkpoint,activation,batch-runner}.ts` 및 관련 processor/HTTP 연결, Functions `src/lookbook/import/queue/followup-admission.ts`와 준비/조회 경로, shared queue 계약 |종료 미확인 시 새 작업0, 확인 후 옛 쓰기 차단·새 시도,5회 소진·다른 완료/미시작 시즌 보호. 일반 실패 시즌의 맨뒤 새 수동 접수 |R0 계약 확정 전 코드 변경 금지. 중간 복원 API 확대 제외 |
| Q7-R2 |실패 목록 저장/갱신/제거의 서버 경로와 상태 projection, 관련 unit/Emulator tests, verification 설정·필수ID |같은 시즌 문서1개, 최신 실패 갱신, 성공/명시적 안 함 제거, 무선택 유지, 원본 실행 보존. 다른 사용자·중복 요청·이전 실행 늦은 응답 거절 |R0의 실제 API/데이터 키 확정 뒤 R1과 순차 구현. 웹 UI 구현 아님 |
| Q7-R3 |현행 소스의 필수 로컬 gate·원본 로그/source digest |G-F Functions, G-W Worker, G-E 제품큐 Emulator, Q7 verifier. Linux 실제 종료/자원 경계 영향이 있으면 G-L. Rules/indexes 변경 시 G-R. 누락/skip/0개/timeout/미준비는 실패 |새 필수ID를 실제 테스트에 연결. Swift/UI를 변경하지 않으면 기존 G-I 결과를 새 기능 검증으로 사용하지 않음 |
| Q7-R4 |새 짧은 Development 실행안·실행기·필수 판정, 후보 배포/readback |정확한 기존 자원/traffic/IAM, 실제 종료/새 시도/산출물·5회 소진/실패 상태·수동새접수·FIFO 증거. 원격과 로컬 검사 범위를 분리 |대상·종료 방법·최소 회차/요청량/전송량/비용 새 산정 및 확인 전 원격 실행0. 기존4접수/62JPEG 산술 사용 금지 |
| Q7-R5 |결과·원본·행렬·하네스·최종 커밋 범위 |합의한 현행 필수 gate/실제 증거 충족, 과거 실패·후속 장시간 미검증 보존, 실제 diff 확인 후 작업별 커밋 |ignore 문서 포함 범위·무관 변경 제외 확인. 전체 완료 전에 커밋하지 않음 |

필수 로컬 회귀는 실제 종료 증거 누락/오조회/이전 epoch, 동시 종료 판정, 재전달과 실제 시도 횟수 구분, 총5회 소진, 승인 저장 실패·재시도, 부분 산출물 정리 경합/완료 시즌 보호, 새 수동 요청 멱등/원래 이력 보존, 실패 문서 갱신·제거 인가/늦은 이전 응답을 포함한다. 테스트명·필수ID·새 API의 정확한 파일명은 R0 세부 계약과 함께 확정한다. 고의 프로세스 종료·플랫폼 증거·실제 전송은 fake 테스트로 통과 처리하지 않는다.

현재 R0 계약은 확정됐고 R1/R2 코드·API를 구현했다. R3 현재 코드 필수 검사는 진행 중이며 R4 새 고의 종료·유료 실행안의 실제 방법/규모 확정과 원격 검증은 아직 전이다. 아래 정상 A/B·A~J 증거는 재사용할 수 있는 기존 결과이며 새 재시도 계약 구현의 통과로 표시하지 않는다.

2026-10-07 최신: [A~J 실제 제품 검증 결과](product-queue-q7-ten-brands-results.md) — 36접수·16시즌 저장·710JPEG와 현재 공개 원장 대조가 완료됐다. 두 100ms 예약 wave에서 실제 서버 순번과 브랜드 대기·실행 비중첩을 확인했다. 앞 run 시작 후 신규 접수는 없었으므로 A/B의 active 중 도착과 동일한 조건으로 표시하지 않는다. 메모리 최고 84.05%, 최대 표본 공백 380.7ms, 이미지 실패·시즌 재시도·중단 0회. 실행기 job 기록 누락은 원본 보존·별도 job index 대조로 정산했으며 이후 도구 기록 연결을 수정했다. 최종 client31/Worker359/Linux2 필수 검사 통과. 실제 장시간·플랫폼 종료 및 청구 전체는 별도 미검증이다. 전체 Q7 완료·커밋은 아직 아니다. 아래 실행 전/진행 중 문구는 과거 기록이다.

Q7 A~J 실행기 준비 완료(2026-10-07): `scripts/q7-wave.mjs::runQ7Wave`는 응답 대기 없이 절대 100ms 간격으로 최대10건을 시작한다. `q7-journal.mjs`/runner는 동시 기록을 직렬·원자 저장하고, 실패하면 새 투입을 멈춘 뒤 시작한 요청을 모두 정리한다. `assertQ7WaveEvidence`는 두 wave 각10건의 예정/시작/HTTP 직전 기록·실제 서버 순번과 서로 다른 브랜드 대기를 검증한다. 실제 서버 도착 간격을100ms로 단정하지 않고 편차와 순서 변경을 기록한다. 승인된 A6/B2/C~J각1·16시즌·36접수·기존 비용/2시간 상한은 유지한다. 필수 verifier gate `1791303321801-54c50236-ead4-40c3-ad2d-f126a1131cbc` passed31; digest `e3da40995238821d1f710fe61930efb6057e14c69792897cc00aa61f155c9c66`. 원격 A~J는 아직 실행 전이다.

## 현재 접수 유지·이어 실행 확정 (2026-10-07 KST)

추출 뒤 기능 저장 전환 사용자 확정: candidate024에서 discovery epoch4를 재실행 없이released 처리했고 A2 import epoch5는3.240s/44다운로드/18,939,777B/awaitingReview로 종료했다. 최고memory11.07%/samplegap309.786ms/download4/job1, CPUprocess2.01s, 원본순서/해시/coverURL이QA일치. 조회가 짧은active구간을 놓쳐 B접수 전 중단했고, 사용자는 현재 결과를 유지해 총7접수 안의 저장기능 smoke를 완료하고 여러브랜드 대기를 A~J100ms에서 확인하는 안을 승인했다. 새CLI `--resume-after-extraction=true`는 idle·동일released·awaitingReview2만 허용한다. report functionalStorageSmoke/overlapObserved=false/이전실패보존, 원래 overlap중단 원본별도보존. Q7 gate24건 통과. 입력/비용/2시간 상한 유지.

복구 해제 준비 지연 보수: preparationSequence가 그대로인 recoveryRequired→idle 이벤트를 준비재개 조건에 추가했다. 같은 prepareNextQueueBatch/owner조건이라 중복이벤트는1회만 준비한다. Functions321/lint/build·Emulator75건 통과 후 Development handler하나만배포했다. 정상 admission/Worker 자원/API/IAM은 바꾸지 않는다.

추가 실제 실패/최소 수정: candidate023에서 같은UID observer ready→epoch2 fresh inspect/durableDrain/쓰기0→decision28ee88a4… resume accepted. epoch3은 memoryStop null/terminalConfirmed/inFlight0이지만 이미 succeeded인 항목을 다시 begin해 NOTQUEUED recoveryRequired다. runner는 terminal processingStatus를 재실행하지 않고 최종 release transaction에서 실제 execution/continuation 종료를 확인하도록 수정한다. 불일치는 recovery 유지. Emulator 필수2건/제품큐74건 통과. observer를 종료했고 원본 proof와 같은 accepted2 checkpoint로 재연결한다. 역사적 복구 run들은 각각 durable audit/종료/비중첩을 확인해 기능 완료와 분리하며 성능 실패를 숨기지 않는다. 시간창/접수 한도 연장 없음.

- run92ad4778의 확정 접수2건 유지, A 생성/A2 import 재전송 없이 남은5건을 이어 run최대7/이전A1 포함누적8. original startedAt1791296622679 기준2시간 창·비용 한도 연장 없음.
- 변경: q7-resume.mjs/.test.mjs, campaign/runner/Q7 verification config. stopped/import-incomplete·accepted2·원본 payload digest/plan/discovery 선택시즌을 고정하고 원본/digest를 evidence/resume-original에 보존한다. 앱/Functions/API 계약 변경 없음.
- 원격 precondition: 같은UID, A domain succeeded/published generation/snapshot 동일, exact discovery head SAMPLE-GAP recoveryRequired, import preparing·target2 동일/jobID null. client OBSERVER_READY 후 새 후보에서 이전run revision022/epoch2 fresh inspect→durableDrain/불확정쓰기0/canResume→고정decisionID conditional resume. A active를 관측한 뒤 B를 접수한다.
- QV07 포함 gate23건 통과(`1791299169976-9d8d1850-9f20-4d04-b52e-fc61bd2dde51`). Ready 전 Playwright JS 준비 후 실제 index+QueueSupervisor/resource sampling Linux1CPU/2GiB/network none: guard21/resource22표본,maxgap103.647ms,memoryStop null,브라우저0. 원본 linux-ready-supervisor.log. Cloud922ms 원인 확정/새 후보 성공 증거로 사용하지 않는다.
- collector는 이전 sample-gap run을 종료/audit로 확인해 raw evidence에 유지한다. 기능 복원 완료와 performanceStatus historicalFailurePreserved를 구분하며 기존 실패를 통과로 바꾸지 않는다. 새 revision은 기존 FIFO/자원 검사 유지. checked.bytes/telemetry reports 참조 오류도 수정했다.
- 다음: Worker/제품큐 gate→0%candidate/readback→client observer→conditional recovery→A2/B1 기능/저장/자원→A~J. 새 실패/범위 변경은 별도 분석한다.

2026-10-06 최신 통합안. 최소 Development recovery IAM과 candidate `00021-kup` 설정 확인, 기존 A 조건부 정산 및 원본 보존 read-back을 완료했다. 현재 페이지는29후보/활성 more0/1page이며 paginate 문자열 오탐을 확인해 최종 DOM 판정을 수정했다. 수정본 Worker gate359 tests/lint/fixtures/deploy contract 통과 후, 사용자가 확정한 기존 이력 보존·새 A/B 실행을 위해 QV02 증거 종결 연결도 추가했다. Verifier18 tests와 product queue72 tests/build 통과; 이 연결을 포함한 최종 Worker gate 진행 중. 수정본 후보 배포 후 새 smoke 최대7회(기존1 포함 누적8)→통과 시 A~J→최종 커밋 순서다. 기본 traffic `00012-fih`100% 유지. 과거 IAM 대기·정산 미실행·inactive-admin/iPhone 문구는 최신 결과로 대체한다.

## 목표와 증거의 범위

### 2026-10-06 확정 — 1~6 실행과 복구 최소 권한

- 사용자 승인: 본인 Google 운영 계정 `gayunkim.1@gmail.com` 하나로 복구 도구를 사용한다. 두 Firebase 로그인 계정 연결·관리자 웹 복구 화면·광범위한 클라우드 관리자 권한은 이번 범위에 추가하지 않는다.
- Development recovery caller는 `lookbook-import-recovery@outpick-test.iam.gserviceaccount.com`이며 해당 Worker service의 `roles/run.invoker`만 가진다. 운영자는 이 service account 리소스의 `roles/iam.serviceAccountOpenIdTokenCreator`만 추가로 사용한다. key·서비스 계정 access token을 만들지 않는다.
- Worker runtime account에는 `logging.logEntries.list`만 포함한 프로젝트 custom role `lookbookRecoveryLogReader`를 부여한다. IAM 권한의 범위는 Development 프로젝트의 일반 로그 조회이고, 코드의 쿼리는 exact service/revision/trace에 한정된다. 로그 수정·삭제·private log 조회는 포함하지 않는다.
- 변경 파일: 배포 스크립트/계약 테스트, `src/queue/recovery-auth.ts`와 인증 테스트, 복구 CLI, Q7 preflight/테스트, Worker gate 필수 테스트 목록 및 하네스. 기존 CLI의 impersonation 방식은 더 넓은 access-token 권한이 필요하므로 사용자 access token으로 IAM Credentials `generateIdToken`을 직접 호출하도록 수정한다.
- 필수 검사: Worker 전체 gate(인증 성공·취소·실패/잘못된 응답·비밀정보 비노출, 배포 env 포함), Q7 verifier gate(복구 env 누락 거절), exact Development IAM/revision read-back, exact A inspect→조건부 settlement. 이 단계에서 Functions/Swift/Rules 변경은 없다.
- 실행 순서: 최소 IAM/로컬 검증/0% candidate 확인 → 기존 A 증거 검사·조건부 정산 → 탐색 신호 증거 확보·수정/검증 → A2/B1 smoke → A~J 16시즌 → 결과·필수 게이트·문서·최종 커밋 정리. 새 권한·비용·설계 선택이 필요한 경우에만 사용자와 논의한다.

### 3번 탐색 판정 수정 — 현재 페이지 증거와 필수 검사

- 현재 read-only probe `discovery-diagnosis-20261006/read-only-probe.json`: static/rendered 후보29, dynamic=false, 활성 more candidate0. 실제 paging은 현재1페이지와 `#none` 이전/다음 링크뿐이다. 두 HTML의 `paginate` 문자열 때문에 기존 finalLoadMoreDetected=true가 되어 unresolvedExpansion을 만든다. 이 probe는 현재 페이지 증거이며 과거 run의 HTML을 복원한 것은 아니다.
- 승인된 extractor 수정 범위: 정적 문자열을 rendered fallback 힌트로 보존한다. rendered 확장 이후에는 활성·가시 more controls와 앞으로 갈 수 있는 pagination을 DOM에서 확인해 final unresolved 판정에 사용한다. 숨은/disabled controls를 클릭하지 않는다. 실제 next page는 처리 완료로 바꾸지 않고 교정 필요를 유지한다. 기존 클릭/스크롤 상한과 분류 합격 기준을 완화하지 않는다.
- 변경: `src/season-discovery-controls.ts`, 해당 local Playwright DOM 회귀 테스트, `season-discovery.ts` 연결, Worker gate 필수 목록/하네스. 필수 검사: one-page paginate/script hint 오탐, 실제 more의 클릭 전/후, hidden/disabled 제외, 실제 next와 이전/현재 링크 구분 및 기존 분류 fail-closed. 본 테스트는 외부 URL 없이 DOM fixture를 사용하고 실제 source probe는 별도 기록한다.
- 소규모 검증 재개 전에 기존 A 영수증을 보존하는 방식과 중단 journal의 안전한 이어 실행을 확정해야 한다. 현재 runner는 중단 run을 자동 재실행하지 않으며 이 차단을 우회하지 않는다.

### 소규모 재개 확정 — 기존 이력 보존·새 A/B 실행

- 사용자 선택: 기존 A의 report/journal은 stopped/accepted 이력 그대로 보존하고 새 A/B smoke를 실행한다. 새 smoke 최대7 mutation, 기존1을 포함한 누적8. 비용/시간 상한은 기존 조건을 유지한다. 기존 A를 재사용하는 이어 실행 기능은 추가하지 않는다.
- 원래 파일을 수정하지 않고 `evidence/terminal-correction-reconciliation.json`과 실제 `settlement-readback.json`을 덧붙인다. `q7-journal.mjs`는 원래 report/journal/read-back digest, 단일 accepted createBrand 영수증, exact batch/brand/job/epoch/stateRevision, terminal/inFlight0, correctionRequired 보존, released 및 복구 audit 증거가 모두 맞을 때만 해당 중단 run을 정산된 이력으로 인정한다. 다른 중단·진행/이미지쓰기·훼손된 증거는 계속 새 실행을 막는다.
- 필수 QV02 회귀: valid proof가 원래 이력을 바꾸지 않고 새 campaign을 허용, digest/대상/run 종료/asset-write 상태 불일치 및 proof 누락 차단. 실제 원격 Q7 preflight는 별도로 current queue/revision을 다시 검사한다. 원본 변경 없이 증거를 붙이는 계약이지 이전 요청 재전송 계약이 아니다.

### 실제 smoke `92ad4778` 중단 — 필수 연결 수정과 자원 진단

- candidate `00022-zic`/digest `d109070f…0b7383` 실제 목록 탐색은 succeeded. createBrand와 import 접수2회만 실행됐고 원래 준비 중 receipt의 jobID=null을 실행기가 오류로 처리했다. 서버 read-back은 discovery batch recoveryRequired(`QUEUE_ENVIRONMENT_SAMPLE-GAP`), 원본 discovery succeeded, 뒤 import batch preparing/두job 미생성이다. B 생성·검토 승인·변환/Storage 쓰기 없음.
- Worker 종료 증거: terminalConfirmed=true/inFlight0, 불확정 asset-write0, inspect canResume=true. 그러나 자원 표본의 최대공백922.277ms와 event-loop922.223ms로 합의한500ms를 초과했다. maxContainerRatio 표본0.3980, RSS279MB이며 표본 틈 때문에 메모리 안전 통과를 선언하지 않는다. 추가 복구 재개·접수는 하지 않고 원인부터 분석한다.
- 승인된 Q7 계약에 필요한 최소 도구 수정: `q7-receipts.mjs`가 preparing receipt를 동일 requestID의 getSeasonImportBatch로 조회해 job 준비/최종 release를 기다린다. target/receipt 변경, failed/skipped/recoveryRequired/timeout은 실패 처리하며 접수 API를 다시 부르지 않는다. discovery domain 성공만으로 후속 import를 보내지 않고 batch release를 확인한다. QV06 fake receipt/clock tests를 gate에 추가한다. 이 수정은 로컬 실행기 범위이며 Worker runtime 변경/기준 완화가 아니다.
- 진단: Mac HTML 후보 파싱2~9ms, 브라우저 모듈 cold185ms/warm0.085ms. 기존 AMD64 Linux 이미지(Node24.21.0/Playwright1.60.0)에서 network none/CPU1/2GiB로 cold503.670ms, 표본공백604.259ms를 재현했고 warm0.357ms였다. AMD64 에뮬레이션이라 native Cloud Run과 같은 속도라는 뜻이 아니며 Cloud922ms의 해당 함수 원인 확정도 아니다. CPU profiles와 원본은 `discovery-diagnosis-20261006/cpu-profile/`.
- 최소 runtime 수정 후보: `src/index.ts::main`에서 HTTP Ready 전에 Playwright JS 모듈만 준비한다. 실제 Chromium process/페이지는 기존 browserImageGate와 작업 차례에서만 실행한다. 표본100ms/공백500ms/85%1s 및 처리 동시성은 유지한다. startup 비용·시간은 별도로 기록하고 첫 작업의 동기 모듈 로딩을 없애는 효과를 actual Development에서 다시 확인한다.
- 필수 검증: Worker/제품큐 gate, local Linux actual entrypoint Ready→warm 첫 접근/100ms 표본 최대500ms 이하/실제 browser process0 검증, 새 candidate preflight. 자원 원인 검증 전 현재 batch를 자동 재개하지 않는다.

UNAFFECTED 브랜드 생성 → 최초 시즌 목록 탐색 → 선택 시즌 추출 → 검토 승인 → 썸네일·상세 JPEG 변환 → 업로드 → 공개 경로 저장을 실제 제품 API로 검증한다. 원본 파일을 그대로 보관하는 계약은 아니다.

| 검증층 | 현재 증거 | 남은 일 |
|---|---|---|
| 구조 성능 비교 | 실제 네트워크에서 브랜드 직렬/병렬·시즌 한도·다운로드/변환 한도 비교 | 조건별1회라 최적값 확정 아님. T2 안전중단, U8 미실행 |
| 제품 종단간 Q7 | A 생성·목록 탐색29개, 최소 recovery IAM·`00021-kup` preflight·exact A 조건부 정산/read-back 완료. 탐색 오탐 수정·새 실행 연결의 필수 로컬 gate 통과 | 수정본 candidate 확인, 새 A/B smoke 추출·승인·저장 및 A~J |

기존 비교 실행기는 고정 입력을 사용하며 실제 createBrand/목록 탐색을 포함한 제품 종단간 비교가 아니다. 현재 제품 큐는 FIFO이므로 요청을 많이 보내도 병렬 대조군이 되지 않는다. 전체 제품 흐름의 병렬 대조군 구현은 별도 서버 설계가 필요하다. 이번에는 기존 구조 비교 증거와 실제 FIFO 제품 연결 검증을 구분해 진행한다.

## 기존 결과와 채택 근거

- [A~J 실험](ten-brand-results.md): S6 249.44초, Sall 245.72초, P6 245.29초, Pall 253.22초, D8 245.70초. 각1회. T2 메모리 중단, U8 미실행이며 전체 게이트 failed를 유지한다.
- [3브랜드 비교](development-screening-results.md)와 [역순 비교](development-reverse-comparison.md)도 전체 완료 시간10% 개선을 입증하지 않았다.
- 제품 후보는 사용자 접수 순서 정책과 안전성 증거에 따라 FIFO 묶음/시즌6/다운로드4/변환1/업로드4/재사용128MiB를 유지한다. 모든 입력의 최적값이라는 뜻은 아니다.
- 비교 입력18시즌(A8/B2/C~J각1)과 제품16시즌(A6/B2/C~J각1)은 다르다. 제품에서 중복 시즌을 제조하지 않으며 두 결과를 직접 속도 비율로 비교하지 않는다.
- P1 Functions320 tests와 제품 큐 Emulator69 tests 통과는 [권한 계획](platform-admin-transition-plan.md)에 기록됐다. P1은 아직 배포하지 않았다. 그 이전 Q6의 Development 배포 기록은 존재한다. 실행 전 현재 상태를 다시 조회한다.

## FIFO의 정확한 의미

한 번 접수한 닫힌 묶음의 시즌은 내부 병렬 처리한다. 다음 묶음은 앞 묶음의 종료·drain 확인 뒤 시작한다. 추가 시즌 선택·검토 승인·수동 재시도는 맨 뒤의 새 요청이다.

A 추출이 검토 대기에 도달하면 B 탐색이 진행될 수 있고 A 승인 저장은 뒤에 접수된다. **A의 모든 최종 저장이 B의 어떤 작업보다 먼저 끝난다는 보장은 없다.** 실제 서버 sequence별 비중첩을 판정한다. 정상 이어 실행은 같은 차례를 유지하며 종료 불명확·메모리 중단은 복구 확인 전 다음 차례를 막는다.

## 단계별 구현 계획 및 현재 상태

| 단계 | 목표·변경 파일 후보 | 완료 기준·필수 검증 | 의존·결정 |
|---|---|---|---|
| P2a | `q7-session.mjs`, login HTML/JS, `q7-journal.mjs` | **완료.** Google popup, 메모리 인증, UID 고정, 원자 journal, stage/run 중복 차단 |
| P2b | `q7-callable.mjs`, `q7-runner.mjs`, 기존 queue contract | **완료.** 고정 callable allowlist, 기존 입력/요청량, 승인 API 및 stage 실행 연결. 응답 불명확한 mutation은 재전송하지 않고 차단 |
| P2c | Storage evidence, Development preflight, 기존 performance session | **완료.** batch/run/epoch·FIFO/drain·generation·JPEG 실제 bytes/hash/dimension 증거 수집 |
| P2d | `verification/lookbook-q7-verifier.json` 및 필수 검사 등록 | **완료.** 최신 Q7 verifier gate 17 tests, Worker gate 354 tests/lint/fixtures/deploy contract 통과 |
| P3 | Development Web app/public config, base service·queue 설정 확인 | **완료.** 전용 Web app과 무시되는 public config, 기존 base traffic/queue 확인 |
| P3b | Verified Worker snapshot deployment contract | **완료.** Development only; gate summary/digest·snapshot file hash 검증; Q7 stable tag 이동; 기존 100% traffic 유지; Performance flag; Worker 354 tests, lint/fixtures/deploy contract 통과; 실제 candidate `00020-yun` Ready |
| Q7a | A2/B1 제품 smoke | **원래 A 이력 보존·새 smoke 준비.** recovery 최소 IAM과 exact A 정산/read-back 완료. 기존 report/journal은 보존하고 digest/terminal/audit proof로 이전 실행 차단을 종결했다. 탐색 오탐 수정 포함 Worker359/verifier18/product queue72 로컬 gate 통과. 수정본 candidate/preflight 후 새 smoke 최대7 mutation(이전1 포함 누적8) 진행 |
| Q7b | A~J16시즌 제품 검증 | Q7a 재개/통과 뒤에만 진행. 36 논리 mutation, 100ms wave, 결과·자원 기록 |
| Q7c | 결과·ENTRYPOINTS·HANDOFF | 원격 결과 후 갱신. 복구/장시간 종료 증거는 별도 잔여 gate로 유지 |

scripts는 `tools/lookbook-import-worker/scripts/` 기준이다. P2에서 구현·검증한 실제 파일 목록은 [P2 결과](q7-verifier-p2-plan.md)를 따른다. 인증, 요청 기록, callable 계약은 단일 runner가 소유하며 Swift DI/Container/Coordinator 변경은 없다.

상세 계약은 [P2 최소 연결](q7-verifier-p2-plan.md), 입력량·계측·검사는 [검증 행렬](q7-verification-matrix.md)을 따른다.

## 실제 실행 순서

소규모1회:
1. A 생성+최초 탐색 후 후보를 대조한다.
2. A2시즌 import 접수 후 실행 중 B 생성+탐색을 접수한다.
3. A 검토 대기·drain 뒤 B 탐색이 자기 sequence에서 시작하는지 확인한다.
4. A 검토와 B 후보를 대조하고 A 승인2건 → B import1건 순서로 접수한다. B 검토 확인 후 승인1건을 접수한다.
5. 총7건 영수증·실행 이력과3시즌 최종 산출물을 판정한다.

A가 이미 끝나 대기를 관측하지 못하면 해당 시나리오는 미검증이다. 실험 추가나 서버 지연 주입으로 임의 보완하지 않는다.

A~J1회:
create+discovery10건100ms wave → 모든 후보 검증 → import10건 별도100ms wave → 검토 대조 후 A~J 순서 승인16건 → 최종 저장·drain 확인. 승인에는 새로운100ms 조건을 추가하지 않는다. 실제 발송 시간과 서버 sequence를 모두 기록한다.

## 추가 비교와 완료 경계

U8 확인이 필요하면 독립 캠페인 준비1+동일18시즌 S6 1+U8 1의 총3회를 후속 제안한다. 기존 halted 캠페인을 해제하지 않는다. 이 추가량은 이번 Q7에 포함되지 않는다.

5쌍에서3회 이상10% 느리고 중앙값도10% 느리면 채택 보류라는 기존 기준은 유지한다. 각1회 결과에 이를 적용하거나10% 우월성·실패율 개선을 주장하지 않는다.

active `platformAdmins` 확인은 실제 A 생성·탐색으로 통과했다. 현재는 그 실행에서 남은 `recoveryRequired` queue head와 복구 endpoint IAM이 차단점이다. 기존 `/recovery/resume`는 batch를 재실행하므로 terminal `correctionRequired` 결과에는 사용하지 않는다. `/recovery/settle-correction`은 exact head/epoch/run revision, `terminalConfirmed=true`, `inFlight=0`, 단일 `discoverSeasons` batch, 원본 job=`correctionRequired`, queue item/execution/attempt=`recoveryRequired`, 미확정 asset write 0건을 요구한다. inspect report digest·state revision을 재검증하고 한 transaction에서 checkpoint·release·90일 audit를 기록하며 원본 job 상태와 종료 evidence는 바꾸지 않는다. 다른 결과나 활성 실행에는 적용하지 않는다. Development 전용 recovery identity를 최소 권한으로 연결한 후 read-only inspect가 통과할 때만 A head를 정산한다. smoke 전체 완료 뒤에만 A~J를 시작한다.

Production·QA 삭제·정식 관리자 웹·iOS 관리자 제거·제품 병렬 스케줄러는 범위 밖이다. 기존 Q7의 실제 복구 IAM·장시간 종료 증거는 정상 smoke로 대체하지 않고 잔여 필수 항목으로 남긴다.
