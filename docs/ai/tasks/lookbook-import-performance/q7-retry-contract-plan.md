# Q7 종료 정산·처음부터 재시도·실패 목록 — 세부 계약안

2026-10-07. 사용자 승인 순서의 Q7-R0 산출물. 사용자 ‘추천안으로 확정하고 진행하자’로 D1/D2 추천 A를 확정하고 구현을 승인했다. API와 변경 파일은 아래 계획대로 순차 구현하며 아직 배포된 계약이 아니다.

## 1. 기존 코드에서 확인한 차이

- `queue/coordinator.ts::claimBatch`는 idle/head/owner 없음만 선점한다. 강제 종료로 active/draining이 남으면 Cloud Tasks 재전달만으로 재시작할 수 없다.
- `checkpoint.ts`는 일반 시도의 attemptCount를 시작 전에 증가시키지만 reviewApproval은 같은 횟수를 유지한다. 승인 저장이 반복 실패해도 재시도 예산을 새로 무한 부여하면 안 된다.
- `processor.ts::materializeContent`는 targetSeasonID/createdPostIDs가 있으면 이전 부분 결과를 재사용한다. 현재 자동 재시도를 처음부터 처리라고 단정할 수 없다. 시즌·post는 pending 자산 상태에서도 status=published로 생성되므로 정리 대상의 참조/생성 주체를 확인해야 한다.
- `batch-runner.ts`는 일반 retryable exception을 즉시 재시도하지만 executor 오류와 소진을 recoveryRequired로 남기는 경로가 있다. 실제 최종 실패와 종료 미확인 상태를 구분해 바꿔야 한다.
- Functions `queue/followup-admission.ts`의 manualRetry는 추출 교정·새 runtime 조건 전용이다. 일반 failed 시즌의 처음부터 재시도 계약을 별도로 연결해야 한다.
- `shared/lookbookQueue/projection.ts`의 failedCount는 admissionStatus 기준이며 실행 실패 수가 아니다. 기존 필드 의미를 바꾸지 않고 실행 결과 집계를 추가한다.

## 2. 이미 확정한 공통 정책

- 종료 확인 뒤 해당 시즌을 처음부터 자동 재시도, 최초 포함 총5회. 누적 재시도 시간 창은 없고 개별 timeout/플랫폼 실행 제한은 유지한다.
- 완료 시즌은 보호하고 미시작/다른 선택 시즌도 끝까지 처리한다. 검토 대기는 등록 성공이 아니며 기존대로 차례를 반환한다.
- 수동 재시도는 맨뒤 새 요청·새 실행·새 총5회. 기존 서버 시도/실행 기록은 보관한다.
- 동일 시즌 실패 목록 문서1개. 재실패는 최신화, 성공/명시적 재시도 안 함은 문서 제거, 무선택은 보관 기간 내 유지.
- 화면 종료는 서버 취소가 아니다. 종료 미확인은 새 시도/다음 브랜드 차단이다. 실제 종료 확인과 옛 실행권의 조건부 쓰기 차단을 유지한다.
- 기존 CPU/메모리/동시성/재사용/12·14·15 안전장치·IAM 범위를 유지한다. 중간 복원 API 확대와 새로운 자원 증설은 없다.

## 3. 사용자 확정 — D1/D2 모두 추천 A

### D1. 실패한 시즌의 부분 산출물

추천 A: 실패한 시즌에 이번 등록이 생성한 season/post의 부분 결과를 정리하고 다시 추출·생성한다. 이미 성공한 다른 시즌과 원래 있던 룩북은 보호한다. 원본 source/실패 식별자는 서버 기록에 유지하므로 season 문서가 제거돼도 다시 요청할 수 있다. 이번 시도의 공개 참조를 해제하고 종료/참조해제를 확인한 미참조 Storage 객체는 기존 정책대로24시간 뒤 exact generation 정리한다. 원격 실험의 실제 삭제 대상은 실행안에서 별도로 지정한다. 참조 해제·도메인 정리 완료 전에 새 시즌 처리를 시작하지 않는다.

대안 B: 실패한 시즌의 이미 생성한 post/파일을 유지하고 재추출 결과와 대조해 재사용한다. 재다운로드/업로드를 줄일 수 있지만 이전/새 후보 매핑·개수/순서 차이·부분 결과 병합이 필요하고 사용자가 제외한 중간 복원에 가까워진다.

추천 A의 partial season/post 정리 정책은 확정됐다. 실제 원격 삭제 대상/실행안은 별도로 확인한다. sourceImportJobID뿐 아니라 대상 실행/시도·경로 원장·현재 참조를 함께 확인하고 타 요청 소유/변경/삭제 중 상태가 섞이면 정리하지 않고 차단한다. 기존 정상 A/B·A~J 자료를 정리 대상으로 삼지 않는다. 기존 등록 시즌의 보수/자산 재전송은 기존 계약을 자동으로 처음부터 삭제 정책으로 바꾸지 않는다.

### D2. 검토 승인 이후 비정상 종료

