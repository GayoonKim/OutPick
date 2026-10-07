# 제품 룩북 FIFO Q6 — 로컬 통합 결과

2026-10-06. 제품 큐 Q6의 로컬 통합 구현과 필수 게이트를 완료했다. 사용자가 재확인한 자동 재시도 정책은 **대기 간격 없이 즉시 재시도, 시즌 실행 최초 시도를 포함해 총 5회**다. 이 결과는 로컬·Firestore Emulator·Linux 컨테이너·iOS Simulator 검증이다. Firebase 배포, Cloud Tasks 원격 송신, 실제 Development URL/Storage 요청, IAM 변경, 원격 정리/복구, 실기기 화면 QA는 수행하지 않았다.

## 구현된 통합 경로

- `tools/lookbook-import-worker/src/queue/batch-runner.ts`와 `activation.ts`가 discovery, 일반 import, asset retry, review approval, manual retry, repair analyze/apply의 batch kind를 실행 차례 안에서 활성화한다. 재진입 때 활성화를 반복하지 않으며 batch owner/run epoch가 유효한 경우에만 continuation과 job 상태를 갱신한다.
- asset retry는 원래 job의 실행 이력을 덮지 않고 별도 child job/execution에 연결한다. source claim도 child job을 가리켜 같은 URL의 중복 요청이 pending retry를 발견하게 한다. frozen source digest가 바뀌면 실행하지 않는다.
- `tools/lookbook-import-worker/src/queue/http-deadline.ts`와 `server.ts`는 batch 요청 14분 경계에서 재시도 가능한 HTTP 503 응답을 보내고 기존 처리 promise의 drain을 계속 기다린다. 요청 종료/시간 중단은 새 pipeline admission을 닫는다. 503 재전달이 와도 coordinator owner/epoch fence가 겹친 batch 실행을 막는다. 이는 로컬 handler 동작이지 Cloud Run이 15분 전에 인스턴스를 종료한다는 증거는 아니다.
- `functions/src/lookbook/import/queue/preparation.ts`의 retry claim을 child job 기준으로 정정했다. Worker/Functions Firestore Emulator가 함께 동작할 때 사용할 수 있도록 activation writes는 SDK 간 Timestamp class 결합 없이 `Date`를 쓴다.
- repair apply 계획은 단일 Firestore transaction의 500-write 한도를 넘지 않도록 대상별 유일성 및 최대 496개 post write와 최대 4개 관련 기록을 검증한다.

## 필수 게이트 결과

모든 아래 게이트의 최종 실행은 `passed`이며 필수 검사 0개, skip, 미실행 오류가 없다. 각각의 결과는 해당 digest에서 생성된 실행 원본을 가리킨다.

| Gate | 실행 ID | 결과와 입력 |
|---|---|---|
| G-F Functions | `1791219881139-a8b3805e-5cd4-45d9-ba2c-bc0835fbdd0f` | lint 및 315 tests 통과. digest `5107dbc72451a90c75580ee3329a0ac82037f2dd2779b3a4c8ae5d942c5df049` (269 files). [summary](../../../../output/verification/1791219881139-a8b3805e-5cd4-45d9-ba2c-bc0835fbdd0f/summary.json) |
| G-W Worker | `1791218636572-414dc6f2-7877-49ce-bb61-e33547bc8b4e` | lint/build, 348 tests 및 fixture 통과. digest `f692d092f79be7afcafcade6417755ad48dc0f0fa2d3d184eedfa4f90351b8f6` (230 files). [summary](../../../../output/verification/1791218636572-414dc6f2-7877-49ce-bb61-e33547bc8b4e/summary.json) |
| G-R Firestore/Storage rules | `1791218212558-3bc9e648-9e39-4f6c-8bec-9723cff8ebd7` | rules/storage 131 tests 통과. digest `d29c942caa12ed25e6bcacca13f5e526a60ea8e9e1072305874ae298ac6dc640` (296 files). [summary](../../../../output/verification/1791218212558-3bc9e648-9e39-4f6c-8bec-9723cff8ebd7/summary.json) |
| G-E 제품 queue Emulator | `1791219933737-c998b4e6-f636-4acf-893b-d26dd6661f8a` | Worker/Functions build와 69 Emulator tests 통과. digest `97d5f5c474e4001da973a28815b803be5abf2b2ff8a8a16727094fe073423758` (286 files). [summary](../../../../output/verification/1791219933737-c998b4e6-f636-4acf-893b-d26dd6661f8a/summary.json) |
| G-L Linux | `1791218807410-700c0a3b-dc59-4e47-9a2a-ffefcb696ec7` | Linux 1 CPU/2 GiB에서 Chromium·cgroup·종료/drain 2개 시나리오 통과. digest `a34522d51abc2f10bb6f431deef7d7e53da7cf911b0241b3a8473ed543748f1f` (228 files). [summary](../../../../output/verification/1791218807410-700c0a3b-dc59-4e47-9a2a-ffefcb696ec7/summary.json) |
| G-I iOS | `1791218887251-6bbec0eb-7ff1-499d-b8b8-f57babe5531d` | iOS 26.2 Simulator 28 tests 통과. digest `e659622d33431c727c4da0f401afd794095601db4d936c539c7ad79b0392cf79` (981 files). [summary](../../../../output/verification/1791218887251-6bbec0eb-7ff1-499d-b8b8-f57babe5531d/summary.json) |

