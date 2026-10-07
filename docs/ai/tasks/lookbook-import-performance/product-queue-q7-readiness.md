# 제품 룩북 FIFO Q7 — Development 연결 준비 및 최소 smoke 안

2026-10-07 최신: [A~J 실제 제품 검증 결과](product-queue-q7-ten-brands-results.md) — 36접수·16시즌 저장·710JPEG와 현재 공개 원장 대조가 완료됐다. 두 100ms 예약 wave에서 실제 서버 순번과 브랜드 대기·실행 비중첩을 확인했다. 앞 run 시작 후 신규 접수는 없었으므로 A/B의 active 중 도착과 동일한 조건으로 표시하지 않는다. 메모리 최고 84.05%, 최대 표본 공백 380.7ms, 이미지 실패·시즌 재시도·중단 0회. 실행기 job 기록 누락은 원본 보존·별도 job index 대조로 정산했으며 이후 도구 기록 연결을 수정했다. 최종 client31/Worker359/Linux2 필수 검사 통과. 실제 장시간·플랫폼 종료 및 청구 전체는 별도 미검증이다. 전체 Q7 완료·커밋은 아직 아니다. 아래 실행 전/진행 중 문구는 과거 기록이다.

Q7 A~J 실행기 준비 완료(2026-10-07): `scripts/q7-wave.mjs::runQ7Wave`는 응답 대기 없이 절대 100ms 간격으로 최대10건을 시작한다. `q7-journal.mjs`/runner는 동시 기록을 직렬·원자 저장하고, 실패하면 새 투입을 멈춘 뒤 시작한 요청을 모두 정리한다. `assertQ7WaveEvidence`는 두 wave 각10건의 예정/시작/HTTP 직전 기록·실제 서버 순번과 서로 다른 브랜드 대기를 검증한다. 실제 서버 도착 간격을100ms로 단정하지 않고 편차와 순서 변경을 기록한다. 승인된 A6/B2/C~J각1·16시즌·36접수·기존 비용/2시간 상한은 유지한다. 필수 verifier gate `1791303321801-54c50236-ead4-40c3-ad2d-f126a1131cbc` passed31; digest `e3da40995238821d1f710fe61930efb6057e14c69792897cc00aa61f155c9c66`. 원격 A~J는 아직 실행 전이다.

## 최신 재개 상태 — 2026-10-07 KST

- 후속: candidate023-met/preflight/같은UID/observer ready 통과 후 epoch2 conditional resume accepted(decision28ee88a4…). epoch3은 memoryStop null/종료확인true/inFlight0이나 완료된 item을 다시 begin해 NOTQUEUED로 recoveryRequired였다. A2 import 준비대기와 접수2건은 유지했다. 조회 도구만 종료해 새 후보에서 같은 run으로 재연결한다.
- terminal item 재실행 방지+release transaction의 execution/continuation 종료 검사를 추가했다. 최종 Worker gate1791300288876-5012c6a9-e515-4f94-bb0e-087c9dd6bf66 passed359/digest69f5fb74…355b, 제품큐1791300034383… passed74/digest693b2d10…92a7, verifier1791300286083… passed23/digest02e9b466…6da4. 중간 verifier1건 실패는 원본 변조 검사를 한 뒤 fixture를 복원하지 않은 테스트 오류로 보존했으며 수정 뒤 재검사했다. 새0%candidate 배포 진행 중. epoch3 fresh inspect도 durableDrain/쓰기0/canResume 확인했으며 실제 새 후보 재개는 전이다.

- 현재 run92ad4778의 A discovery succeeded29, import2시즌 접수까지 완료했고 이미지job0/Storage0이다. 서버 head는 기존 candidate022의 SAMPLE-GAP922ms 복구 상태다. 사용자는 같은 접수 유지·좁은 이어 실행을 승인했다. 재접수 없이 남은5 logical mutation만 진행하며 최초 startedAt 기준2시간 창을 유지한다.
- Worker Ready 전에 Playwright JS 모듈을 준비한다. 실제 Chromium 실행/동시성/메모리 기준은 유지한다. actual local Linux index+QueueSupervisor/network none/1CPU2GiB 검사는 guard21/resource22표본,maxgap103.647ms,memoryStop null,브라우저0으로 통과했다. Cloud 실제 성공은 아직 미검증이다.
- `q7-resume.mjs`/runner --resume가 원본 digest·같은UID·선택snapshot·기존 preparing 대조 후 OBSERVER_READY를 표시한다. 새 후보 fresh inspect/조건부 recovery resume 뒤 같은 요청 조회로 A active→B접수를 이어간다. 이전 실패는 raw evidence/성능 실패로 보존한다.
- 현행 필수 결과: Q7 gate1791299169976… passed23/digest cc25047f…684d, Worker1791299220906… passed359/lint/fixture/deploy/digest f1bad383…d9ff, 제품큐1791299223580… passed72/build/digest03dc56c2…2d70. 원본 summary는 output/verification 각ID.
- snapshot candidate-20261006T150925Z-7819, build aa597d7b-397f-4688-9220-e4cafb49a9f6 진행 중. 0%Q7tag/base100% 유지, Production/삭제/커밋 없음. 상세 진입점·다음 순서는 통합 server-validation-plan 최신 절을 따른다. 아래는 이전 이력이다.

## 현재 진행 상태 — 2026-10-06 (최신)

- 탐색 오탐 수정·새 A/B 시작 연결 최종 로컬 완료: Worker `1791296042475-3e22fc1d-c289-40d8-a39d-df9a6aa57372` passed(359tests/lint/fixtures/deploy contract,digest `d109070f88903b769d04acb2bcf089aa00aa7f0c1c183f8f737553c5950b7383`,252files); verifier `1791295926978-c2539087-f93f-46ec-900a-d28296f747f5` passed(18tests,digest `75f896d088502808c637a43ddcf458a644073f0246a6f03bd3810e2263eee4cd`,24files); product queue `1791295950014-dfc0fd43-4a78-4373-b61b-31fd37232ea8` passed(72emulator+Worker/Functionsbuild,digest `f4214a6923dedcfe8cd74fb0fc297053562a865df1c9cdfa7eee8ed5bb69a82c`,292files). 이 source의 candidate 배포 진행 중. 기존 A 원본파일을 바꾸지 않고 reconciliation proof를 추가했고 실제 campaign 사전검사도 통과했다. 새 smoke7회+기존1회=누적8은 사용자 확정. 이미지 추출/Storage 저장은 아직 미실행이다.

- 1~2 완료: 새 recovery-enabled candidate `00021-kup` Ready/image `sha256:fea287921b7267f134e2da9f7b60f7f5539df3909e683b68e1253cbc962b2ab2`, Q7 preflight 통과(기존 자원·base100%·candidate0%·두 queue RUNNING/0 tasks). A exact inspect가 durable-drain/불확정쓰기0/정산가능을 확인했고 decision `a065e523-d1aa-4b98-a075-e4102f6d7599`로 조건부 정산 accepted. read-back은 queue idle/batch released/stateRevision11, 원본 job correctionRequired·run 종료증거·90일 audit 보존이다. 증거 폴더 `output/lookbook-import-performance/product-queue-q7/recovery-20261006/`. A 목록 탐색 자체는 아직 교정 필요이며 다음은 실제 DOM 신호 진단이다.

