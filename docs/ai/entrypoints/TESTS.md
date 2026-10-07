# Test Entrypoints

Q7 최종 현재소스(2026-10-07): 서버verifier40/Worker362/Functions324/Rules131/Emulator96/Linux2와iOS28개 모두passed. iOS새원본 `1791351931354-77dba3f2-cbfd-48ca-b01e-503e3c4db6e8`. 실제K/L검증도전체8접수·124JPEG·oldrun종료/attempt2·L5회소진/새수동실행/성공제거로passed다. [전체게이트ID·범위·원본](../tasks/lookbook-import-performance/product-queue-q7-final-results.md). 과거실패/실제장시간·24h삭제미검증은보존한다.

Q7 이어 실행 필수(2026-10-07): `q7-retry-contract.test.mjs`의 QV13은 K3확정 영수증·다른UID/head/oldrevision/시도/공개 쓰기 거절과 남은5접수·추가OOM0을 검사한다. QV14는 기존task실행/같은body·SA·audience새task1개, intent실패·불확정응답재전송금지, 추가10/누적30관찰상한을 검사한다. `verification/lookbook-q7-verifier.json`에 필수4개를 추가해 전체40개 passed(`1791350705468-a622bcfb-7122-4c77-83d2-b5f4cbfcc93a`). source 변경 뒤 다른 필수 게이트를 새로 실행하며 원격 정산 통과로 표시하지 않는다.

**Q7 필수최신(2026-10-07):** KR20 exact encoded system logName/old revision·instance·trace, QV11 경로jobID/같은2확정접수복원·만료/불확정차단, QV12 missing assets부모아래writes의bounded조회가추가됐다. Worker362 `1791346980239-fa0f1f54-df09-45c1-a25f-618a41957c8d`, 제품96 `1791347262222-a2a5f8a8-975d-4add-b0bd-098f17fb0b5c`, verifier36 `1791346788346-9228ec44-fbc9-45ea-99b7-2501b05fa6c7` passed. `firestore-tests/run-firestore-tests.mjs`는신고33개를새Emulator에서실행하며`verification/firestore.json`의rules/transactions/transactions-reports3원본을합친총131개·필수항목을유지한다. Rules최종 `1791348368813-0ea75d96-5626-4314-9c04-1a4431e37c09` passed. 원본실패/단독재현·실제K실패및최종Functions324/Linux2는 [결과](../tasks/lookbook-import-performance/q7-retry-development-results.md).

**Q7 K/L 필수 최신(2026-10-07):** KR15/16/17은 Development-only 장치·owned identity·원자적 한 번 소비·원래5시도·새 승인 제외를 검사한다. KR18은 플랫폼 memory-limit 종료와 request-timeout/종료 준비를 구분하고 KR19는 run 정리 뒤90일 감사 증거의 exact generation 정리를 확인한다. `scripts/q7-retry-contract.test.mjs` QV09/10은8접수·새execution·정확종료증거 검증; Linux gate는 실제 `forceQ7OOM` 함수를 제한 컨테이너에서 실행한다. 최신 Worker361/Emulator96/Functions324/Rules131/verifier33/Linux2, 원본 ID·digest는 [결과](../tasks/lookbook-import-performance/q7-retry-local-results.md).

**Q7-R1 검증(2026-10-07):** `functions/src/lookbook/import/queue/failure-service.test.ts`·shared projection tests의 KR01과 `firestore-tests/lookbook-import-queue.emulator.test.mjs` KR02~14를 `verification/functions.json`·`verification/lookbook-product-queue.json`에 필수 연결했다. 인가/동시 접수/멱등/CAS/안 함·성공 제거/원본 보존/기간 정리, 부분 데이터 보호·추출/승인 초기화·총5회/FIFO, 실제 종료 증거 누락·다른 revision·늦은 root 쓰기 거절, 누락 generation의 종료 확인·exact 삭제를 검사한다. Worker lint/test/fixture/deploy, Firestore/Storage, Q7 verifier, Linux 실제 OOM·자원 gate를 별도로 실행한다. Emulator 통과는 Development 실제 종료 증거·전송 통과가 아니다. [최신 상태](../tasks/lookbook-import-performance/q7-retry-contract-plan.md).

2026-10-07 최신: [A~J 실제 제품 검증 결과](../tasks/lookbook-import-performance/product-queue-q7-ten-brands-results.md) — 36접수·16시즌 저장·710JPEG와 현재 공개 원장 대조가 완료됐다. 두 100ms 예약 wave에서 실제 서버 순번과 브랜드 대기·실행 비중첩을 확인했다. 앞 run 시작 후 신규 접수는 없었으므로 A/B의 active 중 도착과 동일한 조건으로 표시하지 않는다. 메모리 최고 84.05%, 최대 표본 공백 380.7ms, 이미지 실패·시즌 재시도·중단 0회. 실행기 job 기록 누락은 원본 보존·별도 job index 대조로 정산했으며 이후 도구 기록 연결을 수정했다. 최종 client31/Worker359/Linux2 필수 검사 통과. 실제 장시간·플랫폼 종료 및 청구 전체는 별도 미검증이다. 전체 Q7 완료·커밋은 아직 아니다. 아래 실행 전/진행 중 문구는 과거 기록이다.

Q7 A~J 실행기 준비 완료(2026-10-07): `scripts/q7-wave.mjs::runQ7Wave`는 응답 대기 없이 절대 100ms 간격으로 최대10건을 시작한다. `q7-journal.mjs`/runner는 동시 기록을 직렬·원자 저장하고, 실패하면 새 투입을 멈춘 뒤 시작한 요청을 모두 정리한다. `assertQ7WaveEvidence`는 두 wave 각10건의 예정/시작/HTTP 직전 기록·실제 서버 순번과 서로 다른 브랜드 대기를 검증한다. 실제 서버 도착 간격을100ms로 단정하지 않고 편차와 순서 변경을 기록한다. 승인된 A6/B2/C~J각1·16시즌·36접수·기존 비용/2시간 상한은 유지한다. 필수 verifier gate `1791303321801-54c50236-ead4-40c3-ad2d-f126a1131cbc` passed31; digest `e3da40995238821d1f710fe61930efb6057e14c69792897cc00aa61f155c9c66`. 원격 A~J는 아직 실행 전이다.

Q7 현재 기능 결과: [smoke결과](../tasks/lookbook-import-performance/product-queue-q7-smoke-results.md). QV05 현재커버원장 경로/generation 및 QV07 확정7건 읽기전용 재검사 필수추가, 최종client gate1791302208309… passed26. 실제126 JPEG 해시/크기/generation·공개원장/epoch 모두검사했다. active중B접수는미검증이며 A~J100ms로후속검증한다.

Q7 기능 저장 재개(2026-10-07): QV07 `추출 후 이어 실행은 동일 종료 batch와 검토 대기 두 항목만 허용한다` 필수 추가, gate1791301500154… passed24. PQ02 `복구 해제는 같은 준비 순번을 즉시 재개하고 중복 이벤트는 한 번만 준비한다` 필수 추가, 제품큐1791301003465… passed75. Functions1791300998982… passed321. 실제A 추출은44GET/18,939,777B/실패0/재시도0/peak download4/maxgap309.786ms/메모리11.07%, 원본 terminal-measurements.json. active overlap/Storage는 아직 미검증이다.

PQ06 복구 재개 필수2건(2026-10-07): `firestore-tests/lookbook-import-queue.emulator.test.mjs`의 종료한 항목 재시도0/attempt1 보존·실제 execution 종료 확인, terminal checkpoint와 execution 불일치 시 recovery 차단을 추가했다. 제품큐 gate1791300034383-e57b2bb4-18ef-488d-a937-ac37f965f805 passed74/build. QV07 원본 보존 검사 후 복원 fixture를 오염시킨 verifier1건은 실패 이력으로 남기고 검사 fixture를 바로잡아 다시 실행한다.

Q7 이어 실행 QV07(2026-10-07): `scripts/q7-resume.test.mjs`는 확정 두 요청/시즌 일치, 지정 run만 campaign 재개, 원본 digest 보존, audit/종료/새 실행 자원 검사와 기존 실패 분리를 검증한다. `verification/lookbook-q7-verifier.json` 필수3건 추가, gate `1791299169976-9d8d1850-9f20-4d04-b52e-fc61bd2dde51` passed23. 실제 index/cgroup supervisor local bootstrap 원본은 `output/lookbook-import-performance/product-queue-q7/discovery-diagnosis-20261006/cpu-profile/linux-ready-supervisor.log`; 새 원격 후보 검증은 별개다.

Q7 preparing 회귀(2026-10-06): QV06 2건을 verifier gate에 추가. preparing→active(job ID생성)→released, 복구/실패/target 변경/timeout을 fake callable+clock으로 확인하고 재접수가 없는지 검증한다. actual smoke의 sample-gap922ms는 이 도구 검사의 통과로 대체하지 않는다.

Q7 새 A/B 연결(2026-10-06): QV02 `정산된 단일 탐색 이력만 원본 digest와 종료 증거로 새 검증을 허용한다`를 verifier gate에 추가했다. 원본 불변·유효 정산 허용, proof 누락/digest 변조/활성 실행/미확정 쓰기/다른 brand/job/epoch를 차단한다. 현재 변경본의 새 gate는 후속이다.

Q7 탐색 DOM 회귀(2026-10-06): `season-discovery-controls.test.ts`의 한 페이지 paginate/script 오탐, 실제 more 클릭/숨김·disabled 제외, 현재/이전/다음 페이지3건을 Worker gate 필수 목록에 연결했다. 외부 URL 없이 route-fulfilled DOM fixture를 사용한다. 수정본의 전체 gate 결과는 진행 중이며 원격 제품 검증을 대체하지 않는다.

Q7 복구 인증 변경(2026-10-06): `tools/lookbook-import-worker/src/queue/recovery-auth.test.ts`의 PQ14 2건을 Worker gate 필수 목록에 추가했다. ID token만 발급, 취소/인증 실패/잘못된 응답/입력과 비밀정보 비노출을 검사한다. Q7 verifier의 QV03은 recovery env 누락을 추가로 거절한다. 새 source gate 결과는 진행 중이며 이전 source 결과를 재사용하지 않는다.

Q7 현재 검증 상태(2026-10-06): 로컬 Q7 gate **16/16 통과**, 전체 Worker gate **350 tests 및 fixture 검사 통과**. Q7 source digest `68eb5365…ee27d85`, Worker `f469f8b8…3e80f64`. Development smoke runner는 로그인 계정의 inactive platform admin 권한으로 0 mutation에서 중단됐다. 제품 흐름/A~J는 미검증이다. 실행 기준은 [검증 행렬](../tasks/lookbook-import-performance/q7-verification-matrix.md)과 [readiness](../tasks/lookbook-import-performance/product-queue-q7-readiness.md)다. 과거 T2 중단/U8 미실행과 복구/장시간 플랫폼 증거 미확보는 별도 한계로 보존한다.

Q7 로컬 gate 원본: `output/verification/1791272777124-46941d42-43ab-428b-b70a-c77be744c82e/summary.json` (16 tests, 0 failure/blocker); Worker gate `output/verification/1791272437943-00200a43-5607-49b6-b296-d9041dbbd14e/summary.json` (350 tests + fixture gate; lint 0 errors, 70 existing warnings). 필수 commands와 QV/QL 완료 상태는 Q7 verification matrix를 기준으로 한다.

Q7 platformAdmins 권한 회귀: `functions/src/shared/platformAuthorization.test.ts`, `functions/src/lookbook/import/queue/authorization.test.ts`, `firestore-tests/lookbook-import-queue.emulator.test.mjs`. 활성/비활성/회수·legacy-only 거부, 삭제 브랜드 거부, 접수된 배치 권한 회수 후 준비 지속을 확인한다. Functions gate `1791267712654-f7786f8f-3eef-4749-b261-71942e017148` 통과(320 tests), 제품 큐 gate `1791267891214-8537e254-a48d-4163-a9a8-89121c86c5da` 통과(Emulator 69 tests). 상세는 Q7 전환 계획에 기록한다.

Q7 실기기 진입 보정(2026-10-06): `LookbookImportQ7DevelopmentUITests.swift`에서 앱 시작 후 `app.tabBars.buttons["룩북"]`을 선택한다. 실제 앱은 오픈채팅 탭에서 시작한다. 이전 관리자 버튼 탐색 실패는 이 전환 누락이며 원격 쓰기 이전 실패였다. 수정된 테스트 빌드·실기기 실행 결과는 Q7 readiness에 별도로 기록한다.

**이전 Q7 준비 gate(2026-10-06):** `verification/lookbook-queue-development-preparation.json`은 입력산술·검토 승인 대조·서버 FIFO/drain 증거용 6개 계약 검사였다. 현재 실행 전 로컬 gate는 `verification/lookbook-q7-verifier.json`에서 수행한다. Remote product execution은 실제 runner 결과가 생성되기 전까지 미검증이다.

**제품 큐 Q6 최종 통합 gate(2026-10-06):** G-F `1791219881139-a8b3805e-5cd4-45d9-ba2c-bc0835fbdd0f` passed(315 Functions tests), G-W `1791218636572-414dc6f2-7877-49ce-bb61-e33547bc8b4e` passed(348 Worker tests+fixtures), G-E `1791219933737-c998b4e6-f636-4acf-893b-d26dd6661f8a` passed(69 Emulator tests), G-R `1791218212558-3bc9e648-9e39-4f6c-8bec-9723cff8ebd7` passed(131 rules/Storage tests), G-L `1791218807410-700c0a3b-dc59-4e47-9a2a-ffefcb696ec7` passed(2 Linux/amd64 scenarios), G-I `1791218887251-6bbec0eb-7ff1-499d-b8b8-f57babe5531d` passed(28 iOS Simulator tests). G-F/G-E의 마지막 코드 수정 후 digest와 모든 summary 경로는 [Q6 결과](../tasks/lookbook-import-performance/product-queue-q6-results.md)에 있다. 실제 Development/Storage·Cloud Tasks·수동 UI QA는 포함되지 않는다.

**Q5 앱 큐 게이트(2026-10-06):** Q5 당시 iOS 26.2 Simulator 28 tests/8 suites가 통과했다. 계약·GRDB request identity/retention·응답 유실 재사용·migration27·계정 삭제·brand create/season import/discovery/review/repair adapters·자산 재시도 polling을 선택했다. 이 단계 결과는 [Q5 기록](../tasks/lookbook-import-performance/product-queue-q5-results.md), 최신 현행 digest를 대상으로 한 재실행은 위 Q6 G-I다. 실제 화면 QA/Development는 미검증이다.

**Q4 제품 큐 최종 로컬 게이트(2026-10-05):** G-F `1791209282584-d438daf9-4d01-4b10-aa84-990ca46cf485` passed(314 Functions tests), G-E `1791209301168-92159c88-087b-4a51-b386-03fa600d7821` passed(68 Emulator tests), G-W `1791209345170-c79b0a40-968f-4321-a4f0-aa394b6cf2ed` passed(347 Worker tests+fixtures), G-R `1791209483839-053eae73-ebd6-47bc-ba83-c4950f73c179` passed(131 rules/Storage tests), G-L `1791209548822-14101190-711a-415a-8dd3-a8fb0055b227` passed(Linux/amd64 2 scenarios). Digest·file count·원본 경로 및 미검증 범위는 [Q4 기록](../tasks/lookbook-import-performance/product-queue-q4-results.md). 검사는 local synthetic/emulator/container 경계이며 원격 배포·실제 복구 호출은 없다.

**Q3 최신 검증(2026-10-05):** G-W `1791204616659-cd78fe1e-aef6-49e2-b259-528722c17cf5` 통과: lint/build/fixture와 Worker 테스트342개, 실패·취소·skip0. G-E `1791202927198-85bb5ef3-5200-4b48-826b-81e92b2814a1` 통과: Worker/Functions build와 Firestore Emulator59개, 실패·skip0. PQ08은 active asset ledger의 post/season/brand 삭제 차단, terminal 뒤 삭제 허용, 이전 cover 보존·두 generation publication·stale epoch·부분 업로드를 검사한다. PQ06은 Chromium 진입 전 공유 batch cache 비우기와 hash/image admission 배타 처리를 포함한다. G-L Linux/amd64 gate는 통과했으며, 실제 URL/Storage·Worker HTTP/Cloud Run 복구·Development 검증은 아니다. G-L `1791204563869-6a8fd235-05d9-4145-84d2-b3dfa48de383` 통과: Linux/amd64 1CPU·2GiB에서 85%/1초 memory stop, Chromium SIGTERM drain과 별도 OOM true/137 확인. [원본·digest·범위](../tasks/lookbook-import-performance/product-queue-q3-results.md).

**Q2 검증 이력:** G-W `1791198150647-0f15e6f2-d818-49c2-ab7b-b2ec8423b7a4`는 332개 Worker 테스트를 통과했다. 당시 14분 응답 deadline은 구현되지 않았으며 Q6에서 로컬 handler 응답/drain 동작을 추가 검증했다. Cloud Run의 원격 15분 종료는 미검증이다. [Q2 기록](../tasks/lookbook-import-performance/product-queue-q2-results.md).

**Q2 실행권 검증(2026-10-05):** Worker `queue/coordinator.test.ts`/`runtime.test.ts` 검사와 Emulator owner/epoch/checkpoint/attempt/drain 경계8개, 구형 실행 경로의 큐 소유 job 우회를 막는 `PQ10` Worker 검사2개가 필수 목록에 있다. 최신 G-W는 Worker327개, G-E는 Emulator48개 통과했다. 독립 SDK transaction은 같은 프로세스 검사이며 Linux 실제 종료/OOM 검증은 후속이다. [원본·검증 경계](../tasks/lookbook-import-performance/product-queue-q2-results.md).

**Q1 후속 접수·준비 자동 실행(2026-10-05):** Emulator에 준비 중복/순번 전진/5회 소진/불명확 owner 보존, 승인 동일 실행/시도 이력·참조 고정·snapshot 변경, 관리자 수동 재시도, 보수 데이터 불변, 탐색 진입점 통합·3회 재시도·재분석 원본 보존을 추가했다. `index.contract.test.ts`는 신규 Firestore trigger2개를 기존 export에 추가한123개와 static document filter를 검사한다. 실제 원본·최종 개수는 [Q1 기록](../tasks/lookbook-import-performance/product-queue-q1-results.md)을 따른다. Worker 동작 fixture와 실제 Worker 실행 검증을 구분한다.

**브랜드 생성 원자 접수 회귀(2026-10-05):** 제품 큐 Emulator 필수 목록에5개를 추가했다. 동시6회 재전송/결정적 job 준비, URL 없음/순번 미소비, 이름·입력 실패/부분 저장 없음, payload 충돌·권한 회수·만료 신규 요청, 영수증 직접 접근 거절을 검사한다. Functions 기존 아키텍처 검사를 유지하며 공통 접수는 shared 계층으로 이동했다. 결과 원본은 [Q1 기록](../tasks/lookbook-import-performance/product-queue-q1-results.md)을 따른다.

**Q1 실제 접수 API 회귀(2026-10-05):** Emulator 필수23개(기존18+실제 callable5). URL 최신 계약/중복/재전송, 후보 snapshot 변경 후 영수증 재조회·부분 실패·URL 중복, asset 재시도 새5회/동일 실행 합류/root 보존, 입력 변경 거절, 후보 불일치/재시도 불가를 검사한다. Functions307개 회귀와 함께 실행했으며 원본은 [Q1 기록](../tasks/lookbook-import-performance/product-queue-q1-results.md)에 보존한다. 실제 앱·클라우드 인증 검증은 아니다.

**Q1 기존 job 참조 회귀(2026-10-05):** `firestore-tests/lookbook-import-queue.emulator.test.mjs`에 기존 상태·이력·실행권 불변, 삭제된 대상 차단·준비 재실행, 잘못된 참조의 순번 미소비 3개를 추가했다. `verification/lookbook-product-queue.json` 필수 검사는 기존15개를 보존한18개다. 실제 결과는 [Q1 기록](../tasks/lookbook-import-performance/product-queue-q1-results.md)을 따른다.

**제품 큐 Q1 진행(2026-10-05):** [공통 접수 계층·변경 파일·검증·남은 adapter](../tasks/lookbook-import-performance/product-queue-q1-results.md). Functions `import/queue/{admission,preparation,dispatch,projection,authorization,functions,model}.ts`와 `import/taskService.ts`, 조회 callable `getSeasonImportBatch`를 추가했다. 기존 trigger/watchdog는 큐 소유 job을 제외한다. `verification/lookbook-product-queue.json`은 demo 프로젝트/8086의 실제 transaction·준비·전달/권한15개를 검증한다. 기존 실행 접수 callable 전체 연결과 Worker 실행은 아직 미완료이며 Q1 전체 완료가 아니다.

**제품 큐 Q0 구현(2026-10-05):** [변경·게이트 원본·남은 범위](../tasks/lookbook-import-performance/product-queue-q0-results.md). 사용자 구현 승인 후 공용 `contracts/lookbook-import-queue-v1.json`, Functions/Worker `queue/contracts.ts`, 앱 `Domains/Entities/LookbookImportQueueContract.swift`와 각5개 계약 검사를 연결했다. 정책/버전/공통 요청/시간 경계/상태 분류를 검사하며 기존 API·DI에는 아직 연결하지 않았다. Functions·Worker 기존 필수 검사를 유지하고 전용 iOS/자체 게이트를 추가했다. Q1 이후 접수/FIFO/실행/저장/복구 및 emulator/Linux 기능 검증은 후속이다. 아래 구현 승인 전 문구는 이전 이력이며 현재 결과는 링크를 따른다.

**A~J 원격 version5 연결(2026-10-05):** [구현·검증 기록](../tasks/lookbook-import-performance/ten-brand-connection-results.md). `remote-input.ts`가18시즌을 독립 ID로 매핑하고 `remote-contract.ts`가100ms 접수·고정8회·단계 증량을 묶는다. `remote-runner.ts`→`arrival-runner.ts` 실행, `remote-arrivals.ts`/`remote-report.ts`의 도착·정책·저장 증거 재검사와 variant별 집계가 진입점이다. Mac/Linux 각각 전체316개·필수208개, emulator5개, 테스트/runtime 이미지 대조를 모두 통과했다. 배포·실제 네트워크 비교는 이번 범위에서 미실행이다.

**100ms 접수 로컬 검증 완료(2026-10-05):** Mac/Linux AMD64 각각313개·필수205개 통과, 실패·취소·skip0. Linux1CPU/2GiB에서 검사했고 기존 lint70경고는 남아 있다. 원본 로그·소스 해시·이미지 대조는 아래 A~J 검증 기록5절에 보존한다. 다음은 원격18시즌·8회 계약 연결이며, Firebase 실측은 이번에 실행하지 않았다.

**A~J 실험 조건 확정(2026-10-05):** [입력·최소 행렬·요청량·비용·연결 계획](../tasks/lookbook-import-performance/ten-brand-execution-proposal.md). 총18시즌(A8/B2/C~J각1), 접수 간격100ms(A0~J900ms), Worker 합산 시즌6/해제 비교, 준비 포함8회로 확정했다. 접수 간격 외 추천 조건은 유지한다. 새 계약 연결·필수 검증·승인된 유료 실행은 아직 미완료다.

**최신 작업(2026-10-05) — A~J 로컬 최종 검사:** [검증 범위·결과·미구현 경계](../tasks/lookbook-import-performance/ten-brand-validation.md). `performance/arrival-runner.ts`가100ms 접수를 재현하고 `season-runner.ts::beforeStart`가 도착 전 실행을 막는다. `arrival-runner.test.ts` TB03~06 및 기존 TB01/02를 `verification/lookbook-import.json` 필수 목록에 연결했다. 원격18시즌·8회 계약 연결과 유료 실행은 아직 미완료다. 제품 FIFO 방향과 기존 실측 증거는 보존한다.

**최신 결정(2026-10-05) — 브랜드 요청 FIFO 확정:** [확정 사항·제품 연결 설계·남은 결정](../tasks/lookbook-import-performance/phase-4-brand-dispatch-design.md). 현재 브랜드 안에서 시즌을 병렬 처리하고 저장·종료·정리 후 접수 순서대로 다음 요청을 진행한다. 뒤 요청 대기를 수용하고 단순성·순서 예측 가능성을 우선한다. 실측에 의한 큰 속도 개선 주장이 아니다. 다음은 요청 묶음/API·실행권·재시도/복구·공용 pipeline의 최소 설계 및 구현 계획이다. 제품 구현·추가 실험·배포는 아직 진행하지 않았으며 아래 기록은 이력이다.