G-W의 직접 Worker lint/build도 종료 코드 0으로 실행됐다. lint는 오류 0, 기존 경고 70개였고 build가 통과했다. G-E의 69개 emulator 테스트는 발견 활성화, retry child job/source claim, 실제 review continuation, repair analyze/apply activation을 포함한다. G-I 첫 샌드박스 실행은 Xcode/SwiftPM/CoreSimulator 접근 제한으로 테스트 0개였으며, 같은 필수 게이트를 허용된 로컬 Xcode 환경에서 재실행해 28개가 통과했다. 이 최초 환경 차단은 통과로 계산하지 않았다.

초기 G-F에서 lint title formatting, G-W에서 loopback `listen EPERM`, G-E에서 asset child claim/Timestamp 호환/기대 checkpoint 불일치 및 stale assertion이 발견됐다. 구현/테스트를 보정한 뒤 재실행해 통과시켰다. 완료된 Cloud Tasks dispatch 연결을 과거 상태로 설명하던 `taskService.ts` 주석을 정정한 뒤 G-F/G-E도 갱신했다. 기본 sandbox의 G-E 재실행은 Firestore Emulator loopback port bind(`listen EPERM`, 테스트 0개)로 차단됐고, 허용된 로컬 실행에서 69개가 통과했다. 해당 차단 원본 `1791219896322-444bd807-88c3-4f38-88ef-52ca03822a11`도 보존했다. 현재 코드의 합격 증거는 표의 최신 ID뿐이다.

## 업데이트된 진입점과 결과 문서

- Worker 실행/시간 경계: `tools/lookbook-import-worker/src/queue/{activation,batch-runner,http-deadline}.ts`, `tools/lookbook-import-worker/src/server.ts`.
- Functions 접수/dispatch: `functions/src/lookbook/import/queue/preparation.ts`와 기존 `maintenance-functions.ts`, `functions/src/index.ts` export 연결.
- 실제 Emulator 연결 회귀: `firestore-tests/lookbook-import-queue.emulator.test.mjs`; deadline 회귀: `tools/lookbook-import-worker/src/queue/http-deadline.test.ts`.
- 계약/필수 검사: `verification/lookbook-product-queue.json`의 activation 필수 테스트와 기존 G-F/G-W/G-R/G-L/G-I 설정.
- 데이터/API·코드 탐색 문서: `docs/ai/{ENTRYPOINTS,DATA_SCHEMA}.md`, `docs/ai/entrypoints/{LOOKBOOK,FIREBASE,DATA,TESTS}.md`, `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`.

## 남은 단계 — Q7 Development smoke

Q7의 읽기 전용 기준 대조와 최소 smoke 설계는 [Q7 readiness](product-queue-q7-readiness.md)에 기록했다. 현재 100% Worker traffic은 구 revision `00012-fih`, Q6 Functions queue triggers/callable은 Development에 없고 `requestSeasonImport`은 기본 Worker URI를 가리킨다. queue는 공유 기존 설정이며 조회 때 비어 있었다. Worker candidate/Functions/index 배포와 실제 URL·Firestore·Storage 쓰기는 수행하지 않았다.

한 번짜리 기능 smoke는 A 브랜드 2시즌(2026SS/2025FW) import 중 B 브랜드의 최초 탐색을 접수하고, A의 저장·종료 확인 후 B의 2025SS를 처리하는 안이다. fixture 기준 source fetch 64회/28,241,613 bytes, JPEG write 126개/15,614,243 bytes, verify read 최대126개다. 이는 첫 시도 입력량이며 retry·build·Firestore·external egress까지 포함한 청구 상한이 아니다. 프로젝트 월별 billing 사용량을 읽지 않아 총 USD 비용은 확정할 수 없다.

Q7 원격 smoke는 revision tag·Functions route·필요 index·정확한 QA input을 확인한 뒤 별도 승인 전에는 시작하지 않는다. 남은 실측은 실제 URL/Storage, FIFO 실행·검토/복구 evidence, 503 delivery/drain, remote IAM/legacy path 및 실기기 화면 QA다.
