# Q7 잔여 장시간·복구 검증 최소 실행안

## 최신 제품 방향 — 2026-10-07

사용자는 최초10개·더보기10개·선택 자유·최근1~2년 중심의 운영 지침을 확인했다. 표현은 **최근 발매한 룩북부터 순서대로**이며 일반 시즌과 콜라보를 동일하게 취급한다. 콜라보 우선이나 최초6시즌 선택 제한을 제품 정책으로 채택하지 않는다. 정책 source는 [관리자 웹 결정](../admin-web-operations-migration/decisions.md)의 룩북 등록·운영 기준이다.

아래 L/T/O·11접수·고의 장시간/종료 기능은 이전 제안으로 아직 승인되지 않았다. 최근 운영 규모의 정상 처리·중간 종료/복구를 우선하는 Q7 범위 조정과 발매순·목록 추가조회 계약은 별도 세부 설계가 필요하다. 이 정책 확인만으로 기존 장시간 필수 항목을 통과 처리하거나 Q7 완료로 바꾸지 않는다. 원격 새 접수·고의 장애·복구 API 보완 구현은 아직0이다.

작성일: 2026-10-07 KST. 사용자 승인 순서: 실행안·요청량·비용 확정 → 실제 검증 → 결과·문서 정리 → 최종 커밋. 이 문서는 코드 조사에 따른 제안이며 아래 추가 기술 결정은 사용자 확인 전 확정하지 않는다. 현재 원격 변경·접수·고의 장애 실행은 0회다.

## 목적과 현재 증거

[A~J 정상 검증](product-queue-q7-ten-brands-results.md)은 36접수/16시즌/710JPEG·공개 원장·FIFO 비중첩을 확인했다. 남은 것은 실제 12분 투입 중단과 정상 이어 실행, 14분 HTTP 응답 경계 및 재전달, 강제 종료 후 증거 기반 복구다. 정상 사례와 고의 장애의 결과를 분리한다.

실행 설정은 Development `outpick-test`, 기존 서비스의 검증 태그, 1CPU/2GiB/min0/revision max1/concurrency2/timeout900초다. 2026-10-07 읽기 전용 조회에서 candidate024 설정을 재확인했다. 기본 100% traffic과 IAM·메모리 85%/1초·표본 100ms/공백500ms·재시도 예산은 유지한다. timeout을 줄여 실제 12/14/15분 검증으로 표시하지 않는다.

## 조사에서 확인한 선행 보완

`QueueSupervisor`는 12분에 신규 투입 신호를 중단하고 14분 초과를 기록한다. `http-deadline.ts`는 14분에503을 반환하되 내부 작업 종료를 계속 기다린다. 큐의 실제 종료·drain 확인 뒤에만 다음 차례가 진행된다.

프로세스가 중간에 죽으면 `finishBatchRun`이 실행되지 않아 queue/batch가 active 또는 draining으로 남을 수 있다. 현재 `inspectQueueRecovery`와 `resumeQueueRecovery`는 두 상태가 recoveryRequired일 때만 재개할 수 있다. 5분 점검도 active 실행권을 시간만으로 회수하지 않는다. 따라서 강제 종료 테스트 전에 안전한 상태 전환 경로가 필요하다.

추천은 전용 recovery 인가에서 실제 플랫폼 종료 증거를 확인하고 exact head/epoch/run/revision/stateRevision을 transaction에서 재확인해 active/draining → recoveryRequired로만 고정하는 조건부 정산 동작이다. owner를 해제하거나 다음 브랜드를 시작하지 않는다. 이어 기존 inspect/resume를 사용한다. 종료 증거, trace→instance 일치, 전체 asset-write 검사 중 하나라도 없으면 거절한다. 과거 run에 terminalConfirmed=true나 inFlight=0을 꾸며 넣지 않고, 원래 실행 상태와 별도90일 감사 기록을 보존한다. endpoint 명칭·데이터 계약은 이 방향을 확인한 뒤 세부 설계에서 확정한다.

