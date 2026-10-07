# 실제 제품 요청 대기열 연결 — 세부 설계 검토본

## 최신 정정 — 시즌 실패 기록·처음부터 재시도(2026-10-07)

실패 목록 문서의 최종 결정: 같은 시즌에 하나만 유지하고 재시도 실패 시 최신 원인·시각·마지막 요청 ID로 갱신한다. 재시도 성공 또는 명시적 ‘재시도 안 함’ 선택 시 목록 문서를 제거하며, 무선택은 보관 기간 내 유지다. 서버 원본 실행 기록은 기존 보관 정책을 유지한다. 문서 식별키/인가/멱등/늦은 응답 경합과 실제 데이터 정리 계약은 후속 상세 설계다. 목록 문서 제거는 시즌/파일 삭제나 실행 중 작업 취소가 아니다.

사용자 확정: 중간 checkpoint 복원·미완료 execution/continuation 이어 실행 추가는 제외한다. 종료가 확인된 비정상 시도는 실패 기록을 남기고 해당 시즌을 처음부터 재시도하며 최초 포함 총5회 소진하면 최종 실패다. 완료된 다른 시즌은 유지한다. 선택 시즌들의 처리 종료·실행 정리 뒤 실패 목록을 확인하고 수동 재시도할 수 있도록 한다. 수동 재시도는 FIFO 맨 뒤의 새 요청·새 실행·새 총5회이며 이전 이력을 보존한다. [최신 계약·기록·남은 상세 설계](season-failure-retry-decision.md)가 아래 중간 복원 설계보다 우선한다. 개별 timeout·플랫폼 제한·종료 미확인 차단은 유지한다. 기존 코드 전체가 새 계약에 맞춰 변경·검증됐다는 의미는 아니다.

## 2026-10-06 Development smoke에서 확인된 종료 상태 계약

실제 A 최초 목록 탐색에서 domain job이 `correctionRequired`로 종료됐을 때 이전 Worker는 `processImportBatchTaskRequest`가 반환하는 domain 상태(`succeeded`, `awaitingReview`, `correctionRequired`, `failed`, `cancelled`)를 queue의 구형 상태 문자열(`passed`, `needsReview` 등)과 비교했다. 그 결과 정상적으로 완료된 추출을 executor error로 바꾸고 batch/head를 `recoveryRequired`에 남겼다. Worker 수정은 실제 domain 상태를 queue terminal outcome으로 명시 매핑하며 `correctionRequired`도 drain 뒤 terminal item으로 보존한다. 추출 교정은 이번 시도를 끝낸 뒤 새 요청으로 FIFO 꼬리에 접수한다.

로컬 검증: Worker 필수 gate `1791278437747-2969911b-2f9f-45ad-b9ef-244f9b03f212` passed(354 tests, lint, fixtures), product queue gate `1791278627925-2abd9823-7307-47e9-85e5-2bffc9c3a8f0` passed(70 emulator tests, Worker/Functions build). 이 변경은 배포되지 않았다.

기존 Development batch는 `correctionRequired` domain job, `terminalConfirmed=true`, `inFlight=0`의 run evidence를 갖지만 batch/head가 `recoveryRequired`다. 현재 `/recovery/resume`는 batch를 다시 queue하고 item outcome을 terminal로 정산하지 않는다. 재실행 시 이미 `correctionRequired`인 job을 claim할 수 없어 다시 복구 상태로 갈 수 있으므로 이 batch에 resume를 호출하지 않는다. 이미 끝난 terminal 결과를 증거 검증 뒤 queue에 반영하는 별도 recovery action은 현재 승인된 conditional-resume 권한에 포함되지 않아, 구현 전에 사용자 결정이 필요하다. 직접 Firestore 수정, force-release, 새 브랜드/시즌 접수는 하지 않는다.

**현재 구현 기준(2026-10-05):** Q0~Q4의 local implementation 상태는 해당 phase 결과 문서가 우선한다. Q4에서는 5분 delivery reconciliation, queue-owned asset ledger 복구 및 generation 조건부 파일 정리, batch/brand receipt/recovery audit 만료 정리, 기본 비활성 OIDC recovery route/CLI를 구현하고 G-F/G-E/G-W/G-R/G-L을 통과했다. 실제 Development IAM·Cloud Run 종료 증거·URL/Storage 전송·복구 호출은 미검증이고 Q5~Q7이 남아 있다. [Q4 결과](product-queue-q4-results.md).

### 확정 추가: 브랜드 생성과 최초 탐색 접수 (2026-10-05)

사용자가 브랜드 생성과 최초 목록 탐색을 한 요청으로 묶기로 확정했다. `createBrand`도 공통 requestID/requestCreatedAt/queueContractVersion을 받는다. 현재 생성 권한을 검사한 뒤 기존 생성 영수증이 있으면 동일 payload의 결과를 재반환한다. 신규 요청은 기존24시간/미래5분 기준을 적용한다. 브랜드·이름 인덱스·탐색 입력·큐 순번·생성 영수증을 같은 transaction에서 확정하며 실제 탐색은 큐 차례에 수행한다. 탐색 실패는 생성된 브랜드를 삭제하지 않는다.

목록 URL이 없으면 브랜드와 생성 영수증만 저장하고 탐색 순번은 소비하지 않는다. `brandCreationRequests/{hash(uid,requestID)}`는 서버 전용 최소 생성 영수증이며 요청자/digest/생성 시각/result와 30일 `receiptExpiresAt`/`retentionNextAt`을 보관한다. Q4 정리는 진행 중 batch/head가 참조하는 receipt를 보호한다. Q5는 브랜드 생성 전에도 같은 계정별 요청 저장소에 payload/ID/시각을 먼저 저장하고 재시작 시 같은 요청을 재전송한다. 생성 응답에는 brandID/discoveryJobID/requestID/batchID를 포함한다. discoveryJobID는 결정적 ID이며 준비 완료 전에는 해당 job 문서가 아직 없을 수 있으므로 batch 접수 상태를 함께 조회한다.

최신 구현 상태: [Q4 복구·정기 점검·보관 결과](product-queue-q4-results.md). Q0~Q4 로컬 코드·게이트 결과는 각 phase record를 따른다. 앱 GRDB/API/UI, legacy 경로 cutover, Development·실기기 QA가 남아 제품 FIFO는 실제 환경에서 활성화하지 않았다.

2026-10-05. 사용자가 실험 후 제품 연결 세부 설계와 [Q0~Q7 세부 구현 계획](product-queue-implementation-plan.md)을 검토하고 구현 진행을 승인했다. 아래 사용자 확정과 기술 제안을 구분한다. 이 문서는 설계 확정 당시 기록을 보존하며 구현 상태는 처음의 Q0 문구가 아니라 [Q4 결과](product-queue-q4-results.md)와 각 최신 phase record를 따른다. 배포·IAM·추가 유료 실험·실제 원격 삭제는 수행하지 않았다.

## 1. 사용자 확정과 실험 근거

### 확정한 제품 동작

- 브랜드 요청을 서버 접수 순서대로 처리한다. 현재 요청 안의 시즌은 병렬로 처리하고 저장·정리 종료 후 다음 요청으로 넘어간다. 작은 요청 추월·브랜드별 순환 배정은 없다.
- **한 번 선택한 시즌 목록은 닫힌 요청 묶음**이다. A 처리 중 A를 추가 선택해도 새 요청으로 맨 뒤에 넣는다. 기존 A 묶음에 합치지 않는다.
- 모든 대상 시즌이 성공·관리자 검토 대기·최종 실패 등 해당 차례의 종료 상태가 되고, 진행 중 작업이 정리되면 다음 요청을 진행한다. 검토 대기를 시즌 등록 성공으로 표시하지 않는다.
- **검토 승인도 맨 뒤의 새 요청**이다. 승인한 snapshot의 저장 단계만 이어간다. 원본 재추출을 다시 시작하지 않는다.
- **명시적 수동 재시도는 맨 뒤 새 요청·최초 포함 새 총5회 예산**, 기존 실행 이력 보존. 자동 재시도는 같은 차례에서 최초 포함 총5회다.
- **이전 Worker 작업 종료가 불명확하면 다음 브랜드를 시작하지 않는다.** 복구 확인 필요 상태를 유지한다. 시간 경과만으로 실행권을 빼앗아 다음 브랜드를 시작하는 방식은 제외한다.
- **선택한 시즌 묶음 하나를 한 Worker 요청에서 실행한다.** 오래 걸리면 같은 FIFO 차례에서 이어 실행한다. 시즌마다 별도 HTTP로 자원 제한을 나누지 않는다.
- **실행별 별도 Storage 경로에 업로드하고 유효한 현재 실행권으로만 앱 참조 경로를 공개한다.** 미공개·이전 파일의 보관 기간과 정리 절차는 별도 설계한다.
- **미참조 파일은 해당 실행 종료 확인·참조 해제 후24시간이 지나면 정리한다.** 현재 참조 파일 및 종료 불명확·복구 중인 실행은 자동 정리에서 제외한다. 정책 확정이며 실제 삭제 실행 승인은 아니다.
- **긴 작업은12분 신규 투입 종료·14분 정리/응답 목표·외부15분을 초기 검증 기준으로 사용한다.** 정상 분할은 같은 차례·같은 시도로 자동 재개하고 정리 미확인 시 다음 실행을 차단한다.
- **메모리85% 이상 표본상1초 지속,100ms 측정·500ms 초과 공백 중단을 초기 검증 기준으로 사용한다.** 중단 후 진행 기록·정리를 수행하고 복구 확인까지 대기열을 유지한다. CPU 사용률만으로는 중단하지 않는다.
- **기존 화면의 상태를 구분하고 앱 재시작 시 요청 ID로 복원한다.** 검토/실패 결과·복구 안내를 무한 처리 중 표시와 구분하며, 화면 닫기는 서버 작업 취소가 아니다.
- **앱은 배포 전이므로 앱·서버를 최신 계약 하나로 통일한다.** 구버전 앱 호환·임시 요청 ID·업데이트 유도 흐름은 만들지 않는다. 이미 Development에 남은 task/revision의 실행 차단은 별개다.
- **인스턴스당 Chromium1개, 브라우저와 이미지의 무거운 처리를 분리한다.** 목록 탐색도 import와 같은 서버 접수 순서로 처리한다. 실행 중 묶음은 끝내고, 탐색 결과에서 시즌을 선택하면 새 import를 맨 뒤에 넣는다.
- **재시작 복원용 요청 기록은 기존 GRDB에 계정별 테이블로 저장한다.** 별도 JSON 저장소는 만들지 않는다.
- **앱 조회는 처리 중3초·대기/재시도 대기10초**다. 화면 닫힘·백그라운드·결과/복구 안내에서는 주기 조회를 중지한다. 서버 누락 점검5분·파일 정리1시간·기록 정리 하루1회를 초기 기준으로 확정했다.
- **성공 상세24시간·최소 완료 기록30일·실패/중단 상세 해결 또는 최종 종료 후30일·복구 결정90일**을 확정했다. 실행/검토/복구에 필요한 기록과 현재 콘텐츠 참조는 보호하고 만료된 요청을 자동 재접수하지 않는다.
- **복구 실행은 현재 배포 담당자인 사용자 본인1인에게만 허용**한다. 전용 인증으로 증거 조회·조건부 재개만 제공하며 앱 관리자 권한·강제 해제·삭제·증설은 포함하지 않는다. 지금 IAM 변경을 실행한 것은 아니다.

### 적용 설계 기준

[실측](ten-brand-results.md)의 유지 후보인 시즌6·다운로드4/변환1/업로드4·시즌별 이미지4개 빈자리 보충·재사용128MiB·경로 기록 제한 없음을 제품 연결 기준으로 검토한다. 다운로드/변환/업로드 한도는 시즌별 배수가 아닌 **현재 Worker에서 실행 중인 묶음 전체 공유**다. 실험의 단계 슬롯 단위를 그대로 유지하고 이미지 내 variant 처리 의미를 임의로 바꾸지 않는다.

S6 249.44초, P6 245.29초(-1.66%), Pall253.22초(+1.51%)/메모리90.24%/재다운로드239건, T2는94.49% 최고 메모리와85% 초과1초 지속으로 중단됐다. U8은 미실행이다. 각1회·동일 인스턴스 자료이므로 최적값이나 모든 브랜드의 안정성을 보증하지 않는다.

실험은 고정된 후보 이미지 목록을 사용했다. 제품의 HTML 파싱·Playwright·품질 판단·검토·materialization까지 통과한 제품 시험은 아니다. 이 차이를 검증 범위에 포함한다.

## 2. 현재 연결과 필요한 변경