추천 A: 승인 저장 단계에서 실패한 시도도 동일 시즌의 총5회 예산 안에 포함한다. 다시 시작할 때 새 추출 결과에 기존 품질/검토 규칙을 적용하며 검토 필요면 새 snapshot으로 다시 승인받는다. 이전 승인 키를 새로운 이미지 후보에 자동 적용하지 않는다. 검토 대기에서 다음 요청을 진행하고 새 승인은 맨뒤 접수하되 **같은 실행의 남은 시도 예산**을 유지한다. 수동 재시도에서만 새5회를 부여한다.

대안 B: 후보 URL/hash/순서/개수와 검토 snapshot이 정확히 같을 때 이전 승인을 재사용하고 다르면 다시 검토한다. 반복 검토를 줄일 수 있지만 snapshot 동등성·변경 판정과 승인 재사용 계약이 추가된다.

추천 A의 시도 정의: 추출 시작 전에1회 증가, 검토 대기/승인 저장은 그 시도의 후속 단계라 횟수 증가 없음. 승인 저장에서 비정상 종료되면 해당 시도를 실패로 종료하고 다음 추출 시작에서 다음 횟수 증가. 같은 승인 재전달이 횟수 증가/새5회를 만들지 않는다.5번째 시도가 승인 저장에서 실패하면 자동 추출6회는 없다. 실패/검토 대기/성공 집계를 구분한다.

## 4. 데이터/API 제안

### 실패 목록 문서

`brands/{brandID}/seasonImportFailures/{failureID}`. failureID는 브랜드 안의 기존 URL claim 정규화와 동일한 sourceURL의 결정적 hash다. 변형 query를 임의로 지워 다른 룩북을 합치지 않는다. 신규 등록 전 seasonID가 없거나 D1 정리로 없어져도 동일 시즌의 실패 목록 identity를 유지한다.

구현 필드: `sourceURL`, `sourceCandidateID`, `displayTitle`, `state(failed|retryQueued|retrying|awaitingReview)`, `version`(증가 정수), `latestRequestID/latestBatchID/latestJobID/latestExecutionID`, `attemptCount/attemptLimit`, `failureStage/errorCode/errorMessage`, `failedAt/updatedAt/expiresAt`, `originalRequestID`. 서버 검증된 오류만 넣고 내부 credential/token/원문 스택은 외부 응답에 넣지 않는다. ‘최초’와 ‘마지막’ 요청은 의미가 다르며 실패 목록에는 상세 시도 배열을 계속 append하지 않는다.

문서 갱신/제거는 최신 실행 ID+version과 원자적으로 조건을 확인한다. 진행 중 삭제·이전 실행의 늦은 성공·실패·옛 안 함 요청은 새 실패 결과를 바꾸지 못한다. 성공/안 함 제거는 server attempts/runs/원본 receipt/season/file 삭제와 별개다. 재시도 접수가 실패하면 목록을 retryQueued로 먼저 바꾸지 않는다.

### Functions callable 제안

| API | 입력/응답·동작 |
|---|---|
| `getSeasonImportFailures` |brandID, optional cursor. active platformAdmins 서버 검사, brand별 updatedAt/failureID 순100개 이하·nextCursor, 상태/version·현재 실행 정보만 반환. 원본 입력/내부 증거 노출 없음 |
| `requestSeasonImportFailureRetry` |기존 queue envelope(requestID/requestCreatedAt/contractVersion)+brandID/failureID/expectedVersion/expectedExecutionID. 현재failed·실행 종료·같은 URL 활성 실행 없음 검사. 원래 source로 새 manualRetry 실행·새5회·맨뒤 sequence와 목록 retryQueued를 원자 접수. 기존 교정 후 재분석 API의 runtime 조건을 제거하지 않음 |
| `dismissSeasonImportFailure` |기존 request envelope+brandID/failureID/expectedVersion/expectedExecutionID. 현재failed만 제거. 큐에 실행 접수를 넣지 않는 metadata 작업. 같은 requestID receipt를 먼저 확인해 멱등 처리, payload 다르면 충돌. stale version/진행 중/권한 실패 시 제거0. 응답 유실 뒤 재전송이 새로 생성된 실패 문서를 지우지 않음 |

위 metadata 작업의 확인 receipt는 server-only 보관30일이며 기존 신규 요청24시간/미래5분 경계를 재사용한다. 실패 목록 삭제 뒤에도 같은 ID의 결과를 재조회할 수 있도록 하고 상태 만료 뒤 자동으로 새 작업 ID를 만들지 않는다. Firestore 직접 클라이언트 읽기/쓰기 대신 callable로 접근하며 필요한 Rules/index 변화가 있으면 해당 gate를 연결한다. 정확한 index·export 계약은 구현 전 파일 계획에 포함한다.

`getSeasonImportBatch`는 기존 admission failedCount 의미를 유지하고 실행 성공/실패/검토대기/미시작·진행 수 및 결과 항목의 현재 실패 identity/version을 추가한다. 기존 root/job 상태가 이후 수동 재시도로 바뀌어도 원래 batch 결과를 새 실행의 결과로 덮어쓰지 않는다.