추가로 현재 resume는 batch만queued로 바꾸며 중단된 execution/continuation을재실행가능상태로복원하지않는다. `beginBatchItemAttempt`는 queued/retryWaiting 실행 또는 queued 승인 continuation만 받아, active/recoveryRequired checkpoint는 notQueued로 거절한다. 기존 실제 복원은 이미 종료된 discovery item을 보존한 사례였고 중간 이미지 작업의 재개와 다르다. 따라서 이번 보완에는 정확히 해당 묶음의 미완료 항목·root claim·execution/continuation 재연결도 포함해야 한다. 완료 항목·이미 공개된 경로·원래 attempt 이력은 보존하고, 기존 최초 포함5회 예산을 초기화하지 않는다. 임의 전체job 재초기화는 하지 않는다. 상세 phase/resumeFrom 필드와 재시도 소진 처리는 기존 activation 계약을 기준으로 세부 설계·Emulator 테스트에서 확정한다.

[Cloud Run request timeout](https://docs.cloud.google.com/run/docs/configuring/request-timeout)은 연결의504와 container 종료를 구분한다. timeout만으로 종료 증거를 만들지 않는다. [종료 신호 설명](https://docs.cloud.google.com/run/docs/configuring/execution-environments#graceful_shutdowns)도 참조한다. 실제 플랫폼 로그는 관측된 원문으로 판정하며 기대 문구가 없으면 해당 검증을 실패·차단으로 남긴다.

## 제안한 세 시나리오

| 시나리오 | 입력·접수 | 조작 지점과 확인 |
|---|---|---|
| L:12분 정상 이어 실행 | 새 A 브랜드7시즌 import, 실행 중 새 B 생성·탐색.3접수 | 첫6항목은 실제 추출·검토 대기 checkpoint를 기록한 뒤 callback 반환을725초까지 유한 지연한다. 대기 중7번째 항목은 시작하지 않는다.12분 신호 뒤 종료·drain, 같은 묶음 새epoch에서7번째만 처리, B는 A 묶음 release 뒤 시작. 정상 분할로 시도 예산을 새로 소비하지 않는지 확인 |
| T:14분 응답·재전달 | 새 A2026SS 추출·승인, 실행 중 새 B 생성·탐색.4접수 | 승인 실행의 실제 작업을915초까지 유한 지연한다.14분503/Cloud Tasks 재전달에서 기존 owner를 중복 선점하지 않고 B를 차단하는지 확인. CPU throttling으로 유한 지연 종료가 늦어질 수 있으므로 응답 후 진행을 보장한다고 가정하지 않는다. 실제 종료·drain 또는 입증된 플랫폼 종료에 따른 조건부 복구만 허용 |
| O:실제 플랫폼 종료·복구 | 새 A2026SS 추출·승인, 실행 중 새 B 생성·탐색.4접수 | 첫 자산의 업로드 결과 확보 후 공개 전 지정 실행만 메모리 압박으로 종료시킨다. 플랫폼 로그의 exact trace/instance 종료 확인 → active/draining 조건부 정산 → inspect/resume. 이전 불확정 파일은 미공개로 보존하고 새epoch 경로·generation만 공개. B는 복구 완료·drain 뒤 시작 |

각 시나리오는1회씩 순서대로 실행하며 앞 시나리오가 종료·정산되지 않으면 다음을 시작하지 않는다. L과 T의 유한 지연은 실제 elapsed-time 경계를 검증하기 위한 장치이고 느린 네트워크나 무거운 이미지 자체의 성능 재현으로 해석하지 않는다. O는 정상 메모리 상한을 늘리는 테스트가 아니라 별도 고의 플랫폼 종료 테스트다.

L 입력은 기존6시즌 + UNAFFECTED2023SS(product_no505)다. 정상 concurrency6에서 미시작 항목을 남기려면 최소7개가 필요하다.2026-10-07 로컬 읽기 전용 추출에서30후보/실패 사유0/검토 필요를 확인했고, HEAD30회에서 원격 크기 합계6,704,829B·누락0이었다.7번째 시즌은 이미지 순서·해시 fixture를 동결한 뒤 실제 검토 결과와 대조한다. L에서는 승인·Storage 저장을 하지 않는다. T/O는 기존2026SS golden을 사용한다.

## 검증 기능의 격리 조건 제안

- 검증 전용 설정은 Development 프로젝트·전용 candidate에만 허용하고 기본값은 disabled다.
- 실행안의 runID·관리자UID·브랜드·requestID/batchID·epoch·지점·만료 시각을 고정한다. URL/body에서 임의 delay·메모리 할당량을 받지 않는다.
- 현재 head/owner와 일치한 지정 실행에서만1회 소비하는 영속 표식을 만든다. 읽기·기록 실패 또는 설정 만료는 장애 조작을 시작하지 않는다.
- 실제 접수는 정상 createBrand/import/review API를 사용한다. queue/jobs를 fixture로 직접 만들어 제품 접수를 우회하지 않는다.
- 장애 조작용 범용 공개 endpoint, 새 IAM, 파일 삭제, 강제 unlock은 추가하지 않는다. 완료 후 검증 설정이 없는 candidate로 복구하고 실제 설정을 다시 읽는다.

## 요청량·전송량 제안

| 항목 | 정상 경로와 지정1회 장애의 계획 범위 |
|---|---:|
| 논리 mutation |11회:브랜드 생성·탐색6 + import3 + 승인2 |
| 신규 import 시즌 |9개:L7 + T1 + O1 |
| 최종 Storage 저장 시즌 |2개:T/O2026SS |
| 원본 이미지 GET |기본284회, O의 저장 원본 전체 재다운로드까지 포함315회 |
| 원본 이미지 bytes |O 전체 재다운로드 포함131,367,981B |
| JPEG 최종 산출물 |124개/4,707,216B |
| 중단된 O가 전체 파일을 제출했다고 가정한 업로드 여유 |추가62개/2,353,608B,합계186개/7,060,824B |
| 최종 content 검증 GET |124회/4,707,216B |
| 원장·orphan metadata 검사 |최대186객체, content 추가 다운로드 없음 |

위 산술은 사이트·이미지/시즌 재시도·SDK 재전송이 없는 조건의 입력량이다. 과금 요청량의 절대 상한으로 부르지 않는다. HTML·브라우저·Functions 상태 조회·Firestore transaction retry·Cloud Tasks 전달은 별도다. 상태 조회는 기본10초, 시나리오별30분 창을 넘어가면 새 접수 중단·복구 상태를 보존한다. 총 원격 실행 창은90분을 제안한다. local gate/build 준비 시간은 이90분 처리 창과 분리하되 비용 항목에 포함한다.

## 비용 관리 제안

정확한 청구액은 공유 무료량·실제 실행/재전송·청구 지연 때문에 지금 확정할 수 없다. [Cloud Run 가격](https://cloud.google.com/run/pricing), [Storage 가격](https://cloud.google.com/storage/pricing), [Firestore 가격](https://cloud.google.com/firestore/pricing), [Tasks 가격](https://cloud.google.com/tasks/pricing)을 확인한다. 기존 서울 단가 기록은 `ten-brand-readiness.md`이며2026-10-07 공식 페이지에서 활성CPU0.0000336 항목을 다시 확인했다. 단순 문자열 존재만으로 모든 지역·SKU 최신 검증을 완료했다고 표시하지 않는다.

실행안 예산 계산은 실제 단가보다 보수적인 가정 CPU0.0001USD/vCPU초·메모리0.00001USD/GiB초를 사용한다. 기존1CPU/2GiB의90분 전체 활성 가정은0.648USD다. 이 가정 단가는 공식 청구 단가를 인용한 값이 아니다. 이를 포함한 항목별 관리 예산을 다음처럼 제안한다.

| 항목 | 관리 예산 USD | 근거·미확정 사항 |
|---|---:|---|
| Worker compute/시작 여유 |0.75 |1CPU2GiB·90분전체활성의보수적산술 + 여유 |
| Functions 실행·조회·trigger |0.50 |11접수/기본10초조회·정상trigger와재전달;실제시간추적 |
| Firestore·Tasks |0.25 |원장/조회/transactionretry/전달횟수추적;요청단가총액아님 |
| Storage·검증 egress·보관 |0.25 |최대계획186uploads/124contentGET/metadata/7.1MB미공개보관 |
| Build·Registry·Logging·기타 여유 |1.25 |candidate/설정해제최대2배포·build최대2회·등록이미지/로그보관 |
| 합계 |3.00 |예상청구확정액이 아닌 항목별관리예산 |

기존 작업의 누적 추정10USD 중단 기준을 유지하고 이 실행안의 추가 관리 예산3USD도 함께 추적하는 안이다. 이미 사용한 금액을0으로 초기화하지 않는다. 실제 사용량 추정이 예산을 넘거나 계측이 불가능하면 새 접수를 중단한다. 청구 지연 때문에3/10USD를 강제 결제 상한이라고 보장하지 않는다. 단가·프로젝트 사용량 확인이 불가능하면 미확정 항목과 보수적 계산을 실행 전에 제시한다.

## 단계별 구현 후보와 필수 게이트

| 단계 | 변경 후보·의존성 | 완료 기준·검사 | 논의 |
|---|---|---|---|
| B0 |이 문서/행렬/ENTRYPOINTS/HANDOFF |입력·새상태전환·테스트격리·요청량/예산 확인 |사용자 결정 대기 |
| B1 |`queue/recovery.ts`, CLI/server DTO·route, 플랫폼 로그 provider/activation/checkpoint 관련 tests, Emulator |실제종료증거 없는active/draining거절,exacthead/epoch/state재검사,동시/중복결정멱등,미완료checkpoint재연결/완료보존/기존attempt예산보존,owner보존·늦은쓰기차단,실패원본보존.직접강제해제0 |확인 뒤 endpoint/API 최종 설계 |
| B2 |Development검증설정 모듈,`config.ts`,`batch-runner.ts`,`processor.ts`의 좁은hook,배포snapshot/테스트 |기본disabled/Production거절/대상·만료불일치무효/지점1회소비/기록실패시fault0/유한지연/기존정상경로회귀 |확인 뒤세부hook계약확정 |
| B3 |별도boundary runner/journal/evidence reader,추가2023SSfixture,`verification/lookbook-q7-boundary.json` 후보 |11접수상한/동일ID/중단후재전송금지/가짜종료증거거절/요청-task-run-instance로그연결/기존gate필수;새테스트식별자는실제코드와연결한뒤확정 |모든로컬검사통과 전 원격실행0 |
| B4 |같은service의0%candidate·exactQA설정 |기존자원/traffic/IAMreadback→L→T→O,각1회.실패·종료미확인 시다음시나리오0;검증설정해제readback |실제추가권한필요하면별도논의 |
| B5 |결과/QL행렬/ENTRYPOINTS/관련계획/최종커밋범위 |원본로그/source/gate/실패·미검증보존,모든필수기준만족후Q7완료,작업단위별커밋 |ignore task문서등commit포함범위는실제목록점검뒤확인 |

필수 로컬 범위는 Worker/Q7 boundary verifier/Emulator/Linux이며 Functions·Rules·iOS는 실제 변경이 있는 범위에만 추가한다. 기존 코드가 바뀌면 해당 source 입력의 이전 gate를 재사용하지 않는다. 앱 DI/Container/Coordinator·정식 관리자 웹은 변경하지 않는다.

## 결정이 필요한 부분

1. 실제 종료 증거로 active/draining을 recoveryRequired로 고정하는 제한된 복구 동작과 Development 전용 지연·고의 플랫폼 종료 기능을 이번 범위에 포함할지.
2. L/T/O각1회·11접수·7번째2023SS·90분·추가관리예산3USD/기존누적10USD를 사용할지, 또는 L만3접수로 먼저 시작할지.

이 두 결정 전에는 구현·배포·원격실험을 시작하지 않는다. 사용자 선택 후 각 API/데이터 계약과hook지점을 최종 문서로 확정하고 순서대로 진행한다.