- 본인 Google 운영 계정 하나의 최소 복구 권한 방향 확정 및 Development IAM 적용 완료. 전용 recovery SA에는 해당 Worker invoker, 본인에게 exact SA OpenIdTokenCreator, Worker runtime에는 `logging.logEntries.list` 단일 custom role. 읽기 되확인과 실제 ID token 발급 성공. 증거는 `output/lookbook-import-performance/product-queue-q7/recovery-20261006/`이며 토큰 원문은 저장하지 않았다.
- CLI 인증 방식·배포 recovery env·Q7 preflight 변경 완료. Q7 verifier `1791294234713-8c8be4dc-760d-456b-b78b-69514fd66431` passed(17 tests). Worker 최종 gate `1791294464207-53fc95bd-29fc-432f-be8a-604791cde8e4` passed(356 tests/lint/fixtures/deploy contract, digest `e359e11d3a970227950f43b2afc9e5d68d9983ffee79bb33fff2326b369773bc`, 250 files). Snapshot `candidate-20261006T135025Z-95013`의 Cloud Build `396e5e61-affb-414a-839e-2f1c3d54cc53` 진행 중. A 상태는 아직 보존 중이다. 아래 IAM 결정 대기/이전 candidate 결과는 이번 변경 전 이력이다.

- Recovery settlement 구현과 PQ14 검증이 로컬에서 통과했다. 최신 Worker gate `1791290297722-acd38c5e-89ae-442f-9a7e-cf88e2da3abb` passed(354 tests/lint/fixtures/deploy contract, digest `91c937c18378935283b1ab0a5d28633aa180d2a401f44761cd43d338f037333b`, 248 files). Product queue gate `1791289769511-4141e4a8-d6d9-4c08-9dc0-a49b5f414fcc` passed(Worker/Functions build, Emulator 72 tests, digest `f473851733e9f4a14d3e42b072d8896e01eaeb1a71010c80bc9e4b44a07f0ad0`, 290 files).
- Q7 verifier gate `1791291465447-14e6e4f2-499b-4903-8151-ed85cc38d67e` passed; 17 required runner/preflight contract tests, digest `bea928bc5a7f8f58c8ed78f705589a252aa2fe92501c2f4ca382d0ef65e80f66`/24 files.
- Development `lookbook-import-worker-development-00020-yun` is Ready, tag `q7-20261006`, image `sha256:9895247b2ff3258c957eddec706b4be71eeb5ce1d7ff33fcf2dc38de6013a5a9`. `OUTPICK_WORKER_VERIFICATION_DIGEST` matches the passed Worker gate and performance instrumentation is enabled. Base `00012-fih` remains 100%; candidate is 0%. Q7 preflight passed at 1 CPU/2GiB/concurrency 2/900s, service maxScale 5/revision maxScale 1, with both task queues RUNNING and empty.
- Snapshot deployment procedure and mock contract tests passed 3/3. The first candidate `00019-qom` omitted `OUTPICK_IMPORT_PERFORMANCE_ENABLED=true`; it was replaced before any product request. The latest candidate was deployed from the gate-bound Worker-only snapshot.
- **복구 적용은 IAM 결정 대기 중:** Worker revision has no recovery service-account environment; read-only check found no `lookbook-import-recovery@outpick-test.iam.gserviceaccount.com`, and service-level invoker policy has no recovery caller. Worker runtime SA's confirmed project role is only `roles/datastore.user`. No `/recovery/inspect` or settlement call has been sent; A batch/head remain unchanged. User was asked to choose a dedicated caller + token minting for self + minimal log listing role, only durable-drain A settlement without log access, or standard `roles/logging.viewer`.
- Until the permission choice is resolved, no further product mutation, image download, or Storage write will be sent. Once configured, sequence is exact batch inspect → guarded settlement → resolve the actual more/load signal → smoke completion → A~J validation.

초기 smoke 경과: [통합 계획](product-queue-q7-server-validation-plan.md)·[P2 연결](q7-verifier-p2-plan.md)·[필수 행렬](q7-verification-matrix.md). Development active platform admin 세션으로 A 생성·최초 탐색을 접수해 29개 후보를 얻었다. domain job은 `correctionRequired`로 종료됐지만 구 Worker의 상태 매핑 오류로 queue batch/head가 `recoveryRequired`에 남았다. 시즌 이미지 import와 Storage 업로드 전에 멈춘 이력이다. 최신 배포·권한 상태는 이 문서의 `현재 진행 상태`를 따른다.

## 최초 Development 연결 준비 기록 — 2026-10-06