## 5. 종료 정산·새 시도 연결안

기존 `/tasks/import-batch`의 재전달 처리와 기존 queue 유지 경로에서 정확한 head/epoch/run/revision의 실제 종료 증거를 확인한다. 증거 조회 helper를 재사용하며 앱/웹 일반 관리자에게 force-release나 임의 복구 권한을 추가하지 않는다. 새 공개 ‘중간 복원’ API는 추가하지 않는다.

종료 확인 후 transaction에서 옛 실행의 쓰기를 차단하고, 당시 active인 시즌 시도를 실패로 기록한다. 완료 item/진행하지 않은 item은 보존한다. 실패 데이터 정리 후 남은 예산이 있으면 같은 순번에서 해당 시즌을 새 시도로 시작하고, 없으면 최종 failed 결과/실패 목록을 남긴다. attempt history/run terminalConfirmed/inFlight 원본을 실제 종료 확인 대신 임의값으로 덮어쓰지 않는다.5회 소진은 종료가 확인된 item의 최종 실패이며 복구 대기로 무한 반복하지 않는다.

Cloud Tasks dispatch 횟수는 시즌 attemptCount와 별개다. 종료 증거를 기다린 재전달·중복 HTTP·claim 거절은 새 시즌 시도로 세지 않는다. SDK 내부 retry도 별도 계층이다. 증거 조회 실패/누락이면 종료 확인 상태를 표시하고 새로운 작업을 시작하지 않는다. 플랫폼 재전달을 즉시라고 보장하지 않는다.

## 6. 변경 파일·순서·필수 검사

1. 계약/데이터/API·required test ID 확정: 이 문서, implementation/server plan·DATA_SCHEMA/ENTRYPOINTS 및 contracts 필요한 범위. D1/D2 결정 기록 전 코드 변경0.
2. Worker 종료 판정/시도·처음부터 재처리: queue coordinator/checkpoint/activation/batch-runner/recovery helper·processor/HTTP 연결. Functions 새 실패 목록 service/callables·신규 실패 수동 접수/준비/projection·export 순차 연결. 동일 계약을 건드리므로 병렬 구현하지 않는다.
3. local tests: fake clock/종료 provider/unit + 실제 Firestore transaction Emulator. 실패 목록 반복 생성0·인가/멱등·version경합/늦은 응답, 자동 총5회/승인 실패 예산/수동새5회·맨뒤, D1 삭제 범위/정리 중 크래시/현재참조·generation 보호, 완료 시즌/미시작 유지, 종료 증거 없는 상태 쓰기0, 같은 실제 종료 정산1회, 처리 실패 수와 접수 실패 수 구분을 필수 gate에 연결한다. 정확한 테스트명과 기존 required ID 유지 여부는 구현 전 고정한다.
4. G-F(Functions)/G-W(Worker)/G-E(제품큐)/Q7 verifier 실행. 프로세스/guard 영향이면 G-L, Rules/indexes 변화면 G-R. UI 없음·Swift/DI/GRDB 변경 없음. 원격와 사람 확인을 local pass로 대체하지 않는다.
5. local 필수 검사 통과 후 짧은 실제 종료·새 시도 실행안 작성. 실제 종료 방법/반복 소진 검증의 local·remote 분담/신규 QA 대상/요청량·전송량·비용을 구체화해 확인하고, 정확한 Development candidate/readback 후 실행한다. 기존4접수/62JPEG 비용은 재사용하지 않는다. Production·새 IAM·증설·기존 QA 삭제 없음.
6. 결과·현행 source digest·원본 로그·미검증과 하네스 갱신. Q7 합의 게이트 완료 후 diff/ignore 문서 범위를 점검해 최종 커밋을 정리한다.

## 현재 상태

[현재 소스 필수 게이트 결과·실패 원본](q7-retry-local-results.md): 제품큐93·Functions324·Worker359·Firestore/Storage131·기존Q7 verifier31·Linux2 통과. [새 짧은 실제 종료/소진/수동 재시도 실행안](q7-retry-development-execution-plan.md)은 고의 종료 방법/8회 범위 확인 전 제안이며 새 원격 실행을 하지 않았다.

D1 부분 산출물 정리·D2 같은 예산/재검토 추천은 사용자 확정·구현 승인됐다. 실패 목록3개 callable/인가·멱등·CAS·기간 정리, Worker checkpoint/부분 정리·새 추출·승인 초기화·총5회 소진, 실행권 transaction 쓰기와 실제 종료 증거 정산을 로컬 구현했다. KR01~11 필수 검사 연결 중이며 이전 단계의 Functions324/Worker359/Firestore131/제품큐87 통과는 이후 변경본의 전체 통과로 재사용하지 않는다. 새 원격 배포·삭제·접수·고의 종료·커밋은 아직0. 남은 순서는 현재 코드 필수 검사→짧은 Development 실행안 확인→실제 종료/재시도 검증→최종 정리다.