**검증 이력 — Development 역순3회 완료:** [계약·구현 계획·요청량·검증](../tasks/lookbook-import-performance/development-reverse-comparison.md). version4는 준비→SP→PP만 허용한다. `remote-contract.ts`/`remote-report.ts`와 관련 필수 게이트가 진입점이며 이전5회 결과는 보존한다. Mac/Linux307개·emulator5개·실제3회·원본 재검사 게이트 모두 통과했다. 이번 SP 전체0.61%/첫 브랜드4.24% 단축으로 큰 처리량 개선 근거는 부족하다. 추가 성능 실험은 실행하지 않는다. 당시 제품 도입 보류 권고는 이후 FIFO 제품 결정으로 대체됐으며 세부 구현은 후속이다.

**최신 — Development 실제 약식5회 완료:** [실측 결과·원본·게이트·비용 추정](../tasks/lookbook-import-performance/development-screening-results.md). 준비1회와 PP/SP/PS/SS 각1회가 모두 성공했고 실제 실행·원본 재검사 게이트를 통과했다. 전체 처리100~104초, 브랜드 순차 후보의 첫 브랜드 완료는 약10% 빨랐으나 각1회·동일 인스턴스·고정 순서이므로 채택은 미판정이다. 추가 실행/운영 반영/삭제는 하지 않았다. 아래 승인 대기·미실행 문구는 실행 전 이력이다.

실행 전 기록: **배포 전 준비:** [약식5회 실행안·현재 대상·비용·검증](../tasks/lookbook-import-performance/development-screening-execution.md). 로컬 원 사이트 HTML7개/원본138개 검사가 통과했고 현재 설정·기존 OIDC와 서울 단가를 재확인했다. 준비 게이트2개 통과, Worker 소스 변경 없음. push/배포/Worker 실험 요청/Firebase 실험 쓰기는 아직 하지 않았다.

**최신 — 약식5회(version3) 로컬 구현·검증 완료:** [확정 조건·구현·검사·요청량](../tasks/lookbook-import-performance/development-screening.md). 준비1회+PP/SP/PS/SS 각1회로 축소한다. 다운로드4·변환1·업로드4·재사용128MiB는 유지한다. `remote-contract.ts`의5회 계약과 `remote-report.ts`의 단일 관측 집계가 현재 기준이며, 채택/반복악화/실패율 개선 판정은 하지 않는다. Mac/AMD64 각각307개·필수199개, emulator5개와 요청량/이미지 대조 게이트를 통과했다. 실제 배포·유료 실험은 미실행이다. 아래21회 실행안·version2·과거 ‘현재/다음’ 문구는 이전 이력이며 추가 실행 권한이 아니다.

- **AMD64 golden 분리 검사 완료:** [원본·게이트](../tasks/lookbook-import-performance/development-amd64-golden.md). `remote-golden.test.ts` RN13~15가 기준/정책 보존·이전 계약/실행 환경 거부·EXIF8방향을 검사한다. Mac/AMD64 각각307개·필수199개,emulator5개와 실제 runtime274개 golden command 게이트를 통과했다. 원격 성능은 미검증이다.

- **AMD64 배포 전 확인:** [게이트·원본·golden 실패](../tasks/lookbook-import-performance/development-amd64-readiness.md). `remote-auth.test.ts` RN11~12를 필수 ID에 연결했다. Mac/Linux AMD64 각각304개/필수196개·emulator5개 통과. 일반 테스트 통과와 실제274개 JPEG golden 일치는 별도이며 후자는152개 불일치로 실패했다.

- **Development 네 구조 계약(version2):** [구현·필수 검사·원본](../tasks/lookbook-import-performance/development-network-implementation.md). `performance/remote-v2.test.ts` RN01~02와 `remote-campaign.test.ts` RN03~10이 21회/실행 순서/증거 재검증/미완주·종료 미확인/시간·비용 중단/대상 경계를 검사한다. `scripts/remote.emulator.mjs` RD05는 smoke부터21회 순서와 변경된 종료 계약 거부다. 기존 RC/RD도 함께 유지한다. 실제 네트워크 성능 검증은 별도이며 AD2b 예약 테스트 구현은 보류했다.

- **AD2b 필수 테스트 설계:** [AB01~12와 구현 순서](../tasks/lookbook-import-performance/adaptive-ad2b-plan.md). 원자적 예약·오래된 표본·커버 확대·제동 중 기존 작업 완료·취소/재시도·CPU 준비·실제JPEG/기존P/S를 검사할 계획이다. 새 테스트는 아직 작성/실행하지 않았으며 아래292개는 AD2a 상태의 증거다.

## 룩북 URL import Worker

- **AD2a 필수 검사·준비 측정 완료:** [원본·상태·한계](../tasks/lookbook-import-performance/adaptive-ad2a-results.md). `memory-preparation.test.ts` AR01~06을 필수 게이트에 연결했다. Mac/Linux 전체292개·필수184개,0 skip/cancel, Linux 실제 cgroup 확인. 로컬18/18회·JPEG42개·독립 집계/정리 통과. 실제 R 성능·원격 전송은 미검증이다.

- **자동 동시성 AD1 검사 연결:** [원본·소스·범위](../tasks/lookbook-import-performance/adaptive-ad1-results.md). `adaptive-controller.test.ts` AP01~08을 필수 게이트에 추가했다. 전체286개/필수178개이며 플랫폼별 실제 결과는 기록을 따른다. 실제 CPU/메모리/네트워크 개선은 이 fake 검사로 입증하지 않는다.

- **최신 Development 연결 검증(2026-10-04):** [원본·소스·수정 이력](../tasks/lookbook-import-performance/development-connection-results.md). `performance/remote.test.ts` RC01~08/11~13, `server.test.ts` RC09, `config.test.ts` RC10을 포함해 Mac/Linux 각각전체278개·필수170개 통과. 고정30회·원본변동·부분업로드·저장물손상·취소·실제시도분모·route격리를 검증한다. `scripts/remote.emulator.mjs` RD01~04는 실제 로컬 Firestore claim 경합과 만료/중복/클라이언트 접근거부를 검사하며 `verification/lookbook-remote.json`에서4개 필수 ID 통과. 아래 숫자는 이전 단계 이력이다. 실제 Cloud Run·Storage 전송 성능과 품질 검토 재개는 별도다.

- 제출 순서 최신 구성은 **전체240개/필수132개**다. `submission.test.ts`의8개 검사는 승인45회/공유 대조, R4/B4 경계, 준비된 변환 우선순위/비선점/맥락 보존, 실제JPEG hit/miss, 실패·취소 정리, trace/시즌완료 변조,5쌍/누락 분모를 확인한다. Mac `1791029167836-02991d5f-f0a1-4484-87a4-4dfd6ab12263`와 Linux `1791029318872-1ea1d740-2374-40e4-819c-d8a3fe7e7b36` 모두 passed. [실험·실패 이력·원본 기록](../tasks/lookbook-import-performance/phase-3-submission-design.md)을 따른다. 아래232개 이하는 이전 단계 이력이다.
- 제출 순서45/45 성공, JPEG12,330개·경로6,165건·SHA/규격/바이트·trace 정책 준수와 독립 재집계 일치. R4/B4는 첫 시즌5/5쌍 악화로 채택 보류, P4는 같은 예산 U/off 대조와 첫 시즌/전체 반복 악화 없음. 최고 메모리89.32%로85% 초과 피크는 있었지만1초 지속 중단은 없었다. 원본은 `output/lookbook-import-performance/submission-d7faf7c4-e051-4ec2-b90a-89fdf1f6fb55/`의 manifest/summary/diagnosis/observations/queue-evidence 및 runs다. 대용량·실제 HTTP/Storage/Firestore는 미검증이다.

- 후속 부하·압박 최신 구성은 **전체232개/필수124개**다. `load-pressure.test.ts`의6개 검사와 `fixtures/performance-input-contract.json`이45회 행렬/교차 순서·고정 입력·실제JPEG 혼합 hit/miss·실패/취소·cache/trace/bytes·5쌍/압박/중단을 확인한다. Mac `1791021865241-74593be5-ed31-4bb2-832c-617bc3b291dc`, Linux `1791021975499-220e07d0-b639-4f7f-99ac-c39148f87793` 모두 passed. [실험 원본·완료 판정](../tasks/lookbook-import-performance/phase-3-load-pressure-proposal.md)이 최신이다. 아래226개 이하는 이전 단계의 코드 이력이다.
- 승인한45회 모두 성공·JPEG10,210개/경로5,105건 정합성·원본 재집계 일치·컨테이너 정리 확인. 최대 메모리83.79%, 최대 표본 간격173.693ms다. 16/32MiB는 첫 시즌3/5쌍과 중앙값 모두10% 이상 악화해 성능 채택 보류다. 64MiB는2/5쌍으로 보류식 미해당이지만 개선 확정이 아니다. 원본은 `output/lookbook-import-performance/load-pressure-a091769b-f0d6-45f2-b0b9-108010025514/`의 manifest/summary/diagnosis/observations/pressure-order-analysis 및 runs다. 실제 원격 업로드·Firestore 저장·대용량 입력은 미검증이다.

- 커버 선준비 최신 구성은 **전체 226개/필수 118개**다. `reuse-comparison.test.ts`에 준비 barrier·읽기·예산 miss·실패/취소 정리·엄격한 15회/5쌍 집계 4개를 연결했다. Mac `1791019391627-02df463a-a354-41a6-b48b-d3490324bca0`, Linux `1791019428675-34ada7f6-bee3-4520-ad6b-138571cc5f47` 모두 passed. [설계·원본·실험 상태](../tasks/lookbook-import-performance/phase-3-cover-preparation.md)가 최신이며 아래 222개 이하는 이전 코드의 이력이다.
- 커버 선준비 실측15/15 성공·JPEG4,110개 정합성·원본 재집계 일치, off/current와의 전체·첫 시즌 각각5쌍 반복 악화 없음. 원본은 `output/lookbook-import-performance/cover-preparation-89b5c2f6-2ea0-4a09-af2f-f6de8351a68e/`의 manifest/summary/diagnosis/observations 및 회차별 기록이다. 6시즌 한 부하이며 전체10% 개선·모든 부하·실제 HTTP/Storage/Firestore 검증을 의미하지 않는다.

- 재사용 지연 진단의 최신 구성은 **전체 222개/필수 114개**다. `reuse-trace.test.ts` 3개와 `reuse-comparison.test.ts`의 실제 JPEG trace 1개를 추가했다. Mac `1791018401055-e8a92ee5-0415-4349-a26c-a9edd34ad499`, Linux `1791018484756-ced33f44-cfc2-45c9-9de3-d735bbc4c6c7` 모두 passed. [진단 원본·결과](../tasks/lookbook-import-performance/phase-3-reuse-diagnosis.md)를 우선하고 아래 218개는 직전 15회 코드 이력으로 본다.
- 진단은 2/2 성공, JPEG 총 548개 정합성/trace 완전성/원본 재집계가 일치했다. 커버의 변환 큐 대기가 시즌 지연을 만드는 직접 증거를 확보했으며, 정책 수정이나 최종 채택 검증은 아니다. 원본은 `output/lookbook-import-performance/reuse-diagnosis-d5d40496-638f-49b1-8731-ecc7e447f262/`다.

- 재사용 15회 연결 비교의 최신 구성은 **전체 218개/필수 110개**다. `performance/reuse-comparison.test.ts` 5개가 계획·실제 작은 JPEG와 예산 miss·병렬 scope·실패/취소 정리·집계·컨테이너 종류를 검사한다. Mac `1791016699684-5a69c208-3ff1-4566-bb3b-5b6fcd1e4c8a`, Linux `1791016759786-d52354cb-711b-4d95-9e6a-4e9d6210e085` 모두 passed. 15/15회 성공·JPEG 4,110개 일치지만 첫 시즌 지연으로 성능 채택을 추천하지 않는다. [재사용 실험 원본·결과](../tasks/lookbook-import-performance/phase-3-reuse-comparison.md)를 우선한다. 아래 213/207개 결과는 당시 코드의 이력이다.

- C 변환 30회 확인 추가 후 구성은 **전체 213개/필수 105개**다. `performance/transform-confirmation.test.ts`의 3개 검사는 30회 계획/교차 순서/다른 축 거절, 첫 시즌 독립 악화 판정, 중단·누락·이전 표본 혼입을 확인한다. 이전 `transform-sweep.test.ts`의 3개 검사도 유지한다. [현재 게이트·실험 원본](../tasks/lookbook-import-performance/phase-3-transform-confirmation.md)을 우선하며 아래 207개는 과거 54회 코드 상태다.
- 최신 Mac 게이트 `1791013758862-ed5b229f-55f1-4586-bc13-3682cd9ca781`, Linux `1791013839969-f1470883-cb50-452e-998e-1ef67896c471` 모두 passed. 세 부하 5쌍의 추가 30회 모두 성공·전체/첫 시즌 반복 악화 없음·원본 재집계 일치. `output/lookbook-import-performance/transform-confirmation-5140f49b-c4c9-48a1-8a12-39e24e2bb20d/{manifest,summary,observations}.json`과 runs를 따른다. 이전 12회 결과와 합치지 않았다.

- 최신 구성은 **필수 ID 99개/전체 207개**다. 직전 201개에 계측 off·오버헤드 교차/오염/실패·Linux volume/외부 결과 검증 5개와 포화 libuv 풀에서 메모리 읽기의 독립 완료 1개를 추가했다. `performance/overhead.test.ts`, `comparison.test.ts`, `container-runner.test.ts`, `resources.test.ts`가 진입점이다. 실제 통과 여부와 원본은 [최신 진행 기록](../tasks/lookbook-import-performance/phase-3-comparison.md)을 따른다.
- Mac `1791008002386-bde1aa5b-7aae-459c-bff3-ea1db54c330c`, Linux `1791008043404-2de19dce-a8dd-4685-ae98-1e42e6b87e7d` 게이트 모두 passed. 로컬 본 54회는 48성공/6메모리 중단, 집계 valid true다. `output/lookbook-import-performance/approved-local-272a52df-4371-4b56-a7b5-fef0da5c33fd/{manifest,summary,observations}.json`과 각 회차 finished/result가 원본이다. 이는 구조 탐색이며 실제 Storage/Firestore/5쌍 채택 판정 검증은 아니다.

- `verification/lookbook-import.json`: Node 24 Worker lint/build/전체 Node 테스트/fixture corpus, 필수 ID 93개(직전76+보유바이트4/비교4/외부감독5/집계4). 실제 테스트가 참조하는 `contracts/lookbook-extraction-issue-v1.json`도 source digest 입력에 포함한다. 현재 src 기반 runner로 lib 테스트를 수집한다.
- 2026-10-03 전체 테스트 201개. `src/performance/{buffer-inventory,comparison,container-runner,comparison-report}.test.ts`는 늦은 형제 보유량·54회 정책·검토/저장 분리·OOM/도구/결과 누락·중앙값·5쌍 악화를 검사한다. [최신 Mac/Linux 게이트·정합성 검사·원본 로그](../tasks/lookbook-import-performance/phase-3-comparison.md), [직전 시즌/메모리 감독](../tasks/lookbook-import-performance/phase-3-runner.md), [재사용](../tasks/lookbook-import-performance/phase-2-reuse.md). 컨테이너 실행 준비는 54회 속도 비교·전체 제품 job lifecycle·클라우드 DB 검증과 구분한다.

## 채팅 검색·차단 목록

[최종 검증 결과·수동 QA·배포 경계](../architecture/CHAT_MESSAGE_SEARCH.md)를 본다. 단계별 phase JSON은 당시 누적 게이트이며 최종 UI 회귀는 search-toolbar.json이다.

- verification/chat-search/search-toolbar.json: 정규화·Repository·GRDB migration/삭제/cleanup·세션·fallback·visibility·이동·읽음 회귀. 최초 500후보 상한, 사용자 과거 이동 후 잔여 10개 선로딩, 유휴 무조회, 현재 순번/확보 개수, 이동/선로딩 스피너 없음, 동일 tombstone 반복 이동 방지를 포함한다.
- ChatSearchNavigationTests의 repeatedContextTombstoneDoesNotRestartAutomaticSelection은 실제 GRDB/삭제 UseCase/Presentation을 결합한다. GRDBChatDeletionSyncStoreTests는 중복/새 revision/같은 revision 정책 교정/소수점 시각을 검사한다.
- verification/blocked-users.json: BlockedUsersViewModelTests의 행별 수요 조회·프로필 실패 fallback·최신 사진/닉네임·중복 해제 억제·재시도·늦은 응답 배제 6개와 기존 visibility/avatar/config 회귀를 실행한다. 실제 메뉴·화면·해제는 사용자 수동 QA로 확인했다.
- verification/chat-search/phase-6.json: Node Unicode/writer, Firestore emulator, iOS 및 ChatSearchScaleTests의 18개 규모/분포를 실행한다. 전량 reference 비교는 테스트 드라이버가 명시적으로 계속 찾기를 반복하는 측정이다. 제품이 백그라운드에서 전량 조회한다는 뜻이 아니다.
- contracts/chat-search의 고정 fixture 25개·Unicode corpus 19,074행·매핑을 Swift/Node에서 검사한다. Socket/test/messages/messageSearchPersistence.test.js와 firestore-tests/chat-message-search.emulator.test.mjs가 서버 저장·삭제 경계를 검증한다.
- DEV 관리자 실쿼리는 로컬 전용 harness로 확인했다. 정리한 QA 자료를 다시 생성하는 스크립트·로컬 dev-live 설정은 배포/회귀 게이트에 포함하지 않는다. 인증된 앱·오프라인·계정 전환·미읽음·방 종료는 사용자/Simulator QA 증거와 구분한다.
- verification/chat-media-retention.json의 migration 필수 ID는 26번째 migration 이름으로 갱신했다. 이 변경이 미디어 전체 게이트 재실행을 의미하지 않는다.

## 채팅 텍스트 전송·키보드

- `OutPickTests/KeyboardDismissSupportTests.swift`: 실제 `UIWindow`에 설치한 공통 제스처의 delegate에 테스트 touch를 전달해 전송 버튼·내부 아이콘 제외, 텍스트 입력 보호, 배경 터치 허용을 검증한다. 실제 손가락 탭·키보드 애니메이션·서버 전송을 검증하는 테스트는 아니다.
- `verification/ios.json`: Development Simulator 빌드, 기존 환경 경계 13개와 키보드 회귀 4개를 필수 ID로 검사한다. `node tools/verification-gate/gate.mjs --project . --config verification/ios.json` 실행 결과는 `output/verification/<실행 ID>/summary.json`에 남는다.
- 수동 QA: 룩북 탭 방문 후 채팅방에서 키보드를 열고 일반 텍스트를 한 번 탭으로 전송 → 메시지 한 개 표시·입력 비움·키보드 유지 → 다음 텍스트 연속 전송 → 대화 배경 탭으로 키보드 닫기. 아래 사용자 확인으로 이 흐름의 실기기 QA를 완료했다. 추가 회귀 후보인 키보드가 닫힌 상태의 전송, 빈 입력의 전송 비활성, 첨부 버튼·메시지 셀 액션은 이번 사용자 확인 범위에 포함하지 않는다.
- 2026-10-01 검증: 수정 전 `1790859690252-bf6b5d95-294c-4575-afac-eecbb1043040`에서 버튼·아이콘 제외 2개 실패, 입력 보호·배경 허용·환경 경계 15개 통과. 수정 후 `1790859774634-bc225cd5-b539-4d19-92aa-b64688f6f611`에서 필수 17개 모두 통과, 실패·차단 없음. 검사 상태는 HEAD `00730d4d` + 작업 트리, 입력 digest `b3ea0bda55c2614aaed60984173456dddc27517cb218b99a389993ab2f1ba910`. 각 실행의 `output/verification/<실행 ID>/summary.json`과 `app-runtime-test/{stdout.log,stderr.log}`가 원본 근거다. 초기 테스트의 시스템 제스처 선택 오류는 보정했고 그때의 2회 결과는 제품 결함 재현 근거로 사용하지 않는다. 최종 게이트 뒤 iPhone 17 Pro/iOS 26.2 Simulator에 서명한 일반 DEV 앱을 빌드·설치·실행하고 로그인 화면을 확인했다. 로그인 및 실제 채팅 전송 QA는 수행하지 않았고 실기기 앱은 변경하지 않았다.

- iPhone 14 QA 완료(2026-10-01): 위 Simulator 검증 이후 현재 수정 코드를 실기기용으로 빌드 성공하고 기존 `GayoonKim.OutPick.dev` 앱 위에 업데이트 설치·일반 실행했다. 앱 제거·데이터 정리·QA 환경변수 사용 없음. 근거는 `/private/tmp/outpick-chat-keyboard-device-build.log`, `outpick-chat-keyboard-device-{install,launch}.json`의 success다. 사용자가 룩북 탭을 거친 채팅방 진입, 한 번 탭으로 메시지 한 개 전송·입력 비움·키보드 유지, 연속 전송, 대화 영역 탭으로 키보드 닫기까지 모두 확인하고 문제없음을 보고했다. 이는 사용자 수동 QA 결과이며 자동 테스트 결과와 구분한다. 코드 추가 변경 없이 이번 수정·검증을 완료했다.

## 채팅 미디어 7일 만료 검증

[최종 결과·실기기 범위](../architecture/CHAT_MEDIA_RETENTION.md), [게이트 실행 기준](../architecture/PROGRAMMATIC_VERIFICATION.md).

- 공용 원본·reporter·자체 검사·설치: `tools/verification-gate/{gate.mjs,node-reporter.mjs,gate.test.mjs,install.mjs}`. [설명](../../../tools/verification-gate/README.md)과 [환경 준비](../../../verification/README.md)를 따른다. 각 Node runner가 JSONL을 연결하고 Xcode는 xcresult를 수집한다. 종료 코드 0/1/2는 통과/실패/차단이다.
- `verification/gate.json`: 실행기 자체 검사, Firebase 빌드 설정, Socket 정적 검사·전송 확정/답장/이벤트 계약.
- `verification/functions.json`: lint·clean build·단위 테스트. `retentionContracts/Storage.test.ts`, `videoPlaybackContracts/Functions/Service.test.ts`, 구형 확정 거부·export 계약을 포함한다.
- `verification/firestore.json`: Rules·Storage 거절과 에뮬레이터 transaction. `chat-moderation.emulator.test.mjs`는 만료 정리와 메시지 삭제·방 종료·탈퇴 경합, `moderation-reports.emulator.test.mjs`는 증거 보류·부분 실패 재시도를 검사한다.
- `verification/ios.json`: Development/Production 환경 경계 13개와 키보드 터치 경계 4개. `verification/chat-media-retention.json`: 28 suite, 필수 ID 91개, 만료/캐시/화면/영상/Photos/QA 제어 회귀.
- `ChatMediaExpiryCacheIndexTests`, `ChatAttachmentImageServiceTests`, `ChatOriginalFileStoreTests`, `ImageCacheRevisionTests`: 계정·generation·기한, hit/write/lease·늦은 응답 정리.
- `ChatMediaSignedDownloadTests`, `ChatVideoPlaybackSessionTests`: 권한·HTTP 만료 분류, 갱신 횟수와 위치/상태 복원, AVKit 조작 경계·만료 화면의 다운로드/저장 0회.
- `ImageViewerOriginalFileTests`, `PhotoLibrarySaverBoundaryTests`, `VideoSaveLifetimeTests`: 만료·닫힘·Photos 권한 대기/제출 경계, 완료 전 파일 수명과 늦은 UI 차단.
- `ChatMediaBoundaryQATests` 8개와 `ChatSignedURLHTTPQATests`/`ChatSignedURLQAHTTPClientTests`: DEV·지정 객체 제한, 보류·취소·HTTP 관측 경계. 실제 장치 조작 검증과 구분한다.
- 실제 Simulator Photos 검사는 photos-add 사전 권한이 필요하다. skip/0개 실행은 통과가 아니다. 게이트 후 로그인 QA용 DEV 앱은 서명 빌드로 복구한다.

- `PhotoLibraryOriginalIntegrationTests`는 `photos-add` 권한이 사전 부여된 Simulator에서 합성 JPEG를 실제 Photos에 저장한다. 권한이 없거나 실제 기기이면 skip하므로 실제 executed/skip 결과를 확인해야 한다. `.bin` 직접 제출3302 실패를 재현했고, `PhotoLibraryPreparedResource`의 올바른 확장자 임시 사본으로 같은 제품 API를 검증한다. Simulator Photos에는 합성 작은 테스트 이미지가 생성될 수 있다.

- `PhotoLibraryOriginalResourceTests`: `.bin` JPEG·확장자 없는 GIF 2frame·확장자가 잘못된 PNG의 실제 Photos 타입/파일명, 바이트·frame 불변, 잘못된 이미지 제출 전 거부. 실제 Photos 저장 검증은 실기기 QA와 구분한다. [기록](../tasks/chat-media-first-view-loading/original-media-results.md).