| 위치 | 현재 코드 사실 | 필요한 연결 |
|---|---|---|
| iOS `StartSeasonImportExtractionUseCase` / 요청 Repository | discovery ID/generation/hash와 후보 IDs 전달, requestID 없음 | 사용자 행동별 안정적인 requestID와 접수 영수증 |
| Functions `requestSeasonCandidateImportJobs` | 최대80후보, job 생성 동시10, 부분 성공 응답 | 묶음 준비가 끝난 뒤에만 실행 가능 상태 공개 |
| `createSeasonImportJobFromSeed` | 활성 시즌 중복 조회와 일부 metadata 보강, 기존 자산 재시도 경로도 호출 | 기존 job 참조와 새 실행 대상을 구분하고 소유 묶음 중복 금지 |
| `onSeasonImportQueued` / task 생성 | queued 시즌마다 즉시 task, payload maxAttempts3, dispatchDeadline 생략 | 새 묶음 job은 기존 trigger로 직접 실행하지 않음 |
| Worker `/tasks/import-job`, `/wake` | 시즌별 claim 또는 순차 scan 실행 | 모두 동일한 묶음 실행권을 거쳐야 함 |
| `claimJob` / `refreshLease` | 시즌별5분 lease/90초 갱신, claim마다 attemptCount 증가; 갱신 owner 확인 뒤 별도 update | 묶음 owner/epoch와 조건부 갱신, 전달과 실제 실패 시도 분리 |
| `processor::runSyncTargets` | optional pipeline이 있으면 공유 슬롯 사용 가능 | 제품 서버에서 공용 runtime 생성·주입·정리 연결 |
| `syncSingleTarget` | 결정적 Storage 경로, Firestore 경로 쓰기에는 묶음 owner 조건 없음 | 늦은 저장 방지와 조건부 경로 공개 |
| 앱 `SeasonImportExtractionProgress` | processing/succeeded/failed, awaitingReview도 processing으로 계산 | 대기열 종료와 등록 성공을 구분한 검토 대기/복구 필요 표시 |