- 프로젝트 `outpick-test`, Web app `OutPick Q7 local verifier 20261006` (`1:86635107099:web:831347d278dea0bba239be`), 로컬 public config `output/lookbook-import-performance/product-queue-q7/firebase-web-config.json` (mode 600, gitignore 대상, Hosting 미배포).
- Cloud Build `6e980790-c540-4c71-89b7-4d08f126a755` 성공. Candidate `lookbook-import-worker-development-00018-zon`, tag `q7-20261006`, URL `https://q7-20261006---lookbook-import-worker-development-xyenspjiwa-du.a.run.app`. Image digest `sha256:6bba1827c26280a6503954f0de0aab7d9a2e357720274ee7986de9a76c2e7a38`.
- Preflight에서 기존 base revision `00012-fih` 100%, candidate 0% traffic, service max 5 / candidate max 1, 1 vCPU / 2GiB / concurrency 2 / timeout 900초를 확인했다. `requestSeasonImport`은 candidate tag URL을 가리킨다. 두 Cloud Tasks queue는 RUNNING/0 pending이었다.
- 로컬 Q7 gate 16/16, Worker gate 350 tests 및 fixture 검사 통과. 현재 Q7 source digests: Q7 23파일 `68eb5365fa8ff0818131a566224fb2f6fb07ad39fa9d2a01bd4033689ee27d85`; Worker 242파일 `f469f8b8ff2a6b1a1f80f51aebbc914dafce65472a0cf25fe1994fb513e80f64`.
- 원래 다음 실행 명령은 `OUTPICK_Q7_STORAGE_BUCKET=outpick-test.firebasestorage.app node tools/lookbook-import-worker/scripts/q7-runner.mjs --stage=smoke --config=output/lookbook-import-performance/product-queue-q7/firebase-web-config.json`이었으나, 현재 기존 queue head가 `recoveryRequired`여서 실행하면 안 된다. Q7 run은 이미 active `platformAdmins` 사전검사를 통과했다. 새 실행은 복구/정산과 candidate 확인 이후에만 한다.
- smoke의 계획량은 최대 7 논리 mutation, 127 source image GET (약 55.7MB; 승인 단계 재다운로드 포함), 126 JPEG Storage writes (약 15.6MB), 이후 결과 확인 GET 최대 126개다. A~J는 최대 36 mutation, 713 source GET (약 566.6MB), 710 JPEG writes (약 106.9MB), 결과 확인 GET 최대 710개다. 재시도·HTML/브라우저/SDK·로그·Firestore·Storage 작업은 별도이고 실제 청구액은 이 byte 산술만으로 확정되지 않는다.
- 사용자 승인된 실행 창은 run별 최대 2시간·추정 누적 비용 US$10에서 중단하는 soft cap이다. 비용은 build/Cloud Run/Tasks/Firestore/Storage/network/logs 포함 추적 대상이지만 청구 지연으로 hard cap은 보장하지 않는다. Seoul Cloud Run 1 vCPU+2GiB 활성 처리의 공식 단가 기준은 약 US$0.1044/시간으로 전체 비용이 아니다. 근거: [Cloud Run](https://cloud.google.com/run/pricing), [Cloud Storage](https://cloud.google.com/storage/pricing), [Cloud Tasks](https://cloud.google.com/tasks/pricing), [Firestore](https://cloud.google.com/firestore/pricing?hl=en).

## 최신 smoke 실행 및 중단 근거 — 2026-10-06

- 실제 runner run `e9049126-5161-48ee-ad67-fc6966a7b8ca`에서 A 브랜드 `57e18f6dfa9d370568f52ff281e5f67df8384f7961aea84705a667dc77b2670b`, discovery job `fbf52fb60d32ae825fc015e7310164b0b6414ed9c8f0ec5b8637de484a0830db`, batch `a424236d30f549afa6d42559dd34915df041b299ba08d22dcc01aef2960ccd3f`가 생성됐다. 최초 탐색은 2026SS `product_no=534`, 2025FW `469`, 2025SS `128`을 포함해 후보 29개를 관측했다.
- 후보 페이지에는 더보기 및 동적 렌더 신호가 있었고 탐색 job은 `correctionRequired`/`waitForExtractorFix`로 종료됐다. 이는 unresolved 확장에 대한 보수적 결과다. 기존 `processor.ts`는 domain job 결과 상태와 다른 문자열을 비교해 이 terminal 결과를 queue executor error로 바꾸었고 batch/head를 `recoveryRequired`에 남겼다. 실제 Cloud Run run record는 `terminalConfirmed=true`, `inFlight=0`; 이미지 변환·JPEG Storage write는 0건이다.
- 추가 read-only Firestore 확인에서 목표 세 시즌 후보는 모두 존재하고 `newSeason`으로 해석됐으며 목록 커버 29개가 기록됐다. discovery root는 `parserStrategy=playwright:staticAnchors`, `adapterKey=cafe24`, 실패 사유 `load_more_detected`·`dynamic_rendering_detected`, `recommendedAction=waitForExtractorFix`다. 후보가 발견됐다는 것만으로 페이지 전체 추출이 완료됐다고 볼 수 없고, import admission은 `succeeded`/`awaitingReview` snapshot만 받아 `correctionRequired` 후보는 현재 승인하지 않는다. 클릭/스크롤 종료 카운터와 HTML 스냅샷은 원격 문서에 없어 실제 버튼 여부를 확인할 수 없다. 코드상 원인 후보로 `loadMoreSignalDetected`가 전체 HTML에서 `btnMore|loadMore|viewMore|moreBtn|paginate` 문자열을 찾는 점을 확인했다. 스크립트·숨은 템플릿의 문자열도 잡을 수 있지만, 이번 Development 실패가 그 오탐 때문이라고는 아직 확정할 수 없다. 실제 활성 버튼 누락과 구분하기 전에는 감지 기준을 완화하지 않는다.
- run 성능 로그: 약 11.043초, 104 samples, 최대 표본 공백 594.949ms, event-loop 최대 553.648ms, 최대 RSS 345,743,360 bytes, heapUsed 109,197,880 bytes, process CPU user 1.8초/system 0.3초. 500ms 표본 공백 중단 기준을 초과해 85%/1초 메모리 기준과 peak cgroup 사용량은 이 실행에서 판정하지 않는다. 메모리 기준 통과로 기록하지 않는다.
- 정확한 read-only queue snapshot: head=batch `a424236d30f549afa6d42559dd34915df041b299ba08d22dcc01aef2960ccd3f`, state=`recoveryRequired`, sequence=1, epoch=1, stateRevision=10; item outcome=`recoveryRequired`. 동일 run `a424...-1`은 revision `00018-zon`, `terminalConfirmed=true`, `inFlight=0`, disposition=`recovery`; execution 상태는 `recoveryRequired`, activeRun 없음, attemptCount 1/limit 3이다. discovery 시도 예산 3은 기존 별도 discovery 계약이며 시즌 import 총5회와 구분한다.
- 복구 API `resume`은 기존 batch를 재실행 큐에 넣으므로 이미 terminal인 `correctionRequired` 결과에는 사용하지 않는다. 사용자가 승인한 새 `settle-correction`은 단일 시즌 목록 탐색 batch, exact head/epoch/run revision, `terminalConfirmed=true`, `inFlight=0`, 원본 discovery job=`correctionRequired`, queue execution/item/attempt=`recoveryRequired`, 미확정 asset write 0건일 때만 허용한다. 상태 정산과 90일 audit를 Firestore transaction 하나로 기록하고 domain job·run의 원본 결과/종료 evidence를 바꾸지 않는다. report digest와 state revision이 바뀌면 거부한다. 다른 batch kind, 다중 item, 진행 중 작업, 검토 대기/실패/성공 결과에는 적용하지 않는다.
- 최초 수정본 gate 결과는 이후 배포 절차 보완 gate 결과로 대체됐다. 현재 유효한 gate run ID·digest와 실제 candidate는 상단 `현재 진행 상태`에서 확인한다.
- 당시에는 미커밋 작업트리 정책과 정합되는 배포 경로가 없어 candidate 재배포·정산을 보류했으나, 이후 Development-only verified snapshot 절차를 추가해 candidate 배포까지 완료했다. 복구 identity·권한은 별도 승인 답변을 기다린다.

초기 실행 직후의 다음 단계 기록은 이후 상단의 현행 상태로 대체됐다. 현재 순서는 recovery 권한 확정·설정 → exact batch inspect/조건부 settlement → extractor 원인 해결 → smoke 완료 → A~J다.

## 소규모 smoke 시도 — 권한에서 fail closed (2026-10-06)

- 첫 실행 `2bb11738-9782-4f37-9a6e-ffb248ebec50`은 sandbox가 localhost listen을 거부해 로그인 화면 전에 종료됐다. mutation 0, journal 요청 0이다. 승인된 loopback 실행으로 재시도했다.
- 두 번째 run `1202de53-a9cd-4c87-89b9-fa514da048d6`에서 Firebase Google 로그인은 완료됐지만 active `platformAdmins` 확인에서 `Q7_PLATFORM_ADMIN_INACTIVE`로 중단됐다. mutation 0, journal 요청 0, 브랜드 생성 0, import 접수 0이다. `report.json`, journal, `evidence/development-preflight.json`이 run directory에 보존됐다.
- 로그인된 계정 권한 확인 후 수행한 read-only Firestore audit 결과: `platformAdmins` 문서 1개, `isActive=false`, `revokedAt` 존재; `lookbookImportQueue/main`은 head 없음, `recoveryRequired=false`. Cloud Tasks import/discovery queue는 preflight 당시 모두 RUNNING/0 pending이다.
- 두 번째 run에서 base revision `00012-fih` traffic 100%, candidate `00018-zon`/tag `q7-20261006` 0%도 다시 확인됐다. Firebase 로그인·preflight 읽기는 발생했으나 이미지 source download, Storage write, 제품 문서 생성은 없었다. 정확한 청구 영향은 분리된 청구 항목으로 확인하지 않았다.
- 다음 단계는 기존 active Development platform admin으로 로그인하는 것이다. Development 권한 부여·회수 상태 변경을 임의로 하지 않는다. 권한 세션이 확인되고 queue preflight가 계속 통과할 때만 smoke를 다시 실행하고, 통과 후 A~J로 진행한다.

## 초기 서버 검증 도구 전환 조사 이력(2026-10-06)

사용자가 iPhone 관리자 검증을 제외하고 UNAFFECTED 입력으로 서버 접수부터 저장까지 검증하는 방향을 승인했다. 이후 실행 기준은 [서버 검증 전환 계획](product-queue-q7-server-validation-plan.md)을 따른다. 아래 iPhone 선행/계정 전환 지시는 과거 이력이며 더 실행하지 않는다. A2/B1 smoke와 A~J16시즌/100ms wave 및 기존 요청량을 유지한다. 관리자 웹 화면 QA는 웹 구현 task로 이관한다.

당시 read-only 조사 결과이며 이후 P1을 `platformAdmins` 기준으로 구현했다. 현재 로그인 smoke와 재확인 audit은 platformAdmins 문서 1개가 비활성·회수 상태이고 활성 문서가 없음을 확인했다. DB/Worker 직접 호출로 우회하지 않는다.

## 사용자 지적에 따른 검증 경로 재검토(2026-10-06)

`admin-web-operations-migration/decisions.md`와 `ios-admin-console-removal/decisions.md`는 관리자 브랜드/시즌/추출/검수/게시를 localhost 웹으로 이전하고 동등성 확인 후 iOS 관리자 콘솔을 제거하도록 확정했다. 웹/제거 상세 구현은 문서상 아직 미승인이다. Q7을 기존 iOS 관리자 화면 필수 검증으로 계속 진행하기 전에 이 제품 결정과 경로를 정합화한다. 계정 전환 및 원격 생성은 보류하며 서버 큐 검증 필요성은 유지한다. 새로운 웹/인증 구현 범위는 별도 논의 대상이다. 탭 진입 수정 후 G-I `1791266480913-9e465a37-ed96-497a-8f26-b75f271a0ffa` passed; 실기기 관리자 진입 실패와 구분한다.

## 15:02 KST 실제 테스트 실행 및 권한 차단

- 설정 변경 없이 새 XCTest 세션에서 자동화 초기화 성공. 이전 시간 초과의 근본 원인은 미확정이다.
- Q7 테스트의 룩북 탭 전환 누락을 수정하고 실기기 빌드 통과(`build-navigation.xcresult`). 수정 소스 SHA256 `bf6843f2daaa18b52d1a65a445cadb0dbab19fe05b9a113a3f807732df84df52`.
- `test-navigation.xcresult`에서 룩북 탭 진입은 성공했지만 관리자 버튼이 없어 실패했다. 앱 stdout은 서버 권한 조회 성공 후 `isTotalAdmin=false roles=[] ownerCount=0 adminCount=0`을 기록한다. 현재 세션 권한 불일치를 사용자에게 안내했다. 관리자 계정 전환 또는 권한 상태 읽기 전용 조사 응답 대기. 브랜드 생성/시즌 import는 모두 0건.
- 원본 로그와 화면 구조/앱 로그는 `device-preflight-20261006-01/navigation-attachments`, `navigation-diagnostics`에 보존한다. 이전 빌드/환경 실패와 구분하며 Q7 통과로 판정하지 않는다.

## 14:56 KST 인증서 신뢰 후 재실행

사용자가 인증서를 신뢰한 후 테스트 Runner 실행까지 성공했으나 `Timed out while enabling automation mode`로 UI 자동화 초기화가 60초 뒤 실패했다. 테스트 본문 미시작, 브랜드 생성/시즌 import 각각 0건이다. 기기 잠금 해제도 재확인했다. 사용자에게 자동화 허용 안내/개발자 설정 상태를 확인 요청했다. 원본은 위 실행 폴더의 `test-trusted.log`, `test-trusted.xcresult`이며 인증서 실패 이력과 구분한다.

## 14:54 KST 실기기 실행 결과

실기기 Q7 테스트 빌드는 자동 개발 서명으로 통과했다. 잠금 해제도 확인했지만 테스트 Runner는 `Developer App Certificate is not trusted`로 시작하지 못했다. 사용자에게 기기 설정에서 인증서 신뢰를 요청한 상태다. 테스트 본문 미시작이므로 QA 브랜드 생성/시즌 import는 각각 0건이며 Q7 통과로 판정하지 않는다. 원본 빌드/실행 로그와 xcresult는 `output/lookbook-import-performance/product-queue-q7/device-preflight-20261006-01/`에 보존했다. 신뢰 완료 후 동일 runID의 단일 후보 탐색 검증을 실행하며, 앞선 미실행 기록은 아래 이력과 구분한다.

2026-10-06 Development 연결 배포 결과와 Q6 로컬 입력 fixture를 합쳐 갱신했다. 사용자는 소규모 연결 확인 → A~J 제품 대기열 검증 → 중단·재개·복구 및 앱 확인 순서, A6/B2/C~J각1 입력, 고정 후보 일치 시 정상 관리자 승인을 확정했다. 최소 연결은 배포·검증됐다. 최신 실기기 재개 상태는 `실기기 Q7 재개 결과`에 기록한다.

## 실기기 Q7 재개 결과 (2026-10-06)

- 사용자 보고: iPhone 14가 연결·잠금 해제되어 있고 기존 총 관리자 계정으로 로그인된 상태다. 이는 사용자 진술이며 앱 화면/Firebase 권한을 독립적으로 확인한 증거와 구분한다.
- `OutPick-Development` / `Development-Debug`를 실제 iPhone 14(iOS 26.7.1)에 같은 Development bundle ID(`GayoonKim.OutPick.dev`)로 설치·실행했다. `devicectl`에서 `passcodeRequired=false`, `unlockedSinceBoot=true`, LCD backlight on/active 및 OutPick 프로세스 실행을 읽었다. 앱 데이터/Keychain 삭제나 로그아웃은 하지 않았다.
- 실행 직전 read-only 재확인: Cloud Run latestReady `lookbook-import-worker-development-00017-loj`, 기본 100% traffic은 `00012-fih`, `q7-20261006` tag는 0%. `requestSeasonImport`는 ACTIVE이고 `OUTPICK_LOOKBOOK_IMPORT_WORKER_URL=https://q7-20261006---lookbook-import-worker-development-xyenspjiwa-du.a.run.app`. candidate image digest `sha256:042f8e2a304d0e4fbeff0efcd34b54bc82c5bdbe83e00d6bf2b8522e747a038a`, concurrency 2, timeout 900초. `lookbook-import-jobs` queue는 RUNNING 설정을 유지하며 task 0개였다.
- 실제 앱의 관리자 세션/화면을 독립 확인할 화면 접근 수단이 현재 없다. Computer Use 검토에서 iPhone Mirroring 사용이 허용되지 않았다. QuickTime iPhone screen source는 검은 화면이었고 짧은 기록 시도는 “기록할 수 없음”으로 실패했다. Xcode Devices의 Take Screenshot도 결과 화면을 제공하지 않았다. 기기 연결·앱 실행만으로 현재 화면을 증명하지 않는다.
- 사용자가 선택한 XcodeBuildMCP 설정으로 `.xcodebuildmcp/config.yaml`에 `simulator`, `device`, `ui-automation`을 추가했다. 이 설정은 XcodeBuildMCP의 프로젝트 설정 경로/스키마에 맞지만 서버가 시작 시 설정을 읽으므로, 현재 세션 도구 목록이 시뮬레이터 도구만 제공하는 상태에서는 재로딩을 확인하지 못했다. 공식 workflow 문서에서 `device`는 실기기 build/install/test, `ui-automation`은 iOS 시뮬레이터 조작으로 정의한다. 따라서 프로젝트 설정 추가만으로 실기기 iPhone의 임의 탭/화면 snapshot은 활성화되지 않는다.
- `OutPickUITests/LookbookImportQ7DevelopmentUITests.swift`를 추가했다. Development 실기기·명시적 opt-in·고유 run ID를 요구하고, 기존 로그인 세션에서 관리자 화면을 확인한 뒤 QA 브랜드 1개를 만들고 최초 후보 탐색까지만 진행한다. 제목 6개·순서를 고정 fixture와 대조하고 스크린샷/목록을 xcresult에 남긴다. 후보가 fixture와 다르면 테스트가 실패하며 시즌 선택·이미지 import는 제출하지 않는다. 실패/성공과 무관하게 생성된 QA 브랜드는 자동 삭제하지 않는다. 아직 실행하지 않았다.
- Q7 테스트 파일은 `TEST_RUNNER_` 접두사와 원래 변수명을 모두 지원한다. 14:43 KST에 앱/Q7 XCTest 전체 Simulator `build-for-testing`이 27.4초에 통과했다. Simulator skip 뒤 도달 불가능 코드 경고 1개이며 실기기 실행 성공을 의미하지 않는다. 원본: `/Users/gy/Library/Developer/XcodeBuildMCP/workspaces/OutPick-35b9c30ceb0b/logs/build_sim_2026-10-06T05-43-12-260Z_pid2638_224be4c1.log`. Q7 소스 SHA256 `b1ddd3aebda95ccec000b195c9a5efcffc768158e34c0e50af06032c0c17a955`.
- scheme 오류의 재현된 원인: 설치된 XcodeBuildMCP 2.7.0 `build/utils/typed-tool-factory.js`는 `testProductsPath`가 있으면 준비된 테스트 입력으로 간주해 scheme/projectPath/configuration/derivedDataPath 기본값을 제거한다. 이 공용 처리가 `build_sim`의 출력 경로에도 적용된다. 동일 factory 최소 재현에서 경로 지정=scheme 오류, 경로 생략=정상 전달을 확인했다. 실제 MCP 호출에서 `testProductsPath`를 생략하자 위 빌드가 성공했다. 서버 재시작으로 해결되는 오류가 아니며 설치된 도구 소스는 수정하지 않았다.
- 필수 iOS gate `verification/lookbook-queue-ios.json` run `1791265465771-86d9b204-7179-4998-895d-01959261cbb2`는 passed/28 tests/8 suites다. source digest `1b6c19b9dc5f651012a29f3efdc4484cbba27ae8f31878fafb24719413267f75`/983 files로 이전 blocked run `1791264989731-a0cc7e51-e84e-4ed2-ba08-851eda32e0e3`와 동일하다. 이전에는 sandbox의 Swift/clang 사용자 캐시 쓰기와 CoreSimulator 접근 제한으로 실행 0개였으며, 동일 게이트에 필요한 접근 권한을 부여한 재실행은 통과했다. 직접 빌드 우회 중 나왔던 SwiftPM product 누락은 앱/패키지 수정 없이 정상 빌드가 통과했으므로 실제 패키지 제품 삭제의 증거로 해석하지 않는다.
- 실기기 도구 미노출: 현재 MCP PID2638은 12:13:16 KST 시작됐고 프로젝트 config 파일은 14:10:49 KST 생성됐다. cwd는 `/Users/gy/Desktop/OutPick`이다. 플러그인 기본 workflow에는 device가 없으며, 설치된 config loader에 현재 파일과 플러그인의 기본 workflow 환경변수를 넣으면 파일이 우선되어 `simulator,device,ui-automation`을 반환한다. 현재 도구 목록에 device API가 없으므로 서버 재시작 후 목록 재로딩 확인이 남았다. 빌드 문제와 이 재로딩 문제를 분리한다.
- 최초 discovery 화면의 cover preview가 iPhone에서 원격 이미지를 요청할 수 있으나, Worker 이미지 import 다운로드·JPEG 생성·Storage 업로드와는 별도다. 본 테스트는 후보 fixture 검증 전 import 이미지 요청을 만들지 않는다.
- **실제 smoke 미시작:** `createBrand`, 후보 목록 탐색 callable, 제품 대기열 callable, Cloud Tasks enqueue, 외부 시즌/이미지 URL 요청, Storage 업로드, 제품 Firestore 쓰기·삭제, QA 자료 정리를 수행하지 않았다. source image GET 0건, Storage JPEG write 0건이다. 브랜드는 생성되지 않았다.
- 남은 선행 조건: 허용된 실기기 UI 접근/자동화 경로를 확보해 로그인 계정의 관리자 권한을 정상 API로 확인하고, A `2026SS (534)` + `2025FW (469)` 및 B `2025SS (128)` live 후보의 URL/순서/개수/cover/hash를 fixture와 대조한다. 일치할 때만 기존 승인량의 smoke를 실행한다. 이후에만 A~J를 진행한다. 비용 hard cap은 미확인이고 요청량/QA cleanup 범위는 기존 확정을 유지한다.

## 재개 후 실제 Development 연결 결과 — 배포 시점 (2026-10-06)

- Worker candidate: Cloud Run service `lookbook-import-worker-development`, revision `lookbook-import-worker-development-00017-loj`, tag `q7-20261006`, image digest `sha256:042f8e2a304d0e4fbeff0efcd34b54bc82c5bdbe83e00d6bf2b8522e747a038a`, tag URL `https://q7-20261006---lookbook-import-worker-development-xyenspjiwa-du.a.run.app`. 기본 revision `00012-fih`는 100%를 유지하고 candidate tag는 0%다. image build는 Cloud Build `57a3b6af-1644-40a1-8b49-1028045ff665` 성공. 1 CPU/2 GiB, concurrency 2, revision maxScale 1, timeout 900초, 기존 runtime SA를 유지했다. candidate의 `OUTPICK_IMPORT_REMOTE_CAMPAIGN`은 제거했다.
- Functions는 product queue contract에 속한 23개 callable/trigger만 배포했고 모두 ACTIVE다: `createBrand`, `requestSeasonImport`, `requestSeasonAssetRetry`, `requestSeasonCandidateImportJobs`, `getLookbookExtractionReview`, `reviewLookbookExtraction`, `retryLookbookExtractionAfterFix`, `requestLookbookSeasonRepair`, `previewLookbookSeasonRepair`, `applyLookbookSeasonRepair`, `onSeasonImportQueued`, `discoverSeasonCandidates`, `requestSeasonDiscovery`, `retrySeasonDiscovery`, `retrySeasonDiscoveryAfterExtractionFix`, `onSeasonDiscoveryQueued`, `reconcileSeasonDiscoveryJobs`, `getSeasonImportBatch`, `onLookbookBatchPreparationRequested`, `onLookbookPreparationSequenceChanged`, `onLookbookQueueHeadChanged`, `onLookbookQueueBatchReady`, `reconcileLookbookQueueDelivery`. `requestSeasonImport`은 Worker tag URL을 사용하고 OIDC audience는 기본 service URI다. retry 가능한 queue trigger 설정을 반영하기 위해 정확한 목록에만 Firebase CLI `--force`를 사용했다.
- Firestore는 전체 `firestore:indexes` 동기화의 dry-run에 로컬 전용 index 10개 추가(이 중 4개는 Q6 필수, 6개는 무관)와 원격 전용 index 2개 삭제가 포함되어 있어 실행하지 않았다. 대신 `collectionGroup=writes`에 필요한 Q6 composite index 4개(status+brandID, executionID+epoch+status, status+targetSeasonPath, status+targetPath)만 add-only API로 생성해 모두 READY를 확인했다. 다른 index 삭제·Firestore rules 변경은 없었다.
- Cloud Tasks `lookbook-import-jobs`는 배포 전후 모두 0 task였다. 기존 RUNNING queue와 dispatch/retry 설정은 변경하지 않았다. post-deploy read-only로 base traffic 100%/Q7 tag 0%, Functions 23/23 ACTIVE, index 4/4 READY를 확인했다.
- 이어진 로컬 재조회 시 sandbox가 `~/.config/gcloud/credentials.db` 쓰기를 막아 Cloud Run/index 상태 재조회가 실행되지 않았다. 따라서 위 상태는 마지막 성공한 post-deploy read-only 증거이고 실제 smoke 직전에 권한·traffic·task queue를 다시 읽어야 한다.
- 필수 gate: Functions `1791260107041-123d86ad-2a62-486c-918e-2d9849ec81b4` passed, 315 tests, lint error 0, digest `98f1f02ee1736a1489b95ae33d5e6262b8b966d1f5918b9eeab7dcd26bac756e`/270 files. Queue Emulator `1791260220289-61b16950-d35c-493b-ab87-5ecdff576694` passed 69/69, digest `97d5f5c474e4001da973a28815b803be5abf2b2ff8a8a16727094fe073423758`/286 files. 앞선 병렬 Emulator run은 gRPC transaction 오류로 68/69였고, 문제 테스트의 단독 재실행과 전체 69개 재실행이 통과했다.
- iOS 앱은 `OutPick-Development`, `Development-Debug`, iPhone 17 Pro Max iOS 26.5 Simulator에서 빌드·설치·실행 성공(PID 23397, 13개 경고). XcodeBuildMCP의 초기 일반 `Debug` 설정은 프로젝트 설정명과 달라 Promises bundle copy에서 실패했다. 프로젝트 설정명으로 맞춰 정상 실행했고 Package.resolved를 수정하지 않았다.
- Simulator `내 정보`에서 닉네임 `AD`를 읽었다. 닉네임만으로 총 관리자 권한을 증명하지 않으며, 이전에 확인한 현재 계정의 `brandAdmins.isActive=false` 상태를 임의로 관리자 권한 부여해 바꾸지 않았다. 따라서 `createBrand`, season import/review, task enqueue, 원본 URL 요청, Storage·Firestore product data write/delete, QA 자료 삭제는 수행하지 않았다.
- 실제 처리 전 남은 필수 단계는 (1) 기존 총 관리자 계정 세션이 맞는지 확인, (2) 고정 후보와 최신 HTML/hash/count/cover를 실행 시점에 비교, (3) A 2시즌/B 1시즌 smoke를 한 번 실행해 URL·Storage·FIFO evidence를 기록하는 것이다. 그 뒤 A~J의 각 브랜드 생성·탐색 10건과 별도 import 10건을 100ms 간격 wave로 접수한다. 실제 청구 hard cap은 확인되지 않았다.

## 확정한 입력 및 제품 경로 차이

- 확정: 이전 A~J 성능 실험은 6개 원본 시즌을 반복 배정해 A8/B2/C~J각1(18시즌)이었다. 제품 `queue/season-admission.ts::seasonTarget`은 같은 브랜드의 sourceURL을 중복 판정하고 `claimKey`로 사용한다. 후보 ID 배열도 중복 제거한다. 따라서 제품 검증 입력은 A6/B2/C~J각1, 총16시즌이다.
- 확정: 기존 원본 확인 기록([ten-brand-readiness](ten-brand-readiness.md) §2)은 6시즌 모두 `needsReview/expected_count_unverified`였다. 고정 후보와 일치하는 QA 시즌만 정상 관리자 검토 API로 승인한다. 실제 후보 URL·순서·개수·커버·content hash와 generation/snapshot을 fixture와 대조한 뒤 `reviewLookbookExtraction`을 호출하고, 승인이 새 FIFO 차례에서 저장되는지 검사한다. 품질 기준을 우회하거나 Firestore 원문을 직접 수정하지 않는다.
- A~J 제품 검증은 성능 8회 재실행이 아니라 최종 6/4/1/4·128MiB 정책의 실제 접수 검증이다. 100ms는 클라이언트 발송 예정 간격이며 네트워크/트랜잭션 이후 서버 접수 시각·sequence도 별도로 기록해야 한다. 제품 FIFO 판정은 실제 서버 sequence를 따른다.
- G-D 준비 검사 `verification/lookbook-queue-development-preparation.json`의 6개 ID가 fixture 양·정상 검토 승인 조건·FIFO/drain 증거를 검사한다. 최신 통과 `1791258452552-818719e3-e5e6-4daf-a108-913eec4b1b6f`, digest `d3e4722df4299a57566aec7c58cd410825dad30fde7064221fcb873a91e4d609`, 11개 입력 파일. 이것은 live Development reader가 아니며 원격 실행 증거를 대신하지 않는다. G-D 원격 evidence 수집/실행 gate는 아직 연결 전이다.

## 최초 연결의 배포 파일·검증 준비 범위

- 최초 후보 export: `createBrand`, `requestSeasonCandidateImportJobs`, `getSeasonImportBatch`, `getLookbookExtractionReview`, `reviewLookbookExtraction`, `onLookbookBatchPreparationRequested`, `onLookbookPreparationSequenceChanged`, `onLookbookQueueHeadChanged`, `onLookbookQueueBatchReady`, `reconcileLookbookQueueDelivery`.
- 함께 갱신해야 하는 기존 전달/감시 경로: `onSeasonImportQueued`, `onSeasonDiscoveryQueued`, `reconcileSeasonDiscoveryJobs`. 현재 로컬 코드는 큐 소유 job을 제외하지만 원격 구버전은 그 보장이 없다. 새 트리거만 배포하면 기존 시즌별 전달과 겹칠 수 있으므로 기존 함수도 대상 대조가 필수다.
- 위 목록은 최소 연결 코드 조사 결과다. 후속 수동 재시도/repair/복구 API는 해당 시나리오 연결 때 별도로 추적한다. 새 retention scheduler 둘은 최초 배포 목록에서 제외한다. QA 자료 삭제는 승인 범위에 없다.
- G-D 준비 gate는 입력량·고정 후보·정상 검토 승인 payload·FIFO drain을 검사한다. 100ms 도착은 브랜드 생성/탐색 10건과 후보 선택 후 import 10건의 별도 wave다. 최신 6 ID 통과는 `1791258452552-818719e3-e5e6-4daf-a108-913eec4b1b6f`, digest `d3e4722df4299a57566aec7c58cd410825dad30fde7064221fcb873a91e4d609`/11 files. 이 로컬 준비 gate는 원격 evidence reader가 아니다.
- 필수 증거: Development 대상/소스 digest, callable 요청·응답·서버 sequence, batch/items/runs/epoch, 검토 후보 대조·승인 영수증, 앞 run drain/release와 다음 run 시작, 실제 Storage generation/해시/크기/공개 경로. 누락·실패·skip은 통과시키지 않는다. 화면 QA와 실제 플랫폼 종료 증거는 별도 잔여 항목이다.

## 최초 배포 전 Development 상태 snapshot

아래 표는 Q7 연결 배포 직전 baseline이다. 현재 상태는 위의 `재개 후 실제 Development 연결 결과`가 우선한다.

대상은 Firebase project `outpick-test`, `asia-northeast3`다. `gcloud run services describe`, revision describe, IAM policy 조회, Cloud Tasks queue describe/list, Firestore composite index list, Functions list를 읽기 전용으로 확인했다.

2026-10-06 재개 후 Cloud Run 설정을 다시 읽었다. source-deploy image URI는 `asia-northeast3-docker.pkg.dev/outpick-test/cloud-run-source-deploy/lookbook-import-worker-development`다. 기본 100% revision은 이전 기록과 같이 `00012-fih`다. 기존 `aj8-261005` tag revision 환경에는 `OUTPICK_IMPORT_REMOTE_CAMPAIGN`이 설정되어 있어 제품 요청 후보로 재사용하지 않는다. 새 제품 candidate는 Q6 Worker source로 만들고 campaign env를 제거한 별도 tag/0% traffic이어야 한다. service-level maxScale 5와 revision-level maxScale 1을 그대로 보존한다.

| 자원 | 읽기 전용 관측 | Q7에 미치는 점 |
|---|---|---|
| Cloud Run service | `lookbook-import-worker-development`; 서비스 URI `https://lookbook-import-worker-development-xyenspjiwa-du.a.run.app` | Worker 요청을 이 기본 URI로 보내면 현재 100% traffic revision으로 간다. |
| 100% traffic revision | `lookbook-import-worker-development-00012-fih`, image digest `sha256:42344ae960f2d837ccfee79498a0e938afb0c681c358dd029411f36531d29287` | 이전 제품 큐 코드다. Q6 gate source digest와 일치하는지 확인되지 않았다. |
| 최신 Ready/tag revision | `lookbook-import-worker-development-aj8-261005`, image digest `sha256:739a7d6cd8b3ce0bdc8ccfd870d1939c274733885e74f28ac1c60e3743307067` | tag는 있으나 traffic 0%. A~J 성능 캠페인 revision이며 Q6 코드 포함 여부는 입증되지 않았다. |
| Worker 자원 | 두 revision 모두 1 vCPU, 2 GiB, concurrency 2, request timeout 900초. 서비스 annotation `maxScale=5`; traffic revision `00012-fih`의 revision maxScale 20, tagged revision `aj8-261005`는 revision maxScale 1. 두 revision에서 minScale annotation은 없음. tagged revision의 `cpu-throttling=true`, startup CPU boost는 둘 다 enabled | service-level cap과 revision-level cap이 다르므로 유효 scale은 배포 전 재확인한다. Q7 candidate는 tag 0% traffic와 revision maxScale 1을 명시한다. |
| 실행 identity | Worker runtime SA `outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com` | 현재 런타임 계정은 그대로 두는 안이다. 권한 추가는 이 smoke에 자동 포함되지 않는다. |
| Worker invoker | 기존 IAM에 task SA `outpick-lookbook-task-dev@outpick-test.iam.gserviceaccount.com`과 default compute SA가 있음. `allUsers`는 확인되지 않음 | 기존 IAM을 유지하는 안이다. tag URL 접근이 동일하게 되는지는 candidate를 만들기 전에 별도 확인한다. |
| `requestSeasonImport` | ACTIVE, 마지막 업데이트 2026-08-01, 기존 revision `requestseasonimport-00003-zug` | 현재 Functions의 `OUTPICK_LOOKBOOK_IMPORT_WORKER_URL`은 기본 Worker URI다. 새 tag URL을 가리키지 않는다. |
| 제품 큐 Functions | 최신 목록에도 `getSeasonImportBatch`, preparation/head/batch-ready trigger와 queue reconciliation이 없음. 기존 일반 create/review callable은 존재 | Q6 queue 계약으로 접수·전달할 수 없다. |
| Cloud Tasks queue | `lookbook-import-jobs`, RUNNING; max concurrent dispatch 6, max dispatch/sec 3, burst 10. max attempts 3, min backoff 30초, max backoff 300초, retry duration 1시간 | 현재 product queue가 공유하도록 설계한 기존 queue다. 조회 순간 task 목록은 비어 있었다. 다른 작업을 넣지 않는 통제된 한 번의 창에서만 사용한다. |
| Cloud Tasks deadline | sender code는 per-task dispatch deadline 900초 | queue 설정과 함께 실행 전에 재확인한다. |
| Firestore index | 전체 composite index 65개 중 `collectionGroup=writes`는 0개(최신 JSON 재조회) | 원장 쿼리에 필요한 인덱스 배포 후 READY 확인이 선행 조건이다. |
| Storage | `outpick-test.firebasestorage.app`, ASIA-NORTHEAST3 regional, `default_storage_class=REGIONAL`, uniform access off, public access prevention inherited, soft delete 604800초(7일) | ACL/Storage rules 변경 없음. 파일 삭제 후에도 7일 soft delete로 복구 가능·보관 비용이 남는다. |

읽기 전용 확인은 Worker tag가 Q6 gate의 source와 동일함을 입증하지 못했다. Functions와 Worker 사이에 현행 Q6 계약 연결도 없다. 따라서 지금 앱에서 import를 보내면 Q6 검증 대상이 아닌 기존 route에 도착할 수 있다. 이 상태에서 실제 이미지 요청을 보내지 않았다.

제품의 시즌 실패 재시도는 **최초 시도를 포함해 최대 5회, 지연 없이 즉시**다. 이는 Worker 안의 business retry다. Cloud Tasks는 별도 전달 계층으로 현재 최대 3회, 30초부터 backoff한다. 원격 설정을 바꾸지 않는 이상 HTTP 503 이후 전달 간격을 즉시로 만들 수 없으며, 두 재시도 숫자를 하나의 횟수로 합산하지 않는다.

## 확정한 실제 URL FIFO smoke

성능 우승 구조를 새로 찾는 비교가 아니라, Q6 제품 대기열이 실제 URL 다운로드·변환·Storage 저장을 포함해 **A의 두 시즌 묶음이 완료되기 전에 B가 실행되지 않는지** 확인하는 한 번의 기능 smoke다. local queue/integration gate는 이미 통과했으므로 Development에서 여러 회차를 먼저 반복하지 않는다.

고정 fixture `tools/lookbook-import-worker/fixtures/performance-remote-input-amd64.json` 기준 입력이다. 최초 추출은 검토 상태에 멈출 수 있으므로 같은 입력의 정상 승인을 별도 FIFO 요청으로 넣고 실제 저장까지 확인한다.

| 가상 브랜드 | 접수 시점 | 시즌 | fixture 기준 raw image URL fetch | unique 저장 asset | JPEG object write |
|---|---|---|---:|---:|---:|
| A | 먼저 생성·탐색, 고정 후보 확인 후 import·승인 | 2026SS (`product_no=534`) + 2025FW (`product_no=469`) | 추출 해시 46 + 승인 저장 재다운로드 46 | 46 | 92 |
| B | A import 진행 중 생성·최초 탐색, 고정 후보 확인 후 import·승인 | 2025SS (`product_no=128`) | 추출 해시 18 + 승인 저장 재다운로드 17 | 17 | 34 |
| 합계 | 논리 batch 7개: A discovery → A import → A reviews×2 → B discovery → B import → B review | 3 seasons | **127 GET / 55,687,489 bytes** | **63 assets** | **126 JPEG objects** |

고정 season URL은 2026SS `https://unaffected.co.kr/collection/view.html?product_no=534&cate_no=88&display_group=1`, 2025FW `https://unaffected.co.kr/collection/view.html?product_no=469&cate_no=88&display_group=1`, 2025SS `https://unaffected.co.kr/collection/view.html?product_no=128&cate_no=88&display_group=1`다. 입력 전체 digest는 `c4fb65f71fa5f26a6f9a531e58b8629ba2aff0f612c81e75e7cdeb05028f0c56`다. season HTML SHA는 차례대로 `df4194c36b40f72a5b5817e0846c40620bc9c68bde8886fb7ea8441e2a2e67d8`, `c6ad5ad47e8e08b1b8a720075827501ad92293fe472c137a49edf770bb86e7e1`, `50311bd28ec7b54057e68fbb5e705762cc81454f08f7b726d994eff289fa3533`다. fixture의 HTML SHA와 고유 후보 수를 실행 직전 실제 추출 결과와 비교한다. 후보 구성/계절 선택이 fixture에서 달라졌으면 이미지 다운로드를 시작하지 않고 새 입력량으로 실행안을 다시 산정한다.

- source image 예상은 최초 추출 해시 64 GET/28,241,613 B + 승인 저장 재다운로드 63 GET/27,445,876 B, 합계 **127 GET/55,687,489 B(53.1 MiB)**다. 재시도가 없는 fixture 계산이다. HTML, browser, redirect, retry·SDK traffic은 추가될 수 있다.
- 예상 첫 성공 경로 Storage write: JPEG 126개, 총 15,614,243 bytes (약 14.89 MiB). 처리 종료 뒤 golden hash·dimension·orientation·path를 확인하며, 검증 GET은 최대 126개/동일 payload 크기까지 계획한다.
- 소규모 mutation callable은 createBrand+최초 discovery 2회, 선택 시즌 import 2회, 정상 검토 승인 3회로 총7회/FIFO batch 7개다. A~J는 createBrand+discovery 10건을 100ms 간격으로 접수한다. 후보가 나온 뒤 import 10건을 별도의 100ms wave로 접수하며 review 승인 최대16건은 각 추출 후 FIFO 끝에 넣는다. mutation 합계36회다. 상태 조회와 trigger/reconciliation/task delivery는 별도다.
- 정확성 증거(2026-10-06 정정): 승인 저장은 FIFO 맨 뒤의 새 요청이다. A import가 검토 대기·drain되면 앞서 접수된 B discovery가 먼저 실행될 수 있다. A 전체 저장 우선이 아니라 각 서버 sequence의 이전 실행 종료·drain 뒤 다음 실행 시작을 판정한다. requestID·sequence·batchID·runID·epoch·task delivery·revision/instance·검토 snapshot·저장 path/generation을 manifest에 기록한다.
- 제한: 1회만 실행. 수동 재시도와 반복 회차는 포함하지 않는다. Worker 900초/Task delivery 3회 및 business retry 총5회는 제품이 이미 가진 정책이다. candidate count가 fixture보다 크거나 URL/입력이 달라지면 다운로드 전에 중단한다. 부분 실패 시 다음 가상 브랜드를 임의로 진행하지 않고 종료·복구 상태를 보존한다.
- 데이터: A/B는 실행 전 중복이 없는 QA 이름으로 생성하는 제안이다. 성공 이미지와 Firestore test documents는 제품 경로로 저장된다. 자동 삭제는 실행 범위에 포함하지 않고, 정확한 QA brandID/runID만 대상으로 한 cleanup은 결과 확인 후 별도 요청에서 진행한다. 코드의 24시간 asset cleanup은 자동으로 삭제 여부를 확인한다.

## 비용 추정과 한계

정확한 총액은 아직 산출할 수 없다. 프로젝트 billing account의 월 free-tier 사용량·현재 Storage bucket storage class·Firestore operation 수·배포 시 Cloud Build/Artifact Registry 사용량을 확인하지 않았다. 외부 원본 이미지가 Worker로 들어오는 전송은 ingress이며 이를 Worker의 인터넷 egress로 계산하지 않는다. 검증 이미지의 로컬 다운로드 등 외부 송신은 별도다. 비용은 호출량만으로 고정되지 않고 retry/실행 시간/기존 월별 사용량에 따라 달라진다. 그래서 과거 성능 캠페인의 US$0.4~1 추정을 이 smoke의 확정 비용으로 재사용하지 않는다.

이 문서의 이전 `$0.1044/시간` 예시는 서울 리전 단가 확인 없이 기본 표시 요금을 사용했으므로 철회한다. 2026-10-05 서울 단가 확인 기록은 [ten-brand-readiness §3](ten-brand-readiness.md)에 있으며 1CPU/2GiB 활성 1시간 산술은 `$0.14616`이었다. 이는 과거 확인 시점의 Worker 계산 예시이며 Q7 총액이나 현재 단가 검증을 대신하지 않는다. 검토 승인 후 재다운로드, Functions 실행·조회, Firestore 작업, Storage 보관/쓰기/검증 읽기·외부 송신, Tasks 전달, 배포/registry/logging을 포함해 확정 입력으로 재산정한다. 과거 기본 리전으로 계산한 Storage 보관 `$0.00029`도 Q7 서울 확정 비용에서 제외한다. 무료 잔여량과 실제 청구 상한은 미확인이다.

Cloud Run 요청 기반 CPU/메모리 비용은 활성 요청 구간에, Storage는 데이터 보관·요청 operation·네트워크 항목으로 과금된다. Cloud Tasks는 API 호출과 push 전달 시도를 billable operation으로 센다. [Cloud Run 요금](https://cloud.google.com/run/pricing), [Cloud Storage 요금](https://cloud.google.com/storage/pricing), [Cloud Tasks 요금](https://cloud.google.com/tasks/pricing). 결제 반영 지연 때문에 예산 알림은 강제 차단 장치가 아니다. 실행 승인 전에는 실제 billing 사용량을 확인하고 별도 stop 기준을 기록해야 한다.

## 최초 연결 배포 전 체크리스트

아래는 배포 전에 작성한 단계별 체크리스트다. 1~4는 위의 실제 연결 결과에서 완료했다. 5~6은 실제 smoke/A~J 증거 수집 시 적용한다.

1. 완료: Worker candidate tag를 traffic 0%로 배포하고 base 100% traffic을 유지했다. revision/image 및 OIDC 설정은 위 current status에 기록했다.
2. 완료: exact queue Functions 23개를 배포해 ACTIVE 확인했다. Worker URL은 candidate tag를 가리킨다.
3. 완료: 필요한 `writes` 복합 index 4개를 add-only로 만들어 READY 확인했다. 기존 Firestore/Storage rules를 변경하지 않았다.
4. 완료: post-deploy traffic, tag, Functions, index와 shared Cloud Tasks queue empty를 확인했다. 권한 정책은 수동 변경하지 않았다.
5. 대기: 고정 fixture/golden과 A→B live 후보를 대조한다. 재시도 제외 smoke 예상 image GET127/55.69MB, JPEG write126/15.61MB, 검증 GET 최대126이다. 현재 Simulator 계정의 총 관리자 여부 확인이 선행돼야 한다.
6. 대기: 실행 시 관측 원본, 비용 snapshot, request/task/run/instance/Storage manifest를 기록한다. 종료 또는 stale run이 확인되지 않으면 다음 요청/브랜드를 접수하지 않는다. QA test data 삭제는 별도 승인 후 exact ID로만 한다.

## 현재 남은 단계 및 한계

- Worker/Functions/index 최소 연결 및 앱 실행은 완료됐다. 실제 iOS 접수→UNAFFECTED 페이지 탐색→원본 다운로드→변환→Storage 저장→FIFO/drain/재개 증거는 아직 수집하지 않았다.
- Simulator `내 정보`에는 닉네임 `AD`가 보이나 이는 역할 증거가 아니다. 이전 Firebase user 확인은 `brandAdmins.isActive=false`였다. 기존 총 관리자 계정으로 전환을 선택했지만 그 계정 세션이 현재인지 확정되지 않았으므로 `createBrand`를 호출하지 않았다. 권한/IAM을 임의로 추가하지 않는다.
- `lookbook-import-jobs`는 마지막 조회에서 비어 있었고 queue 설정을 변경하지 않았다. 시작 직전 다시 확인한다. 실제 billing 사용량과 hard cost ceiling은 미확인이다.
- UI 상의 앱 로그인 상태와 서버 총 관리자 권한을 서로 다른 증거로 확인한 뒤에만 소규모 smoke를 시작한다. QA test data 정리는 수행하지 않았으며 결과 검토 후 정확한 QA ID만 대상으로 별도 승인 절차를 따른다.