- 원본 Phase3·4: `ChatOriginalFileStoreTests`의 fake SDK barrier로 공유 취소/마지막 취소 permit·임시 파일 유지/계정/세대/삭제/재시작/용량과 pin 검증. `ImageViewerOriginalFileTests`는 실제 UIKit 뷰어의 원본 저장·실패 재시도·닫기 후 차단·±1 수요를 검증한다. `ChatMediaPreviewServicesTests`는 스트리밍 시작의 전체 다운로드0 및 저장/캐시 lease를 검증한다. 실행 근거·실기기 미검증 항목은 [원본 결과](../tasks/chat-media-first-view-loading/original-media-results.md).

- 예측선로딩회귀30개통과(`/private/tmp/outpick-predictive-prefetch-tests.log`): policy4/viewport10/surface3/directdisk3/files10. near/도착24상한과중간전구간제외·빠른이탈유예없음 신규검증. 기기체감은별도QA.

- direct disk 회귀47개통과(XCTest13+SwiftTesting34), `/private/tmp/outpick-direct-disk-tests.log`. 기기파일시스템/체감검증 `/private/tmp/outpick-direct-disk-device.log` 진행중.

- `ImageDirectDiskDecodingTests`: hardlink의교체/삭제중내용보호와해제,Data예산/files슬롯이차도direct캐시진행,기존Data복구3개. `/private/tmp/outpick-direct-disk-tests.log` 공용회귀, 실제기기파일시스템/체감비교는후속QA.

- 1GiB/LRU회귀: 공용57개통과 및 최종집중5개통과(고유58), `/private/tmp/outpick-display-budget-{tests,lru-final-tests}.log`. 기기QA진행 `/private/tmp/outpick-display-budget-device.log`, 실제압박동작검증은자동주입시험과구분.

- `ImageLRUMemoryStoreTests`: LRU조회/교체/삭제·압박해제/재유입상한/정상복귀·단일초과미보관·wrapper NSCache중복보관방지·디스크최근접근파일보호. `/private/tmp/outpick-display-budget-tests.log` 회귀, 실제1GiB QA와시스템경고실측은별도.

- ③ Phase2 통합89개 통과(XCTest22+SwiftTesting67/7suite), `/private/tmp/outpick-cache-reuse-phase2-regression.log`. 기기비교QA 대기이며 중간16/46개와 중복합산하지 않음.

- `ImageFileDownloadSchedulingTests` 추가3개: 메모리퇴거+pending 재조회 중복전송 방지/다른키 독립 조회, 로컬저장 표시준비 후 독립쓰기, 준비 중 삭제에 따른 늦은 저장 차단. Phase2 통합 회귀 `/private/tmp/outpick-cache-reuse-phase2-regression.log`.

- `ChatMediaViewportControllerTests.testMemoryHitOnReentryPublishesImageWithoutLoadingOrAsyncRequest`: 방 재진입 memory hit의 동기 image·loading0·async 요청0. viewport/service/surface 회귀 `/private/tmp/outpick-cache-reuse-immediate-tests.log`, 실행 결과는③ 기록 참고.

- ③ Phase1 계측 회귀25개 통과(XCTest15+SwiftTesting10), 실기기 기준선 QA 진행. `/private/tmp/outpick-cache-reuse-instrumentation-tests.log`; [현재 결과](../tasks/chat-media-first-view-loading/cache-reuse-results.md).

- **2026-09-23 ③ 계측:** `ImageCacheMetricsTests.cacheIdentityConnectsResourceStorageAndEvictedFilenameWithoutRawPath`가 resource/storage/file hash 연결과 원문 비노출을 검증한다. disabled 테스트에 linkCacheKey 무동작 검증 포함. metrics·file scheduling·revision·viewport 회귀 결과는 [실행 기록](../tasks/chat-media-first-view-loading/cache-reuse-results.md).