Cloud Tasks는 실행 순서와 중복 없는 실행을 보장하지 않으므로 task 도착 순서만으로 FIFO를 구현하지 않는다. [공식 동작](https://docs.cloud.google.com/tasks/docs/common-pitfalls).

## 3. 최소 구조 제안

**Firestore는 순서·실행권·진행 상태, Cloud Tasks는 깨우기, Worker는 현재 묶음의 처리**를 맡는다. 기존 Firebase/Cloud Run/TypeScript/Swift와 MVVM-C·Repository·UseCase·DI를 유지한다. 별도 Redis, 공정성 스케줄러, 자동 동시성 조절, 이미지 예약 시스템을 추가하지 않는다.

한 묶음을 한 Worker 요청 안에서 실행하는 방식을 사용자가 확정했다. 최대6시즌이 하나의 runtime을 공유하므로 실험한1CPU/2GiB의 제한과 직접 대응한다. 긴 묶음은 같은 차례를 유지한 채 진행 상태로 이어 실행한다. 시즌별 HTTP 유지 방식은 여러 인스턴스 사이의 단계 슬롯·128MiB 예산 공유가 추가로 필요하므로 선택하지 않았다. **구조 확정과 제품 구현 승인은 구분한다.**

범위는 프로젝트 내 이미지 import와 시즌 목록 탐색 요청이다. 사용자 후속 결정으로 두 종류를 같은 접수 순서에 넣는다. Development와 Production은 각각 독립된 순서를 가진다. 브랜드별 별도 실행권만 두면 서로 다른 브랜드가 동시에 실행될 수 있으므로 전역 coordinator 한 곳에서 현재 묶음을 지정한다. 이는 전체 Cloud Run 서비스/다른 기능이1인스턴스만 사용한다는 뜻이 아니다.

### 데이터 제안 — 새 최상위 컬렉션은 두 종류를 우선 검토

| 경로 후보 | 책임·필드 |
|---|---|
| `lookbookImportQueue/main` | `nextSequence`, `headBatchID`, `ownerToken`, `epoch`, `leaseUntil`, `heartbeatAt`, `drained`, `recoveryRequired` |
| `lookbookImportBatches/{batchID}` | 요청 영수증+선택 목록+순서+전달 의도를 함께 저장. `requestedBy`, `requestID`, `payloadDigest`, `brandID`, `sequence`, `kind`, `items`, `state`, `createdAt`, `completedAt`, `dispatchGeneration`, `dispatchState`, `nextEligibleAt`. 목록 탐색 kind는 기존 discovery job 한 개를 참조 |
| 기존 `brands/{brandID}/importJobs/{jobID}` | 현재 처리 상태/검토 이력 유지, `batchID`, `executionID`, `queueContractVersion`, `attemptNumber`, `checkpoint`, `queueStatus` 등의 필드 연결 후보 |
| 기존 job의 실행 이력 하위 문서 | `executionID`, 이전 실행 참조, 실제 시도 시작/결과/오류/종료 증거. 수동 재시도 때 이전 기록을 덮어쓰지 않음 |

별도 영수증 collection/outbox collection은 우선 만들지 않고 batch 문서에 합친다. 필드 크기·index·transaction 비용 확인 후 최종 이름/스키마를 확정한다. 최대80개 선택과 예상 job 참조가 Firestore 문서/transaction 제약에 맞는지 검증하며, 실측18시즌을 근거로80시즌 처리까지 검증됐다고 하지 않는다.

queue/batch 원본은 서버 전용으로 두는 안을 추천한다. 앱에는 자신의 권한으로 볼 수 있는 job 상태와 접수 영수증만 제공해 다른 브랜드의 대기 요청 정보가 새로 노출되지 않게 한다. 기존 브랜드 권한·검토 권한·OIDC/SSRF 검사를 유지한다.

## 4. 접수·멱등성·순번

1. 기존 인증/브랜드 권한과 discovery snapshot을 검증한다. candidate 순서는 요청 순서로 보존하며 URL 중복은 기존 규칙대로 정리한다.
2. `(uid, requestID)`로 결정되는 batch 영수증을 transaction에서 찾거나 생성하고, 서버 `sequence`를 부여한다. FIFO 기준은 이 서버 접수 transaction의 확정 순서다. 앱 탭 시각이나 HTTP 시작 시각을 전체 기기의 절대 순서로 보장하지 않는다.
3. 같은 ID·같은 payload는 기존 접수 결과를 반환한다. 같은 ID·다른 payload는 충돌 오류다. 비교 digest에는 순서 있는 후보 목록·brand/discovery identity·작업 종류·검토 snapshot이 포함된다.
4. batch를 `preparing`으로 저장한 후 선택 항목별 job 생성/참조 결과를 기록한다. 새 job은 생성 transaction부터 batch에 귀속하고 기존 per-job trigger가 무거운 작업을 시작하지 못하도록 한다. 맨 앞 `preparing`을 뒤 요청이 추월하지 않는다.
5. 기존 부분 성공 응답 계약을 유지하는 안을 추천한다. 항목별 결과가 모두 확정되면 성공한 **새 실행 대상만** `queued`로 공개한다. 유효 대상0개 또는 기존 job 참조만 있으면 처리 슬롯 없이 `released` 영수증으로 종료한다.
6. 기존 활성 job은 소유 batch를 옮기지 않는다. 새 batch가 기존 job 종료를 자기 실행 조건으로 기다리는 구조를 만들지 않는다. 동일 시즌을 중복으로 실행하거나 순환 대기를 만들지 않기 위함이다.
7. 접수 중 Functions가 종료되면 영수증과 항목별 진행 상태로 준비를 회수한다. 저장 성공 후 응답 유실에도 같은 ID를 재사용한다. 준비 복구는 최초 포함 총5회로 사용자 확정했으며 시즌 실행5회와 별도다. 종료·쓰기 결과가 불명확하면 준비 실패를 임의 확정하지 않고 복구 확인 상태로 둔다.

requestID는 iOS UseCase/Repository 경계에서 생성·재사용하고 View에서 Firebase를 직접 생성하지 않는다. 응답 유실 후 사용자가 같은 행동을 재전송하는 동안 유지해야 한다. 앱 재시작까지 pending ID를 GRDB에 보존하는 방향은 사용자 확정이다. 배포 전 최신 계약으로 통일하며 requestID 없는 앱을 위한 호환 경로는 만들지 않는다. 임의 새 ID 발급만으로 앱 재시작 멱등성을 보장한다고 하지 않는다. 세부 데이터/API는 §12·15를 따른다.

## 5. 전달·정상 처리·정리

batch에 전달 의도(`pending`, generation, 예정 시각)를 먼저 영속화한다. trigger가 결정적인 이름의 task를 만들고, 전송 실패/응답 유실은 같은 의도를 재확인한다. Firestore 반영과 Cloud Tasks 생성이 하나의 transaction이라고 가정하지 않는다. 정기 복구 담당자는 누락된 전달 의도만 회수하고 임의의 다른 브랜드를 시작하지 않는다. 복구 담당자의 주기·읽기 비용은 최종 배포안에서 산정한다.

Worker route 후보는 `/tasks/import-batch`, payload 후보는 `{batchID, dispatchGeneration, queueContractVersion}`다. 클라이언트가 URL 목록·재시도 횟수·동시성 한도를 주입할 수 없게 한다. 서버에 저장된 승인 입력을 읽는다. 같은 task가 중복 전달돼도 실행권 취득 전 HTML/이미지 요청·변환·업로드를 시작하지 않는다.

coordinator/head/batch를 transaction으로 확인하고 현재 owner/epoch를 부여한다. 다른 묶음 또는 이미 실행 중인 owner의 task는 중복 실행하지 않는다. 거절된 전달은 시즌 실패 시도로 세지 않으며, 필요한 다음 깨우기가 영속적으로 보장된 경우에만 task를 확인 처리한다.

현재 묶음의 선택 순서대로 최대6시즌을 시작한다. 슬롯이 비면 같은 묶음의 다음 시즌을 시작한다. 공용 runtime은 다운로드4/변환1/업로드4, source store128MiB를 공유하고 각 시즌의 source scope는 분리한다. 다음 HTTP 실행·관리자 검토 대기를 넘는 원본 캐시는 없다.

모든 대상이 종료 상태가 되더라도 다음 묶음은 즉시 시작하지 않는다. `draining`에서 실행 중 Promise·네트워크/SDK 작업·변환·슬롯 대기·browser·scope/Buffer를 정리한다. `active=0`, 대기0, borrowed/retained0, 마지막 상태 반영 확인 후 owner/epoch 조건 transaction으로 현재 차례를 `released`하고 다음 전달 의도를 남긴다. 단순 status 문자열만으로 정리 완료를 추정하지 않는다.

### 묶음 상태

| 상태 | 의미·허용 전이 |
|---|---|
| preparing | 접수 항목 결과 고정 중 → queued 또는 실행 대상 없는 released |
| queued | 자기 차례 대기 → active |
| active | 현재 묶음 실행 → draining |
| draining | 작업·저장 정리 → retryWaiting / queued(정상 이어 실행) / released / recoveryRequired |
| retryWaiting | retryable 실패를 원장에 기록한 직후 같은 실행 안에서 즉시 다음 시도. 별도 backoff timer 없음. |
| recoveryRequired | 이전 실행 종료/저장 확정 불명확; 자동 다음 차례 금지 |
| released | 차례 종료. 전체 성공/검토 대기/부분 실패 등 결과 요약을 별도 보존 |

## 6. 재시도·검토·긴 작업

- 시즌 실행 예산은 Cloud Tasks retry header 대신 서버에 기록한 실제 실행 이력으로 관리한다. 최초1, 재시도 가능한 실패 후 즉시 다음 실제 시도 시작 때 증가, 최초 포함 총5회를 넘지 않는다. 사용자 확정에 따라 자동 재시도 대기시간은 두지 않는다.
- 중복 task, claim 거절, 네트워크 응답 유실 후 완료 영수증 재조회는 시도 횟수를 늘리지 않는다. 정상 checkpoint 재개도 새 실패 시도가 아니다. crash를 정상 이어 실행으로 처리해 무한 재시도하지 않는다.
- 자동 재시도는 해당 season item 안에서 즉시 반복하고 같은 묶음의 실행권을 유지한다. `retryWaiting` 원장 값은 다음 시도 시작 전 아주 짧은 checkpoint 상태이며 지연 timer를 의미하지 않는다. 요청이 중단돼 다음 HTTP 실행이 필요한 상황은 자동 재시도와 별도인 전달/복구 경로에서 다룬다.
- 검토 대기에 들어간 시즌은 해당 차례에서 종료다. 승인 시 새 batch를 뒤에 넣고 같은 execution의 승인 snapshot 저장 단계만 이어간다. 승인 자체나 정상 재개만으로 실패 횟수를 증가시키지 않으며 자동 실패 이력은 보존한다.
- 수동 재시도/수정 후 재추출/자산 재시도는 새 execution과 새 총5회 예산으로 뒤에 접수한다. 기존 issue 검증·관리자 권한·재시도 가능 버전 조건은 유지한다.
- 요청은 최대80시즌이므로 한 HTTP에서 끝난다고 가정하지 않는다. 시즌/이미지 경계의 checkpoint, 이미 공개된 이미지 skip, 부분 업로드 재조정이 필요하다. 긴 단일 시즌도 이어 실행 가능해야 한다. 완료된 경로 존재만으로 서로 다른 실행의 결과를 동일하다고 간주하지 않는다.

현재 task의 dispatchDeadline은 생략돼 HTTP task 기본10분이 적용될 수 있고, 이전에 확인한 Cloud Run timeout은900초다. 두 제한은 독립적이다. [Cloud Tasks 계약](https://docs.cloud.google.com/tasks/docs/reference/rest/v2/projects.locations.queues.tasks). 사용자가 아래12/14/15분을 제품 초기 검증 기준으로 확정했다. 실험의840초 신규 투입 중단과 다른 시간표이며, HTML/브라우저/이미지별 취소·정리 검증 및 향후 배포 시 실제 설정 대조가 필요하다. 이번에는 클라우드 설정을 바꾸거나 재조회하지 않았다.

### 긴 요청 시간표 — 초기 기준 확정·구현 검증 전

사용자가 **12분 신규 투입 종료 / 14분 정리·영속화·응답 목표 / 외부15분**을 확정했다. 제품 동작 검증을 위한 초기값이며 성능 최적값이나120초 정리 보장이 아니다.15분은 한 번의 HTTP 제한이며 묶음 전체 처리 시간 제한이 아니다. 정상 분할을 이유로 시즌을 실패 처리하거나 다음 브랜드로 넘어가지 않는다.

| 요청 경과 | 동작 | 다음 실행 허용 조건 |
|---|---|---|
| 시작 전 | 입력/실행권/메모리 측정 가능 여부 확인. 시간은 실행권 취득 이후가 아닌 요청 수신부터 단조 시계로 계산 | 준비 시간이 길어져도 뒤에 별도12분을 더 주지 않음 |
| 0~720초 미만 | 현재 묶음의 시즌6·공유4/1/4 실행 | 메모리·실행권 이상이 없을 때만 새 투입 |
| 720초 | 새 시즌·이미지·재시도·브라우저 시작 중지. 시작하지 않은 대기 작업은 checkpoint상 미완료로 남김 | 이미 시작한 이미지의 변환/업로드/공개는 정리를 위해 진행 가능 |
| 720~840초 | 실행 중 작업을 끝내고 브라우저·Buffer·슬롯·heartbeat 정리. 가능하면 즉시 checkpoint와 다음 전달 의도를 저장하고 응답 | 모든 잔여 작업0, 현재 owner 조건으로 중간 종료 기록 확정.840초까지 일부러 기다리지 않음 |
| 840초 목표 초과 | 정리 또는 마지막 DB 반영을 확인하지 못했으면 recoveryRequired. 추가 공개/투입 차단 후 진행 중 작업 정리 지속 | 정리 완료를 꾸며내거나 다음 task를 실행 가능 상태로 만들지 않음 |
| 900초 | Cloud Tasks dispatchDeadline 명시900s, Cloud Run timeout900초를 배포 때 대조 | 외부 timeout을 작업 종료 증거로 사용하지 않음 |

Cloud Tasks의 타이머에는 전달 과정도 포함되므로 Worker 시계와 완전히 같지 않다. 마지막60초는 전달·상태 반영·응답 여유로 둔 제안이다. 외부 deadline이나 연결 종료가 먼저 관찰되면 신규 투입을 즉시 중단한다. task 생성 코드·배포 설정·실제 revision 세 값의 불일치는 배포 검증 실패로 다룬다. 플랫폼 timeout과 Worker 작업 생존은 별개다. [Cloud Run 공식 설명](https://docs.cloud.google.com/run/docs/configuring/request-timeout).

현재 코드의15초 HTML/20초 이미지/20초 browser navigation 제한만으로 이 시간표가 충족됐다고 판정하지 않는다. 이미지 다운로드 내부3회 재시도, URL 검증, browser launch/close, Sharp 변환, Storage SDK 내부 재시도, Firestore transaction 대기를 함께 확인해야 한다. 개별 호출 제한은 남은 요청 시간도 넘지 않도록 연결하며, 취소할 수 없는 작업은 완료 확인 전 활성 수에서 빼지 않는다. `Promise.race`의 timeout만으로 SDK/Sharp가 종료됐다고 취급하지 않는다.

정상 이어 실행의 다음 전달 의도는 **정리 완료와 같은 transaction에서만 실행 가능하게 만든다.** timer가 먼저 새 task를 내보내지 않는다. 새 요청이 다른 인스턴스로 간다는 보장은 없으므로 재개 전 자원 검사를 다시 한다. 정상 분할은 같은 execution/attempt를 이어가며, 정상 실행2구간 연속으로 image checkpoint 또는 단계 전환이 전혀 전진하지 않으면 `noProgress` 복구 확인으로 전환하도록 사용자가 확정했다. heartbeat/updatedAt 변화와 의도적인 retryWaiting은 진행으로 세지 않는다.

### 중간 저장·재개 계약 제안

재개 기준은 메모리 Buffer나 처리한 이미지 개수가 아니라 **영속화한 이미지별 완료 기록**이다. 실패한 앞 이미지와 성공한 뒤 이미지가 섞일 수 있으므로 단순한 마지막 index만 저장하지 않는다.

| 식별자 | 수명·역할 |
|---|---|
| batchID | 접수 순번을 가진 닫힌 요청. 검토 승인은 새 batch지만 승인 대상 execution을 이어감 |
| executionID | 시즌 추출/저장 실행 이력. 정상 이어 실행·자동 재시도에서는 유지, 명시적 수동 재시도에서는 새 값 |
| epoch / ownerToken | Worker가 실행권을 얻을 때 부여. 정상 이어 실행도 새 실행권을 사용하고 이전 값의 공개·상태 쓰기를 거절 |
| assetKey | 확정된 snapshot·대상 post/media 위치·원본 후보·변환 정책 버전을 식별. 입력이 바뀐 이미지를 완료로 오인하지 않음 |
| writeID | 실제 산출물 생성 단위. 같은 execution의 재시도도 이전 쓰기를 덮어쓰지 않도록 별도 경로 사용 |

저장 기록은 기존 job 실행 이력 아래 이미지별 하위 문서로 두는 안을 제안한다. batch 한 문서에 모든 이미지 경로·결과를 누적하지 않는다. 필드 후보는 assetKey/snapshot identity, writeID, 두 객체 경로와 확인된 generation, 상태, publishedAt, supersededAt, cleanup 상태다. 실제 문서 이름과 최소 필드는 구현 계획에서 확정한다.

1. 파싱·중복 확인·검토 판단 결과를 snapshot으로 고정하고, materialization에서 만든 시즌/포스트와 이미지 대상 매핑을 기록한다. 원본 Buffer는 이 기록에 저장하지 않는다.
2. 이미지의 두 JPEG 업로드가 확인되면 현재 queue owner/epoch·job execution·승인 snapshot·대상 존재/삭제 상태를 transaction으로 재확인한다.
3. 같은 transaction에서 앱 참조 경로와 해당 이미지의 공개 완료 기록을 갱신한다. 하나만 성공한 업로드를 완료로 기록하지 않는다. 기존 이미지를 교체한다면 새 쌍의 공개까지 이전 참조를 유지한다.
4. 정상 시간 분할에서는 새 시즌/이미지 투입을 멈추고 이미 시작한 작업을 정리한 뒤 중간 종료 기록과 다음 전달 의도를 저장한다. 같은 batch가 head를 유지하므로 다른 브랜드가 사이에 들어오지 않는다.
5. 다음 Worker는 완료 기록과 현재 대상 참조를 대조한다. 일치한 이미지는 skip하고 남은 대상부터 진행한다. 같은 HTTP 안의 source Buffer만 재사용하므로 다음 실행에서는 필요한 원본을 다시 다운로드한다.
6. 저장 응답 유실 시 먼저 완료 기록을 재조회한다. Storage만 성공한 경우 등록된 writeID와 객체 증거를 확인해 재조정하고, Firestore 완료가 없다는 이유만으로 전체 시즌을 처음부터 다시 만들지 않는다.

예: 한 시즌20개 중1~7번 공개 완료,8번 썸네일만 업로드,9번 공개 완료 상태에서 정상 분할했다면 다음 실행은1~7·9번을 건너뛴다.8번은 미완료 산출물 확인 후 재개하고10~20번은 계속 처리한다. 이전 epoch가 늦게 완료돼도 현재 앱 참조를 갱신할 수 없다. 정상 분할 자체는5회 실패 예산을 소모하지 않지만 실제 실패를 분할로 숨기지 않는다.

## 7. 장애·늦은 쓰기·복구

Cloud Run의504/요청 timeout은 컨테이너가 종료됐다는 증거가 아니다. [공식 timeout 동작](https://docs.cloud.google.com/run/docs/configuring/request-timeout). lease 만료도 실제 작업 종료를 증명하지 않는다.

heartbeat는 owner/epoch 조건 transaction으로 갱신한다. owner 상실·갱신 실패·취소를 알면 신규 투입을 멈추고 실행 중 작업을 정리한다. 취소 신호를 전달했다고 업로드/Sharp 작업이 끝났다고 기록하지 않는다. heartbeat 겹침과 해제 뒤 늦은 heartbeat의 실행권 부활도 막아야 한다.

정리 확인이 불가능하면 사용자 확정대로 `recoveryRequired`에서 차례를 유지한다. 정상 시간 분할의 자동 재개에는 **저장된 정상 종료/checkpoint 증거가 필요**하다. 메모리/관찰 문제로 중단된 경우에는 정리 증거가 있어도 자동으로 차단을 해제하지 않는 정책을 사용자가 확정했다. OOM·프로세스 소실·네트워크 분할처럼 종료 증거가 없는 경우의 운영 확인 절차는 아래 제안을 따른다. 수동 확인 버튼만 누르면 안전하다고 가정하지 않는다.

### 메모리 부족과 복구 — 초기 기준·복구 대기 정책 확정

사용자가 실험의 안전 기준을 **제품 초기 검증 기준**으로 사용하고, 중단 후 자동 반복 실행 없이 복구 확인을 기다리는 방식을 확정했다. CPU 사용률만으로 작업을 실패시키거나 슬롯 수를 자동 조절하지 않는다. CPU 사용·throttling·이벤트 루프 지연은 관찰 지표로 남긴다.1CPU/2GiB와 고정4/1/4·128MiB 설정을 유지한 채 검증하며, 메모리 부족 시 자원을 자동 증설하지 않는다.

- 컨테이너 전체 cgroup 사용량/한도를100ms마다 측정한다.85% 이상인 표본이1초 이상 이어지면 신규 투입을 중단한다. 표본 간 실제 연속 사용량을 완벽하게 알 수 있다는 뜻은 아니다.
- 유효 표본 간격500ms 초과, 읽기 실패, 한도 변경 등은 메모리 사용량0으로 대체하지 않고 `monitorUnavailable`로 중단한다. 단순 메모리 부족과 관찰 불가 원인을 분리한다.
- 작은 cgroup 파일만 동기로 읽는 기존 검증 방식을 검토한다. 제품 HTML/Chromium이 들어간 부하에서 측정 지연·CPU 부하도 다시 검증한다. 컨테이너 총량에는 이미지 처리 외 작업도 영향을 주므로 원인을 특정 시즌으로 단정하지 않는다.
- 시작 시 이미85% 이상이면 새 이미지 작업을 시작하지 않고 복구 확인 대상으로 삼는 초기안이다. 시작 중단은 아직 실행하지 않은 시즌의 실패 횟수를 늘리지 않는다.
- **128MiB는 원본 재사용 저장소의 한도이지 Worker 전체 메모리 한도가 아니다.** Buffer 참조가0이어도 프로세스/네이티브 할당/브라우저의 실제 사용량이 바로 낮아졌다고 가정하지 않는다.

| 상황 | 서버 처리 제안 | 차례·시도 예산 |
|---|---|---|
| 정상 시간 분할, 정리·checkpoint 확인 | 다음 구간 자동 전달 | 같은 차례·같은 시도 |
| 일시적 다운로드/업로드 실패, 작업 종료 확인 | 기존 총5회 안에서 자동 재시도; 완료 이미지 유지 | 같은 차례. 재시도 대기 중 다른 준비된 형제 시즌은 진행 가능 |
| 메모리/관찰 기준 중단, 정리 확인 | `recoveryRequired`, reason=memoryPressure/monitorUnavailable, termination=drained | head 유지. 다음 브랜드도 대기. 자동5회 반복이나 새로운 인스턴스라고 가정한 재요청 금지 |
| deadline/응답 유실/heartbeat 소실, 종료 미확인 | `recoveryRequired`, termination=unknown. 직접 기록할 수 없으면 coordinator 복구 담당자가 표시 | 시간만 지나도 인계 금지. 기존 소유권을 완료로 바꾸지 않음 |
| OOM·프로세스 소실 | 확인된 플랫폼 증거와 실행 identity를 대조하고 산출물 재조정 필요 | OOM 추측만으로 종료 확인 처리하지 않음 |

Cloud Run은 메모리 한도를 넘은 인스턴스를 종료한다. 따라서85% guard는 그 전에 정리할 기회를 얻는 장치이며, 급격한 증가로 OOM이 먼저 발생하는 상황까지 막는 보장은 아니다. [공식 메모리 동작](https://docs.cloud.google.com/run/docs/configuring/services/memory-limits). 반면 timeout/lease 만료/잠시 사라진 로그는 종료 증거가 아니다.

복구 시 확인할 기록은 batch/execution/epoch, Worker boot 식별자·revision·확인 가능한 platform instance identity, 중단 사유/시각, 마지막 checkpoint, stage별 active/queued, browser/Buffer 잔여, 마지막 공개 transaction과 정리 영수증이다. 시즌 성공 기록을 일괄 실패로 덮어쓰지 않는다. 미시작 시즌과 성공 시즌은 중단된 시즌 시도와 구분한다.

복구 절차 제안:

1. 신규 실행권 발급을 차단한 상태에서 해당 epoch의 정상 정리 영수증을 확인한다. 없으면 정확히 해당 실행이 종료됐음을 확인할 수 있는 플랫폼 증거·운영 절차가 필요하다. 트래픽0%, 새 revision 배포, 새 요청의 응답 성공, 로그 부재만으로는 부족하다.
2. 미완료 산출물과 현재 앱 참조를 대조한다. 종료 확인은 DB/Storage 결과 확인을 대신하지 않는다. 확인 전24시간 정리도 적용하지 않는다.
3. 메모리/관찰 문제의 원인 조치와 재개 대상 환경의 측정 정상 여부를 확인한 뒤 권한 있는 서버 작업으로 복구 결정을 기록한다. 일반 앱의 ‘다시 시도’가 전역 차단을 해제하지 못하게 한다.
4. 원래 차례의 복구 재개는 기존 총5회 이력을 유지한다. 정상 완료가 입증된 시도는 재수행하지 않고, 실행 도중 중단된 시도를 다시 시작하면 남은 예산을 사용한다. 수동 재시도의 새 execution·새5회·맨 뒤 접수와 구분한다.
5. 종료 증거를 얻을 수 없으면 차단을 유지한다. 이전 Worker의 HTTP 이후 살아 있는 작업도 정리되었는지 Development 장애 주입으로 확인하기 전에는 운영 복구가 완성됐다고 하지 않는다.

이 방식은 중단 시 뒤 브랜드도 기다리는 가용성 비용이 있다. 사용자에게 대안인 메모리 회복 후 자동 재개의 장단점을 제시했고 복구 확인 방식을 선택받았다. Q4에서 기본 비활성 `/recovery/inspect`·`/recovery/resume`와 운영자 CLI를 로컬 구현했다. 실제 운영 IAM과 종료 증거 획득 가능성은 Development에서 검증해야 하며 로컬 fake evidence 성공으로 대체하지 않는다. [Q4 결과](product-queue-q4-results.md).

DB 상태/경로 공개는 owner·epoch·execution 조건을 재확인해야 한다. 이 조건은 이미 보낸 Storage 쓰기를 취소하지 못하므로 **사용자가 선택한 실행별 새 경로+조건부 공개**로 이전 실행의 덮어쓰기를 피한다. Storage와 Firestore를 하나의 원자적 작업으로 취급하지 않는다.

### 실행별 저장 경로 제안과 기존 코드 호환

- 본문: `brands/{brandID}/seasons/{seasonID}/posts/{postID}/imports/{executionID}/{epoch}/{assetKey}/{writeID}/{thumb|detail}.jpg`
- 커버: `brands/{brandID}/seasons/{seasonID}/imports/{executionID}/{epoch}/cover/{writeID}/cover.jpg`, 같은 폴더의 `cover_thumb.jpg`
- 기존 공개 경로를 일괄 이동하지 않는다. 새로 만드는 산출물부터 이 계약을 적용하는 제안이다. 이미 참조 중인 이전 epoch 파일은 정상 재개만으로 교체하지 않는다.

현재 Worker의 경로 helper는 포스트별 `thumb.jpg/detail.jpg`, 시즌별 `cover.jpg/cover_thumb.jpg`를 사용한다(`processor.ts`). 현재 삭제 구현은 포스트/시즌/브랜드 prefix 단위로 파일을 삭제하므로 새 파일도 해당 대상의 하위에 둔다(`functions/src/lookbook/deletion/functions.ts::purgePostTarget/purgeSeasonTarget/purgeBrandTarget`). 별도 최상위 임시 버킷 경로로 빠져 기존 삭제에서 누락되지 않게 한다. **prefix 호환은 삭제와 실행의 경합 해결을 뜻하지 않는다.** 삭제된 대상에 늦은 업로드가 생기지 않도록 삭제 경로도 실행 중 작업 정리와 연결해야 한다.

iOS `Season.swift`의 coverThumbPath는 coverPath의 `.jpg`를 `_thumb.jpg`로 바꾸는 계산 속성이다. 새 커버 경로도 이 파일명 관계를 유지한다. 공개 시 앱의 coverPath와 이미지 완료 기록의 두 경로를 함께 기록하는 안이며, 앱이 별도 썸네일 필드를 읽는다고 가정하지 않는다. 본문은 mediaIndex뿐 아니라 고정된 assetKey/snapshot을 확인하고 media 배열의 동시 갱신 손실도 transaction 검증 대상으로 삼는다.

여기서 ‘공개’는 **앱이 사용하는 Firestore 참조에 연결**한다는 뜻이다. 현재 `storage.rules`의 브랜드 하위 객체 get은 읽기 가능한 계정에 허용되므로, 미참조 파일이 비공개 접근 제어를 받는다는 뜻이 아니다. 이번 설계에서 새로운 비공개 미디어 기능을 추가하거나 기존 읽기 권한을 완화하지 않는다. 실행별 경로의 클라이언트 쓰기 허용 여부는 기존 브랜드 쓰기 권한과 함께 규칙 검토 대상으로 남긴다.

### Q3 구현 추가 — 활성 업로드와 삭제 경합 차단

Queue-owned `writes/{writeID}` 문서는 업로드 전에 `status=uploading`, `brandID`, `targetSeasonPath`, `targetPath`를 기록한다. 기존 upload/publication transaction이 이를 `published`, `unpublished`, `failed`로 끝낸다. post·season·brand purge는 각각 targetPath·targetSeasonPath·brandID와 uploading을 복합 인덱스로 조회하고 하나라도 있으면 Storage/Firestore 삭제를 시작하지 않는다. soft-delete가 먼저 기록되어 새 `beginAssetWrite`를 막고, 이전 transaction과 순서는 같은 brand/season/post 문서 경쟁으로 fence한다. 조회 실패도 purge 실패로 처리하므로 fail closed다. 인덱스 3개는 local `firestore.indexes.json`에 추가했으며 실제 배포는 하지 않았다. Q4는 정확한 project/service/revision/epoch 종료 증거를 요구하는 recovery inspect/resume를 추가했으며 증거가 없거나 IAM이 준비되지 않으면 uploading 원장과 FIFO 차단을 유지한다.

이 fence는 queue-owned write path에만 적용된다. 기존 direct Worker route는 execution ledger를 만들지 않아 cutover 전에는 동일 보호를 우회할 수 있다. Q6에서 해당 경로를 차단하거나 동등한 실행권·원장·조건부 공개로 이전한 뒤 제품 FIFO를 활성화한다.

### 미참조 파일 정리 — 24시간 정책 확정·로컬 구현

사용자가 **실행 종료 확인과 참조 해제 중 늦은 시점부터24시간 보관 후 정리**를 확정했다. 미공개 산출물은 정상 종료가 확인된 시점부터, 교체된 산출물은 참조가 해제되고 관련 실행이 정리된 시점부터 계산한다.24시간은 비용·복구 여유를 고려해 선택한 정책값이며 실측 최적값이 아니다. 기존 추출 증거7일 정책은 이미지 버전 보관 정책과 별개다. 보관 시간만 지난 활성/복구 중 파일은 삭제하지 않는다.

정리 담당자는 등록된 산출물 기록을 기준으로 아래 조건을 검사한다. schedule은 매시간 실행되며 회당 최대5 page/500 object operations 또는120초 동안만 새 객체를 처리한다. 실제 Storage 접근/삭제 검증은 Development에 남는다.

1. 관련 실행 종료가 확인됐고 recoveryRequired/진행 중/재개에 필요한 산출물이 아니다.
2. 앱의 현재 참조가 아니며 보관 시간이 지났다. terminal write ledger와 현재 실행/head 보호를 확인하고, 대상 문서를 각 객체 삭제 직전에 다시 읽어 참조가 생기면 정리 시도를 미룬다.
3. 기록한 객체 generation을 대상으로 삭제하고 variant별 결과를 남긴다. generation mismatch는 삭제하지 않고 보류하며, transient Storage 오류는 다음 hourly pass를 위해 재예약한다. 경로 전체를 무조건 지우지 않는다.

업로드 전에 writeID/경로 의도를 기록해 응답 유실 파일도 추적한다. 종료 불명확한 실행은 보관 기간만으로 정리·인계하지 않는다. 일반 미참조 버전 정리가 기존 브랜드/시즌/포스트 삭제 정책의 보관 시간을 임의로 연장하지 않도록 구분한다. 정리 주기는 매시간이며 정확한 generation만 대상으로 한다. Q4 로컬 정리는 합성 object/emulator로만 검사했으므로 실제 Storage generation/IAM 동작은 Development 확인 전 미검증이다. **Q4에서 실제 원격 삭제나 정리 배포를 실행하지 않았다.**

## 8. 우회 경로·전환 범위

신규 선택 요청뿐 아니라 `requestSeasonImport`, `requestSeasonAssetRetry`, `reviewLookbookExtraction`, `retryLookbookExtractionAfterFix`, `applyLookbookSeasonRepair`, asset failure retry task 및 `/wake`도 실행권을 우회하지 않아야 한다. 새로운 import job을 만드는 경로와 같은 job을 queued로 돌리는 경로 모두 연결 대상으로 분류한다. 사용자 확정에 따라 시즌 discovery도 같은 순서를 따른다. 저장 없는 진단/보수 미리보기도 네트워크·브라우저를 쓰면 별도 작업 종류로 대기열을 거쳐 자원 제한을 우회하지 않는 계약 제안이다. 이미 저장된 상태 조회는 차례를 기다리지 않는다.

앱은 배포 전이므로 사용자 지시대로 최신 계약만 구현한다. 전환은 기존 Development 활성 import/task 정리 확인→앱/Functions/Worker의 동일 계약 배포 검증→신규 접수 경로 사용 순서다. 구형 앱용 adapter·임시 ID·업데이트 안내 화면은 제외한다. 다만 남아 있는 task나 이전 revision이 기존 route로 실행하면 새 전역 FIFO가 깨지므로 서버 실행 우회는 반드시 막는다. feature flag를 끄는 것만으로 새 batch를 구형 작업으로 재전송하지 않는다. 롤백은 신규 접수 중지·현재 작업 정리·영수증 보존을 포함한다. 기존 task/데이터 삭제·운영 배포·대량 마이그레이션 승인은 이번 범위에 없다.

## 9. iOS 흐름·권한·표시

기존 선택 화면→UseCase→Repository→Functions 흐름을 유지한다. 서버의 선택 목록·처리 결과를 신뢰하고 requestID를 한 사용자 행동의 재전송 동안 유지한다. `SeasonImportBatchRequestResult`와 mapper를 batch/항목별 식별자를 포함하는 최신 응답 계약으로 함께 변경한다. 구버전 응답 fallback은 새로 만들지 않는다. 상태 조회 callable과 권한 필터는 §12 제안을 따른다.

사용자가 기존 선택 진행/관리 화면에 ‘대기 / 처리 / 자동 재시도 대기 / 검토 필요 / 실패 / 복구 확인 필요’를 구분하고 결과·복구 안내로 전환하는 방식을 확정했다. queue released와 시즌 등록 성공은 별도다. 기존 `completedCount`에 검토 대기를 무조건 성공으로 합치거나 영구 processing으로 남기지 않도록 아래 집계·표시를 제안한다. 대기 순번/예상 완료 시각/새 관리자 화면은 자동 추가하지 않는다.

Repository protocol·UseCase·DTO/mapper·진행 모델이 주요 경계이며 LookbookContainer/기존 CreateBrandFlow 조립부를 함께 확인해야 한다. Coordinator 경로 변경은 현재 목표가 아니다. 기존 소유자/관리자 권한과 검토 snapshot 검증을 유지하며 클라이언트가 전역 coordinator를 수정할 수 없게 한다. 결제·UGC 노출·외부 링크 흐름을 새로 추가하지 않는다.

### 기존 화면에 적용할 상태 계약 — 방향 확정·세부 매핑 제안

현재 `StartSeasonImportExtractionUseCase`는 awaitingReview를 processing으로 분류하고 candidate별 최신 updatedAt job을 선택한다. `CreateBrandCandidateSelectionView`는800ms 조회와 completedCount로 완료 화면을 결정한다. 새 계약에서는 접수 영수증의 **batch/item/job/execution 식별자**로 조회해야 뒤의 수동 재시도가 앞 요청의 결과로 섞이지 않는다. 기존 job을 참조한 중복 접수도 그 job의 실제 상태를 표시한다. 자기 batch가 실행 대상 없이 released됐다는 이유로 중복 참조 job까지 성공/종료했다고 하지 않는다.

| 서버 의미 | 시즌별 표시 제안 | 화면/행동 |
|---|---|---|
| preparing / queued | 접수 중 / 대기 중 | 접수 중 중복 전송 방지. 접수 확인 후 기존 ‘현황에서 계속 확인’으로 닫기 가능 |
| active / 정상 checkpoint 이어 실행 / draining | 처리 중 | 필요하면 ‘진행 내용을 저장하고 있습니다’ 보조 문구. 분할마다 완료 표시하지 않음 |
| retryWaiting | 자동 재시도 대기 | 서버 상태로 계속 진행. 별도 수동 중복 요청 유도 금지 |
| succeeded | 등록 완료 | 저장이 확정된 성공 수에만 포함 |
| awaitingReview | 검토 필요 | 성공/실패와 구분. 기존 권한 있는 검토 흐름 사용 |
| failed / partialFailed / cancelled 또는 확정된 접수 실패 | 실패 / 일부 저장 실패 / 취소됨 / 접수 실패 | 결과 보존, 재시도 가능 여부는 서버 계약을 따름 |
| recoveryRequired | 복구 확인 필요 | 무한 spinner 종료, 이미 저장한 결과와 안내 표시. 미완료 전체를 성공 또는 최종 실패로 표시하지 않음 |
| 다른 head 복구로 자기 요청이 대기 | 처리 일시 중지 | 자기 요청의 대기 사유만 표시. 다른 브랜드 이름/요청 정보를 노출하지 않음 |
| 조회 실패 / 응답 유실·접수 확인 전 | 상태 확인 중 | 마지막 확인 상태 유지. 성공/실패 수를 임의로 바꾸지 않음 |

화면 종료 기준은 ‘모든 시즌 등록 성공’과 ‘현재 자동 처리가 더 진행되지 않는 상태’를 분리한다. 진행/자동 재시도 대상이 남아 있으면 진행 화면, 전부 성공·검토 대기·확정 실패/취소면 결과 화면이다. 복구 필요 상태는 차례가 종료되지 않았더라도 안내 화면으로 바꾸며 성공 완료 이벤트를 보내지 않는다. 사용자가 닫는 행위는 서버 취소나 다음 차례 허용이 아니다. 상태 조회 Task의 취소만으로 서버 작업을 취소하지 않는다.

집계는 후보별 상호 배타적인 결과로 한다. `total = 등록완료 + 검토필요 + 확정실패/취소 + 대기/처리/자동재시도 + 복구대기 + 상태미확인`으로 정의하고 ‘처리 결과가 나온 수’와 ‘등록 완료 수’를 별도 표시한다. 접수 실패 ID를 job 결과에 더해 두 번 세지 않는다. 예:6시즌 중3성공·2검토·1실패면 ‘3개 등록 완료,2개 검토 필요,1개 실패’이며 ‘6개 등록 완료’가 아니다. 복구 중1개가 남으면 해당1개를 별도로 표시한다.

사용자가 앱 재시작 시 저장한 요청 ID로 복원하는 방향을 확정했다. 구현 제안은 계정별 pending 요청 저장이다. 첫 전송 전에 requestID·brand/discovery/snapshot·순서 있는 candidate IDs·작업 종류를 로컬에 저장하고, 응답 후 batch 영수증과 항목별 identity를 연결한다. 저장 실패 시 멱등성을 보장한 것처럼 전송하지 않는다. 전송 응답 유실/앱 재시작은 같은 ID로 조회·재전송하고, 사용자가 새로운 선택/명시적 재시도를 하면 새 ID를 만든다. 계정 전환 시 다른 계정의 pending을 전송/표시하지 않으며 인증 토큰이나 이미지 Buffer를 여기에 저장하지 않는다. 기기 저장소 삭제 후까지 복원이 보장된다고 하지 않는다.

기존 선택 진행/관리 화면과 닫기 경로를 사용하며 새 관리자 복구 화면·대기 순번·완료 예상 시각은 추가하지 않는 안이다. 비활성 화면/앱 백그라운드에서800ms polling을 지속하지 않고, 재진입 시 서버 상태부터 조회한다. 복구 안내/종료 결과에서 빠른 polling을 계속할지는 별도 조회 정책 검토 대상으로 남긴다. 영수증 조회 API와 GRDB 연결은 §12·15를 따른다. 구버전 앱 호환은 범위에서 제외했다.

## 10. 검증 설계 — 아직 미구현·미실행

| ID 묶음 | 필수 검증 | 도구·완료 기준 |
|---|---|---|
| PQ01 접수 | 동일ID 동시호출/응답유실, 다른 payload 충돌, 새 선택·수동재시도 별도 ID | Functions unit+emulator, 중복 batch/실행0 |
| PQ02 준비 | 부분 성공, 준비 중 crash, 전부 중복, 서로 겹치는 시즌 요청 | emulator transaction/barrier, 고아 실행·추월·순환 대기0 |
| PQ03 전달 | DB성공/task실패, task성공/응답유실, 순서 역전·중복 전달 | fake Tasks+durable intent, 유실/중복 무거운 실행0 |
| PQ04 실행권 | 두 Worker 동시 claim, stale epoch, 늦은 heartbeat, 기존 route 호출 | 독립 호출+emulator, 전역 활성 batch 최대1 |
| PQ05 FIFO | A8 진행 중 B2/C~J/추가A 접수, 저장 지연·partial/review 종료 | fake clock/barrier, A 정리 전 다음 시작0·같은 묶음 남은 시즌 우선 |
| PQ06 자원 | 6시즌 공유4/1/4, 시즌별4,128MiB, 취소 대기·Buffer 반환 | Linux컨테이너, 설정/최고 동시성/종료0 잔여 확인 |
| PQ07 시도 | 최초포함5/6번째거절, 중복전달0증가, backoff·checkpoint·검토승인·수동새예산 | 지속 상태 재시작+fake clock, 이력/예산 일치 |
| PQ08 저장 | 두JPEG 중 하나 실패, DB실패, 업로드 응답 유실, stale write/repair 충돌, 완료한 비연속 이미지 재개, 공개와 정리 경합, 삭제 중 늦은 쓰기 | fake Storage/DB+emulator, 미공개/부분 결과 성공0·현재 참조 삭제0·완료 이미지 중복 처리0 |
| PQ09 장애 | deadline/lease/네트워크분할/종료불명확/OOM·브라우저 종료 | 별도 프로세스+컨테이너, recoveryRequired 및 다음 작업0 |
| PQ10 전환 | 잔여task/이전revision 실행 거절, 모든관리자 경로, discovery 간섭, 최신 앱·서버 계약, 전환/롤백 | 통합 검사+Development QA, 우회 없음·권한 유지. 구버전 앱 호환 테스트 제외 |
| PQ11 앱 | requestID 재사용·부분결과·검토/복구 상태, 재진입 | fake Repository/UseCase+실기기 QA, 화면 표시 사람이 확인 |

이번 세 항목의 필수 경계 시나리오를 기존 PQ에 추가한다. 아직 테스트 코드나 게이트에 연결한 상태는 아니다.

- PQ07/09:719.999초·720초·840초 경계, claim 준비 지연, 대기 슬롯에 남은 이미지, 정상 분할5회 이상에도 실패 예산 유지, 실제 실패를 분할로 숨기지 않음. fake monotonic clock/barrier로 새 투입0과 checkpoint/전달 순서를 검사한다.
- PQ08/09: 업로드/Sharp가 취소 신호 후에도 살아 있는 경우, 마지막 checkpoint DB 응답 유실, heartbeat 뒤늦은 성공, task중복·외부 timeout을 주입한다. 정리 미확인 시 다음 Worker의 이미지 네트워크 시작0을 검사한다.
- PQ06/09:85% 경계·1초 지속/짧은 초과·500ms 초과 공백·cgroup 읽기 실패·시작부터 고메모리·정리 후 높은 RSS·실제 OOM을 구분한다. memory reason/termination evidence 일치와 자동 재실행 여부는 확정 정책대로 검증한다.
- PQ09/10: 플랫폼 종료 증거와 잘못된 instance/epoch 증거를 대조하고, 새 revision만 생겼을 때 복구를 거절한다. 실제 종료 증거 획득·운영 복구는 Development에서 별도 검증하며 로컬 fake 성공으로 대체하지 않는다.
- PQ11:6시즌3성공/2검토/1실패, 전부 중복 접수지만 기존 job 진행 중, 앞 요청 뒤 수동 재시도, 접수 실패 중복 합산, 복구 중 화면 닫기, 응답 유실 직후 앱 재시작, 계정 전환, 조회 장애를 fake Repository로 검사한다. 실제 문구·화면 전환·백그라운드 복원은 실기기 QA로 확인한다.

기존 `verification/lookbook-import.json`, `functions.json`, `firestore.json`, `ios.json`을 확인했다. ios.json은 룩북을 선택하지 않으므로 전용 앱 검사 연결이 필요하다. 제품 큐 통합/emulator 항목과 보관/권한 검증은 §19의 PQ01~15를 구현 계획에서 필수 게이트로 연결한다. 기존316개 및 실험 게이트는 제품 분산 큐의 검증을 대신하지 않는다. 현 단계에서 새 PQ 테스트/게이트는 없으며 통과를 선언하지 않는다.

## 11. 설계 결정과 남은 검증 경계

FIFO·닫힌 묶음·재시도/검토 차례·종료 불명확 차단, 묶음 Worker, 실행별 경로·조건부 공개, 미참조24시간 정리,12/14/15분 초기 시간표, 메모리 중단 후 복구 확인, 앱 상태 구분·GRDB 재시작 복원, 최신 앱·서버 계약 통일, Chromium1개·이미지 처리 분리, 목록 탐색의 같은 FIFO 접수가 확정됐다. 구버전 앱 호환과 서비스 분리는 제외한다.

§12~19는 정확한 연결을 검토할 수 있는 기술 계약·검증 제안이다. 조회/정리 주기,24시간·30일·90일 기록 수명, 본인1인 조건부 복구까지 사용자 확정됐다. 다음은 이미 확정한 정책을 다시 선택하는 문제가 아니라 **세부 구현 계획에 명시하고 최종 검토할 대상**이다.

1. 데이터/API 필드·권한·항목별 preparation 복구 한도, 동시 중복 접수의 transaction/claim 검증.80시즌 최악 입력 크기와 index 목록을 확인한다.
2. inspect/resume 권한 주체는 본인1인으로 확정했다. 전용 호출 계정/환경별 IAM 실체·감사 형식과 실제 Cloud Run 종료 증거 확보 가능성을 검증한다. 증거가 없는 경우는 기존 정책대로 차단을 유지한다.
3. 브라우저 phase 전환 때 재사용 캐시 비우기와 정상 이어 실행2구간 연속 영속 진행 없음 감지는 사용자 확정했다. 새 입장 시 고메모리 차단과 실제 drain 동작은 구현·검증 대상이다.12/14/15분은 SDK/Sharp 정리 시간 보장이 아니다.
4. 확정된 주기·보관 기간은 §16~17을 따른다. 정리 page100/회당500건·신규 투입120초, 오류 backoff10/20/40/60초, requestCreatedAt 신규 접수24시간·미래5분, 로컬 확정 기록30일도 사용자 확정했다. [세부 구현 계획](product-queue-implementation-plan.md)에 단계/파일/필수 게이트와 연결했다. 승인된 보관 정책을 이유로 기존 로그/콘텐츠 보관을 일괄 변경하지 않는다.
5. 기존 Development task/revision·진단/보수 네트워크 경로까지 우회가 없는지 검사하고, 앱/Functions/Worker/GRDB/rules의 필수 게이트 목록을 연결한다. 구버전 앱 호환 QA는 제외한다.

이번 산출물은 세부 설계 초안과 확정 정책이다. 제품 코드·클라우드·실험 실행권·데이터 변경 없이 코드 진입점과 공식 Cloud Tasks/Cloud Run 계약을 조사했다. 아래는 사용자가 요청한 데이터/API·실제 복구·브라우저·앱 저장소의 구체 계약 제안이며, 아직 코드 구현이나 실행 가능한 복구 도구가 아니다.

## 12. 데이터/API 구체 계약 제안

### 최소 영속 데이터

새 제품 큐의 계약 버전 후보는 `queueContractVersion: 1`이다. 기존 성능 실험 결과 version5나 추출기 버전과 다른 필드다. 요청 ID는 UUID 형식을 검증하되 서버가 누락 값을 임의 생성하지 않는다. batchID는 인증 UID와 requestID의 결정적 digest로 만들며, 입력 digest는 서버가 정규화한 작업 종류·순서 있는 후보 목록·snapshot·대상 식별자로 계산한다.

| 문서 | 필수 내용 제안 | 갱신 주체·불변 조건 |
|---|---|---|
| `lookbookImportQueue/main` | nextSequence, headBatchID, epoch, ownerToken, leaseUntil, heartbeatAt, state, blockedReason | 서버 transaction만 쓰기. head 차례 변경에는 종료 증거 필요 |
| `lookbookImportBatches/{batchID}` | contractVersion, requestedBy, requestID, payloadDigest, brandID, kind, sequence, items, state, dispatchGeneration/State, nextEligibleAt, timestamps, stateRevision | identity/선택 순서는 접수 후 불변. 최대80개의 작은 item 결과만 유지 |
| batch 하위 `runs/{runID}` | epoch/owner/bootID/revision, 시작·중단·정리 시각, reason, 종료 증거, checkpoint 요약 | HTTP 실행별. 종료 기록 뒤 늦은 heartbeat로 실행 상태 부활 금지 |
| batch 하위 `recoveryDecisions/{decisionID}` | 대상 epoch, evidence 참조/digest, 이전·다음 상태, 운영 주체, reason, 결정 시각 | 복구 기록. 임의 true 플래그를 종료 증거로 쓰지 않음 |
| 기존 import job 및 `executions/{executionID}` | batch 참조, 승인 snapshot, phase/checkpoint, 시도 이력, 고정된 season/post 매핑 | job 최신 요약과 과거 execution 구분. 자동 재시도와 수동 새 실행 분리 |
| execution 하위 `assets/{assetKey}/writes/{writeID}` | 경로 쌍, 객체 generation/크기, epoch, 업로드 의도/결과, 공개·교체·정리 상태 | 두 변형 완료 후에만 공개. deleting인 write 재공개 금지 |

items의 항목은 `{itemID, candidateID 또는 기존 대상ID, ordinal, admissionStatus, jobID, executionID, errorCode}`로 제안한다. admissionStatus는 pending/created/duplicate/failed/skipped이며 execution 상태와 별개다. HTTP가 끊겨도 item별 준비 결과를 재조회한다. URL·HTML·이미지 Buffer·전체 오류 stack은 API 응답이나 batch items에 싣지 않는다. 서버 승인 입력 중 재개에 필요한 URL/snapshot은 서버 전용 실행 입력에 고정한다. 모든 이미지 기록을 batch 한 문서에 넣지 않는다.

재사용할 이름은 기존 `requestSeasonCandidateImportJobs` callable이다. iOS DTO·mapper도 같은 배포 단위에서 변경한다. 접수 필수 입력은 기존 brandID/discoveryJobID/generation/candidateIDs/candidateSnapshotHash에 requestID/requestCreatedAt/queueContractVersion을 더한다. 동시성·예산·owner·sequence·직접 Storage 경로는 클라이언트 입력으로 받지 않는다.

### API 경계

| 호출 | 입력·반환 제안 | 권한/효과 |
|---|---|---|
| `requestSeasonCandidateImportJobs` | 최신 접수 입력 → requestID/batchID/brandID/receiptState/items/집계/stateRevision | 현재 브랜드 쓰기 권한. preparing 응답도 접수 성공이며 전체 job 준비 완료라는 뜻은 아님 |
| `getSeasonImportBatch` 신규 callable | requestID 또는 batchID 중 하나 → 자기 요청 영수증과 현재 항목별 진행 상태/blockedReason | 인증 UID·브랜드 권한 재검사. 다른 브랜드 순번/owner/전체 큐 미노출 |
| 기존 승인/수동 재시도/repair/직접 URL 접수 callable | 기존 대상·검토 버전 검증+requestID/contractVersion → 같은 영수증 형태 | 각 기존 권한 유지. 서버에서 kind 결정, 사용자가 임의 kind로 우회하지 않음 |
| 기존 `discoverSeasonCandidates` | 기존 archive/브랜드 입력+requestID/contractVersion → batch 영수증과 기존 discovery job 식별자 | 목록 탐색도 같은 FIFO. 기존 후보 snapshot 공개/조회 계약 유지 |
| `/tasks/import-batch` | batchID/dispatchGeneration/contractVersion → accepted/outcome/continued 또는 recoveryRequired | 기존 task OIDC. 영속 상태 확정 후 응답,2xx를 전체 등록 성공으로 해석하지 않음 |
| 운영 복구 도구 | 대상 프로젝트/batch/epoch/evidence → 검사 보고·조건부 복구 결과 | 일반 앱 API에 전역 복구 권한 추가하지 않음. §13 참조 |

접수 재전송의 검증 순서는 인증·현재 브랜드 권한→requestID 영수증 조회→동일 payload 대조→신규 접수인 경우에만 현재 discovery snapshot 유효성 검증이다. 이미 받아 놓은 요청을 snapshot 만료만으로 잃지 않게 한다. 권한이 사라진 사용자는 기존 영수증도 무조건 조회할 수 없다. 신규 접수 transaction에서 검증한 snapshot 식별자와 승인 입력을 고정하고, 이후 preparation이 새 discovery generation을 읽어 다른 선택으로 바꾸지 않는다. 삭제/권한 등 실행 불가 조건은 별도로 확인한다.

준비 중 동일 항목 처리의 중복 방지는 결정적인 item/job identity와 transaction으로 구현하는 제안이다. 서로 다른 requestID가 같은 시즌을 동시에 요청하는 경우 기존 활성 job 조회의 경쟁 안전성을 emulator에서 검증한다. 쿼리만으로 입증하지 못하면 브랜드 하위에 canonical source/기존 season 대상별 claim 문서를 추가해 같은 transaction에서 기존 job 참조 또는 새 job 귀속을 결정한다. 테스트 없이 ‘중복 방지됨’이라고 하지 않는다.

오류 code 제안은 REQUEST_ID_CONFLICT(동일ID 다른입력), SNAPSHOT_STALE(신규 접수만), PERMISSION_DENIED, INVALID_CONTRACT, TARGET_DELETED다. 이미 접수된 요청의 일시 조회 실패는 ‘접수 실패’가 아니다. 서버 과부하/DB 장애에서 임의 새 ID로 재전송하지 않는다. 복구 대기는 정상적인 상태 응답이며 무한 transport retry를 유도할 오류로 반환하지 않는다.

영수증 준비 전에는 pending item을 실패 수에 더하지 않는다. preparing이 끝나면 item별 결과로 집계를 계산하며 병렬 increment와 별도 합산으로 중복 수를 만들지 않는다. status 응답은 stateRevision과 각 실행 identity를 포함해 오래된 응답이 최신 표시를 되돌리지 않게 한다. current 상태를 얻기 위해 candidate별 최신 updatedAt job을 다시 고르는 방식은 제거한다.

### 조회·규칙·비용 경계

queue/batch/runs/executions의 내부 원본은 앱 직접 읽기·쓰기 금지, callable이 필요한 항목만 반환하는 안이다. 기존 브랜드 권한으로 읽는 job 요약은 유지하되 ownerToken·내부 증거·다른 사용자 요청 목록은 내보내지 않는다. 현재 importJobs 규칙이 허용한다고 새 실행 하위 문서까지 읽힌다고 가정하지 않는다. 쓰기 권한 변경과 새 Storage 실행 경로 보호는 구현 계획의 rules 검증 대상으로 연결한다.

큐 선택 쿼리는 미종료 여부+sequence, 전달 회수는 dispatchState+nextEligibleAt, 정리는 cleanupState+eligibleAt로 범위를 제한하는 제안이다. 대용량 items/input/증거의 불필요한 자동 index는 제외 검토한다. 앱 조회마다 전체 큐·모든 시즌을 스캔하지 않고 해당 batch와 연결된 최대80항목만 조회한다. polling 주기·복구 scheduler 주기·페이지 크기는 현재 실험 비용과 별개인 제품 비용 항목으로 구현 계획에 명시한다. 필요한 composite index와 최악 문서/transaction 크기는 emulator·실제 설정 검사에 포함한다.

## 13. 운영 복구 절차와 실행 증거

### 현재 가능한 것과 추가해야 하는 것

현재 `index.ts`의 instanceID는 `randomUUID()`로 만든 **프로세스 부팅 ID**다. 이를 Cloud Run platform instance ID라고 해석하지 않는다. claim 시 batch/epoch/runID/bootID/revision을 구조화 로그와 runs 문서에 같이 남기고, Cloud Logging의 `labels.instanceId`로 플랫폼 인스턴스와 연결하는 제안이다. 공식 로그 계약에서 해당 label은 서비스 인스턴스를 식별한다. [로그 필드](https://docs.cloud.google.com/run/docs/logging).

로그 연결은 Worker stdout event를 bootID+runID로 찾고 그 로그의 resource project/service/revision 및 labels.instanceId를 읽어 증거에 보존한다. 누락/서로 다른 instance 매핑이면 판정 불가다. bootID와 플랫폼 ID가 같은 문자열이라고 가정하거나 새 요청이 같은 인스턴스로 전달될 것으로 가정하지 않는다.

| 증거 | 판정 가능 범위 | 금지할 추론 |
|---|---|---|
| 해당 epoch의 durable drained 영수증 | 추적한 작업·browser·슬롯·Buffer 종료와 마지막 DB 반영 | 메모리가 회복됐다는 뜻은 아님 |
| 해당 platform instance의 명시적인 강제 종료/OOM 시스템 증거 | 그 인스턴스의 프로세스 실행 종료 | 실패한 모든 Storage 요청이 서버에서 취소됐다는 뜻은 아님 |
| HTTP200/500/504, lease 만료, SIGTERM 수신 로그, 시작 로그 | 요청/관찰 사건 | 단독으로 실행 종료 판정 금지 |
| 로그 부재, 트래픽0%, 새 revision 또는 새 bootID | 환경 변화 | 이전 실행 종료 판정 금지 |

Cloud Run의 메모리 초과 종료 오류는 `varlog/system` 등 관련 로그로 확인할 수 있지만, 실제 환경에서 정확한 종료 사건과 대상 instance를 연결하는 절차는 Development에서 검증해야 한다. [공식 장애 진단](https://docs.cloud.google.com/run/docs/troubleshooting). Cloud Run 서비스는 종료 시 SIGTERM 뒤 짧은 종료 유예를 사용하므로, 앞서 정한12/14/15분의 정상 분할 여유를 SIGTERM 시에도 사용할 수 있다고 가정하지 않는다. [컨테이너 종료 계약](https://docs.cloud.google.com/run/docs/container-contract).

### 운영 도구의 두 단계 계약 — 로컬 구현, 실제 운영 검증 미완료

1. **inspect(읽기 전용):** 프로젝트/서비스/revision/batch/expectedEpoch를 명시해 coordinator, run, 실행·산출물 기록, 정확히 일치하는 로그 증거를 모은다. 보고서에 canResume/차단 사유/이미 완료된 이미지/남은 시도/불명확한 원격 쓰기/예상 변경을 표시한다. 인증·원본 URL의 민감 query 값은 보고서에서 제외한다.
2. **resume(조건부 쓰기):** 운영자가 검토한 보고서 digest와 decisionID로만 실행한다. 서버를 다시 읽어 head/epoch/stateRevision/증거가 바뀌지 않았는지 확인하고, 감사 기록·다음 dispatch 의도·복구 전이를 transaction으로 반영한다. 같은 decisionID 재전송은 같은 결과를 반환한다. `force`, `assumeStopped`, 임의 drained=true 옵션은 두지 않는다.

도구는 `recovery` OIDC caller와 Worker runtime Cloud Logging read 권한을 사용하는 별도 진입점이며 일반 브랜드 관리자 권한과 같다고 간주하지 않는다. 사용자 확정은 본인1인·조건부 복구다. `tools/lookbook-import-worker/scripts/lookbook-import-recovery.mjs`가 고정 대상·digest·stateRevision·decisionID를 제출하며 route는 dedicated recovery service account 설정이 없으면 비활성이다. 실제 service account·IAM·Development log evidence는 실행안에서 확인하며 현재 설정/권한을 추정하지 않는다. Q4 구현 과정에서 호출과 IAM 변경은 하지 않았다.

메모리 중단 후 drained가 확인된 경우에도 원인 조치·관찰 정상 확인 없이는 resume하지 않는다. resume는 ‘메모리 안전이 영구 입증됨’이 아니라 기존 차례의 재개 시도를 허용하는 것이다. Worker는 실행 입장 시 메모리/관찰 상태를 다시 검사하고 실패하면 신규 이미지 작업을 시작하지 않은 채 차단을 유지한다. 재개를 위해 인스턴스가 새로 생긴다고 가정하지 않는다.

종료만 확인되고 이전 원격 쓰기의 결과가 불명확하면 이전 epoch의 경로를 새 결과로 승격하지 않는다. 현재 참조는 유지하고 확인된 checkpoint부터 새 writeID로 재개한다. 불명확한 이전 객체는 별도 정리 대기로 남겨 다음 실행 결과와 분리한다. 중복 원격 요청이 확정될 때까지 삭제 완료로 기록하지 않는다. CPU 작업 종료와 원격 저장 결과 확정을 분리한다.

종료 증거를 얻을 수 없는 경우의 결과는 **blocked 유지**다. 요청이 특정 Cloud Run 서비스 인스턴스로 라우팅된다고 가정한 `/kill` 호출이나 신규 Cloud Run Instances 제품의 stop API를 현재 서비스에 적용하지 않는다. 운영자가 이전 revision을 조치해야 한다면 영향 범위와 승인을 별도로 확인하고, 그 조치 자체가 종료 증거를 대신하지 않는다.

필수 검증은 정상 정리·응답 유실·실제 OOM·SIGTERM 도중 미완료 작업·다른 instance 로그·지연된 Storage 완료·동일 복구 결정 재전송이다. 종료 증거를 실제로 확보할 수 없는 케이스는 통과가 아니라 운영상 차단으로 남긴다.

## 14. 브라우저 자원 공유 계약

사용자가 **인스턴스당 Chromium1개·이미지의 무거운 처리와 분리·진행 중 import 동안 별도 목록 탐색 대기**를 확정했다. 숫자1은 제품 HTML/Playwright를 포함해 다시 검증할 초기값이며 기존 이미지 실험의 최적값으로 주장하지 않는다.

실제 구현은 `queue/browser-gate.ts` module singleton을 import, discovery, image/hash 경로가 공유한다. import는 `processor.ts::renderHTMLWithPlaywright`, discovery는 `season-discovery.ts::renderedDiscovery`가 이를 통과한다. 목록 진단 경로와 repair preview에서 발견되는 추가 browser/이미지 경로도 같은 gate를 통과하는지 Q3 Linux audit에서 확인한다. 우회하는 숨은 `chromium.launch`가 없는지 검색한다.

인스턴스 자원 상태 제안은 image/closingImages/browser/idle다. browser 대기가 생기면 새 이미지·해시용 다운로드 투입을 닫고, 이미 시작한 이미지의 다운로드→변환→업로드→경로 기록까지 끝내 슬롯·borrowed Buffer를 반환한다. 재사용 캐시도 이 전환에서 비우는 방식을 사용자가 확정했다. 메모리 경쟁을 줄이되 추가 다운로드량은 제품 검증에 기록한다. 진행 중 이미지가 브라우저 permit을 다시 기다리는 순환 의존을 만들지 않는다.

이미지 작업 정리가 확인되면 SSRF 검사와 취소 조건을 유지한 채 Chromium 한 개를 띄운다. browser/context 종료를 확인한 뒤 이미지 입장을 다시 연다. 렌더링 결과는 제한된 HTML/후보 metadata로 옮기고 browser 객체를 이미지 저장 단계까지 보관하지 않는다. 종료가 불명확하면 permit을 반환한 척하지 않고 recoveryRequired로 전환한다. 대기 중12분 경계를 넘은 브라우저 작업은 시작하지 않고 checkpoint로 넘긴다.

정적 HTML 요청은 Chromium 실행과 구분하되 무제한 Promise로 늘리지 않고 현재 시즌6의 입장 범위 안에서 수행하는 제안이다. Chromium의 내부 CSS/JS/이미지 요청 수는 이미지 다운로드4에 포함되지 않는다. 따라서 ‘네트워크 요청 전체가4개 이하’라고 표시하지 않는다. 페이지 자원을 무작정 차단하면 추출 결과가 달라질 수 있으므로 현 렌더링 의미를 유지하고 실제 트래픽·메모리를 따로 측정한다.

목록 탐색을 기다리게 할 때 task HTTP나 browser permit을 잡고 장시간 대기하지 않는다. 기존 discovery 문서의 generation/snapshot 계약은 유지하고, 실행 차례가 올 때만 실제 claim과 attempt 시작을 한다. 대기 때문에 발견 시도 예산이 소모되거나 watchdog가 재시도 폭주를 만들지 않도록 기존 `season-discovery-processor.ts` claim 앞에 연결해야 한다.

**사용자가 목록 탐색도 import와 같은 접수 순서로 처리하는 안을 확정했다.** 같은 서버 sequence에 종류만 다른 요청으로 접수한다. 기존 두 최상위 collection 안에서 batch.kind=discoverSeasons, items에 기존 discovery job 한 개를 참조한다. 실행 중 import는 끝내고 sequence상 다음 요청을 실행한다. discovery 내부 렌더링은 자기 차례 안에서 끝내며, 결과를 보고 사용자가 시즌을 선택하면 새 import를 맨 뒤에 넣는다. 목록 요청이 들어오기 전에 접수된 B import를 추월하지 않고, 뒤늦은 C import 때문에 앞서 접수된 목록 요청이 영원히 밀리지 않는다. 목록이 사용자 검토 대기에 들어가거나 최종 종료하면 정리 후 차례를 넘기며 선택 입력을 기다리는 동안 큐를 붙잡지 않는다. discovery의 실패 예산은 기존 계약을 먼저 확인하고 시즌 import 총5회를 임의로 복사하지 않는다.

coordinator는 프로젝트 전체의 해당 요청 실행 순서를 제어하고, 인스턴스 permit은 내부 browser/image 중첩을 막는 역할로 나눈다. 서비스 전체 maxInstances를 변경하거나 별도 Worker 서비스를 만드는 범위는 포함하지 않는다. 여러 인스턴스가 가능한 환경을 ‘프로세스 변수 하나면 전역 제한’으로 해결했다고 하지 않는다.

추가 검증은 browser 활성 최대1, browser-active 동안 image/hash stage 활성0, 이미지 정리 후 browser 시작, browser 종료 후 이미지 재개, 시즌6개의 동시에 발생한 렌더링 대기, discovery/진단 우회, task 재전달 중 실제 작업0, 전환 중 메모리 중단이다. Chromium과 재사용 캐시 반환을 포함한 조건이 달라지므로 제품 Development 검증에서 처리 시간·재다운로드량도 다시 기록한다.

2026-10-05 구현·검증: shared gate·browser priority·cancellation-aware permit·등록된 source-buffer cache purge를 연결했다. G-L Linux/amd64·1CPU·2GiB에서 실제 Chromium을 띄워 browser/image 겹침0·cache 반환·cgroup 표본16개/최대 간격103.99ms·최대 container 비율15.47%·SIGTERM 후 Chromium 프로세스4개 종료를 검사했고 별도192MiB container의 실제 OOM kill(`OOMKilled=true`, exit137)을 확인했다. task redelivery·진단/repair 경로 교차 및 실제 Worker HTTP 서버/Cloud Run 종료·복구는 아직 미검증이다. 전체 실행 원본은 [Q3 결과](product-queue-q3-results.md).

## 15. 앱 GRDB·최신 계약 연결

사용자 확정대로 기존 GRDB를 사용한다. `AppDatabase`는 `OutPick.sqlite`와 `GRDBMigrationRegistry`를 사용하고 AppCompositionRoot가 한 번 만든다. 요청 복원 때문에 별도 DB 파일이나 새 DatabasePool을 만들지 않는다.

테이블 후보는 `lookbookImportRequest`다. 복합 키는 `(ownerUID, requestID)`, 필드는 contractVersion/brandID/kind/inputJSON/payloadDigest/localState/batchID/receiptJSON/stateRevision/createdAt/updatedAt이다. localState는 prepared/submitting/accepted/needsReconcile/settled로 제안하며 서버 job 상태와 분리한다. JSON에는 선택 식별자·snapshot·영수증만 넣고 이미지·인증 토큰·전체 큐는 넣지 않는다. `(ownerUID, localState, updatedAt)` 조회를 기준으로 필요한 index를 설계한다.

DB write가 성공한 뒤에만 첫 접수를 보낸다. 앱 종료 후 submitting/needsReconcile은 같은 ID로 먼저 조회하고, 영수증이 없으면 기존 입력 그대로 재전송한다. 그사이 snapshot이 만료됐다면 신규 접수 실패를 표시하고 재선택을 요구한다. accepted 요청을 새 UUID로 복제하지 않는다. 같은 화면에서 재탭하거나 두 UseCase가 동시에 실행돼도 같은 사용자 행동의 저장 레코드를 재사용하도록 로컬 transaction과 화면의 행동 ID를 연결한다. 다른 선택은 별도 ID다.

| 경계 | 제안 변경 |
|---|---|
| GRDB | migration/Record/Store 추가. 신규·기존 DB 모두 검증하며 채팅 임시 검색 정리 시 import 요청을 지우지 않음 |
| 도메인 | 좁은 요청 기록 저장 protocol과 영수증 조회 Repository protocol. UseCase가 전송/재조회/복원 순서 소유 |
| AppCompositionRoot | 기존 AppDatabase로 Store 구현 생성·주입 |
| AppCoordinator→LookbookContainer | protocol 의존성 전달. 화면이 DB나 Functions를 직접 생성하지 않음 |
| LookbookContainer/CreateBrandFlowView | 현재 두 곳의 StartSeasonImportExtractionUseCase 직접 조립을 같은 Container factory로 연결. fixture도 fake store 주입 |
| DTO/mapper/진행 모델 | 최신 batch/item/execution 식별자·상태로 교체. candidate 최신 job 선택 제거 |
| 계정 삭제 정리 | `deleteAllUserSessionData()`의 삭제 대상에 새 테이블 연결. 서버 import 취소와 로컬 기록 삭제를 혼동하지 않음 |

일반 계정 전환/로그아웃은 해당 UID의 관찰·전송을 중지하고 다른 UID 기록을 읽지 않는다. 같은 계정의 재로그인 복원을 위해 미확정 접수 기록을 보존하는 안을 제안한다. 계정 삭제 때는 기존 local scrubber와 함께 지운다. 서버에서 최종 결과가 확인된 기록의 보관/제거 기준은 로컬 데이터 수명 항목으로 구현 계획에서 명시하고, 응답 유실 상태를 단순 시간 경과로 삭제해 중복을 만들지 않는다.

최신 앱·서버의 필수 필드가 맞지 않으면 계약 오류로 드러내며 조용히 per-job 구형 실행으로 떨어지지 않는다. 별도 최소 앱 버전 정책/업데이트 화면/구버전용 decoder fallback/임시 requestID는 만들지 않는다. 이전 Development 잔여 작업과 서버 route 우회만 배포 전 점검한다.

검증은 기존 DB migration과 계정 삭제 scrubber 회귀, 저장 실패 시 HTTP0, DB 저장 직후 앱 종료, 서버 접수 후 응답 유실, 재시작 동일ID, 계정 전환 중 늦은 응답, 두 화면 동시 접수, 승인·수동재시도의 새 ID, 같은 job의 다른 execution 결과 혼합 방지다. fake Store/Repository 자동 검증과 실제 앱 재시작·문구·닫기 QA를 분리한다.

## 16. 조회·점검·정리 주기 — 초기 기준 확정

사용자가 아래 주기와 세부 backoff/회당 상한을 확정했다. 비용과 표시 지연을 고려한 초기 운영 기준이며 실측 최적값이 아니다. 정상 접수·다음 차례·정상 checkpoint 재개는 durable intent와 이벤트로 바로 이어가며, 정기 점검 주기를 기다려 시작하지 않는다.

| 구분 | 확정한 초기 주기 | 수행 범위와 종료 조건 |
|---|---|---|
| 앱 처리/접수 준비 중 | 직전 조회 완료 후3초 | 화면이 보이고 앱이 활성인 동안. 요청 중 새 조회를 겹치지 않음 |
| 앱 queued/자동 재시도 대기 | 직전 조회 완료 후10초 | 순번·예상 시간 전체 조회 없이 해당 영수증/연결된 항목만 확인 |
| 앱 결과/복구 안내/백그라운드/닫힘 | 주기 조회 중지 | 화면 재진입·앱 foreground 복귀·명시적 새로고침 때1회 조회. 복구 안내에서 스스로 변화를 계속 감시하지 않음 |
| 서버 누락/정체 점검 |5분 | pending 전달·중단된 preparation·현재 head/lease 이상. 복구 필요를 발견해도 종료 미확인 작업을 자동 인계하지 않음 |
| 미참조 파일 정리 |1시간 | 기존24시간 조건과 현재 참조·종료 증거·정리 잠금 확인 후 삭제 |
| 상세 기록 압축/만료 정리 |하루1회 | 아래 보관 조건에 도달한 대상만 처리. 실행 이력과 앱 콘텐츠 데이터를 분리 |

처리 중3초는 현재800ms polling 대비 이론상 분당 조회 시작 횟수를 약75회에서20회로 줄인다.10초 대기는 약6회다. 응답 시간·페이지 수·재시도에 따라 실제 값은 다르며 금액 절감률로 환산하지 않는다. 여러 화면이 같은 batch를 보면 같은 관찰 작업을 공유하고, 계정 전환/세션 만료 시 중지한다. 최신 요청의 상태가 섞이지 않도록 batch/execution별 observation을 구분한다.

일시적 조회 오류는 마지막 상태를 보존하고 같은 주기를 고집해 폭주하지 않게 backoff한다. 사용자가 연속 오류 시10→20→40→60초 상한, 성공·수동 새로고침 때 정상 주기 복귀를 확정했다. 권한/계약 오류는 자동 재조회로 해결하려 하지 않고 안내 상태로 전환한다. 이 backoff는 화면 polling 정책이며 시즌 총5회 예산과 무관하다.

5분 점검은 하루288회,1시간 정리는24회, 일일 기록 정리는1회에 해당한다. 정기 확인은 저렴한 coordinator/대상 index 확인을 우선하며 빈 시간에 전체 job/버킷을 스캔하지 않는다. 기존 `reconcileSeasonDiscoveryJobs`는10분 주기·최대100건·15분 stale/최대3시도 계약이 있으므로 최신 큐 대상에 중복 적용하지 않는다. 기존 discovery3회와 import5회 예산은 혼동하지 않고 해당 요청 종류에 보존한다.

회당 작업량은 index page100건·최대5page(500건) 또는120초에 신규 처리를 중단하는 것으로 사용자 확정했다. 이미 시작한 요청은 종료를 확인하며120초 만에 강제로 성공 처리하지 않는다. 파일 정리는 최대500개 객체, 기록 정리는 최대500개 실제 문서 변경/삭제로 별도 계수한다. 부모 한 개 아래 수천 하위 문서 삭제를 ‘1건’으로 세지 않는다. CPU/네트워크 작업 동시성은 기존 안전한 정리 helper를 재사용하되 신규 무제한 fan-out은 없다. 정리 cursor·처리 결과를 저장하고 남은 대상은 다음 주기에 이어간다. 같은 문서가 계속 보호 상태여서 뒤 만료 대상 전체를 가리지 않도록 보호 조건과 eligibleAt을 구분한다.

정기 전달은 중복될 수 있으므로 정리용 lease와 cursor/조건부 상태 전이를 사용하고 한 번 실행을 가정하지 않는다. [Cloud Scheduler 실행 모델](https://docs.cloud.google.com/scheduler/docs/overview). 파일 generation 조건을 지키며, 실패한 삭제는 완료로 세지 않는다. 클라우드 스케줄러 시간은 UTC 고정 시각으로 문서화하고 사용자 표시만 KST로 변환하는 제안이다. 실제 스케줄 표현식은 배포 계획에서 확정한다.

주기는 완료 SLA가 아니다. 예를 들어24시간 보관 조건을 넘긴 파일은 다음 시간 점검부터 정리 가능하며 backlog/권한 오류가 있으면 더 늦어질 수 있다. 각 실행에 scanned/eligible/protected/deleted/failed/remaining·oldestEligibleAge를 기록해 정리 적체를 확인한다. 신규 비용은 scheduler 실행·Functions·Firestore read/write/delete·Storage list/metadata/delete로 분리해 배포안에 산정한다. 기존 실험 비용을 제품 월비용으로 재사용하지 않는다.

## 17. 기록 보관과 만료된 요청 — 기간·접수 시간 창 확정

사용자가 성공 상세24시간·최소 완료30일·실패/중단 상세30일·복구 결정90일과 보호 예외를 확정했다. 성공 상세 기록은 오래 보관하지 않고 최소 접수 영수증과 현재 콘텐츠의 참조 정보를 분리한다. 파일24시간 정리 정책과 아래 **작업 기록** 수명은 별개다.

| 대상 | 확정 기간·기준 시점 | 기간만으로 삭제하면 안 되는 조건 |
|---|---|---|
| 성공한 실행의 상세 run/성공 중간 checkpoint | 정상 종료·정리 확인 후24시간 | 다른 실행/승인·복구가 참조, 미해결 산출물 있음 |
| 최소 완료 영수증 | 해당 요청 최종 종료 후30일 | 연결된 실제 실행/검토/복구가 미종료. 중복만 접수된 released도 연결 job 결과 확인 전 보존 |
| 실패·중단 상세 | 문제 해결 또는 확인된 최종 종료 후30일 | recoveryRequired/종료 불명확/검토 승인에 필요한 snapshot/재개 중 |
| 복구 결정 감사 기록 | 결정 후90일 | 미해결 복구나 후속 검증이 해당 증거를 참조 |
| 현재 공개 이미지 경로·generation·출처 최소 식별자 | 콘텐츠가 참조하는 동안 | 작업 성공 기록 보관 만료와 무관 |
| 미공개/이전 파일의 정리 원장 | 해당 객체 정리 확정까지 | 원격 쓰기 결과 불명확·현재 참조·종료 불명확 |

최소 완료 영수증은 requestID/요청 주체/payloadDigest/결과 분류/생성 대상 ID/종료 시각/만료 시각만 남기는 제안이다. HTML·원본 이미지·상세 단계 시간·오류 stack을 성공 영수증에 유지하지 않는다.30일은 과거 결과를 다시 확인하고 중복 접수를 막는 보장 기간으로 명시하며 영구 이력 서비스로 취급하지 않는다.

실패를 거쳐 나중에 성공한 요청은 성공 결과만 보고 장애 증거까지24시간에 지우지 않는다. 성공한 단계의 불필요한 상세만24시간으로 정리하고 장애·복구에 필요한 부분은 해당30/90일 기준을 적용한다. 검토 대기는 성공이 아니며 승인 snapshot을 보존한다. job 실행 기록 정리 때문에 공개 write의 generation/정리 책임이 사라지지 않도록 콘텐츠 또는 별도 최소 산출물 원장으로 필요한 필드를 남긴 후 상세를 압축한다.

이 기간은 새 제품 큐가 관리하는 구조화 기록의 수명이다. 기존 추출 증거7일 정책, Cloud Logging·백업·실험 결과의 보관을 자동 변경하지 않는다. raw HTML/미디어를 장기 복사하는 대신 실패 code·checkpoint·필요한 종료 증거만 보관한다. 정확한 플랫폼 종료 증거는 로그가 만료되기 전에 최소 필드와 원본 식별자/digest를 검증 후 복구 감사 기록에 남겨야 한다. 다른 저장소의 원문이90일 유지된다고 주장하지 않는다.

### 영수증 만료 후 재접수 방지 — 고정 ID·생성 시각 확정

30일 뒤 영수증을 삭제하고 같은 요청을 무조건 신규로 받으면 중복 방지가 깨진다. 단순 TTL 삭제만으로 완료하지 않는다. 사용자 확정에 따라 신규 접수에는 **변하지 않는 requestCreatedAt**을 requestID와 함께 저장·전달하고 digest에 포함한다. 서버 검증 순서는 기존 영수증 조회 우선이며, 존재하는 요청은 생성 시각이 오래돼도 허용된 보관 범위에서 재조회한다.

영수증이 없을 때만 신규 접수 시간 창을 검사한다. requestCreatedAt으로부터24시간 이내·서버 시각보다 미래5분 이내를 사용자가 확정했다. 서버 시간으로 판정하고, 오래되거나 잘못된 시각의 입력은 REQUEST_EXPIRED/CLOCK_INVALID로 반환한다. 시간 창은 권한 증명이 아니며 브랜드 권한·활성 job 중복 검사는 그대로 수행한다. 의도적으로 timestamp를 바꾼 요청에 대한 무제한 멱등성을 보장한다고 하지 않는다.

앱은 동일 행동 재전송에서 ID·생성 시각을 바꾸지 않는다. accepted 상태에서 서버 영수증이 사라지면 새 요청을 자동 생성하지 않는다. ‘이전 요청 기록이 만료되어 결과를 다시 확인해야 합니다’로 안내하고 현재 시즌 데이터 확인 후 사용자가 명시적으로 새 선택/재시도를 하게 한다. 응답 유실 상태도24시간을 넘어 영수증이 없으면 자동 재전송하지 않는다. 필요에 따라 새 UUID를 만드는 동작은 사용자 새 행동으로만 수행한다.

로컬 GRDB는 미확정/진행/검토/복구 기록을 유지하고, 확정된 결과는30일 후 앱이 활성일 때 정리하는 방식을 사용자가 확정했다. 앱이 꺼져 있는 동안 정확한 만료 시각에 삭제된다고 가정하지 않는다. 계정 삭제는 기존 scrubber 경로로 즉시 정리한다. unresolved 레코드는 나이가 많다는 이유만으로 삭제하지 않으며, 재진입 때 권한·서버 결과를 확인한다.

## 18. 복구 도구 권한 — 운영 주체·허용 동작 확정

사용자가 운영 주체를 현재 배포 담당자인 본인1인으로 확정했다. 앱 브랜드 관리자 권한으로 전역 큐 차단을 해제하지 않는다. 허용 동작은 증거 조회·조건부 재개이며 강제 해제·삭제·증설은 제외한다. 인증 구현은 기존 운영자 runbook의 좁은 OIDC 발급 방식을 재사용하되 **환경별 복구 호출용 서비스 계정**을 별도로 두는 제안이다. 키 파일은 만들지 않는다.

| 주체/경계 | 허용 범위 제안 | 제외 |
|---|---|---|
| 본인 운영자 | 정확한 복구 호출 계정에 OIDC ID token 발급 | 프로젝트 전체 Token Creator·임의 SA impersonation 신규 부여 |
| 복구 호출 계정 | 해당 환경 Worker 서비스 호출 + 앱 내부 inspect/resume route 허용 | 직접 Firestore/Storage 관리 권한, task 실행 route 우회 |
| Worker 복구 route | inspect: 증거 읽기·판정. resume: 승인된 대상 head/epoch의 조건부 재개·감사/전달 의도 쓰기 | force 해제, 데이터 삭제, 다음 브랜드 추월, 자원 증설, 배포/IAM 변경 |
| task/Functions 호출 계정·앱 사용자 | 기존 자기 역할의 route | 복구 route 호출 |

OIDC 발급만 필요하면 `roles/iam.serviceAccountOpenIdTokenCreator`는 정확한 서비스 계정 리소스에 한정한다. 이 역할은 access token 발급 권한과 다르다. [공식 IAM 역할](https://docs.cloud.google.com/iam/docs/service-account-permissions). Cloud Run Invoker는 서비스 단위이므로 route별 권한은 기존 OIDC verifier를 확장해 별도로 검증해야 한다. [서비스 간 인증](https://docs.cloud.google.com/run/docs/authenticating/service-to-service). Development 토큰으로 Production 복구를 실행하지 못하도록 프로젝트/service/audience/호출 주체/contractVersion을 모두 묶는다.

복구 payload의 operator 이름을 신뢰하지 않는다. 감사에는 실제 검증한 서비스 계정 principal, 환경, 결정 ID, 검사 보고 digest, 대상 epoch/stateRevision, 결과를 기록하고1인 운영자와의 허용 매핑 및 확인 가능한 token 발급 감사 연결을 남긴다. 서비스 계정 토큰만으로 원래 사람의 이메일이 자동 증명된다고 하지 않는다.

inspect 결과 파일을 사용자가 수정해도 resume의 근거가 되지 않도록 서버가 Firestore·객체 metadata·원본 로그를 재조회/대조한다. 필요한 log 읽기 권한은 현재 runtime IAM을 확인한 뒤 정확한 환경 범위로 산정하며, 부족하면 미검증/거절로 처리한다. 단순 evidenceVerified=true 입력은 받지 않는다. 별도 광범위한 운영 관리 API는 만들지 않는다.

토큰 발급 권한이나 운영 IAM을 이번에 실제 추가하지 않는다. 서비스 계정 이름·운영자 실제 principal·Cloud Run binding·로그 조회 권한은 배포안에서 확인할 항목이다. 기존 프로젝트 Owner/Admin의 직접 관리 권한을 이 도구가 기술적으로 차단한다는 뜻은 아니다. 향후 운영자가 늘어나면 주체별 권한/감사 방식을 다시 검토한다.

## 19. 필수 검증 목록과 게이트 연결 제안

`test-design-workflow`와 프로젝트 프로그램적 검증 기준에 따라 아래를 필수로 연결한다. **이번에는 설계와 기존 설정 확인만 했으며 테스트 코드/게이트 수정·실행을 하지 않았다.**

현재 설정 확인: lookbook-import는 Worker lint/test/fixtures와 requiredTests208개, functions는 lint/test와 requiredTests9개, firestore는 rules/emulator suite와 requiredTests11개다. 이 숫자는 현재 필수 ID 등록 수이며 전체 테스트 수가 아니다. ios.json은 AppRuntimeConfiguration/KeyboardDismiss 두 suite만 선택하고 requiredTests17개이므로 새 룩북/GRDB를 자동 검증하지 않는다.

| 필수 범위 | 필수 시나리오·합격 기준 | 연결 위치 제안 |
|---|---|---|
| PQ01·02 접수 | 동일ID 병렬/응답 유실/다른payload, 부분 preparation crash, 전부중복, 겹치는 시즌,80항목. 중복 실행·고아·집계 중복0 | Functions unit + Firestore emulator 새 필수 ID |
| PQ03·04 전달/실행권 | DB성공-task실패, 전달 역전·중복, 두 Worker claim, stale epoch/heartbeat, 이전 route. 전체 활성 작업 차례 최대1 | 제품 큐 통합 게이트 신규 설정 제안 |
| PQ05 FIFO/탐색 | A8/B2/추가A/목록 탐색 섞인 접수,100ms 도착, 검토·최종실패·정리 지연. 순번 추월·정리 전 다음 시작0 | fake clock/barrier + emulator |
| PQ06 자원/브라우저 | 공유 시즌6·4/1/4·128MiB, Chromium 최대1, browser/image 중첩0, 캐시·borrowed 반환, discovery 우회0 | Worker 필수 ID +1CPU/2GiB Linux 컨테이너 |
| PQ07 재개/예산 |12/14/15분 경계, 정상 구간은 실패 예산0증가, import6번째시도 거절, discovery 기존3회와 분리, 부분 이미지 재개 | Worker/Functions+emulator |
| PQ08 저장/삭제 | 한 JPEG 실패, 공개 응답 유실, stale write, 기존 이미지 참조 유지, 공개/삭제 경합, generation 불일치 | fake Storage + Storage/Firestore emulator |
| PQ09 장애/복구 | 메모리/표본 중단, 실제 OOM, SIGTERM, SDK 미종료, DB소실, 잘못된 instance 증거, 복구 중복/상태 변경. 증거 없으면 다음 시작0 | Linux 프로세스 장애 주입 + Development 증거 검사 |
| PQ10 최신 계약/권한 | task/Functions/앱/복구 계정 route 분리, 다른브랜드/계정·다른환경 거절, 이전revision 우회0 | rules emulator + OIDC unit + Development IAM |
| PQ11 앱/GRDB | 신규·기존DB migration, 전송 전 저장 실패, 응답 유실 재시작, 다른UID 늦은응답, 상태 집계, 계정삭제 정리 | 룩북 전용 iOS 게이트 신규 설정 제안 |
| PQ12 보관/만료 |24시간/30일/90일 직전·정각·이후, 현재참조/검토/복구 보호, 성공 후 과거 장애 보존, 만료ID 신규실행0, 삭제 후 자식 기록 누락0 | fake clock + emulator + GRDB test |
| PQ13 주기/적체 |3/10초 전환·겹친조회0·백그라운드0,5분/시간/일 중복실행, page/cursor/500건·120초 상한, 특정 보호항목으로 정리기아 없음 | 앱 fake clock + 정리 unit/emulator |
| PQ14 운영 복구 보안 | 위조 보고서/다른 epoch/다른 audience/task 계정 거절, inspect mutation0, resume 동일결정1회, force/delete/scale 입력 거절 | OIDC/서비스 unit + emulator + IAM 실제 확인 |
| PQ15 실행 기록 | 필수 ID 누락·skip·0개·timeout·증거 누락을 통과시키지 않음. 소스digest/설정/원본 로그 연결 | 기존 gate/reporters 활용, 신규 설정 self-check |

예상 실행 연결은 기존 `verification/{lookbook-import,functions,firestore}.json` 보강과 룩북 전용 iOS·제품 큐 통합 설정 추가다. 새 파일 이름/실제 test ID는 구현 계획에서 확정한다. 아직 없는 설정 경로를 실행 완료나 준비 완료로 표시하지 않는다. Worker/Functions 빌드·fixture 회귀와 iOS build를 포함하고, Functions export 추가로 바뀐 계약 테스트는 실제 새 API 목록을 검증하도록 갱신한다. 실패를 없애려고 required 목록에서 빼지 않는다.

실행 순서는 순수 로직/빌드→emulator→Linux 자원·프로세스 장애→앱/GRDB→승인된 Development 연결→실기기 QA다. 같은 빌드 산출물/DB/시뮬레이터를 공유하는 게이트는 순차 실행한다. 실제 네트워크·IAM·플랫폼 종료 증거는 로컬 fake 결과로 대체하지 않는다. Development는 기존 성능 실험을 그대로 반복하는 것이 아니라 새 제품 경로의 최소 smoke·재개·복구·브라우저·정리 검증이며, 대상·요청량·비용은 별도 실행안으로 제시한다.

수동 QA는 화면 문구/닫기/재진입/실제 앱 재시작·백그라운드 복원과 운영 복구 보고서의 이해 가능성이다. 자동으로 확인 가능한 counts/state/권한 결과와 구분한다. 실패·미검증은 원본과 함께 남기고 모든 필수 항목이 현재 코드에 대해 실제 실행돼야 완료다. 구버전 앱 호환, 무제한 부하 탐색, 자동 자원 증설 검증은 이번 범위에서 제외한다.