- SDK 취소 회귀: `OutPickTests/FirebaseDownloadCancellationRegressionTests.swift`는 Firebase12.17.0 실제 SDK의 cancel→늦은 enqueue 보호를 고유 fake bucket/HTTP testBlock으로 확인한다. 테스트 전용 `@testable FirebaseStorage` 사용, 운영 전송 구현에 SDK private API 추가 없음. 관련87개 회귀 통과, 구12.3.0 비교/실기기최종QA는 [진행 기록](../tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 2026-09-22 다운로드② 저장 실패 회귀: `OutPickTests/ImageFileDownloadSchedulingTests.swift`의 `testDiskWriteFailurePreservesDisplayAndReleasesFileThenRecovers`. 실제 캐시 쓰기 실패에서 표시/메모리 유지·임시 파일/permit 반환·다음 저장 복구 확인. iPhone14에서 suite7개 실패0. [실행 기록](../tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 다운로드② 실제 기기: 기존 baseline의 file body parent와 network span을 연결해 최대6개 동시 전송 확인. 전용 SDK fixture 없이 사용자 기존 캐시 스크롤을 측정했고 종료 시 network/files/decode/io active/waiting0. 취소 callback/RSS/동일 cold 비교는 별도 미검증. [결과](../tasks/chat-media-first-view-loading/download-bottleneck-results.md).

- 다운로드② 실행: `ImageFileDownloadSchedulingTests`6개는 실제 processor/pipeline와 독립 cache·제어 transport로 다운로드/쓰기 분리, 공용 파일 입장, 표시 선반환, 취소·오류 정리를 검증한다. 기존 코드 실패 재현 후 XCTest24＋Swift Testing51=75개 통과. 실SDK/실기기 증거는 [결과](../tasks/chat-media-first-view-loading/download-bottleneck-results.md)에서 구분한다.

- 다운로드② 테스트 설계(미작성/미실행): 예정 `ImageFileDownloadSchedulingTests`에서 A 전송 hold 중 B 시작/캐시 쓰기 진행, 전역 network/files 상한, SDK 종료 전 취소 permit 보존, 저장까지 파일 보유·정리를 검증한다. 기존 resource/coordinator/revision 및 서비스/viewport 회귀와의 경계·실기기 비교는 [세부 계획](../tasks/chat-media-first-view-loading/download-bottleneck-plan.md)에 정리했다.

- 회전 지연 회귀: `ChatMediaViewportSurfaceTests.testMediaCellResizesWithoutReconfigureAndKeepsRenderedImage`는 실제1장/30장 메시지 셀을390→844→390pt로 바꾸며 reconfigure 없는 크기 갱신과 UIImage 보존을 검증한다. 수정 전4assertion 실패, 비율 제약 수정 후 Surface3개/Continuity5개＋기기 회전 UI1개 재실행 통과. 누적 단위/컴포넌트95개·UI3개, 체감 지연은 사용자 QA로 구분. [근거](../tasks/chat-media-first-view-loading/qa-results.md).

- 채팅 미디어 수명 후속: `ChatMediaViewportDevelopmentUITests.testKeyboardSettingsSearchAndCancelledBackRestoreMedia` 및 `testPhotoPickerCancellationAndRotationRestoreMedia` 실행 통과. 회전 직후 XCTest `isHittable` 오류를 피하고 collection viewport 교차 셀의 loaded 상태를 검사한다. `ChatRoomRouteLifecycleStateTests`5개 통과, 누적 단위/컴포넌트94개·UI3개. 가로 캡처 이상은 실제 화면 확인 전까지 시각 통과로 분류하지 않는다. [실행 기록](../tasks/chat-media-first-view-loading/qa-results.md).

- 채팅 미디어① 실행 갱신: iPhone14 단위/컴포넌트89개＋실제 방 UI1개 통과. `ChatMediaViewportSurfaceTests`의 mixed-media thumbnail-only/카드56pt 좌표, controller의 transport 취소·삭제 후 stale 결과 경계를 추가했다. `ChatMediaViewportDevelopmentUITests`는 `TEST_RUNNER_OUTPICK_MEDIA_VIEWPORT_QA=1`을 xcodebuild에 전달해 명시 실행하며 기존 방 읽기/스크롤/확대/복귀만 수행한다. 신규 전송·SDK 오류·cold 성능은 이 결과로 대체하지 않는다. [로그와 잔여 QA](../tasks/chat-media-first-view-loading/qa-results.md). 아래 실행 보류는 구현 직후 기록이다.

- 채팅 미디어 ①: `ChatMediaViewportPolicyTests`는 visible 무상한/offscreen 고유24/방향을, `ChatMediaViewportControllerTests`는 실패 재등장·방 세션·유예·늦은 응답 및 실제 ImageLoadCoordinator 합류/다른 소비자 보존을 검증한다. `ChatImagePreviewContinuityTests`는 표시 연속성·재사용·30장 개별 frame·원본 fallback 차단을 다룬다. `ImageViewerPagePolicyTests`의 본문 preview 경로 기대값을 thumbnail-only로 변경했다. 삭제된 ChatVideoAssetService 전용 테스트는 제거했다. 자동 테스트 실행은 보류이며 빌드와 QA 결과는 [진행](../tasks/chat-media-first-view-loading/progress.md)에 구분한다.

- PR 리뷰 회귀: `AvatarNestedViewportTests.testSwiftUIViewportPrefetchesChangedPathWithoutScrolling`은 실제 SwiftUI viewport modifier와 spy를 연결해, 같은 행/좌표에서 nil→첫 사진→변경 사진으로 바뀔 때 선로딩 요청을 검증한다. 수정 전 두 경로 모두 실패한 재현과 수정 후 결과는 [리뷰 기록](../tasks/avatar-image-loading/review.md) 참조.

- 잔여QA 최종 iPhone14 실행: AvatarRouteContractTests3개·AvatarNestedViewportTests1개(XCTest4)와 AvatarImageServiceTests12개(SwiftTesting) 통과. 실제컴포넌트/가짜transport·독립cache로 정책/원본only/중첩요청/연속캐시를 검증하고 전용폴더잔여0 확인. 기기로그 `/private/tmp/outpick-avatar-remaining-device-tests.log`. 기존112개회귀와중복되므로합산금지, [검증방법·한계](../tasks/avatar-image-loading/progress/phase-5.md).

- `AvatarNestedViewportTests.swift`는 실제 ParticipantsSectionParticipantCell 50명과 AvatarCollectionViewport를 UIKit에 올려 최초 요청0, 상단/하단/중간의 화면·선로딩 범위/고유24 제한을 spy로 계측한다. `AvatarImageServiceTests.continuousAvatarViewsPromoteMemoryThenReuseDiskWithoutAnotherFetch`는 실제 AvatarImageView 두 정책과 공용 pipeline을 사용해 메모리→디스크 승격, 같은 프로세스의 메모리 제거 후 디스크→댓글 재사용을 검증한다. test 전용 디스크/가짜 전송으로 실제 서버·계정과 분리한다.

- `AvatarRouteContractTests.swift`: 실제 상세 화면 factory·UIKit 아바타 표시와 spy를 통해 memoryOnly/memoryAndDisk 전달을 검증한다. 참여 상태를 false→true→false로 바꿀 때 같은 scope의 read/load/prefetch 정책과 원본 위임도 확인한다. 상위 탭/화면 이동 전체를 자동 실행한 테스트는 아니며 DI 코드 대조와 함께 사용한다.

- 2026-09-21 정상 소스 최종 회귀: 아바타 서비스/세션/표시/viewport/관찰, 공용 store/revision/coordinator/resource, 룩북 HTTP/viewport, 프로필 mutation, viewer page/state의 Swift Testing102개/13suite+XCTest10개 통과. `/private/tmp/outpick-avatar-final-regression-{build,tests}.log`, [Phase5](../tasks/avatar-image-loading/progress/phase-5.md). 전체 route spy·원본only 자동계약과 실기기 세부 미검증은 [체크리스트](../tasks/avatar-image-loading/qa-checklist.md)에서 구분한다.

- 프로필 원본 제한: `AvatarImageServiceTests.originalTimeoutAllowsImmediateRetryAndRejectsLateTransport`, `closingOriginalBeforeDeadlineRemainsCancellation`, `thumbnailDoesNotStartOriginalDeadline`. 제어 가능한 타이머/전송 gate로 시간 초과·즉시 재시도·화면 취소·썸네일 범위 제외 확인. 기존 `ImageViewerStateTests`의 preview 유지·retry 교체·늦은 결과 차단을 함께 실행한다.

- 즉시 아바타 메모리 조회: `AvatarImageSessionTests.immediateReadIsBlockedThroughoutSessionClear`/`immediateReadCannotRestoreRetiredPhotoDuringInvalidation`, `AvatarImageServiceTests.immediateReadSharesCacheWithoutStoringAndHonorsRemoval`, `AvatarImagePresentationStateTests.memoryImageIsAvailableBeforeAsyncLoaderAndCannotSurviveIdentityChange`. 가짜 비동기 gate로 정리 중 반환 차단을 검증하고, 공용 캐시 동일 이미지·disk 승격·identity 변경 후 늦은 결과 차단을 확인한다.

- 아바타 Phase5: `AvatarViewportPrefetchTests`의 실패 선행 조건은 `AvatarImagePrefetchController.loadingPaths`로 확인한다. 고정 yield 횟수는 작업 완료를 보장하지 않으므로 실패 이후 이벤트 테스트의 완료 대기로 사용하지 않는다. [통합 회귀·실기기 QA](../tasks/avatar-image-loading/progress/phase-5.md).

- 아바타 Phase4: `AvatarViewportPrefetchTests.swift`는 방향·고유24·중복 경로 정책·제어 clock299/300ms·빠른 복귀·새 visible 이벤트·저장 정책 승격·종료 경합을 검증한다. AvatarImagePresentationStateTests에 메시지 token/명시 refresh, AvatarImageServiceTests에 unavailable 서버 요청 억제/해제를 추가했다. [실행 증거](../tasks/avatar-image-loading/progress/phase-4.md).

- 아바타 Phase3: `AvatarImagePresentationStateTests.swift`의 동일 identity·늦은 성공/실패·reset/재등장 경합, `ImageViewerStateTests.swift`의 transient 종료/로컬 provider 우회 차단/취소된 disappearance, `AvatarImageServiceTests.swift`의 오류 분류. [실행 결과·시각 QA 잔여](../tasks/avatar-image-loading/progress/phase-3.md).

- 아바타 Phase2 회귀: `AvatarImageServiceTests.swift`, `AvatarImageSessionTests.swift`, `AvatarObservingPublicProfileRepositoryTests.swift`, `UpdatePublicProfileUseCaseTests.swift`. 사용처 승격·원본 비저장·세션 전환·늦은 성공/실패·authoritative nil·서버 변경 실패 보존·추가 조회 없는 관찰을 확인한다. [검증 증거와 실제 사진 비교](../tasks/avatar-image-loading/progress/phase-2.md).

- 아바타 공용 저장 정책: `OutPickTests/ImageCacheStorePolicyTests.swift` — memory-only→disk 승격, 기존 disk 읽기, transient 캐시 우회·합류·영속 요청 분리·취소 회수, 지연 인코딩 단일화·무효화·재시도·출력 한도. [실행 명령과 결과](../tasks/avatar-image-loading/progress/phase-1.md). JPEG/PNG 제품 형식 비교나 실제 화면 QA를 대신하지 않는다.

- PR 리뷰 보완: `LookbookHTTPImageCacheTests.diskBodyWaitsForDecodeBudgetBeforeReadingAndHandlesEviction`은 용량 예약 전 디스크 본문 보유를 방지한다. 예약 대기 중 파일 제거를 제어하며 기존 코드 실패를 확인했다. [공개 QA 요약](../qa-image-loading-concurrency-2026-09-16.md).

- 이미지 Phase5 최종 완료(2026-09-16): 기존 자동90개/UI1개 통과 근거와 iPhone14 Phase0/최신 통합 스크롤 CPU·메모리·OutPick hitch 비교를 [최종 검증 기록](../tasks/image-loading-stage-concurrency/phase-5-validation.md)에 모았다. 사용자가 측정 한계를 수용하고 현 설정을 채택했다. 이번 마무리는 코드 변경 없이 계측/문서 갱신으로 진행해 자동 테스트를 중복 실행하지 않았다.

- 이미지 Phase 5 집중 회귀: `ImageCacheMetricsTests`/`ImageLoadCoordinatorTests`/`ImageCacheRevisionTests`/`ImagePipelineResourcesTests`/`LookbookHTTPImageCacheTests`/`LookbookViewportPrefetchTests`/룩북 세 VM/`ChatAttachmentImageServiceTests`에서 64개, 관리자 preview·좋아요/관심 목록 26개 통과. `OutPickUITests/LookbookSmokeUITests.testImageRetryDoesNotOpenCardDetail`은 `LookbookUITestFixtureRepositoryProvider`의 `--uitest-lookbook-image-fail-once`를 사용해 브랜드/시즌/포스트 재시도 터치·복구를 확인했고 1개 통과. 실행 명령/로그·제외된 실서버와 CPU/RSS는 [Phase 5](../tasks/image-loading-stage-concurrency/phase-5-validation.md).

- 이미지 Phase 4: `OutPickTests/LookbookViewportPrefetchTests.swift`는 방향 전환·24장 cap·동일 수요 중복 방지를, `LookbookHomeViewModelInterestTests.swift`/`BrandDetailViewModelTests.swift`는 이미지 요청 대기 중 목록 선표시를, `SeasonDetailViewModelTests.swift`는 viewport 수요만 선예약하고 append 전체 예약을 피하는지를 확인한다. 컴파일·실행 상태는 [진행](../tasks/image-loading-stage-concurrency/progress.md) 참조. 실제 프리패치 거리/취소율·실패 버튼 터치는 iPhone QA 대상.


- 이미지 Phase 3: `OutPickTests/LookbookHTTPImageCacheTests.swift` 12개는 fake HTTP로 fresh network0, stale 304, no-cache/no-store, 404 제거, 동시 검증1회, 일시 오류 cooldown, 디스크 metadata 재시작 복원, validator 없는 동일 본문, Referer/maxBytes 키 분리, 표시/프리패치 후보 순서, 200 교체, Age를 확인하도록 작성. 실제 실행 여부·빌드 결과는 [진행](../tasks/image-loading-stage-concurrency/progress.md) 참조. 실서버 헤더·화면 교체는 별도 QA.


- 2026-09-16 이미지 Phase2 QA: 캐시/자원/취소/계측26개 함수(27시나리오) iPhone14 통과. PNG fixture 배율 의존3개 실패를 format.scale=1로 고친 뒤 재검증. [실기기 기록](../tasks/image-loading-stage-concurrency/phase-2-qa.md). 초기값 조정은 아모멘토 실측 후 판단.

- 이미지 Phase 2: OutPickTests/ImagePipelineResourcesTests.swift 9개(단계/바이트 상한, 취소·승격, 저장 정체 중 반환, 큰 파일 정리, 실패 회수, 네트워크 전 backpressure). ImageLoadCoordinatorTests 저장 승격은 persistence flush 후 확인. 앱·테스트 컴파일 확인, 실행은 사용자 미요청으로 보류. [최종 증거·수동 QA](../tasks/image-loading-stage-concurrency/progress.md).

- 이미지 로딩 Phase 1: `OutPickTests/ImageLoadCoordinatorTests.swift`(인자 포함9개) + `ImageCacheRevisionTests.swift`(5개). 원자 통합·소비자 취소·이전 job 완료·store/remove/clear 경합·진행 저장 승격·maxBytes 분리·기존 디스크 cache-only 호환. **14개 작성/실행 미수행**, 최종 Development generic Simulator `build-for-testing` 통과(`/private/tmp/outpick-image-phase1-verified-build.log`). 컴파일 성공을 자동 회귀 통과로 해석하지 않는다. [구현](../tasks/image-loading-stage-concurrency/phase-1-implementation.md).

- 이미지 로딩 Phase 0: `OutPickTests/ImageCacheMetricsTests.swift` — 비활성 no-op, 중복 end/보유 바이트, 동시 span 집계, 요청 결과·오류·TaskLocal 복원·키 hash 검증4개 작성. 테스트 실행은 사용자 요청이 없어 보류. 앱 build/테스트 컴파일/실측 결과는 [진행](../tasks/image-loading-stage-concurrency/progress.md), 계측 해석은 [사용법](../tasks/image-loading-stage-concurrency/baseline-instrumentation.md) 참조.

- 최종 조합 Development 수동QA(2026-09-14):3장 smoke→70장30/30/10(seq58~60)→네트워크 차단 실패버블 재시도 성공(seq61/2장). 사용자스크롤/입력/재입장 확인. 삭제버튼 표시는 확인했으나 실제삭제 수동 실행은 주장하지 않는다. 자동41개/124개 및 [증거·한계](../tasks/chat-media-concurrency-qa-rollout/progress.md) 참조.

- 2026-09-14 최종 동시성 로컬 검증: `ChatMediaSelectionUseCaseTests` 설정 누락/잘못된 값의 기본 정책 유지·DEBUG/dev opt-in·준비 중 부모 취소의 임시 파일 제거/원본 보존을 추가했다. 기존70장 분할/순서·실패복원, SourceAcquisition/UploadUseCase/UploadTurnQueue와 함께 iPhone14 Development41개/4 suites 통과. `/private/tmp/outpick-concurrency-final-ios-tests.xcresult`.
- Socket `test/media/directMediaUploadService.test.js`: 입력 크기별 전체 조회·전체60개 서명·역순 완료 정렬·서명/조회 일부 실패 drain·서명 도중 취소·전체 취소 삭제 일부 실패/지연정리·ready 파일 보존. `test/media/boundedMap.test.js`:73개 전체 실행과 빈 대상. check 및 전체124개 통과, `/private/tmp/outpick-concurrency-final-socket-tests.log`. 최종 Development 결합 실측은 별도 대기.

- 2026-09-11 PR 최종 집중 회귀: gap policy·page loader·save queue·VM message action·deletion store·목록 삭제 총 48개/6 suites 통과. 로그 `/private/tmp/outpick-cache-sync-pr-review-tests.log`. 초기 99개 실행·후속 60,000개 저장·실제 서버 QA와 중복 합산하지 않는다.

- PR 리뷰 경합 보완: `socketEventAtEmptyReconciliationExitIsAppliedBeforeReturning`은 head=cursor인 동기화의 cleanup 조회를 멈추고 새 Socket 삭제를 접수한 뒤, 이벤트 호출이 반환하기 전에 cursor가 전진하는지 검증한다. `handleSocketEvent`는 완료된 공유 작업의 cursor가 이벤트 revision에 못 미치면 해당 이벤트를 다시 처리한다.

- 목록 삭제 수정 최종 검증(2026-09-11): `RoomListsViewModelDeletionTests` 4개(실제 GRDB stale 원문 정리·로컬 오류 fallback 차단·복귀·역순 응답)와 deletion store 9개·profile overlay 2개, 총 15개 통과. 실행 로그 `/private/tmp/outpick-list-deletion-fix-tests.log`, 시뮬레이터 두 계정 표시 검증은 task progress 참조.

- `RoomListsViewModelDeletionTests`: 복귀 즉시 이전 원문 제거와 로컬 조회 완료 후 삭제 표시, 역순으로 완료한 오래된 조회의 원문 복원 차단을 continuation fake로 검증한다. GRDB 삭제 마커·답장 정리와 프로필 보존은 `GRDBChatDeletionSyncStoreTests`, `RoomPreviewProfileOverlayTests`를 함께 실행한다.

- 삭제 동기화 경합 QA: `GRDBChatDeletionSyncStoreTests.socketRevisionArrivingDuringPageFetchIsIncludedInSameReconciliation`은 delta 조회 gate 중 Socket revision 2 접수 후 cursor·tombstone·조회 횟수를 검증한다. `ChatDeletionSyncUseCase.pendingRevisionForDebug`로 고정 sleep 없이 접수 완료를 확인한다. 2026-09-11 suite 9개 통과. 실제 계정 간 전파는 task progress에서 별도로 추적한다.

- 실제 캐시 통합 QA 후속: `ChatRoomViewModelMessageActionTests`의 stale generation·partial retry 원본 범위2개 추가, WindowStore와32개 회귀 통과. `GRDBChatMessageAdmissionTests.sustainedBurstsKeepNewestCacheContiguousAcrossPruning`은6만개/60회 저장 후 매회 최신seq·3300이하·연속성 검사, 약92.5초에 통과. 실제 서버250개 fixture 및 LLDB Firestore 연결 중단/복구로 retry버튼·스크롤 기준점 검증. 세부 실행과 남은 두 기기 로그인은 task progress 참조.

- 캐시 후속 QA(2026-09-11): PageLoader의 실패 범위만 재조회·오프라인/잘못된 방 응답·실제 병렬 중첩, SaveQueue의 중복100회·저장 중 계정 무효화, GRDBAdmission의 SQLite 3000개 burst 및 시간/resident 계측을 추가했다. 진행 결과와 로그인 의존 UI 검증은 `tasks/chat-message-cache-sync/progress.md` 참조.

- 채팅 캐시 동기화: `ChatMessageCacheGapPolicyTests`(범위·혼합 복구·병합), `ChatMessagePageLoaderTests`(부분 실패·재조회·식별자 교정), `ChatMessageSaveQueueTests`(즉시5회·1000개 직렬 저장·방 session), `GRDB/GRDBChatMessageAdmissionTests`(삭제 transaction·무효 session·교정), `ChatOutgoingOutboxUseCaseTests`(확정 seq와 저장 성공 후 정리). 기존 읽음/최신창/Socket 순서/방 종료/VM을 포함한 집중 회귀 99개/13 suites 통과. 전체 앱 테스트나 실기기 성능 측정을 의미하지 않는다. 실행 기록은 `tasks/chat-message-cache-sync/progress.md`.

- 공용 확대 화면: `OutPickTests/ImageViewerStateTests.swift`의 제어 가능한 loader/saver로 local-only·저장 중복/실패 복구·페이지 이동 중 저장 대상·실패 미리보기 보존·재시도/닫힘 후 늦은 응답 차단 검증. 컨트롤 렌더링 attachment 포함. 기존 `ImageViewerPagePolicyTests`로 GIF/페이지 계약 회귀. 결과는 `tasks/shared-image-viewer-editorial/implementation-plan.md`.

- 사진300MB·실패 원본: `ChatMediaSelectionChunkerTests`의10진300MB/30장 경계, `ChatDirectMediaPreparationTests`의300MB 초과 조기 거부·고밀도 썸네일4MiB 초과 허용 및 영상4MiB 유지, `ChatMediaSelectionUseCaseTests`의부분 실패 원본 보존/재시도/삭제/child 저장 실패/31장실패30+1 복원. Socket `test/media/directMediaUploadService.test.js`의본/썸네일 경계·본 파일만 합산·영상 기준 유지. 실행 결과는 `tasks/chat-media-preview-continuity/photo-size-failure-recovery.md`.

- `OutPickTests/ChatImagePreviewContinuityTests.swift`: 안정적 첨부 ID, 서버 확정 후 기존 이미지/레이아웃 유지·추가 로딩 금지, 로컬 로딩 성공 유지/실패 후 최신 경로 복구, 같은 ID로 재사용된 셀의 취소 요청 응답 차단, 다른 메시지 이미지 제거, 목록 초기화·재진입 로딩을 제어 가능한 loader/continuation으로 검증한다. 실행 상태와 수동 QA는 `tasks/chat-media-preview-continuity/implementation.md` 참조.

- 2026-09-10 머지 전 최종 실행: 미디어 Swift 회귀62/62(시뮬레이터), Storage 규칙5/5(로컬 Firestore/Storage Emulator), Socket113/113, Functions262/262, worker22/22 통과. Storage suite는 계약2/3 각각 확정 전 읽기 차단·SDK write 차단·확정/비노출 읽기를 검증한다. 성능 synthetic 테스트는 환경 변수 opt-in이며 이번 회귀에 실행하지 않았다.

- 미디어 PR 최종 검증: Socket 전체113/113, Functions 전체262/262, worker22/22. iPhone 기존 직접 업로드52개+파일 준비4개(중복 포함), 실제3장/70장 전송 확인. PR 리뷰에서 uploader 등록 전 취소 회귀를 추가했으며 최종 Swift 실행 결과는 PR 설명을 참조한다. Animation Hitches는 저장/export 미완료로 성능 지표에 사용하지 않는다.

- `OutPickTests/ChatMediaForegroundUploaderTests.swift`: 실제 URLSession 업로더의 동시 최초 업로드 30개가 모두 완료되는지 URLProtocol fake로 검증. Development 실전 QA에서 발견한 lazy 세션 초기화/taskIdentifier 충돌 회귀.

- 직접 업로드: `OutPickTests/ChatDirectMediaPreparationTests.swift`는 원해상도 본 파일/썸네일, GIF 메타데이터 제거, 바이트 진행률을 검증한다. `ChatMediaUploadUseCaseTests.filesInsideBatchRunAtMostFourAtOnceBeforeFinalize`는9장18파일 PUT4 회귀다.
- 서버 계약3: `Socket/test/media/directMediaUploadService.test.js`의30장60파일·누락썸네일·중복seq·강퇴/제재/취소·tombstone·metadata 불일치. `functions/src/chat/media/directUploadCleanup.test.ts`의만료전금지·manifest범위·재정리·ready보호. 실제 signed PUT/Storage rule QA는 Development 전환 때 확인한다.

- 선택 순서 사전등록: `ChatMediaUploadTurnQueueTests.registeredSelectionOrderWinsOverTaskArrivalOrder`는 마지막10장 Task가 먼저 도착해도 등록된30/30/10 순서를 지키는지 확인한다. `removingUnstartedRegisteredBatchDoesNotBlockFollowingBatch`는 실행 전 제거한 등록 항목이 뒤를 막지 않는지 검증한다.

- 순차 묶음 회귀: `ChatMediaUploadUseCaseTests.nextBatchAndManualRetryWaitForExplicitTerminalRelease`는 queued/일반실패 이후 명시 반환 전 다음 예약 금지와 재시도 맨뒤를 확인한다. `filesInsideBatchRunAtMostFourAtOnceBeforeFinalize`는 gate uploader로 동시4 상한과 전체PUT 후finalize를 확인한다. `ChatMediaUploadProgressViewTests.testWaitingReplacesSpinnerWithStaticCountAndResetsOnReuse`는 회전제거·장수·전송전환·reuse 검증이다. 기존 TurnQueue 취소/FIFO, SelectionUseCase70장30/30/10·부분정리, PendingStore 상태 및 SourceAcquisition중복콜백도 함께 실행한다.

- 사진 원본 provider callback 경합: `OutPickTests/ChatMediaSourceAcquisitionTests.swift`는 실제 acquire경로에 파일provider callback을 주입해 오류뒤취소/중복성공뒤오류/동시16오류가 continuation을중복완료하지않고첫결과를보존하는지검증한다. 기존 `ChatMediaSelectionUseCaseTests`의 전체확보/실패부분정리도함께확인한다.

- 이미지 dispatcher 완료 barrier: `functions/src/chat/media/dispatcher.test.ts`는 실제 handler에서 완료 gate 이전 HTTP응답이 없음을 확인한다. `readyService.test.ts`는 publish/slot반환 후 즉시 next claim, Firestore 이벤트 선행 멱등성, manifest 누락, stale lease, 취소를 검증한다. fake Firestore 기반이며 실제 Cloud Tasks 연속70장 QA로429가 없어졌는지 별도 확인한다.

- finalize/worker 병렬 회귀: `Socket/test/media/mediaUploadService.test.js`, `tools/chat-media-processing-worker/src/{boundedMap,cloudJob.parallel}.test.ts`, `OutPickTests/ChatMediaUploadUseCaseTests.swift`. 누락 재개·조회 수·순서/동시성·실패 drain·generation·변환 중 취소를 확인하며 성능 최적값은 실제 Development QA로 별도 결정한다.

## 미디어 제한 병렬 전송 회귀

- 정상 앱 전제 QA: `OutPickUITests/ChatMediaDevelopmentSmokeUITests.swift`가 실제 Development 세션의 main 화면과 실패 화면 부재·screenshot을 확인한다. `ChatMediaDevicePerformanceTests`도 실제 main 진입을 매 회차 선행 조건으로 확인한다. Debug 인증 구성 + 명령별 컴파일 최적화를 사용하며 fake UI와 Release entitlements override 조합을 사용하지 않는다.

- 실기기 성능 QA: `OutPickTests/ChatMediaDevicePerformanceTests.swift`. 정상 Development-Debug 인증 구성에 명령별 `SWIFT_OPTIMIZATION_LEVEL=-O`, `GCC_OPTIMIZATION_LEVEL=s`를 적용하고 `OUTPICK_MEDIA_DEVICE_BENCHMARK=1`로 opt-in한다. `testRealMainScreenBeforeMediaQA`는 실제 main 진입·캡처, `testImagePreparationSweep`은 준비 폭 1/2/3/4와 JSON·전후 화면을 기록한다. synthetic 준비 단계이며 전송 E2E/실제 사용자 사진 결과로 해석하지 않는다. 상세 실행·근거는 해당 task QA 문서.

- `ChatMediaSelectionUseCaseTests`: 전체 확보 barrier/부분 파일 정리, 70→30/30/10, 준비 실패 제외·원래 순서 보존, parent-child 중간 종료 복원·계정 격리.
- `ChatMediaUploadTurnQueueTests`: 제한 실행·FIFO·waiting 취소·중복 ID/중복 release. `ChatMediaUploadUseCaseTests`: queued 직후 turn 반환, 같은 identity transport/예약 복구·cancel/ready 경합·복원 조회.
- `ChatOutgoingOutboxUseCaseTests`: 미확정 identity 보존, 실제 terminal 실패 세션 종료, 7일 보관. `GRDBChatMessageStoreTests`/`GRDBChatOutgoingOutboxStoreTests`: 성공 이후 stale 실패/조건부 삭제/outbox 부활 차단.
- Socket/Functions는 `entrypoints/FIREBASE.md`의 테스트를 포함해 로컬 회귀 실행. 이번 실행 결과와 미실행 UI·실기기·서버 E2E는 `tasks/chat-media-bounded-parallel-upload/progress.md`/`qa-checklist.md`를 따른다.

## 공통

- moderator delegation 최종 리뷰 회귀: `RoomRoleEventPayloadTests`의 Codable 분리 unread 순번 보존·legacy fallback·role event 제외, `ChatRoomRoleSessionTests`의 취소된 콜백 무시·구독 generation 격리·foreground 재확인 경계를 검증한다.
- PR 준비 재검증(2026-09-02): Functions lint 오류 0·기존 경고 14, build·252/252, Socket check·106/106, migration fixture 7/7 통과. 최종 리뷰에서 Codable unread 복원 누락과 cancel 뒤 stale role callback 반영 가능성을 수정하고 해당 경계 테스트를 추가했다. 기존 Rules 47/47·transaction 59/59와 Development 사용자 수동 QA 기록은 아래 moderator delegation 검증 이력을 따른다.
- 위 두 리뷰 수정 포함 최종 iOS 검증은 iPhone 17 Pro Max iOS 26.2의 `OutPick-Development` 7개 suite 52/52 통과(실패·skip 0)다. `RoomRoleEventPayloadTests`, `ChatRoomRoleSessionTests`, `ChatReadStateStoreTests`, `ChatRoomReadStateStoreTests`, `ChatUnreadCatchUpStateTests`, `ChatMessageMediaAttachmentMappingTests`, `GRDBChatMediaIndexStoreTests`를 실행했다.

- 단위 테스트: `OutPickTests`
- UI 테스트: `OutPickUITests`
- 앱 빌드 기본 검증:

```bash
xcodebuild -scheme OutPick-Development -destination 'generic/platform=iOS Simulator' build
```

- iOS 실행 환경 경계: `OutPickTests/AppRuntimeConfigurationTests.swift`
  - Development/Production canonical Socket·Kakao 조합, Firebase Bundle ID·project·Google callback 불일치와 양방향 Firebase project 교차를 검증한다.

- Phase 6 통합 회귀: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-integration-tests.md`
- Phase 6 배포·smoke gate: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-deployment.md`
- Phase 6는 Phase 2~5 targeted test, iOS generic build, Functions test/lint/build와 Socket check/test를 같은 배포 commit SHA 기준으로 실행한다.
- Firestore rules emulator: `firestore-tests/room-document-id.rules.test.mjs`
  - room/member/joinedRooms 원자 transaction과 Rooms `ID`/`id` create/update 차단을 검증한다.
  - 실행: `cd firestore-tests && npm install && npm test`.

## Lookbook

- 브랜드 생성 시즌 discovery 오류 문구: `OutPickTests/SeasonDiscoveryManagementViewModelTests.swift`
  - repository의 Firebase/infrastructure 오류 원문을 화면 상태에 노출하지 않고 고정된 한국어 문구를 발행하는지, 성공 시 기존 job 결과를 정상 발행하는지 검증한다.
  - 실행: `xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'platform=iOS Simulator,id={simulator-id}' -only-testing:OutPickTests/SeasonDiscoveryManagementViewModelTests test`.
  - 2026-08-06 관련 9/9와 `OutPick-Production`/`Production-Debug` Simulator build가 통과했다. 실패 화면의 줄바꿈·버튼 시각 QA는 안전한 재현 시 사용자가 수행한다.

- iOS Cloud Functions 계약 테스트: `OutPickTests/CloudFunctions/`
  - 공통 decoder와 transport spy, Auth/Admin capability, Brand/Request, Engagement/Comment, Import/Deletion의 사용 callable 38개를 검증한다.
  - 실제 Firebase 서버를 호출하지 않고 function name, payload, response mapping과 오류 보존을 고정한다.

- Lookbook interaction/store tests: `OutPickTests/LookbookInteractionStoreTests.swift`, `OutPickTests/LookbookDebugFailureInjectionStoreTests.swift`
- Lookbook detail tests: `OutPickTests/PostDetailScreenViewModelTests.swift`, `OutPickTests/SeasonDetailViewModelTests.swift`
  - 시즌 상세는 24개 초기 page, 마지막 12개 trigger, page 간 PostID 중복 제거, 동시 호출 병합, 빈 visibility page 연속 조회, refresh race와 실패 재시도를 검증한다.
  - 이미지 prefetch는 첫 12개·현재 위치 앞 32개·concurrency 4, append 직후 새 page 24개 등록, 반복 카드 노출의 경로 중복 방지를 `SeasonDetailBrandImageCacheSpy`로 검증한다.
- 좋아요 탭 tests: `OutPickTests/LikedViewModelTests.swift`, `OutPickTests/LoadLikedSeasonsUseCaseTests.swift`
  - 자동 회귀: 섹션별 초기 로드·부분 실패·pagination·좋아요 취소와 무효화 store 연동은 ViewModel 테스트로 검증한다.
  - 수동 QA: `SAVED EDITS` 헤더, 브랜드/시즌 가로 카드, 포스트 2열 그리드, 섹션별 로딩·빈 상태·실패 패널, 메뉴·상세 이동·pull-to-refresh를 Simulator에서 확인한다.
- 브랜드 생성·관리자 편집 로고 tests: `OutPickTests/CreateBrandViewModelTests.swift`, `OutPickTests/AdminBrandManagementViewModelTests.swift`, `firestore-tests/brand-storage.rules.test.mjs`
  - ViewModel은 두 로고 업로드·경로 패치 완료 대기, 실패 후 같은 브랜드 문서 재시도, 양 화면에서 내부 오류를 제외한 동일 사용자 문구, detail 실패 시 thumb rollback을 검증한다.
  - Storage emulator는 active 총 관리자·브랜드 관리자의 로고 업로드 허용과 inactive/무권한 사용자 거부를 검증한다.
- 삭제 요청 관리 pagination/retry tests: `OutPickTests/AdminLookbookDeletionManagementViewModelTests.swift`
- Firestore 문서 ID 경계: `OutPickTests/FirestoreDocumentIDBoundaryTests.swift`
  - 저장된 legacy `id`보다 경로 ID가 우선하는지, 빈 경로 ID가 실패하는지, Season write payload에 `ID`/`id`가 없는지 검증한다.
  - 실행: `xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'platform=iOS Simulator,id={simulator-id}' -only-testing:OutPickTests/FirestoreDocumentIDBoundaryTests test`.
  - 2026-07-14 Phase 4에서 영향 범위 11개 suite의 runtime test 59개, Firestore Emulator 11개, generic Simulator build와 test target build-for-testing이 통과했다. 실제 로그인 QA에서도 Chat/Lookbook read·write 경계와 `I-FST000002` 0건을 확인했다.
  - rules 운영 배포와 Rooms legacy `ID` 4건 cleanup 후 재감사에서 `ID`/`id` 보유 0건, 방 4개 유지, 핵심 불변식 누락 0건과 로그인 앱 목록 read를 확인했다.
- UI smoke/failure tests: `OutPickUITests/LookbookSmokeUITests.swift`, `OutPickUITests/LookbookInteractionFailureToastUITests.swift`
- Q7 live UI preflight: `OutPickUITests/LookbookImportQ7DevelopmentUITests.swift`. Physical-device only, opt-in via `OUTPICK_Q7_DEVELOPMENT_UI_TEST=1` plus a unique `OUTPICK_Q7_RUN_ID`; it also accepts these values with a `TEST_RUNNER_` prefix for runners that namespace XCTest environment values. Creates one QA brand and runs initial candidate discovery, captures candidate titles/screenshot, and never selects/submits image import. This is a Development data mutation and is not part of routine CI/G-I. Candidate fixture mismatch fails before image import; created QA brand is retained. App/Q7 XCTest Simulator build-for-testing and the required 28-test iOS gate passed; live iPhone execution is still pending. XcodeBuildMCP 2.7.0 build_sim must omit testProductsPath because the shared handler incorrectly clears source defaults for this output option. See `product-queue-q7-readiness.md` for reproduction and original logs.
- UI test support/robots: `OutPickUITests/LookbookUITestSupport.swift`, `OutPickUITests/LookbookPostDetailRobot.swift`, `OutPickUITests/LookbookCommentsRobot.swift`

Lookbook import worker tests:

- `tools/lookbook-import-worker/src/extraction/core.test.ts`
- `tools/lookbook-import-worker/src/extraction/adapter-registry.test.ts`
- `tools/lookbook-import-worker/src/extraction/review.test.ts`
- `tools/lookbook-import-worker/src/extraction/retained-evidence.test.ts`
- `tools/lookbook-import-worker/src/extraction/youth-fixture.test.ts`
- `tools/lookbook-import-worker/fixtures/season-images/incidents/youth-programmatic-gallery/`
- `tools/lookbook-import-worker/src/fixture/corpus.test.ts`
- `tools/lookbook-import-worker/src/config.test.ts`, `oidc-auth.test.ts`, `server.test.ts`
  - 환경별 canonical Storage bucket·audience·caller 계정 조합과 route별 401/403, 올바른 caller의 handler 진입을 검증한다.
- `scripts/ai/test-deploy-lookbook-import-worker.sh`
  - Development/Production 배포 project·service·runtime account·Storage bucket·OIDC identity 조합과 `--no-traffic`, Production 확인 gate, Cloud Run candidate tag 결합 길이 제한을 검증한다.
- `tools/lookbook-import-worker/src/fixture/run-corpus.ts`
- `tools/lookbook-import-worker/fixtures/{discovery,season-images}/`
- `tools/lookbook-import-worker/fixtures/discovery/platform/cafe24-underscore-detail-list/`
- `tools/lookbook-import-worker/src/processor.test.ts`
- `tools/lookbook-import-worker/src/job-lifecycle.test.ts`
- `tools/lookbook-import-worker/src/public-http.test.ts`
- 실행: `cd tools/lookbook-import-worker && npm test` (root와 하위 test 모두 포함, 2026-08-04 기준 88/88 통과).
- durable 시즌 discovery: `src/season-identity.test.ts`, `src/season-discovery-processor.test.ts`, `src/server.test.ts`에서 URL/정규화 이름 동일성, 충돌·복수 일치, task identity route와 publish 경계를 검증한다.
- 관리자 discovery UI: `OutPickTests/SeasonDiscoveryManagementViewModelTests.swift`에서 최신 상태 stream 반영, 요청·재시도·취소, review 성공 완료와 실패 시 후보 보존을 검증한다. 2026-08-04 iPhone 17 Pro iOS 26.2 Simulator에서 4/4 통과했다.
- fixture gate: `cd tools/lookbook-import-worker && npm run test:fixtures` (외부 fetch 없이 현재 corpus 5/5와 구조화된 differential을 검증).
- 2026-08-03 Production candidate `lookbook-import-worker-00024-fow`에서 task `/readyz` 200, task 빈 import 500, Functions 빈 diagnostic 500, Functions→import 교차 caller 403을 확인했다. traffic 100% 전환 후 전용 W3C import가 post 5개·asset 6/6 `ready`로 성공했고 ERROR·queue pending·smoke 데이터 잔존은 모두 0건이었다.
- 2026-08-04 Development Worker `00004-xal`에서 Cloud Tasks OIDC `/readyz` 200을 확인하고 traffic 100%로 전환했다. OUTSTANDING 실제 URL discovery 2회가 HTTP 200·attempt 1로 완료됐고, 동시 callable 3건은 job 하나로 합쳐졌다. 실제 품질 결과는 44개 후보와 `load_more_detected`/`dynamic_rendering_detected`로 `correctionRequired`였으며 queue·ERROR·QA 데이터 잔존은 0건이었다.
- extraction review Functions contract: `functions/src/lookbook/import/reviewContract.test.ts`, `taskService.test.ts`, `importValidation.test.ts`, `functions/src/index.contract.test.ts`.
- extraction review iOS targeted tests: `OutPickTests/LookbookExtractionReviewViewModelTests.swift`, `OutPickTests/CloudFunctions/CloudFunctionsSeasonImportRepositoryTests.swift`.
- existing-season reconcile: worker `src/extraction/reconcile.test.ts`, Functions `repairContract.test.ts`, iOS `LookbookSeasonRepairViewModelTests.swift`와 `CloudFunctionsSeasonImportRepositoryTests.swift`.
- review 이미지 로더: `OutPickTests/LookbookRemotePreviewImageLoaderTests.swift`에서 동일 URL 동시 load 병합과 prefetch URL 중복 제거/동시성 상한을 검증한다.
- 2026-07-23 Phase 4에서 Functions 53/53와 lint/build, iOS targeted 6/6와 iPhone 17 Pro Max Simulator build가 통과했다. 실제 Firebase/Cloud Tasks 통합과 관리자 화면 수동 QA는 미수행이다.
- Phase 5 cleanup path contract는 `functions/src/lookbook/import/evidenceCleanup.test.ts`에서 검증한다. Phase 5 전체 Functions 55/55와 lint/build가 통과했으며 실제 Storage delete smoke QA는 배포 전까지 보류한다.
- Phase 6 전체는 worker 57/57, fixture 4/4, Functions 57/57, iOS 관련 targeted 9/9가 통과했다. 2026-07-23 운영 배포 후 YOUTH repair preview `keep 1/add 45/reorder 0/remove 0`을 같은 season에 적용해 post `1 → 46`, 기존 `post_0000` 보존, post asset `ready` 46과 job asset failed 0을 확인했다.
- 2026-07-23 Phase 7 전 review UI 보완은 Functions 57/57와 lint/build, remote preview loader·review/repair ViewModel·Cloud Functions repository targeted 11/11, iPhone 17 Pro Max Simulator build/run을 통과했다. repair 2열 grid의 실제 운영 데이터 스크롤 시각 QA는 남아 있다.
- 같은 날 repair no-change terminal 보완은 Worker 59/59와 fixture 4/4, Functions 58/58와 lint/build, iOS repair 상태/ViewModel/repository/loader targeted 10/10 및 Simulator build/run을 통과했다. worker `lookbook-import-worker-00017-stx`와 Firebase Functions 운영 재배포 후 Ready/traffic 100%, 큐 RUNNING, 새 revision recent ERROR 0건과 repair callable ACTIVE를 확인했다. 실제 운영 no-change 비교 smoke는 데이터 mutation을 수반하므로 별도 실행 대상으로 남겼다.
- Phase 7 adapter registry는 Cafe24 positive, Generic/비-Cafe24 negative, domain fixture/host gate, 전체 adapter version cache invalidation을 자동 검증한다.
- Phase 8은 Worker lint/build와 65/65, fixture corpus 4/4·diff 0건, Functions lint/build와 58/58, iOS targeted 14/14 및 Simulator build/run을 통과했다. 운영 worker `lookbook-import-worker-00018-zwl` 배포 뒤 OUTSTANDING static 12 → rendered 44, YOUTH read-only live URL static 1 → source 46, HATCHINGROOM 후보 17을 확인했고 queue pending 0건과 새 revision ERROR 0건이었다.
- Phase 8 종료 후 YOUTH 신규 등록 회귀 보완은 `collection_detail.html`과 분리된 이미지/제목 anchor 최소 fixture를 추가했다. extractor `1.2.1`, Worker lint/build와 65/65, fixture corpus 5/5·diff 0건이 통과했고 2026-07-23 현재 YOUTH 공개 목록 HTML의 정적 후보가 `0 → 20`으로 복구됨을 읽기 전용으로 확인했다.
- 같은 보완 worker를 `lookbook-import-worker-00019-ftd`로 운영 배포해 Ready/traffic 100%, startup probe·port listen, ERROR 0건과 queue task 0건을 확인했다. 별도 health task는 Cloud Run 인증 계층 404로 container request log에 도달하지 않아 모두 삭제했지만, 이후 사용자 수동 QA에서 실제 앱의 YOUTH 시즌 추출 목록이 정상 표시돼 callable→worker→후보 저장·표시 smoke를 완료했다.
- extraction review 수량 기준 보완은 예상 수 일치/불일치/미확인, 첫 signature 자동 진행, raw 후보 감소 evidence-only, content hash 차단을 Worker 66/66과 fixture 5/5로 검증했다. iOS는 미달 승인 차단·예상 수 prefill·미확인 수동 승인/부족 보고·무결성 차단과 repository contract targeted 10/10, Simulator build/run을 통과했다.
- 같은 worker를 `lookbook-import-worker-00021-ghs`로 운영 배포해 Ready/traffic 100%, startup probe·port 8080 listen, recent ERROR 0건, queue RUNNING/pending 0건을 확인했다. rollback은 `lookbook-import-worker-00019-ftd`다.
- expected-count 활성 grid scope 후 extractor `1.2.3` Worker 67/67·lint/build·fixture 5/5와 실제 저장 YOUTH HTML `46/49` evidence를 확인했다. 운영 `lookbook-import-worker-00022-5gn`은 Ready/Active·traffic 100%, recent ERROR 0건, queue RUNNING/pending 0건이며 rollback은 `00021-ghs`다.

Firebase Functions tests/build entry:

- Phase 4 Functions 모듈화 테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-4-firebase-functions-tests.md`
  - 구현 시 49개 export/`__endpoint` metadata, 초기화 owner, 재귀 test discovery, feature policy와 고위험 service failure를 검증한다.
- Functions package: `functions/package.json`
- Functions source: `functions/src`
- export/runtime 계약: `functions/src/index.contract.test.ts`
- 초기화 owner/import 방향/root 구조 계약: `functions/src/architecture.contract.test.ts`
- Lookbook deletion purge lease: `functions/src/lookbook/deletion/purgeLease(.test).ts`
- Lookbook deletion purge drain: `functions/src/lookbook/deletion/purgeDrain(.test).ts`
- 기능 단위 테스트: `functions/src/{auth,brand,chat,lookbook}/**/*.test.ts`
- `functions/package.json`의 `npm test`는 clean build 후 `lib/` 아래 `*.test.js`를 재귀 발견해 실행하며 0개면 실패한다.
- 실행: `cd functions && npm test`
- extraction issue operations Phase 1~4: 양 런타임 공통 계약과 Phase 2 recorder/cleanup, Phase 3 IAM API/CLI 테스트에 더해 Worker `runtime-contract.test.ts`·server route와 Functions `release{Contract,Service}.test.ts`가 runtime/source revision, partial traffic, stale CAS, 실제 smoke/ground truth와 verified 전이를 검증한다. Worker `issue-recorder.test.ts`는 구형 occurrence 지연 도착 시 cluster blocked runtime 단조 증가, fixed job retry projection, duplicate 재투영과 verified cluster terminal 보존도 검증한다. 2026-08-06 지연 occurrence 보완 기준 Worker lint/build, 118/118과 fixture 9/9가 통과했다.
- AMOMENTO Cafe24 모달 시즌 목록 회귀는 Worker `season-discovery.test.ts`와 `fixtures/discovery/platform/cafe24-modal-data-url/`이 `button[data-url]`, `collection-single.html`, 끝자리 날짜 제거, navigation 제외와 후보 순서를 고정한다. release 회귀는 0% tag traffic 제외, 삭제된 대표 job의 동일 fingerprint 현존 job fallback, 새 시즌 재시도 job의 fix projection 승계를 고정한다. 2026-08-05 최종 기준 Worker 103/103·fixture 6/6·lint/build, Functions 145/145·lint/build, iOS 관련 12개 targeted test와 Development Simulator build가 통과했다. Development 실제 AMOMENTO 재시도는 후보 15개·contract 2·cluster verified를 확인했다.
- Phase 7은 adapter 없는 Generic 상세 fixture와 Cafe24 최신 `xans-product-additional`·구형 직접 `collection-images` fixture로 목록 이미지 우선, 실제 시즌 콘텐츠 영역의 최상단 첫 유효 이미지 fallback, header/navigation/banner/footer/related 제외, cover 기반 후보 제거 금지, 실패 격리와 30개·동시 3개·15초 경계를 검증한다.
- durable 시즌 discovery: `functions/src/lookbook/import/seasonDiscoveryContract.test.ts`, `functions/src/index.contract.test.ts`에서 fingerprint/status/retention/task ID, review 연결 대상의 삭제 lifecycle, revision readiness·legacy fingerprint 호환, enqueue 후 terminal 상태 덮어쓰기 방지, 현재 published snapshot import gate, 76개 export metadata와 watchdog/readiness collection-group index 설정을 검증한다. 2026-08-05 기준 전체 113/113 통과.
- 브랜드 discovery projection 호환성: `OutPickTests/FirestoreDocumentIDBoundaryTests.swift`가 구형 `success`와 durable pipeline의 `succeeded/awaitingReview/correctionRequired/cancelled/superseded`를 포함한 모든 영속 상태의 Firestore 디코딩을 검증한다. iPhone 17 Pro Max iOS 26.2에서 suite 4/4가 통과했다.
- 개선 요청 구현은 Functions 순수 계약 테스트로 `extractionContractRevision` 경계와 legacy 호환을, iOS fake Repository로 요청됨·higher revision ready·새 queued generation 전이를 검증한다. callable의 실제 권한·중복·stale snapshot·transaction 경합과 진행 묶음 중앙 배치는 마지막 Development 통합 QA에서 확인한다.
- 스타일 무드: `functions/src/styleMoods/{policy,functions,seedValidation}.test.ts`
  - NFKC/공백/소문자 정규화, ID·그룹·alias 충돌, 최종 update 조합, 관리자 handler, v1 56개·featured 20개·전체 용어 고유성을 검증한다.
- Firestore rules: `firestore-tests/style-moods.rules.test.mjs`
  - 인증 사용자의 active-only read, 비인증 read 거부, 모든 client write와 term/metadata 접근 거부를 검증한다.
  - `cd firestore-tests && npm test`는 Emulator에서 rules 16개와 seed 초기 dry-run/apply/재-dry-run 변경 0건을 함께 검증한다.
- 계정·공개 프로필: `functions/src/profile/{policy,functions}.test.ts`, `functions/src/shared/accountStatus.test.ts`
  - 닉네임 정규화·인증 기반 가용성 조회, 관심 무드 1~5개, UID 소유 avatar path, handler active guard와 Firebase Auth email lookup을 검증한다.
  - `firestore-tests/profile.rules.test.mjs`는 private/public/index 접근 경계를 검증한다.
  - `profile-storage.rules.test.mjs`는 owner+active upload/delete와 signed-in read를 검증한다.
  - `profile-transactions.emulator.test.mjs`는 닉네임 동시 단일 승자, inactive/missing mood rollback, nickname index 교체/rollback을 실제 Admin transaction으로 검증한다.
  - 2026-07-28 Phase 2 결과: Functions 80/80, rules 23/23, transaction 5/5.
- Phase 7 계정 삭제:
  - `functions/src/accountDeletion/{policy,functions,providerCleanup}.test.ts`는 generation request ID, intent 입력, 최근 인증, 정확한 취소 경계, retry backoff, provider claim과 Kakao unlink 멱등성을 검증한다.
  - `firestore-tests/account-deletion.emulator.test.mjs`는 intent 단일 소비, 즉시 pending 잠금, 취소 복원, 정확한 만료 시각 거부를 실제 transaction으로 검증한다.
  - `Socket/test/auth/socketAuthMiddleware.test.js`, `Socket/test/users/userLookup.test.js`는 pending handshake 거부와 상태 listener fail-closed를 검증한다.
  - 2026-07-29 Functions 97/97·lint/build, Socket check·64/64, Rules 26/26, account/profile transaction 7/7이 통과했다.
- Phase 8 iOS 계정 삭제:
  - `AccountDeletionUseCaseTests.swift`: 재인증 선행, 서버 수락 전 세션 보존, 수락 후 receipt/scrub 실패 fail-closed, provider 불일치 취소 차단과 receipt 유실 취소 인증을 검증한다.
  - `CloudFunctions/CloudFunctionsAccountDeletionRepositoryTests.swift`: prepare/request/status/cancel callable 이름·payload·응답 상태 guard를 검증한다.
  - `AccountDeletionReceiptStoreTests.swift`: 고유 Keychain service에서 opaque receipt 저장·조회·삭제를 검증한다.
  - `GRDB/AccountDeletionLocalDataCleanupTests.swift`: message/FTS/media/outbox/profile cache 7개 테이블의 원자 정리를 검증한다.
  - `GoogleAccountDeletionReauthenticationPolicyTests.swift`: pending scrub 후 세션 없음 sign-in, 같은 UID reauthenticate, 다른 UID 거부를 검증한다.
  - `OutPickAppCheckProviderPolicyTests.swift`: Debug 구성의 기기 공통 Debug Provider와 Release의 Simulator Debug Provider/실기기 App Attest 분기를 검증한다.
  - 2026-07-29 iPhone 17 Pro Max Simulator에서 신규 targeted 9/9와 앱 build/install/launch가 통과했다.
  - App Check와 Google pending 취소 보완 후 관련 targeted 14/14, Simulator build/run, Kakao AD-1·Google AD-2 운영 요청/취소 QA가 통과했다.
  - 전체 회귀는 422 passed, 18 skipped, 3 failed이며 실패는 Phase 8 비관련 관심 스타일 비동기·media dedupe·기존 문구 기대값이다.
- iOS 새 온보딩·bootstrap:
  - `ProfileSetupViewModelTests.swift`
  - `AvatarSetupViewModelTests.swift`
  - `StyleMoodOnboardingViewModelTests.swift`
  - `LoadCurrentUserBootstrapUseCaseTests.swift`
  - `CompleteOnboardingUseCaseTests.swift`
  - `CloudFunctions/CloudFunctionsProfileMutationRepositoryTests.swift`
  - 2026-07-28 iPhone 17 Pro Max iOS 26.2 Simulator에서 13/13, 앱 compile-only build가 통과했다.
  - 에디토리얼 3단계 UX 보완 후 닉네임·아바타 선택/건너뛰기·featured/검색/선택 유지와 기존 완료/bootstrap을 묶은 15/15가 같은 Simulator에서 통과했다.
  - 문구 보완과 닉네임 사전 확인 추가 후 중복/사용 가능/조회 실패를 포함한 관련 17/17, Simulator build가 통과했다. Functions는 81/81·lint·build가 통과했고 신규 callable 운영 등록도 확인했다.
  - 닉네임 확인을 첫 단계로 이동한 후 성공/중복/조회 실패와 아바타 선택/건너뛰기, callable mapping 관련 9/9와 Simulator build가 통과했다.
- iOS Phase 6 관심 스타일 브랜드:
  - `LoadInterestedStyleBrandsUseCaseTests.swift`
  - `InterestedStyleBrandListViewModelTests.swift`
  - `LookbookHomeViewModelInterestTests.swift`
  - 정렬·가시성·ID 중복 제거, 빈 관심값 query 생략, 전체 보기 append·동일 커서 중복 호출 차단, 관심 스타일 변경 재조회, 개인화 빈 상태·실패와 전체 브랜드 목록 상태 분리를 검증한다.
  - 2026-07-29 iPhone 17 Pro Max iOS 26.2 Simulator에서 신규 targeted test 10/10이 통과했다.
  - 같은 날 운영 index `CICAgLiT_JAK`가 `READY`가 된 뒤 실제 query의 실패→재시도→매칭 0건, 빈 상태 CTA 두 경로, 검색 중 섹션 숨김·복원을 확인했다. DEBUG fixture에서는 매칭 카드 상세와 전체 보기 진입을 확인했다.
  - 비정상적인 관심 스타일 0개에서 query를 생략하고 섹션을 숨기는 `noStylePreferenceHidesSectionWithoutQuery` 테스트를 추가했다. 이번 문구·섹션 구분 보완에서는 프로젝트 테스트 실행 원칙에 따라 별도 테스트 실행은 보류했고 Simulator build/install/launch로 컴파일을 확인했다.
- iOS Phase 4 마이페이지·공개 프로필 직접 소비:
  - `UpdatePublicProfileUseCaseTests.swift`
  - `ProfileEditViewModelTests.swift`
  - `StylePreferenceEditViewModelTests.swift`
  - `ChatProfileSyncManagerTests.swift`
  - `RoomPreviewProfileOverlayTests.swift`
  - `CommentAuthorProfileStoreTests.swift`
  - `CloudFunctionsProfileMutationRepositoryTests.swift`
  - 아바타 누락/문자열/null payload, 업로드→mutation→이전 파일 삭제 순서, cleanup 부분 실패 기록, 닉네임 사전 확인, 관심 스타일 1~5개와 공개 프로필 cache 직접 소비를 검증한다.
  - 2026-07-28 관련 24/24와 iPhone 17 Pro Max iOS 26.2 Simulator build/install/launch가 통과했다.
  - 2026-07-28 피드백 회귀 27/27에서 방 목록 최신 공개 프로필 overlay, 댓글 작성자 강제 refresh/실패 보존, upload/callable/cleanup 실패, 닉네임 확인 네트워크 실패, 관심 스타일 load/save 실패와 저장 중 중복 호출을 검증했다.
- Phase 5 브랜드·시즌 스타일 무드:
  - Functions는 `functions/src/shared/styleMoodAssignmentPolicy.test.ts`, `functions/src/lookbook/admin/seasonMoodFunctions.test.ts`, `functions/src/brand/admin/brandValidation.test.ts`, `functions/src/index.contract.test.ts`에서 0~5개 할당, 중복·잘못된 ID, 총 관리자 guard, restricted brand patch와 callable export를 검증한다.
  - import worker는 `tools/lookbook-import-worker/src/processor.test.ts`에서 신규 시즌의 `moodIDs: []`와 legacy `tagConceptIDs` 미기록을 고정한다.
  - Firestore rules는 `firestore-tests/style-moods.rules.test.mjs`에서 총 관리자와 브랜드 owner의 season client direct create/update 거부를 검증한다.
  - iOS는 `AdminBrandManagementViewModelTests.swift`, `CloudFunctionsBrandRepositoryTests.swift`, `CloudFunctionsStyleMoodAdminRepositoryTests.swift`, `StyleMoodManagementViewModelTests.swift`, `FirestoreDocumentIDBoundaryTests.swift`에서 권한별 저장 가능 상태, callable payload, 생성 무드 즉시 선택, canonical 그룹과 Brand/Season `moodIDs` mapping을 검증한다.
  - 관리자 검색 회귀는 `StyleMoodManagementViewModelTests.swift`의 키워드 이름·alias·그룹 필터와 `AdminBrandManagementViewModelTests.swift`의 시즌 표시명·원본명·연도·S/S·F/W 필터로 검증한다. 검색 중 선택 유지와 화면 빈 상태는 실제 앱 QA 대상이다.
  - 2026-07-29 관리자 검색 관련 11/11과 iPhone 17 Pro Max Simulator build/install/launch가 통과했다.
  - 브랜드 search-first picker 정책은 `StyleMoodManagementViewModelTests.swift`에서 빈 검색 결과 0개, active 이름·alias 부분 검색, inactive 제외, 결과 없음·5개 미만에서만 생성 액션 노출을 검증한다.
  - 2026-07-29 search-first picker 정책을 포함한 관련 iOS 13/13과 iPhone 17 Pro Max Simulator build/install/launch가 통과했다.
  - 2026-07-28 Functions lint/build·87/87, worker lint/build·68/68, rules 24/24, profile transaction 5/5, seed 재-dry-run 변경 0건, iOS 핵심 14/14와 iPhone 17 Pro Max iOS 26.2 Simulator build/install/launch가 통과했다.
  - 운영 배포 후 기존 무드 editor sheet의 초기 target이 create 상태로 고정되는 결함을 `StyleMoodManagementView`의 식별 가능한 sheet target으로 수정했다. 관련 ViewModel·callable 계약 3/3과 Simulator build/install/launch, 운영 `미니멀` 값 초기화·동일 값 저장을 확인했다.
- purge drain 핵심 시나리오: 20개 초과 page 반복, 서로 다른 브랜드 최대 3개, 같은 브랜드 순차, 부모 target 우선, 실패/lease skip 후 계속 처리, 7분 cutoff.
- 브랜드·채팅 선택 초기화: `functions/src/developmentReset/brandChatManifest.test.ts`에서 root collection 분류, 보존 경계, 안정적인 confirmation hash, project·queue·미분류 collection apply gate를 검증한다. 실제 데이터 삭제는 자동 테스트하지 않고 dry-run manifest와 사후 audit로 검증한다.
- 운영 통합 결과와 남은 관찰 항목: `docs/ai/tasks/lookbook-deletion-purge-drain/progress.md`, `qa-checklist.md`.
- Functions workflow: `.codex/skills/firebase-functions-workflow/SKILL.md`

## Chat / Realtime

### Chat UGC safety/moderation 테스트

- exact behavior: `contracts/chat-moderation-v1.json`
- Phase 7.0 worker: `tools/chat-media-processing-worker/src/{imageProcessor,videoProcessor}.test.ts`, `runtimeVerification.ts`, `benchmark.ts`.
  - 실행: `cd tools/chat-media-processing-worker && npm test`, container codec 확인은 `npm run verify:runtime`, 30장/GIF 측정은 `npm run benchmark`.
  - 2026-08-18 실제 HEVC HEIC decoder 부재를 확인한 뒤 iOS HEIC/HEIF→JPEG·서버 raw HEIC/HEIF 거부로 확정해 계약을 보정했다. Node.js 24.19.0 build와 12/12, runtime verification, 1시간 video remux·metadata/부가 track 제거가 통과했다.
  - 로컬 benchmark: 4096x4096 JPEG 30장 10.537초, 190-frame 1024x512 GIF 99,614,720 decoded pixel 3.750초, peak RSS 약 393 MiB. 201-frame GIF는 decode 전에 `resourceLimit`으로 거부했다.
  - Development Cloud Build `c57a715a-2948-45ea-b464-21437cf474c7`: Linux verification image와 최종 runtime image에서 Node.js 24.19.0, sharp 0.35.3, libvips 8.18.3, ffmpeg/ffprobe 5.1.9를 확인했다. 12/12, runtime verification과 최종 image 재검증이 통과했다. Linux benchmark는 JPEG 30장 32.992초, GIF 9.538초, peak RSS 약 336 MiB였다. 이에 상한과 2 vCPU·1 GiB·task 내 순차 처리를 확정했다.
- Phase 7.1 로컬 lifecycle:
  - Socket `test/{handlers,media,contracts}`가 v2 UUID preflight/finalize/status/cancel, exact manifest, principal image 2/video 1 slot, v1 호환과 ready 전 message/seq/emit/push 0을 검증한다.
  - Functions `src/chat/media/*.test.ts`와 `index.contract.test.ts`가 deterministic task ID, 환경별 execution slot, duplicate claim, stale lease retry/terminal 7일 TTL, private dispatcher·trigger·watchdog export와 index를 검증한다.
  - worker `cloudJob.test.ts`와 processor integration test가 Cloud Job env/ready path, 이미지/GIF 정규화와 1시간 video remux·512px thumbnail을 검증한다.
  - `firestore-tests/chat-media-quarantine-storage.rules.test.mjs`가 예약 owner의 exact source 최초 create만 허용하고 타인·read/delete·잘못된 MIME·terminal/expired 업로드를 거부한다. 실행은 기존 `cd firestore-tests && npm test` 전체 Emulator 회귀에 포함된다.
- Phase 7.2 ready/delivery/cleanup:
  - Functions `readyService.test.ts`가 message/seq/index/preview/delivery/slot 반환 원자성, worker 완료 replay, cancel 선행과 message ID 충돌 fail-closed를 검증한다.
  - Socket `mediaDeliveryWatcher.test.js`가 lease 후 emit→push→completed와 emit 실패 retry 후 동일 messageID/seq 재전달을 검증한다.
  - `chat-media-storage.rules.test.mjs`가 message 생성 전 ready 객체 read 거부, visible attachment 허용, Phase 7.4 당시 전역 비노출 이후 거부를 검증한다. Phase 7.5에서는 자동 비노출 제거와 관리자 content delete 이후 거부 회귀로 교체한다.
  - 같은 Rules test는 ready media read가 account + message 두 문서 한도 안에서 동작하도록 room 문서 제거 뒤 허용, 비활성 account·비노출 message 거부를 함께 검증한다.
  - `OutPickTests/ChatMessageMediaAttachmentMappingTests.swift`가 v2 attachment의 전용 bucket·path·ID·format metadata 보존을 검증한다.
  - 2026-08-19 Development 반영 전후 Functions lint/build와 213/213, Socket check와 96/96, worker 16/16가 통과했다. Firestore·Storage Rules 45/45와 transaction 29/29도 통과했고 media exact index 4개와 기존 cleanup exact index 2개는 `READY`, TTL 2개는 `ACTIVE`, Phase 7 Function 9개는 `ACTIVE`다.
  - 2026-08-20 GIF 중복 frame 회귀 보정 뒤 worker 17/17이 통과했다. 신규 integration test는 빨강 25 + 파랑 25의 연속 중복 50프레임 fixture를 처리해 input/output frame 수, 전체 delay 배열과 loop가 동일한지 검증한다. 로컬 runtime verification은 번들 ffmpeg/ffprobe 경로 지정 후 통과했고, Linux Cloud Build `89daa082-3e7b-4e0e-b7b2-b5717b5e19a0`와 배포 image build `d1d238d9-1f96-41ae-bc71-7cf099b20069`도 test·runtime verification·benchmark를 통과했다.
  - 2026-08-20 GIF 표시 계약 보정은 Functions 전체 test·lint(오류 0, 기존 moderation warning 17)·build, Development generic Simulator build를 통과했다. `readyService.test.ts`가 GIF `mediaFormat`·`animated`의 message/media index 투영을 검증하고, `ChatMessageMediaAttachmentMappingTests`와 `ImageViewerPagePolicyTests`의 대상 7개 시나리오가 부팅된 Simulator에서 통과했다. animated viewer test는 2-frame GIF를 lazy frame source로 만들고 전체 frame 선로딩이 없음을 검증한다. `onChatMediaWorkerCompleted` Development exact 배포 뒤 `ACTIVE`와 ERROR 0건, iPhone 14용 Development build·설치·실행 성공도 확인했다. 새 seq 20 GIF는 attempt 1 ready·cleanup completed, message/mediaIndex의 gif·animated metadata, 정적 badge·viewer animation·정적 thumbnail 복귀까지 실기기 QA를 통과했다.
  - 2026-08-20 첫 31장 QA와 finalize-only 순차화 재QA에서 각각 마지막 1장이 reservation 전 실패한 원인을 보정했고, 세 번째 iPhone 14 QA에서 30+1 모두 전송 성공했다. 후속 대량 전송은 `ChatMediaUploadTurnQueueTests`가 kind별 FIFO·image/video lane 독립성·취소 waiter 제거를, `ChatMediaUploadUseCaseTests`가 `active_upload_limit` 동일 identity 재시도와 비비용량 오류 즉시 실패를 검증한다. `ChatMediaSelectionChunkerTests`는 60→30+30과 70→30+30+10의 순서·index 보존을 추가로 검증했으며 네 suite targeted Simulator test와 Development device build·설치가 통과했다. 새 설치본의 iPhone 14에서 70장 30+30+10 세 메시지가 모두 실패 없이 최종 전송됐다. 60장은 자동 경계 검증과 70장 상위 시나리오 성공을 근거로 별도 실기기 반복을 생략했다.
  - 2026-08-20 영상 앱 종료 QA에서 재실행 직후 왼쪽 실패 표시가 노출된 뒤 server finalize 완료로 성공 전환되는 restore race를 확인했다. `ChatMediaUploadUseCaseTests`에 status-only `uploading → queued`, cancel/ready race, retry 소진 manual retry, status 오류 시 foreground PUT 미호출 4개를 추가하고 `ChatOutgoingOutboxUseCaseTests`에 session credential 제거·local retry payload 보존을 추가했다. 두 suite 26개 targeted Simulator test와 iPhone 14 Development build·설치가 통과했으며 silent pending 선복원의 실제 실패 표시 미노출 재QA는 남아 있다.
  - 교체 전 조각형 signed PUT backend E2E는 276-byte JPEG 단건과 31,364,213-byte MP4 두 조각에서 preflight/PUT/reconciliation/Compose/finalize→Job→ready→part/source cleanup을 통과했다. image/video execution은 각각 8.49초/10.49초, attempt 1이었다. 현 단일 source foreground 계약의 Development E2E는 image Service IAM·Functions 전환 뒤 다시 수행한다.
  - 첫 cleanup scheduler 자동 실행에서 Development 원격에 없던 기존 manifest index 2개가 순차적으로 드러났다. 두 index를 exact 생성한 뒤 `drainChatModerationCleanupJobs`의 다음 5분 자동 실행이 HTTP 200으로 끝났으며 수동 cleanup mutation은 실행하지 않았다.
  - 2026-08-20 Phase 7.0~7.3은 PR #15와 service account 축약 보정 PR #16으로 병합했고 최종 merge SHA는 `e5100643f67500cc79dd9f7a7df03a69f0ff8078`이다. Functions lint/build와 214/214, Socket check와 97/97, worker 17/17·runtime verification·benchmark, Firestore/Storage Rules 45/45와 transaction 29/29를 통과했다. iOS는 올바른 `Production-Release` 구성의 iPhone arm64 unsigned Release build와 개인 개발 서명의 `Production-Debug` 기기 build·설치·실행을 확인했다. Release 직접 설치는 개인 개발팀이 Production App Attest entitlement를 발급할 수 없어 수행하지 않았다.
  - 같은 날 Production에서 Socket `outpick-socket-p73-prod-0820` traffic 100%와 live `/readyz` 200, 인증 handshake 101을 확인했다. 사용자 단건 JPEG·영상 전송은 각각 image Service HTTP 200과 video Job `exit(0)`으로 완료됐고 dispatcher/worker-completion Function은 2xx, 전환 이후 관련 Socket·Functions·Service·Job ERROR는 0건이었다. Firestore/Storage의 개별 QA 식별자를 broad credential로 재조회하지 않았으며, 최종 완료 판정은 사용자 앱 완료 UI와 식별자 비노출 운영 로그를 함께 근거로 한다.
- Phase 1 완료:
  - Functions `moderation/{identity,state}.test.ts`, `shared/accountStatus.test.ts`: versioned HMAC alias, provider claim, capability matrix, 제한 만료.
  - Emulator `moderation-principal.emulator.test.mjs`: 동시 재가입 UID 수렴, suspended 복원, old/new key alias 회전.
  - Socket `moderation/capabilities.test.js`, auth/userLookup/room lifecycle tests: restricted read-only, suspended 거부, projection watch와 owner close 차단.
  - Rules `moderation-capabilities.rules.test.mjs`, profile/brand/room rule fixtures: projection fail-closed, restricted read와 write deny, 내부 문서 deny, active/restricted 재가입자의 missing own-account 단일 get 허용과 cross-user/list/suspended deny.
  - iOS `LoadCurrentUserBootstrapUseCaseTests.swift`: active/deletionPending/restricted/suspended 및 suspended 선행 read 차단.
  - Functions backfill `moderation/backfill.test.ts`, `scripts/backfill-moderation-principals.mjs`: Development/Production project allowlist, dry-run 기본, Kakao Admin API ID exact match, 비숫자·불일치·미연결·HTTP 실패 unresolved, 식별자 비노출 summary, Production 확인 문자열·예상 건수·unresolved apply 차단을 검증한다. 2026-08-07 Phase 1-P 구현 뒤 Functions 전체 164/164와 lint/build가 통과했다.
  - 2026-08-07 Development 실제 dry-run은 Google 1명 resolved/unresolved 0, apply 후 account/principal/alias 각각 1개와 민감 필드 0개를 확인했다. Phase 1-P Production은 total 2/Google 1/Kakao 1/Apple 0/unresolved 0 dry-run과 exact-gated apply를 통과했고, account/principal/alias 각 2개·active·참조 무결성·민감 원문 0개를 확인했다.
  - `test-admin-server/src/seed/lookbook{Basic,Comments}Seed.ts`는 표시용 Firestore fixture만 생성하고 `uitest-*` Firebase Auth 사용자를 만들지 않는다. 실제 Development 로그인은 Google 계정을 사용한다.
  - 2026-08-07 Development 배포 후 `getMyModerationState` ACTIVE·Secret v1 연결, Socket revision `outpick-socket-development-00002-hal` traffic 100%·canonical `/readyz` 정상·ERROR 0건을 확인했다. 실제 provider 탈퇴·재가입 QA는 미완료다.
  - Google restricted 실제 재가입에서 신규 UID→기존 principal 서버 binding은 성공했으나 missing `users/{uid}` get이 거부되는 Rules 회귀를 발견했다. 본인 bootstrap get만 허용하는 수정 후 전체 Rules 35/35·transaction 11/11을 통과하고 Development Rules를 재배포했다.
- Phase 2 완료 범위:
  - Functions `moderation/reports/contracts.test.ts`, `moderation/admin/contracts.test.ts`, `index.contract.test.ts`: submission ID, unique/total count, reopen revision, 1분 10건 burst, recent auth, review transition과 callable export를 검증한다.
  - Functions `moderation/admin/platformAdminOperations.test.ts`: provider 분류, Production exact confirmation·전체 Auth/provider 예상 건수와 audit apply 차단을 검증한다.
  - 2026-08-10 최종 자동 검증은 Functions lint/build·177/177, Rules 35/35, Firestore transaction 17/17, iOS 대상 6개와 generic Simulator build를 통과했다. Production exact Function 6개와 rules/index 배포 후 index `READY`, Function `ACTIVE`, 무인증 401, 활성 Kakao 관리자 목록 성공, Google 비관리자 `PERMISSION_DENIED`, ERROR 0건을 확인했다. smoke rate bucket·임시 App Check token·Token Creator binding 잔존은 모두 0건이다.
  - Emulator `moderation-reports.emulator.test.mjs`: 동시 동일 신고의 submission/rate 단일 수렴, 10/11건 경계, terminal reopen, 동시 stale `caseVersion` 관리자 mutation을 실제 Firestore transaction으로 검증한다.
  - Rules `moderation-capabilities.rules.test.mjs`: 신고 aggregate와 사용자·관리자 rate bucket의 client direct read/write deny를 검증한다.
  - iOS `CloudFunctionsChatModerationReportingRepositoryTests.swift`, `CloudFunctionResponseDecoderTests.swift`: 사용자·방 callable payload/receipt와 소수점 포함 ISO-8601 응답 날짜를 검증한다.
- Phase 3 Functions/cleanup 완료:
  - `functions/src/chat/moderation/contracts.test.ts`: message seq·신고 참조·room lifecycle·관리자 사유 입력 계약.
  - `firestore-tests/chat-moderation.emulator.test.mjs`: 실제 message tombstone, last summary, reply/media/Storage cleanup, owner close, 사용자별 30일 안내, 물리 room 삭제와 삭제 후 idempotent replay.
  - `functions/src/index.contract.test.ts`: 신규 callable 3개, trigger 2개, 5분 scheduler와 cleanup due-query/TTL index 계약.
  - 미디어 technical validation retry/cancel race/ready message+seq 단일 생성, metadata 제거와 GIF resource-limit
- Phase 7 신규 worker/Functions/Socket/Rules/iOS 검증 matrix는 `docs/ai/tasks/chat-ugc-safety-room-moderation/phase-7-implementation-plan.md`의 테스트 계획을 기준으로 추가한다.
- Phase 7.4A `functions/src/moderation/messageEvidence/contracts.test.ts`: versioned canonical tuple ID와 revision reopen, processing/available/failed 접수 효과, queue 비강등, 24시간·7일 경계 ±1ms, distinct reporter/message, retention·appeal/legal hold를 deterministic clock으로 검증한다. 2026-08-21 신규 대상 12/12와 Functions 전체 226/226가 통과했다.
- Phase 7.5A `functions/src/moderation/messageEvidence/contracts.test.ts`, `functions/src/moderation/admin/contracts.test.ts`, `firestore-tests/moderation-reports.emulator.test.mjs`: 자동 hide 없는 queue count, 분리된 관리자 action 조합 검증, 3명 신고 뒤 원문 유지, delete+warning과 keep+warning/temporaryRestriction, 기각의 기존 삭제 미복원, 동일 UUID replay·다른 action 충돌을 검증한다. 2026-08-27 Functions 243/243, Rules 46/46, transaction 51/51, build·lint 오류 0이 통과했다.
- Phase 7.5B `functions/src/chat/deletion/mutation.test.ts`, `firestore-tests/{chat-moderation,moderation-reports}.emulator.test.mjs`, `moderation-capabilities.rules.test.mjs`: 결정적 단건/bulk outbox ID, evidence-aware cleanup, 일반 삭제 표시 보존/계정 탈퇴 익명화 tombstone, 최초 삭제 revision과 replay 무소비, 관리자 incident transaction 결합, 계정 탈퇴 2개 방의 `seq → ID` 연속 revision·방별 outbox·cleanup 완료 gate, client outbox read/write deny를 검증한다. 2026-08-27 Functions 245/245, Rules 46/46, transaction 52/52, build·lint 오류 0이 통과했다.
- Phase 7.5C `Socket/test/deletion/deletionDeliveryWatcher.test.js`, `Socket/test/architecture/entrypoint.contract.test.js`, `functions/src/index.contract.test.ts`: 단건/bulk room-scoped 최소 payload, 다른 room 격리, 실패 후 동일 revision 재전달, 유효 lease skip, 만료된 마지막 lease의 같은 attempt 회수, 10번째 실패 terminal, graceful shutdown과 due/lease 복합 인덱스를 검증한다. 2026-08-27 Socket check·103/103, Functions 245/245, Rules 46/46, transaction 52/52가 통과했다.
- Phase 7.5D `OutPickTests/GRDB/{GRDBChatDeletionSyncStoreTests,AppDatabaseMigrationTests}.swift`, `OutPickTests/RealtimeSocketListenerBinderTests.swift`: 표시 보존/계정 익명화 tombstone·reply·FTS·media index·발신 outbox scrub과 cursor/cleanup 원자성, revision gap rollback, 새 설치 head bootstrap, multi-page, page 밖 삭제 reply target 마커, migration, Socket 단건/head binding을 검증한다. 2026-08-27 Simulator build·build-for-testing, deletion sync 5/5, migration 2/2, Realtime binder 15/15가 통과했다.
- Phase 7.5E `OutPickTests/ChatMessageReportViewModelTests.swift`, `OutPickTests/CloudFunctions/CloudFunctionsChatModerationReportingRepositoryTests.swift`, `OutPickTests/ChatMessageActionPolicyTests.swift`, `functions/src/index.contract.test.ts`: 화면 내 network retry의 동일 UUID·입력 유지, terminal failed의 새 UUID, processing/duplicate/delete-first 결과, callable payload/receipt 매핑, 삭제 tombstone·본인 메시지 신고 차단과 방장의 타인 메시지 `신고 + 삭제` 동시 권한, root callable export를 검증한다. 2026-08-27 iOS 대상 suite 13개, generic Simulator build, Functions 245/245와 build·lint 오류 0이 통과했고 공동 QA 메뉴 보정 뒤 액션 정책 7/7과 Development build/run이 재통과했다.
- Phase 7.5F 통합 회귀는 Functions 245/245·lint 오류 0, Rules·Storage 46/46, Firestore transaction 52/52, Socket check·103/103, 계약/index JSON parse와 `git diff --check`를 통과했다. iPhone 17 Pro Max iOS 26.2 Simulator에서 D/E와 주변 메시지 회귀 9개 suite 60/60, `OutPick-Development` generic Simulator build가 통과했다. deletion cutover 추가 검증은 `chat-deletion-cutover-plan.test.mjs` 5/5, Functions 재실행 245/245, build·lint 오류 0을 통과했고 Development index 두 scope READY·cleanup 10/10 completed·reply/media 잔존 0·revision 10/10/head 10을 원격 감사했다. 실제 Phase 7.5 backend 연동과 강제 종료·오프라인·접근성/keyboard 수동 QA는 미수행이다.
- Phase 7.4B `firestore-tests/moderation-reports.emulator.test.mjs`: text message 최초 accepted 뒤 관리자 terminal 상태에서 동일 clientRequestID 지연 retry가 최상위 receipt의 revision 0 결과를 반환하고 새 UUID만 revision 1을 여는지 검증한다. 새 UUID receipt 10회 허용·11번째 제한, 동일 UUID 무료 replay, preparation 1회만 생성되는 기술 limiter, media `processing → available → accepted` drain과 추가 UUID receipt의 조회 시 개별 수렴, partial cleanup 완료 전 실패 재시작 거부와 preparation/bundle/copy job 동일 generation 증가, stale generation 거부, report-first 삭제의 `awaitingEvidence`, delete-first의 receipt-only 결과도 포함한다. `functions/src/chat/{media/readyService,cleanup/moderationCleanup}.test.ts`는 ready evidence descriptor와 `awaitingEvidence` claim 차단을 검증한다.
- Phase 7.4C-1 `functions/src/moderation/messageEvidence/{contracts,evidenceCopy}.test.ts`와 `firestore-tests/moderation-reports.emulator.test.mjs`: generation-scoped path, 최초 포함 3회·1분/2분 retry, exact ready bucket/path/generation/bytes/MIME/count, 중복 attachment 거부, copy 성공·accepted/public cleanup 해제, 실행당 30건 drain continuation, 3회 실패·부분 attachment cleanup·failed receipt, retention generation delete·bundle 완전 삭제·7일 최소 receipt, 완료 job 재실행 멱등성을 검증한다. 마지막 3회차 copy와 20회차 cleanup lease 중단은 만료 뒤 같은 시도 번호로 회수해 영구 `processing` 없이 terminal 상태로 수렴시킨다.
- Phase 7.4C-2/C-3 `functions/src/index.contract.test.ts`, `functions/scripts/qa-message-evidence-development.mjs`: 환경별 dedicated service account/maxInstances와 root export 계약을 고정하고, Development에서 30장·150MiB와 MP4 350MiB copy, 익명 403, generation cleanup, ready/evidence 잔여 0을 실증한다. 버킷 운영자 사용자와 무관한 chat-media 서비스 계정의 object read 거부는 별도 IAM probe로 확인한다.
- Phase 7.4D `functions/src/moderation/admin/{contracts,evidenceAccess}.test.ts`, `functions/src/index.contract.test.ts`, `firestore-tests/{moderation-reports.emulator,moderation-evidence-storage.rules.test}.mjs`: message view별 direct query·cursor/index 계약, current revision 상세, decision별 same-seq restore/moderationRemoved/confirmed violation/계정 제재/Evidence 즉시·30일 retention과 audit 원자성, terminal preparation scrub+TTL, exact generation·Storage ownership metadata, Cloud Logging 실패 시 URL 미반환, copy/cleanup과 분리된 signer identity, Evidence Storage client deny-all을 검증한다. 2026-08-26 Functions 243/243, Rules 46/46, Firestore transaction 49/49, build·lint 오류 0을 통과했다. 같은 날 Development Rules·exact index/TTL·Function 7개·IAM/Logging/DATA_READ를 반영했고 Function `ACTIVE`, index `READY`, TTL `ACTIVE`, 무인증 Evidence callable 401을 확인했다. 일회성 fixture로 실제 URL 발급·전체/Range GET·캐시 정책과 동일 issuanceID의 app event 1건/Storage GET 2건, 전용 routing 및 `_Default=0`을 확인했다. 임시 자원 잔여 0과 기존 관리자 상태 원복 뒤 log bucket은 Analytics·1,095일·`locked=true`로 확정했다.
- 잔여 Development E2E는 유효 PNG와 정확히 350 MiB인 재생 가능 MP4를 사용해 원격 playable probe, 전체 GET, 앞/뒤 Range, 5분 만료 후 이미지·영상 HTTP 400, recent-auth 갱신 뒤 새 URL·issuanceID와 Range 성공을 확인했다. 기간과 actor/incident/revision/object/result 결합 조회 2건이 내림차순으로 정렬됐고 첫 영상/재발급/이미지 issuance의 Storage GET은 각각 6/1/1건, `_Default`는 0건이었다. 영구 debug token 없이 종료했고 임시 Auth/Firestore/Storage/rate bucket 잔여 0, 기존 Auth 2명·active platform admin 0명, 최근 Function ERROR 0을 확인했다.
- 배포 직후 retention index `CREATING` 중 scheduler 1회가 `FAILED_PRECONDITION`을 남겼지만, `READY` 뒤 수동 재실행은 HTTP 200·신규 ERROR 0을 통과했다.
- Socket unit test 후보:
  - restricted/suspended handshake와 기존 연결 disconnect
  - room ban 사용자의 active room read 비회귀, membership/participant Socket join/message-media write 거부, 전역 차단 recipient push 제외
  - principal+room+messageKind rate key와 reconnect 회귀
  - ready 전 broadcast 없음과 ready 이후 단일 broadcast/seq. 기존 hiddenPendingReview/restore 회귀는 Phase 7.4 구현 이력이며 Phase 7.5에서 queue-only + 모든 서버 확정 메시지 삭제의 공통 Deletion Sync 회귀로 교체한다. 단건 message outbox와 일반 삭제 표시 보존 tombstone, 계정 탈퇴 collection group 방별 batch의 연속 revision 범위·head-advanced outbox·익명화 tombstone을 각각 검증한다.
- Firestore·Storage emulator Phase 3 완료:
  - message direct update와 room lifecycle direct update 거부, 폐쇄 room read 차단, 폐쇄 안내 본인 read/delete와 타인 접근·client create/update 거부.
  - room ban은 후속 Phase 범위다. active room read는 유지하고 membership create·message/media write만 principal ban으로 거부한다.
  - `chat-media-storage.rules.test.mjs`는 활성 계정의 서버 reservation 일치 업로드·이미지 read를 허용하고, reservation 누락/만료/종류·sender 불일치와 deletionPending 계정의 read를 거부한다.
  - account capability v2 보정 후 최종 회귀는 Functions 185/185, Socket 70/70, Rules 40/40, transaction 20/20과 JSON/dry-run compile을 통과했다. 170명 추가 참여자 방 종료로 closure notice/projection write가 Firestore batch 500 한도 안에서 분할됨을 검증한다.
- iOS unit test 후보:
  - bootstrap active/deletionPending/restricted/suspended routing
  - 신고·차단·삭제 ViewModel state와 Coordinator route spy
  - room remove 뒤 non-member 읽기 전용 전환, pending outbox·미완료 upload 취소와 기존 message/FTS/media cache 유지
  - 현재 window 보존, hidden seq·pagination cursor 소비, 기존 payload/FTS/cache 유지와 재표시 차단, unblock 뒤 강제 재조회 없는 자연 복원
  - pending media relaunch/retry/failure와 ready ACK 수렴
- Phase 5 Functions/transaction 자동 검증:
  - remove/unban idempotency와 ban generation, member/joinedRooms/memberCount 단일 변경
  - 영구 정지 전체 membership page sweep 재실행과 정지 해제 뒤 자동 복구 없음
  - 방별 successor joinedAt/UID tie-break, 부적격 후보 race 재선정, 동시 leave/remove/suspension에서 owner 중복 0
  - 적격자 없음의 account deletion `closedByOwner`, permanent suspension `closedByModeration` 수렴
  - 2026-08-13 최종 Functions lint/build·191/191, Socket check·76/76, Rules 41/41, transaction 26/26, iOS 관련 suite와 Production Simulator build 통과. transaction suite는 유효 lease의 `processing` succession job 재점유 금지와 최대 시도·만료 lease의 `failed` 종결을 검증한다. Production rollout과 두 계정 앱 QA, 대용량 pending upload 취소, 같은 provider 재로그인까지 완료했다.
- Moderator delegation Phase 2 로컬 검증:
  - `functions/src/chat/moderation/{contracts,index.contract}.test.ts`: 역할 mutation UUID/입력과 신규 callable 5개 export를 고정한다.
  - `firestore-tests/chat-moderation.emulator.test.mjs`: 첫 임명의 server-only count 생성, 임명·replay·회수, 사임·퇴장·수동 이전, owner/moderator 제재 matrix, 퇴장 작성자 과거 메시지 삭제, event/outbox/receipt 원자성을 검증한다.
  - `firestore-tests/moderation-capabilities.rules.test.mjs`: owner/role/private state/event 직접 mutation, member 직접 삭제와 read frontier rollback을 거부한다.
  - `OutPickTests/CloudFunctions/CloudFunctionsChatModerationLifecycleRepositoryTests.swift`: role access와 임명·회수·사임·퇴장·이전 callable 매핑을 검증한다.
  - 2026-09-01 Functions 246/246, Rules 47/47, transaction 56/56, iOS 집중 7/7과 Development Simulator build가 통과했다. 배포·Production 변경은 수행하지 않았다.
- Moderator delegation Phase 3 로컬 검증:
  - `Socket/test/messages/sequenceStore.test.js`, `Socket/test/roles/roleEventDeliveryWatcher.test.js`, architecture contract가 일반 message 이중 sequence, legacy replay, role event emit/즉시 삭제, retry/10회 실패 TTL, forged event 거부와 production start/stop 연결을 검증한다.
  - `functions/src/chat/media/readyService.test.ts`와 Firestore transaction suite가 media 이중 sequence와 role mutation의 timeline-only sequence를 검증한다.
  - iOS는 `RoomRoleEventPayloadTests`, `JoinedRoomProjectionTests`, `ChatMessageActionPolicyTests`, `RealtimeSocketListenerBinderTests`, `ChatReadStateStoreTests`, `ChatRoomReadStateStoreTests`, `ChatUnreadCatchUpStateTests`, GRDB migration/mapper/store와 ChatRoomViewModel 관련 suite에서 렌더 계약, dedupe, 검색·action 제외와 dual frontier를 검증한다.
  - 2026-09-01 Socket 106/106, Functions 246/246·lint 오류 0, Rules 47/47, transaction 56/56, iOS 관련 12개 suite와 보강 read-state suite, Development build-for-testing이 통과했다. 실제 reconnect·background·pagination·Dynamic Type 수동 QA와 배포는 미수행이다.
- Moderator delegation Phase 5 로컬 검증:
  - 부모 장애 회귀(2026-09-02): deadline Emulator suite에 부모 query 실패 후 독립 승계·오류 보존, claim 뒤 부모 실패 경쟁, 실제 fence 취소, 실패 부모 watchdog 만료와 failed-room-only replay, 부모 attempt 소진을 추가했다. 기존 fake 재현의 completed/staleFence 오기록을 수정했으며 변경 후 해당 suite와 chat moderation 합계 31/31을 통과했다.
  - 2026-09-02 최종 보정 검증: Functions 253/253·lint 오류 0·build 성공, 선택 Rules suites, deadline 포함 transaction 32/32, TTL/index manifest 4/4. Development 실제 Cloud Tasks에서 성공·50초 만료·중복/지연 task·실패 방 재처리를 검증했다. Production 최신 빌드 임명→회수 QA는 역할 원복·이벤트 2건·unread/preview 유지·읽음 마커 제외·outbox 0·관련 ERROR 0을 확인했다. 아래 2026-09-01 미배포 표기는 당시 이력이다.
  - `functions/src/chat/moderation/roomMembershipSweep.test.ts`와 `index.contract.test.ts`가 방별 최대 4회·50초 deadline 경계, 실패 후 대기 5/15/20초, 일시/영구 오류 분류, Firestore trigger retry false와 Task Queue metadata를 고정한다.
  - `firestore-tests/room-succession-deadline.emulator.test.mjs`는 부분 성공, 일반 참여방 27개 pagination, claim 뒤 시간 만료, commit 응답 유실, processing 장애 후 실패 확정, 방별 4회 상한·독립 예산, 수동 재처리 generation, stale 계정 fence와 legacy creatorUID 재발견 제외를 검증한다. fake clock과 Firestore transaction 응답/오류 주입을 사용한다. `run-firestore-tests.mjs`에 포함되며 Emulator 전용 project/host를 assert한다.
  - `firestore-tests/room-role-indexes.contract.test.mjs`는 receipt/outbox/방별 완료 상태 TTL과 기존 subject index 보존을 검증한다. `node --test firestore-tests/room-role-indexes.contract.test.mjs`로 독립 실행한다.
  - `firestore-tests/chat-moderation.emulator.test.mjs`가 일반 참여자 제외·earliest moderator 승계, 후보 없음 종료, account deletion resolved finalizer gate, stale permanent fence, pagination attempt 비소비, 역할 이벤트 익명화/outbox를 검증한다.
  - iOS `ChatRoomSessionActorTests`, `RealtimeSocketListenerBinderTests`, `JoinedRoomsClosureNoticeTests`가 동일 event ID 익명화본 1회 수용과 `ownerDeleted` 안내를 검증한다.
  - 2026-09-01 Functions 249/249·lint 오류 0·build 성공, Rules 47/47, transaction 59/59, iOS Development build-for-testing과 관련 3개 suite가 통과했다. Task Queue/Functions/index 배포와 실제 Cloud Tasks 시간 QA는 미수행이다.
- Moderator delegation Phase 6 migration planner 검증:
  - `functions/scripts/room-moderator-cutover-plan.test.mjs`가 joined projection 전체 inventory와 mismatch/orphan 차단, legacy 누락 backfill, role event 혼합 dual frontier, owner/role 충돌과 counter 역전 fail-closed, 결정적 plan hash, exact apply fence, 멱등 재실행을 검증한다.
  - `functions/src/chat/moderation/rollout.test.ts`가 기본 비활성 서버 gate와 신규 권한 생성 callable 두 곳의 연결을 고정한다. `OutPickTests/AppRolloutGateTests.swift`는 의미적 버전, 업데이트 URL, 설정 오류 fail-open/기능 fail-closed를 검증하고 `ChatRoomParticipantRolePolicyTests`는 flag off의 신규 임명 숨김과 기존 안전 액션 보존을 검증한다.
  - 2026-09-01 planner fixture 7/7, Functions 전체 252/252, lint 오류 0(기존 warning 14), Socket check·106/106, iOS Development build-for-testing과 두 집중 suite가 통과했다. Development migration은 15 writes apply 후 write 0·blocker 0으로 수렴했고 Rules/index/TTL·Functions·Socket·두 flag를 반영했다. 실제 앱 수동 QA와 Production 변경은 수행하지 않았다.
- Phase 6 텍스트·rate-limit 자동 검증:
  - `functions/src/lookbook/comments/contracts.test.ts`는 UTF-16 1,000 경계, UUID, 결정적 comment ID, UTC minute/retryAt과 20회 quota를 검증한다.
  - `firestore-tests/comment-write-rate-limit.emulator.test.mjs`는 동시 replay가 comment/metric/quota를 한 번만 소비하는지, 댓글·답글 합산 20회와 멱등 충돌을 transaction으로 검증한다. Rules suite는 client의 rate bucket read/write 금지를 검증한다.
  - Socket handler/payload/push/rateLimiter tests는 canonical principal key, 종류별 limit, 같은 message ID 재소비 방지, idle sweep/cap fail-closed와 `senderEmail`·원문 로그 비노출을 검증한다.
  - iOS는 `CloudFunctionsCommentRepositoryTests`, chat/GRDB 관련 기존 suite와 Development Simulator build로 UUID payload, 입력 정책, 모델·DB schema의 email 제거 회귀를 검증한다.
  - 2026-08-18 Socket check·85/85, Functions lint/build·197/197, Rules 41/41, transaction 29/29, iOS 관련 6개 suite 고유 테스트 26개와 Development build-for-testing이 통과했다.
- Phase 4 전역 차단 자동 검증:
  - `UserBlockSessionControllerTests.swift`: cache 선적용 뒤 서버 교체, 서버 실패 cache fallback, snapshot 없는 실패의 UGC fail-closed, block/unblock mutation 뒤 메모리·계정별 snapshot 동기화와 이전 계정의 지연 실패가 새 계정 Store를 지우지 않는 경쟁 조건을 검증한다.
  - `ChatVisibleUnreadUseCaseTests.swift`: 앱 종료 중 누적된 혼합 발신자 메시지를 page 단위로 필터링하고, 전부 숨김·고정 latestSeq·목록 visible unread/preview 교체·조회 실패 raw unread fallback을 검증한다.
  - `ChatMessageActionPolicyTests.swift`: 타인 메시지의 block action과 기존 reply/copy/delete/report/announcement 권한 회귀를 검증한다.
  - `ChatRoomBannedUsersViewModelTests.swift`: 강퇴 사용자 첫 페이지·pagination 중복 제거, 선택 항목 강퇴 해제 성공 제거, 실패 시 목록·작업 상태 보존을 fake UseCase로 검증한다.
  - `ChatRoomViewModelMessageActionTests.swift`: hidden seq와 현재 window의 visible seq를 합쳐 read frontier 연속 구간을 계산해 숨김 뒤 정상 메시지도 읽음 처리되는지 검증한다.
  - `AppDatabaseMigrationTests.swift`, `GRDBChatMediaIndexStoreTests.swift`, `OutPickTests.swift`: 16번째 media sender UID migration, 저장/페이지 순서, local/remote dedupe와 차단 visibility용 sender UID 계약을 검증한다.
  - Functions `lookbook/safety/blockContracts.test.ts`와 전체 suite는 exact block/unblock payload, 자기 차단·unknown field 거부, 신규 callable export를 검증한다. Socket `push/chatPushService.test.js`는 recipient 차단과 relation lookup 실패 시 push fail-closed를 검증한다.
- iOS Phase 3: `CloudFunctionsChatModerationLifecycleRepositoryTests`, `ChatRoomExitUseCaseTests`, `ChatRoomMessageUseCaseTests`, `ChatRoomFirestoreMapperTests`, `JoinedRoomsClosureNoticeTests`가 callable payload, lifecycle version, 서버 성공 후 local cleanup 위임, legacy room 기본 version, 종료 안내 문구와 확인 후 stale fetch 중복 방지를 검증한다. `BannerPresentationQueueStateTests`는 이전 화면의 stale leave가 현재 visible room을 해제하지 않는 계약을 검증한다.
- Socket Phase 3: `roomClosureWatcher.test.js`가 pending/completed job의 단일 emit과 강제 leave, 잘못된 job 무시를 검증하고 `roomHandlers.test.js`가 방장 종료 handler는 ACK만 반환하며 watcher의 단일 종료 side effect와 경합하지 않음을 검증한다.
- Phase 3.1 공용 종료 tombstone: `chat-moderation.emulator.test.mjs`가 콘텐츠 즉시 정리, 방장 즉시 cleanup, 확인 사용자만 membership 제거, active room 확인 거부, 멱등 재확인과 170명/14일 batch 정리를 검증한다. `moderation-capabilities.rules.test.mjs`는 joined projection 보유자만 tombstone을 읽고 Messages는 읽지 못함을 검증한다. iOS는 `ChatRoomRuntimeUseCaseTests`와 `CloudFunctionsChatModerationLifecycleRepositoryTests`에서 종료 payload 전달과 `acknowledgeRoomClosure` callable을, `ChatNavigationStackPolicyTests`에서 종료 확인 뒤 목록 복귀·생성 route 제거·같은 방 안내 1회 제한을, `RealtimeSocketListenerBinderTests`에서 권위 종료 최초 1회 수용과 방 재생성 reset을 검증한다. `JoinedRoomsClosureNoticeTests`는 실시간·오프라인 확인 직후 제거된 방의 stale fetch 재삽입 차단, 서버 응답 전 optimistic 제거, 서버 실패 시 목록 복원을 검증한다. 2026-08-11 오프라인 보정 뒤 해당 suite 5개가 iPhone 17 Pro Simulator에서 통과했다.
- 수동 QA:
  - Phase 3.1 방장 접속 중·오프라인 종료와 관리자 접속 중·오프라인 종료를 Google/Kakao Production 계정으로 완료했다. 마지막 오프라인 관리자 종료는 양 계정 모두 안내 1회·확인 즉시 행 제거·재실행 미복원을 통과했고 member/joinedRooms/roomStates 0건, 14일 retention 예약과 관련 ERROR 0건을 확인했다.
  - 메시지/프로필/참여자/방 설정 신고 진입과 문구·접근성
  - 두 계정 block/unblock, background/banner/push, creator remove/unban
  - 2026-08-11~12 Production 앱 종료 혼합 unread는 기존 두 계정과 QA 방 한정 비차단 합성 발신자로 `lastReadSeq=1`, 차단 `seq=2`, 비차단 `seq=3`을 구성해 목록 unread 1·비차단 preview·재진입 차단 메시지 제외를 통과했다. 방/메시지/projection/block/Storage 잔존은 0건이다.
  - Google·Kakao 재인증·탈퇴·재가입과 동일 restricted principal 복원은 2026-08-07 Development에서 통과했다. Apple은 로그인 구현 전이라 미완료이며 Production Kakao User ID Fixed 콘솔 확인은 출시 gate다.
  - 허용 패션/성적/폭력/UNKNOWN 이미지·동영상 corpus
- Phase 0에서는 테스트 코드를 추가·실행하지 않는다. 이후 Phase는 실패 비용이 큰 인증·삭제·Rules·Storage 계약이므로 해당 Phase 완료 전에 자동 테스트와 build를 실행한다.

- Phase 6-A read frontier/catch-up state: `OutPickTests/ChatReadStateStoreTests.swift`, `OutPickTests/ChatUnreadCatchUpStateTests.swift`
  - seeded monotonic frontier, visible candidate의 연속 상한, explicit gap 승인과 window 없는 final frontier를 검증한다.
  - scalar unread count, 고정 target, generation 기반 stale/중복/실패 거부와 10,000개 latest event payload 비보관을 검증한다.
  - 2026-07-17 iPhone 15 Pro iOS 17.2 Simulator에서 2개 suite 19개 테스트와 generic Simulator build가 통과했다.

- Phase 6-B bounded catch-up/persistence: `OutPickTests/ChatLatestMessageWindowTests.swift`, `ChatRoomMessageUseCaseTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `ChatRoomViewModelMessageActionTests.swift`
  - 고정 80개 server-authoritative target query, `Int64.max` 분기, target 이하 정규화·누락 실패를 검증한다.
  - 10,000개 catching-up incoming의 scalar-only 상태, manager 저장 성공 이후 outbox reconciliation, 서버 확정 ID batch 삭제를 검증한다.
  - 2026-07-17 iPhone 15 Pro Simulator에서 4개 suite 22개 테스트와 generic iOS Simulator build가 통과했다.

- Phase 6-C latest UI/read handshake state: `OutPickTests/ChatReadStateStoreTests.swift`, `ChatUnreadCatchUpStateTests.swift`, `ChatLatestMessageWindowTests.swift`, `ChatMessageWindowStoreTests.swift`, `ChatRoomViewModelMessageActionTests.swift`
  - realtime 없는 initial entry tail preview 상태, target/preview 동시 고정과 이후 신규 seq 잔존, 표시 실패/retry, visible 연속 상한과 window-independent final frontier를 검증한다.
  - latest window 교체의 서버 확정 ID 우선과 unresolved failed local message 보존, 날짜 separator/300개 virtualization 회귀를 검증한다.
  - explicit 이동 표시 성공 뒤 즉시 server persistence, server 성공 이후 shared mark, 실패 pending 보존을 lifecycle spy로 검증한다.
  - 2026-07-17 iPhone 17 Pro Max Simulator에서 5개 suite 고유 테스트 48개와 앱 전체 Simulator build가 통과했다. 실제 Firebase pop/re-entry persistence, preview card·keyboard/reply/notice 충돌과 VoiceOver는 Phase 6-D 수동 재QA 대상이다.
  - 후속 initial preview sender 계약으로 local profile cache hit의 닉네임+내용과 cache miss의 nil sender fallback 테스트 2개를 `ChatRoomViewModelMessageActionTests`에 추가했다. 프로젝트 실행 원칙에 따라 새 테스트 실행은 보류했고 2026-07-17 iPhone 17 Pro Max Simulator 앱 build는 통과했다.
  - 2026-07-17 최종 제품 결정으로 위 initial preview 테스트 계약을 폐기하고 `initialEntryTailShowsLatestJumpWithoutRealtimeEvent`와 local profile cache 테스트를 제거·반전했다. no-realtime 미표시, realtime 닉네임+내용, sender 누락 fallback, dismiss 시 unread 불변과 stale timer target 방어 테스트를 추가했다. Phase 6 관련 5개 suite 52개를 실행해 실패·skip 0개로 통과했다. 실제 3초 경과와 pop/re-entry 비복원은 두 Simulator 수동 QA도 통과했으며 diffable visible target 억제는 남아 있다.
  - persistence 계측 추가 뒤 동일 5개 suite 52개를 재실행해 실패·skip 0개로 통과했다. explicit 성공은 authoritative readback 호출을, write 실패는 readback 미호출을 spy로 검증한다. 계측 추가 빌드도 iPhone 17 Pro Max Simulator에서 성공했다.
  - initial latest 위치 수정 중 같은 52개 테스트를 다시 실행해 실패·skip 0개를 확인했다. 최종 UIKit-only reload/layout-settle 변경은 Simulator build와 실제 Firebase `lastRead/latest=92`, `999999` 재진입 화면으로 수동 검증했다.

- iOS Socket listener 안정화 test: `OutPickTests/RealtimeSocketListenerBinderTests.swift`
  - client event 3개와 named event 5개의 최초 1회 등록, 같은 binder 재호출 무효, 반복 connect callback 중 등록 수 불변, 새 Socket/binder 독립 등록과 payload 전달을 검증한다.
  - Phase 1의 mixed message event FIFO와 queue 종료, joined-room 공통 ID admission의 room 분리·local seq 0 우회·300개 eviction·reset, background high watermark promotion과 stale visible lease 종료 거부를 검증한다.
  - 실행: `xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'platform=iOS Simulator,id={simulator-id}' -only-testing:OutPickTests/RealtimeSocketListenerBinderTests test`.
  - 2026-07-16 `RealtimeSocketListenerBinderTests`와 `ChatRoomSessionActorTests` 대상 19개 테스트가 iPhone 15 Pro iOS 17.2 Simulator에서 통과했다.
  - 실제 reconnect gate는 cold launch 5회와 background/foreground 5회, room rejoin/text 중복 부재와 credential raw log 부재를 확인한다. 상세 절차는 `docs/ai/tasks/core-infrastructure-modularization/phases/phase-6-ios-socket-stabilization.md`에 있다.

- Phase 5 Socket 테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-5-socket-tests.md`
  - `Socket/test/`에서 application/architecture, auth, room/message/media handler와 service, lifecycle/runtime/state 계약을 검증한다.
  - `Socket/scripts/run-tests.mjs`는 모든 `*.test.js`를 재귀 발견하며 0개 test를 실패 처리한다.
  - 실행: `npm --prefix Socket run check`, `npm --prefix Socket test`.
  - 2026-07-14 syntax check와 43개 `node:test`, ADC 기반 room preload/health/graceful shutdown local smoke가 통과했다. Cloud Run/iOS 실제 송수신 smoke는 미수행이다.

- Socket message dedupe Phase 1~2 tests: `Socket/test/messages/messageDeliverySingleFlight.test.js`, `Socket/test/messages/sequenceStore.test.js`, `Socket/test/handlers/messageHandlers.test.js`, `Socket/test/lookbookShare/lookbookShareHandler.test.js`, `Socket/test/handlers/mediaHandlers.test.js`, `Socket/test/media/mediaUploadService.test.js`
  - 동일 identity owner/follower 병합, kind/room/message key 분리, 실패 공유·entry 해제·재시도를 검증한다.
  - 신규 transaction `{ seq, created: true }`, 기존 message `{ seq, created: false }`, duplicate no-write와 winner-only emit/push를 검증한다.
  - media 완료 retry의 sender/kind/path 검증, reservation 삭제 race 재확인과 독립 coordinator transaction loser를 검증한다.
  - 2026-07-16 closeout에서 syntax check와 전체 62개 테스트를 다시 통과했다.
  - 2026-07-15 `npm --prefix Socket run check`와 Socket 전체 62개 `node:test`가 통과했다.

- Chat route lifecycle hardening tests: `OutPickTests/ChatNavigationControllerTests.swift`, `ChatNavigationStackPolicyTests.swift`, `ChatOpenRoomRequestStateTests.swift`, `ChatOpenRoomRequestRegistryTests.swift`, `ChatRoomRouteLifecycleStateTests.swift`
  - Chat navigation은 root edge-pop 차단, 일반 push 허용, 화면 정책에 따른 방 생성형 push 차단, iOS 26 content-pop 유지 계약을 검증한다.
  - 같은 stack의 기존 Chat route 교체와 non-Chat prefix 보존, top same-room no-op를 검증한다.
  - stack별 요청 격리, same-room 실제 Task 공유, same-stack latest-wins, stale 성공·실패 무시와 실패 후 재시도를 검증한다.
  - terminal route가 `didAppear`로 부활하지 않고 transient binding 복구 대상에서 제외되는 lifecycle 계약을 검증한다.
  - 2026-07-22 D19 방 생성 차단 보강 뒤 Chat navigation 4개와 관련 navigation/route/lifecycle/request 묶음 24개, iOS 26.2 Simulator build/install/launch가 통과했다. 방 생성 swipe 차단과 Back 확인창도 Simulator 수동 QA를 통과했으며 이 시점에는 실제 Chat·실기기 swipe가 남아 있었다.
- Lookbook interactive-pop tests: `OutPickTests/LookbookNavigationControllerTests.swift`, `BrandRequestViewModelTests.swift`, `AdminLookbookDeletionManagementViewModelTests.swift`, `LookbookExtractionReviewViewModelTests.swift`
  - root/browse/stateful 동적 허용, iOS 26 content-pop 상태와 브랜드 요청·삭제·검토 draft 판정을 검증한다.
  - 같은 날 실제 Chat·검색 실기기 swipe 취소/완료로 Phase 6을 종료했다. Phase 7 dead transition 네 파일 제거 뒤 정적 참조 0건, 같은 24개 회귀와 generic Simulator build가 통과했다.
  - Phase 7 삭제 후 Chat push/pop과 Profile modal 열기/닫기 수동 smoke QA도 통과했다.
  - Phase 7B Profile modal edge-swipe는 단순 touch wiring이라 별도 UI unit test를 추가하지 않았다. 기존 24개 회귀와 generic Simulator build, iOS 26.2 Simulator 설치·실행이 통과했고 사용자가 짧은 swipe 유지, 임계값 충족 닫기, X 버튼·avatar tap을 수동 확인해 Phase 7B를 종료했다.
  - Phase 8 Chat gesture는 UIKit touch arbitration 전용 추상화를 추가하지 않고 기존 `ChatRoomViewModelMessageActionTests`, `ChatMessageActionPolicyTests`를 회귀 대상으로 유지한다. 제거 symbol 참조 0건, `git diff --check`, generic Simulator build가 통과했고 기존 테스트 실행은 보류했다. iPhone 17 Pro Max iOS 26.2에서 keyboard/attachment/message menu background dismiss, input/attachment control 보존, message/announcement long press, settings dim, Lookbook과 retry cell tap이 통과했다. 마지막 media/profile cell tap도 사용자의 실제 Simulator 확인으로 통과해 Phase 8 수동 QA를 완료했다.
  - Phase 9 최종 회귀에서 위 5개 suite 24/24를 재실행했다. 이어 `ChatRoomSessionActorTests`, `RealtimeChatIngressOrderingTests`, `RealtimeSocketRoomSummaryOwnershipTests`, `RealtimeSocketListenerBinderTests`, `ChatReadStateStoreTests`, `ChatRoomReadStateStoreTests`, `ChatUnreadCatchUpStateTests`, `ChatMessageWindowStoreTests`, `ChatRoomViewModelMessageActionTests` 86/86과 최신 Debug build/install/launch가 통과했다.
  - 실제 Simulator에서 검색 prefix 보존, RoomCreate 취소 흐름, Lookbook 공유 완료 후 명시적 Chat 이동, 참여중/Lookbook stack 복원을 확인했다. 실제 Firebase 완료 순서 역전은 fetch가 빨라 수동 재현하지 않았고 request state/registry 자동 테스트를 최종 판정 근거로 사용한다.
- 시즌 대표 이미지 보강 Phase 7: Worker `src/extraction/{image-candidates,season-cover}.test.ts`, `season-discovery.test.ts`, `season-discovery-processor.test.ts`, fixture `fixtures/season-cover/`; Functions `seasonCandidateParser.test.ts`, `seasonDiscoveryContract.test.ts`. 최종 Worker 115/115·fixture 9/9, Functions 146/146·각 lint/build와 Development Simulator build가 통과했다. Development AMOMENTO 실제 후보·대표 이미지 15/15, 저장 URL과 상세 첫 이미지 일치, 앱 카드 렌더링, queue/ERROR 0을 확인했다.

### Chat route 테스트 파일 지도

| 테스트 파일 | 고정하는 계약 |
| --- | --- |
| `OutPickTests/ChatNavigationControllerTests.swift` | root 차단, push 허용, 화면별 opt-out과 iOS 26 content-pop 유지 |
| `OutPickTests/ChatNavigationStackPolicyTests.swift` | non-Chat prefix 보존, 기존 Chat 제거, same-room no-op |
| `OutPickTests/ChatOpenRoomRequestStateTests.swift` | stack별 token/snapshot, supersede와 stale completion 판정 |
| `OutPickTests/ChatOpenRoomRequestRegistryTests.swift` | 실제 Task coalesce, 오류 공유, retry cleanup과 same-stack latest-wins |
| `OutPickTests/ChatRoomRouteLifecycleStateTests.swift` | transient cover, 취소/완료 pop, dismiss/replacement 단일 finish와 terminal 비가역 |

Chat gesture 자체는 UIKit touch delivery를 위한 별도 추상화를 만들지 않았으므로 전용 unit test가 없다. gesture wiring은 Simulator/실기기 수동 QA로, gesture 이후 message/read/realtime 상태는 Phase 9의 86개 영향 범위 테스트로 검증한다.

- iOS message ingress dedupe Phase 3 tests: `OutPickTests/ChatRoomSessionActorTests.swift`
  - 한 명/두 명 consumer의 동일 ID 단일 전달, 종류와 무관한 ID 정책, 같은 ID·다른 seq first-wins, 실제 300개 oldest eviction과 actor 재생성 reset을 검증한다.
  - 로컬 실패 메시지가 같은 ID의 후속 서버 확인 event를 차단하지 않는 source 분리도 검증한다.
  - 2026-07-15 신규 actor 6개와 `ChatMessageWindowStoreTests`, `GRDBChatMessageStoreTests`, `RealtimeSocketListenerBinderTests` 회귀를 합친 고유 테스트 20개, generic Simulator build가 통과했다.
  - 공통 admission은 Phase 1에서 구현했다. Phase 2·3 strict seq/recovery와 Phase 4 suspend/rejoin 감사·terminal 종료는 `OutPickTests/RealtimeChatIngressOrderingTests.swift`, Banner hard-cap summary는 `OutPickTests/BannerPresentationQueueStateTests.swift`, baseline 전달은 `ChatRoomRealtimeUseCaseTests.swift`, 실제 route 판정은 `ChatRoomRouteLifecycleStateTests.swift`에서 검증한다.
  - Phase 5 차단 결함 회귀는 `ChatMessageWindowStoreTests`의 same-day/cross-day older·newer separator identity, `RealtimeRoomJoinStateTests`의 concurrent join/stale ACK/reconnect invalidation, `BannerSubscriptionRetryPolicyTests`의 capped backoff와 recoverable 재구독으로 검증한다. 관련 17개 suite 87개 테스트와 generic Simulator build가 2026-07-16 통과했다.
  - room-close 최종 회귀는 `RealtimeSocketListenerBinderTests`의 authoritative closure 선행/observer 후행 replay와 same-room create reset, room-not-found ACK mapping, `ChatRoomRuntimeUseCaseTests`, `ChatRoomRouteLifecycleStateTests`로 검증한다. 2026-07-17 대상 테스트가 통과했다.
  - 실제 QA는 셀룰러 iPhone 14 disconnect/reconnect의 `680001 → 680004`, `990001` leave 목록 제거, room close 자동 route 종료와 Cloud Run 종료 후 join 재시도 0회까지 통과했다.

### Moderator delegation Phase 4 iOS 자동 검증

- `ChatRoomRoleSessionTests`: 현재 방 listener 단일 생성, cache/server/mutation 활성화 경계, background 해제·foreground 재시작, legacy 역할 호환, joined projection 삭제를 검증한다.
- `ChatRoomParticipantRolePolicyTests`: 나→방장→관리자→일반 참여자 정렬, pinned/page 중복 제거, owner/moderator action matrix, cache/offline 비활성, 안정 오류 문구를 검증한다.
- `ChatMessageActionPolicyTests`: 역할 이벤트 action 제외, server-confirmed owner/moderator 운영 권한, 관리자 상호 제재 금지, 퇴장 작성자 메시지 운영 판정을 검증한다.
- `ChatRoomExitUseCaseTests`: 일반 퇴장·방 종료·소유권 이전 성공 뒤 로컬 cleanup과 서버 실패 시 cleanup 보류를 검증한다.
- 2026-09-01 iPhone 15 Pro iOS 17.2에서 위 suite와 `ChatRoomViewModelMessageActionTests`, `CloudFunctionsChatModerationLifecycleRepositoryTests`, `RoomRoleEventPayloadTests`가 통과했고 Development `build-for-testing`이 성공했다. 실제 Firebase·background·Dynamic Type 수동 QA는 미수행이다.

- Socket candidate QA configuration tests: `OutPickTests/SocketDebugQAConfigurationTests.swift`
  - DEBUG 전용 message kind별 첫 성공 ACK 유실 설정을 검증한다.
  - launch environment key는 `OUTPICK_DEBUG_DROP_FIRST_MESSAGE_ACK_KIND`이며 Release에서는 코드가 컴파일되지 않는다.
  - Socket URL DEBUG override는 환경 분리 작업에서 제거했다. 앱은 선택한 scheme의 canonical Socket URL만 사용한다.

- iOS send receipt tests: `OutPickTests/ChatMessageEmitAckMapperTests.swift`, `ChatOutgoingOutboxUseCaseTests.swift`, `LookbookChatShareUseCaseTests.swift`
  - ACK의 identity/seq/duplicate 파싱, matching message 실패 해제와 서버 attachment 병합, identity mismatch 거부를 검증한다.
  - outbox 유무와 관계없는 서버 확정 GRDB 저장과 Lookbook 결과 불명 retry의 동일 message ID 재사용을 검증한다.
  - 2026-07-15 receipt 영향 범위 9개 suite test, test target build-for-testing, Debug/Release generic Simulator build가 통과했다.

- Socket room summary ownership regression: `OutPickTests/RealtimeSocketRoomSummaryOwnershipTests.swift`
  - Socket ACK 이후 iOS가 `updateRoomLastMessage`를 호출하지 않고 서버 seq transaction만 `Rooms.lastMessage*`를 쓰는 source 계약을 검증한다.
  - 2026-07-15 기존 ACK mapper/outbox/Lookbook suite와 합친 targeted test 26개와 양쪽 Simulator Debug build가 통과했다.

- App database bootstrap unit tests: `OutPickTests/AppBootstrapFailureInjectorTests.swift`, `OutPickTests/AppCompositionRootTests.swift`
  - DEBUG once/always 실패 주입 상태와 database factory 오류 mapping을 검증한다.
- App database bootstrap UI tests: `OutPickUITests/AppBootstrapFailureUITests.swift`
  - 실제 DB 손상 없이 실패 root, once 재시도 성공, always 반복 실패·앱 생존을 검증한다.

- Phase 3 GRDB 테스트 계획: `docs/ai/tasks/core-infrastructure-modularization/phases/phase-3-grdb-tests.md`
  - temporary `AppDatabase` fixture로 production DB를 열지 않는다.
  - 15개 fresh migration, mapper, message/FTS/media strict rollback, outbox, profile LRU, transient/exit cleanup transaction을 검증한다.
  - 구현 파일: `OutPickTests/GRDB/`의 migration/mapper/Store 7개 test suite와 `TestSupport/TemporaryAppDatabase.swift`.
  - 관련 UseCase/Manager 회귀: `ChatOutgoingOutboxUseCaseTests`, `ChatProfileSyncManagerTests`, `ChatRoomExitUseCaseTests`.
  - 2026-07-13 targeted test 묶음과 generic Simulator build가 통과했다. 수동 QA는 미수행이다.

- Image viewer unification verification:
  - Task QA checklist: `docs/ai/tasks/image-viewer-unification/qa-checklist.md`
  - Phase progress and performed verification: `docs/ai/tasks/image-viewer-unification/progress.md`
  - Pure policy tests: `OutPickTests/ImageViewerPagePolicyTests.swift`
    - `ChatImagePreviewItem.previewPaths` thumb/original ordering and duplicate local pending path handling.
    - `ChatMessage.displayableAttachments` sorting/filtering contract used by chat preview/viewer mapping.
    - `ImageViewerPage` local-only initial image contract and `SimpleImageViewerVC.ProgressivePage` compatibility alias.
  - 기본 회귀 확인은 1장/30장/pending/final/빠른 paging/manual save QA와 `xcodebuild -scheme OutPick-Development -destination 'generic/platform=iOS Simulator' build`를 기준으로 한다.
- Image viewer targeted test:

```bash
xcodebuild -scheme OutPick-Development -destination 'platform=iOS Simulator,name={simulator}' test -only-testing:OutPickTests/ImageViewerPagePolicyTests
```

- Joined rooms session store tests: `OutPickTests/JoinedRoomsSessionStoreTests.swift`
  - `JoinedRoomsSessionStore` snapshot API, replace/add/remove/clear/contains 동작을 확인한다.
- Room exit use case tests: `OutPickTests/ChatRoomExitUseCaseTests.swift`
  - socket leave/close 성공/실패, local cleanup, joined room remove 경로를 확인한다.
- Chat room Firestore mapper tests: `OutPickTests/ChatRoomFirestoreMapperTests.swift`
  - 경로 document ID 우선, 핵심 필드 검증, ancillary 기본값과 identity-free write payload를 확인한다.
- Create room use case tests: `OutPickTests/CreateRoomUseCaseTests.swift`
  - duplicate 차단, Repository 반환 room 이벤트, 저장 실패 시 이벤트 미발행을 확인한다.
- Media upload tests: `OutPickTests/ChatMediaUploadUseCaseTests.swift`
  - image/video upload orchestration, preflight/finalize 실패, pending/outbox 연동을 확인한다.
  - 동기 socket connected guard가 아니라 preflight/finalize ACK 실패 경로를 검증한다.
  - `active_upload_limit`이면 같은 `uploadID`·`clientMutationID`로 configured backoff 뒤 재예약하고, 다른 오류는 재시도하지 않는지 검증한다.
  - 앱 재실행 session은 foreground PUT을 호출하지 않고 status만 2·4·8초 reconcile하며, server active 전환·cancel/ready·retry 소진·조회 오류가 각각 monitoring 또는 manual retry로 수렴하는지 검증한다.
- Media upload turn queue tests: `OutPickTests/ChatMediaUploadTurnQueueTests.swift`
  - image/video kind별 FIFO, 두 lane의 독립 진행, 취소된 waiter 제거와 다음 waiter 승계를 검증한다.
- Media reservation error mapping tests: `OutPickTests/ChatMediaReservationErrorMappingTests.swift`
  - Socket ACK의 `serverErrorCode == active_upload_limit`만 typed capacity error로 매핑하고 다른 오류 원문은 보존하는지 검증한다.
- Pending media presentation tests: `OutPickTests/ChatPendingMediaUploadStoreTests.swift`, `OutPickTests/ChatMessageActionPolicyTests.swift`. 활성 상태 무표시·실패 상태 액션 분류와 미확정 로컬 메시지의 서버 액션 차단을 검증하며, 2026-08-20 시간 위치 아이콘 리팩토링 뒤 iPhone 17 Pro iOS 26.2 Simulator에서 14/14 통과했다. UIKit의 실제 아이콘 위치·터치 영역은 실기기 수동 QA 대상이다.
  - uploading/queued/processing은 무표시, failed/expired만 사용자 복구 UI 대상이라는 상태 계약을 검증한다.
  - 서버 확정 전 활성 `seq == 0` 로컬 미디어 메시지는 답장·복사·삭제·신고·차단·공지·내보내기 액션을 노출하지 않는지 검증한다.
  - `ChatMediaUploadUseCaseTests`는 pending attachment가 upload source를 직접 가리키는지, `ChatOutgoingOutboxUseCaseTests`는 재실행 복원 attachment도 보존된 original source를 가리키는지 검증한다.
  - `ChatAttachmentImageServiceTests`는 큰 local upload source를 원본 비율을 유지한 최대 1024px 이미지로 다운샘플링하는지 검증한다.
- Restored failure window tests: `OutPickTests/ChatMessageWindowStoreTests.swift`
  - server의 첫째 날·둘째 날 메시지 뒤 첫째 날 로컬 실패 메시지를 복원해도 반복 날짜 separator identifier가 유일하고 diffable initial snapshot이 중복 ID를 받지 않는지 검증한다.
  - 2026-08-20 관련 window/pending/action suite 26/26을 iPhone 17 Pro iOS 26.2 Simulator에서 통과했다.
  - `ChatOutgoingOutboxUseCaseTests.mediaReservationPersistsOnlySessionIdentityUntilTerminalFailure`는 reservation 뒤 session identity와 local retry payload는 보존하되 signed PUT URL·필수 header가 DB payload에 들어가지 않고, terminal 실패 뒤에도 재실행 실패 액션을 복원할 수 있는지 검증한다. 복원 수정 뒤 outbox/window/pending/action suite 34/34를 통과했다.
- Media selection chunk tests: `OutPickTests/ChatMediaSelectionChunkerTests.swift`
  - 30장 count 경계, 150 MiB aggregate 분할, 60장·70장 분할, 선택 순서와 각 메시지의 0-based attachment index 재부여를 검증한다.
- Outgoing outbox tests: `OutPickTests/ChatOutgoingOutboxUseCaseTests.swift`
  - 실패 message 복원, retry, local-only delete, 7일 실패 media/source 만료 정리, uploaded media cleanup과 v2 session identity 영속화, signed PUT URL·필수 header 비영속화, terminal/relaunch manual retry와 local payload 보존을 확인한다.
- GRDB migration tests: `OutPickTests/GRDB/AppDatabaseMigrationTests.swift`
  - fresh 19개 migration과 Phase 7.3 upload/session column 생성을 검증한다.
- Phase 7.6 Development rollout 후 Socket check·103/103, canonical/tagged readiness와 인증 handshake, Socket·영향 Function ERROR 0, deletion revision 10/10·delivery job 0을 확인했다. iPhone 17 Pro Max iOS 26.2 Simulator에서 Phase 7.5 관련 9개 suite 60/60과 `OutPick-Development` generic Simulator build가 재통과했다. 실제 A/B/admin 삭제·신고·오프라인 복구는 공동 수동 QA 대상이다.
- Phase 7.6 공동 QA에서 방장 타인 메시지 신고 누락과 커스텀 메뉴의 touch 종료 dismissal·하단 `내보내기` clipping을 발견했다. `ChatMessageActionPolicyTests` 7/7로 방장 `신고 + 삭제`, 본인/pending/deleted 차단을 검증하고 UIKit native context menu 전환 후 Development build/run을 통과했다. iPhone 17 Pro Max iOS 26.2 Simulator에서 touch 종료 뒤 유지, 외부 탭 종료, `복사` 실행 뒤 종료와 7개 항목 전체 접근·`내보내기` 미잘림을 확인했고 Development 실기기에서도 같은 메뉴 동작을 확인했다.
- seq 6 이미지 신고의 evidence descriptor 배포 drift 보정 전 Functions 전체 245/245·build·lint 오류 0을 통과했고 `readyService.test.ts`가 Message/mediaIndex의 generation·content type 보존을 확인했다. 신고 CTA activity indicator 제거 뒤 `ChatMessageReportViewModelTests` 3/3과 Development Simulator build가 통과했으며, B 시뮬레이터에서 제출 중 `신고` 비활성 버튼과 spinner 미표시를 확인했다.
- delete-first seq 7의 최종 UI 계약은 기존 메시지 셀의 정렬·버블·프로필·닉네임·시간·답장 영역을 유지하고 본문만 `삭제된 메시지입니다`로 교체하는 것이다. UIKit 단일 셀 happy path라 별도 snapshot test는 추가하지 않았다. 표시 메타데이터 보존 계약 보정 뒤 Functions build·lint 오류 0, `chat-moderation.emulator.test.mjs` 10/10과 `moderation-reports.emulator.test.mjs` 28/28로 작성자·관리자 삭제의 UID·닉네임·아바타·시간·답장 보존/본문·미디어 제거와 계정 탈퇴의 UID·아바타 제거/`알 수 없는 사용자`·시간 보존을 검증했다. Development 실제 seq 9·11 삭제는 활성 방 즉시 반영과 비활성 재진입 원문 flash 없음, Firestore sender 표시 필드 보존, Room revision/outbox 수렴을 통과했다. 재진입 server fetch가 sender 표시를 nil 처리하고 legacy marker가 `true`로 고착되던 회귀를 보정한 뒤 `ChatMessageRecordMapperTests` 4개와 `GRDBChatDeletionSyncStoreTests` 7개, 총 11/11 및 Development build가 통과했다. AD2 수정 앱에서 과거 seq 9 닉네임 `AD` 복구와 seq 11 tombstone 유지를 확인했다. seq 12 앱 종료·오프라인 복구는 Room head/message revision 4와 delivery `completed/attempt=1`, 온라인 복귀 뒤 원문 flash 없는 첫 tombstone 렌더링, 닉네임·시간·버블 유지, 삭제 원문 방 검색 0건을 실기기에서 확인했다.
- Phase 7.6 최종 자동 회귀는 Functions 245/245·build·lint 오류 0(기존 warning 24건), Rules·Storage 46/46, transaction 52/52, Socket check·103/103, iOS 관련 10개 suite 66/66, `OutPick-Development` Simulator build, 계약/index JSON parse와 `git diff --check`를 통과했다. iOS 첫 실행에서 과거 정책에 남은 방 생성자 신고 기대값 1건을 확정 정책인 타인 메시지 `신고 + 삭제` 허용으로 교정했고, 해당 suite 16/16 뒤 전체 66/66을 재검증했다. diff 리뷰에서는 중복 message ID admission 크래시 위험을 안전한 tombstone/revision 우선 병합으로 보정하고 회귀를 추가해 deletion sync·migration 10/10과 전체 관련 67/67을 재통과했다.

최근 targeted test 예시:

- Moderator delegation iOS 회귀: `ChatMessageWindowStoreTests`가 role event 단독 tail에는 읽음 마커가 없고 뒤의 첫 실제 unread message 바로 앞에만 마커가 생기는지 검증한다. 2026-09-01 `ChatMessageWindowStoreTests`와 `ChatRoomParticipantRolePolicyTests` 관련 21/21, Development build/run을 통과했고 iPhone 17 Pro Max 최대 접근성 글자 크기에서 참여자 이름·역할 배지 비중첩을 수동 확인했다.
- 2026-09-02 Development 수동 QA에서 방장 UI 임명·회수·취소, 관리자 본인 사임과 방장 제재 미노출, 소유권 이전·기존 방장 퇴장, 전용 임시 방 후보 없음 종료, 열린 설정 실시간 임명·회수, 실제 홈 background 중 회수와 foreground/pagination 복구를 확인했다. 최종 role projection·unread counter·outbox와 관련 Functions·Socket ERROR 0건도 재감사했다.
- 2026-09-02 최종 결함 수정은 `RoomRoleEventPayloadTests`의 목록 preview 역할 이벤트 제외·일반 메시지 순서, `ChatMessageMediaAttachmentMappingTests`의 bucket 기반 `gs://` resource path, `GRDBChatMediaIndexStoreTests`의 resolved path 영속을 집중 검증해 모두 통과했다. Development 초기화 후 새 방의 텍스트·GIF/JPEG·2초 MP4로 목록 preview, 설정 thumbnail/전체 미디어, 이미지·동영상 viewer와 방장 이전 후보 선택 UI를 iPhone 17 Pro Max iOS 26.2에서 수동 검증했다.

```bash
xcodebuild -scheme OutPick-Development -destination 'id={simulator-id}' test -only-testing:OutPickTests/JoinedRoomsSessionStoreTests
xcodebuild -scheme OutPick-Development -destination 'id={simulator-id}' test -only-testing:OutPickTests/ChatRoomExitUseCaseTests -only-testing:OutPickTests/JoinedRoomsSessionStoreTests
```

- 시즌 extraction issue 운영 테스트:
  - Functions `extractionIssueContract.test.ts`는 fixed와 상위 동일-stage runtime만 재시도를 허용하며, `index.contract.test.ts`는 새 callable export와 projection 인덱스를 고정한다.
  - Worker `issue-recorder.test.ts`는 자동 occurrence, terminal 재발, fixed runtime 실제 성공의 verified 전이를 검증한다.
  - iOS `SeasonDiscoveryManagementViewModelTests.swift`, `LookbookExtractionReviewViewModelTests.swift`, `CloudFunctionsSeasonImportRepositoryTests.swift`는 상태 매핑, fixed-only action과 callable 계약을 fake Repository/transport로 검증한다.
  - 2026-08-05 Functions 141개, Worker 102개, iOS 관련 4개 suite 22개와 양 TypeScript lint/build, Development Simulator build가 통과했다.
# 현재 메시지 전체 디스크 준비 검증

`ChatMediaViewportControllerTests`의 디스크 준비 최신 순서/예산 중단/이탈 취소, `ChatMediaViewportPolicyTests`의 먼 후보 거리순/중복 제거, `ImageDirectDiskDecodingTests`의 cache-only miss/hit, `ImageLRUMemoryStoreTests`의 무퇴거 삽입/압박 차단. 기존 파일 다운로드 회귀 포함 실행 로그 `/private/tmp/outpick-room-disk-preparation-tests.log`. 실기기 빠른 스크롤 체감은 별도 QA.
# 진입 초기 준비 검증

`ChatMediaViewportControllerTests.testPreparationStartsBeforeViewportResumeAndStopsOnDisappearance`, `ChatMediaViewportPolicyTests.testInitialPreparationStartsAtEntryAnchorWithoutLayout` 추가. 디스크/LRU 관련 회귀 실행 `/private/tmp/outpick-early-disk-preparation-tests.log`. 진입 직후 빠른 스크롤 개선은 실기기 QA로 별도 판정.
# 디스크 준비 동시성 검증

`ChatMediaViewportControllerTests.testTwoPreparationsRunTogetherButBudgetStopsRefill`: 두 후보 동시 시작/세 번째 상한/예산 중단. viewport+LRU+coordinator 회귀 로그 `/private/tmp/outpick-dual-disk-preparation-tests.log`. 실제 진입 즉시 스크롤 효과는 기기 QA로 별도 확인.
# 제한 해제 QA 검증

재실행 유지 검증: ChatMediaViewportControllerTests.testUnlimitedPreparationStartsAllCandidatesAndCancelsAll은 실제 viewport 기본 조립으로 5개 동시 시작/전체 취소를 검증한다. 별도 환경변수 설정 없음. ImageDirectDiskDecodingTests는 점유된 decode/IO 게이트 우회·파일 수명을 검증한다. 최종 회귀 로그 `/private/tmp/outpick-unlimited-default-tests.log`, 기기 빌드 `/private/tmp/outpick-unlimited-default-build.log`.

`ChatMediaViewportControllerTests.testUnlimitedPreparationStartsAllCandidatesAndCancelsAll` 및 `ImageDirectDiskDecodingTests.testUnlimitedDiskPathBypassesOccupiedDecodeAndIOGates` 추가. 기존 캐시/세대/메모리/취소 회귀 포함 `/private/tmp/outpick-unlimited-disk-preparation-tests.log`. 일반 경로와 QA 우회 경로를 각각 검증한다.
# 로컬 단계 준비 및 셀 캐시 표시

`ChatRoomViewModelMessageActionTests.localMediaPreparationIsForwardedWithoutRenderingMessages`는 힌트가 별도 render를 만들지 않는 VM 전달을 검증한다. `ChatMediaViewportSurfaceTests`의 최초 캐시 hit/원격경로 교체 차단/loading 직전 캐시 도착 시험 추가. viewport/continuity/VM 회귀 `/private/tmp/outpick-local-early-media-tests.log`. 실서버 이벤트 순서 및 체감은 코드 대조와 실기기 계측으로 별도 확인.
# 전환/이탈 픽셀 연속성

ChatImagePreviewContinuityTests의image→loading→idle이미지유지 및reuse해제, ChatMediaViewportSurfaceTests의remote경로변경차단, viewport취소회귀. `/private/tmp/outpick-media-entry-transition-tests.log`. 실제전환애니메이션과빠른스크롤빈칸은실기기QA로검증한다.
# 실제 스피너 추적 검증

ChatImagePreviewContinuityTests.testSpinnerTracePairsActualStartWithImageAndReuse: injected ImageCacheMetrics sink로중복시작차단/span연결/이미지보유시미시작/reset종료검증. surface+metrics회귀 `/private/tmp/outpick-spinner-trace-tests.log`. 사용자실기기재현과같은key/span대조전원인확정금지.
# 현재 원본 우선 회귀 — 2026-09-24

`ImageViewerOriginalFileTests`의 지연 fake로 현재 파일 확보 전 인접 요청0, 페이지 이동 후 이전 완료 무시, 현재 확보 후 인접2 요청, 닫기 후 인접0을 검증한다. 기존 저장/닫기/정적 인접 범위 포함7개 통과: `/private/tmp/outpick-original-current-first-tests.log`. 실제 속도 개선 수치는 실기기 QA에서 별도로 확인한다.
# 영상 원본 저장 회귀 — 2026-09-24

`PhotoLibraryOriginalIntegrationTests`가 AVAssetWriter 합성 MP4/MOV를 `.bin`으로 작성 후 실제 Photos에 저장하고 원본 바이트 보존을 확인한다. Simulator photos-add 허용 때만 실행하며 사용자 기기 영상 사용 없음. 기존 코드 MP4 저장3302 실패 재현 `/private/tmp/outpick-video-save-red.log`, 수정 검증 `/private/tmp/outpick-video-save-green.log`. `PhotoLibraryOriginalResourceTests`에 MOV 내용/잘못된 mp4 확장자·truncated bin 헤더 추가.
# 캐시 영상 재생 검증 — 2026-09-24

`PhotoLibraryOriginalIntegrationTests`의 합성 MP4/MOV bin에 실제 resolver의 `cachedPlaybackAsset`을 적용해 AVURLAsset.isPlayable, Photos 저장, lease 해제 후 링크 제거와 원본 보존을 확인한다. 기존 캐시 hit/miss resolver 회귀 함께 `/private/tmp/outpick-video-playback-tests.log`. isPlayable은 실제 플레이어 첫 프레임/소리 QA를 대체하지 않는다.
# 영상 저장 중 닫기 — 2026-09-24

`VideoSaveLifetimeTests` 6개: ChatVideoPlayerViewController/VideoPlayerOverlayVC 각각 준비 중 닫기, 제출 후 성공·실패. 실제 UIWindow/present/dismiss로 수명 콜백 실행, fake 응답을 닫기 뒤 해제한다. 준비 중 닫기는 saver0회, 제출 후에는 callback 전 파일 유지/후 해제, 두 경우 늦은 결과 토스트 없음·player nil·실제 재생 링크 삭제·원본 bytes 보존·lease1회 해제를 확인한다. 로그 `/private/tmp/outpick-video-lifetime-tests.log`. 실제 Photos 저장 취소/첫 프레임 재생 테스트는 아니다.
# 룩북 대용량 준비 검증(2026-10-03)

- `tools/lookbook-import-worker/src/performance/large-input.test.ts` 신규7개를 `verification/lookbook-import.json`/로컬 Linux 게이트의 필수139개에 포함했다. 전체247개가 Mac/Linux에서 실행·통과했다. [정확한 코드 식별자·원본 결과·7회 상태](../tasks/lookbook-import-performance/phase-3-large-input-design.md).
- 실제 작은JPEG84개 변환과 독립Buffer/중복 제거/부분 재사용, 예산 경계/조기반환, hash·path·취소 정리, 엄격7회 계획,1만 건 초과/한도/변조, 중단·미수행 분모를 검사한다. 메타데이터 산술과 집계용 가짜 사건은 실제 JPEG 검사와 구별한다.
- 큰 이미지 실측의 현재 진입점은 `output/lookbook-import-performance/run-large-input.mjs`이고 새 컨테이너7회만 승인됐다.5쌍 성능 채택·Development 검증을 이 검사로 대체하지 않는다.
# P4 비재사용 대조군 필수 검사(2026-10-03)

`performance/large-input.test.ts`의 P4 비재사용 신규3개를 필수142개에 연결했다. 계획 변조/과거7회 혼입, 실제JPEG84개·114회 읽기·커버6개선준비/cache없음, 큰 입력 집계1,584회읽기·중단분모를 확인한다. 전체250개 검사의 실제 결과와 원본은 [대조군 기록](../tasks/lookbook-import-performance/phase-3-p4-off-control.md)에 남긴다. 기존247개 회귀도 유지한다.
# 브랜드 순차 비교 필수 검사(2026-10-04)

[BF01~BF12 설계](../tasks/lookbook-import-performance/phase-3-brand-fifo-design.md)를 `performance/brand-scheduling.test.ts`6개와 `brand-comparison.test.ts`6개로 구현해 `verification/lookbook-import.json`과Linux게이트에 필수157개로 연결했다. 브랜드FIFO·내부병렬·업로드/경로/정리전환 barrier·review/실패/총5회재시도·취소·한브랜드회귀·고정입력/20회계획·대기포함지표·분모·실제JPEG·OOM경계기록과출력실패시신규작업금지를 검사한다. 전체265개 실제 실행 결과·source·로그는 [검증 기록](../tasks/lookbook-import-performance/phase-3-brand-fifo-results.md)을 따른다. 실제CloudRun/Storage/Firestore는 이 로컬검사의 통과 범위가 아니다.

# P4 다섯 쌍 확인 검사(2026-10-03)

`performance/large-input.test.ts`의 신규3개가 엄격15회행렬/과거표본격리,반복악화·10%속도기준·중단쌍미판정,실제payload형식통합집계의이미지/measurement중복을 검사한다. 전체253개·필수145개와 lint/build/fixture가 Mac/Linux에서 통과했다. 실제JPEG와취소반환은기존필수회귀를함께실행했다. [실제실행결과·source식별자](../tasks/lookbook-import-performance/phase-3-p4-confirmation.md)를 따른다.
