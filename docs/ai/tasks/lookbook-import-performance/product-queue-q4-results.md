# 제품 룩북 대기열 Q4 — 복구·정기 점검·만료 정리 구현 결과

2026-10-05. Q4의 로컬 구현과 필수 게이트를 완료했다. 이 완료는 Development/Production 배포, IAM 권한 부여, 실제 Worker 복구, 원격 파일 삭제 승인이 아니다. 사용자 결정대로 자동 재시도는 별도 대기 없이 즉시 반복하고 시즌 작업 최초 시도를 포함해 총5회로 제한한다.

## 구현 결과

- Functions `queue/maintenance-functions.ts`는 queue head 변경·batch 준비 완료 이벤트로 head만 전달하고, 5분 reconciliation은 준비 누락·released head 전진·15분 미claim 전달 회수만 수행한다. 경과 시간만으로 실행 owner를 빼앗거나 다른 batch를 시작하지 않는다.
- Worker `queue/recovery.ts`는 프로젝트·Cloud Run service·revision·batch·epoch를 고정해 현재 head/run/state revision, durable drain 또는 정확한 Cloud Logging 종료 증거, 현재 epoch의 `uploading` asset ledger 전체 조회를 검증한다. 다른 환경 target은 Firestore나 Cloud Logging을 조회하기 전에 거절한다. report digest가 현재 상태와 다르면 resume를 거절한다.
- Worker `/recovery/inspect`와 `/recovery/resume`은 별도 `recovery` OIDC caller만 받는다. 전용 service account 환경 설정이 없으면 route는 기본 비활성이다. `scripts/lookbook-import-recovery.mjs`는 gcloud impersonated ID token과 고정 project/service/revision/batch/epoch를 요구하며 force, 삭제, 차례 강제 해제 옵션은 제공하지 않는다.
- 조건부 resume는 동일한 recovery decision ID의 응답 유실 재전송만 멱등 처리한다. unresolved `uploading` ledger는 `unpublished`로 바꾸고 종료 확인 후 24시간 파일 정리 후보로 둔다. run의 `terminalConfirmed`를 꾸며내지 않고 같은 head를 재개한다. 감사 문서는 batch 하위 `recoveryDecisions/{decisionID}`에 90일 보관한다.
- Cloud Logging provider는 exact trace로 request log를 찾고 단일 instance identity를 얻은 뒤 같은 project/service/revision/instance의 `varlog/system` 종료 event를 확인한다. 누락·모호·조회 실패·지원하지 않는 형식은 복구를 허용하지 않는다.
- Asset 정리는 현재 콘텐츠 참조·미종료 실행을 보호하고 terminal `failed/unpublished/replaced` ledger의 정확한 GCS generation만 삭제한다. 연결된 두 JPEG와 Storage precondition을 확인한다. `functions/src/brand/admin/functions.ts::createBrand`의 30일 `brandCreationRequests` 영수증도 같은 정책에 연결했다.
- 일일 기록 정리는 성공 상세 24시간, 최소 batch/brand 생성 영수증 30일, 해결된 실패 상세 30일, 복구 결정 90일을 적용한다. page 100·총5개 비어있지 않은 page·최대500개 기록 변경 또는 120초에 새 처리를 멈춘다. batch 정리는 최대3 page/300건, 브랜드 영수증과 복구 감사에는 각각 최대1 page/100건을 남겨 큰 batch 기록이 두 나머지 종류를 굶기지 않는다. head·진행·검토·복구 상태는 연장 보호한다.
- Functions/Worker queue policy는 `shared/lookbookQueue/contracts.ts`의 동일 제품 계약을 사용한다. 브랜드 feature가 lookbook feature 내부 경로를 직접 import하지 않는다.

## 변경 진입점

- Functions: `functions/src/lookbook/import/queue/{maintenance-functions,record-retention,asset-retention,dispatch}.ts`, `functions/src/lookbook/import/functions.ts`, `functions/src/brand/admin/functions.ts`, `functions/src/index.ts`.
- Worker: `tools/lookbook-import-worker/src/queue/{recovery,cloud-logging-evidence,recovery-cli,coordinator,batch-runner}.ts`, `server.ts`, `oidc-auth.ts`, `config.ts`, `index.ts`; 운영자용 명령은 `tools/lookbook-import-worker/scripts/lookbook-import-recovery.mjs`.
- 규칙·검사: `firestore.indexes.json`, `firestore-tests/lookbook-import-queue.emulator.test.mjs`, `verification/{functions,lookbook-import,lookbook-product-queue,lookbook-queue-linux,firestore}.json`.

## 필수 게이트 증거

공통 Git HEAD `1d67d61faa04984783083971688a7c628df74748`; 각 gate는 미커밋 소스를 자체 digest로 식별한다.

| 게이트 | 결과 | 실제 실행 | source digest / 파일 |
|---|---|---|---|
| G-F `verification/functions.json` | passed | 314 Functions tests, lint 포함 | `9f9055d46fda3f43662cfa27703e94d018e51f8d841bbe6b9038b2ad9b4dd42c` / 268 |
| G-E `verification/lookbook-product-queue.json` | passed | 68 Firestore Emulator tests | `3973aaba7ab1489808a57179c66a95098a7d12797745e613510e64fb6281c900` / 282 |
| G-W `verification/lookbook-import.json` | passed | 347 Worker tests, lint/build/fixture 포함 | `a59cd2306b0f2df2ccdcf2ef914e80cfc2346fbd0f01085cd1c739d3cd61d29a` / 227 |
| G-R `verification/firestore.json` | passed | 131 Firestore/Storage tests | `078c28ba55163381cc071bedcfe161e161f620e6174016b4422f93ced99b14f6` / 295 |
| G-L `verification/lookbook-queue-linux.json` | passed | Linux/amd64 1 CPU·2 GiB 시나리오 2개 | `d8b0c49de28c85114ef85231716f68e4b311dd2e00b7f93dfcf4434747205660` / 225 |

원본 요약은 각각 `output/verification/1791209282584-d438daf9-4d01-4b10-aa84-990ca46cf485/summary.json`, `1791209301168-92159c88-087b-4a51-b386-03fa600d7821/summary.json`, `1791209345170-c79b0a40-968f-4321-a4f0-aa394b6cf2ed/summary.json`, `1791209483839-053eae73-ebd6-47bc-ba83-c4950f73c179/summary.json`, `1791209548822-14101190-711a-415a-8dd3-a8fb0055b227/summary.json`에 있다. G-E의 새 필수 case는 expired brand receipt·recovery audit의 보호, 모든 종류 합산500건 상한과 category별 정리 진행, 환경이 다른 inspect의 no-lookup를 확인한다.

검증 중 최초 G-F `1791209242729-b3592890-9af0-4240-9dfa-58e0316f2b3f`는 brand feature에서 lookbook feature 내부 정책 경로를 직접 import한 아키텍처 계약 위반으로 실패했다. import를 공용 `shared/lookbookQueue/contracts.ts`로 옮긴 뒤 G-F/G-E/G-W/G-R/G-L을 새 digest에서 다시 실행해 통과했다. 앞선 Worker lint 오류도 수정 후 최종 G-W에서 lint와 전체 테스트를 통과했다.

## 아직 실제로 확인하지 않은 범위

- Development/Production에 Functions·Worker를 배포하거나 queue task를 보내지 않았다. 실제 원격 URL 다운로드, Storage upload/delete, Firestore live write를 실행하지 않았다.
- Recovery route 기본값은 off다. 전용 운영자 principal, Cloud Run invoker, Worker runtime의 최소 Cloud Logging 읽기 권한을 부여하거나 검증하지 않았다.
- Cloud Run request log와 `varlog/system`의 실제 instance label·trace 연결 및 종료 문구는 Development 종료 주입으로 검증해야 한다. 이 증거를 찾지 못하면 resume는 계속 거절한다.
- 실제 Worker HTTP 연결 종료 시 취소·drain과 14분 내 응답은 아직 보장하지 않는다. Linux gate는 프로세스·Chromium·OOM 경계 검사이지 Cloud Run/Firestore 통합 복구가 아니다.
- Q5 앱 GRDB/API/상태 표시, Q6 전 진입점·legacy 실행 경로 통합, Q7 승인된 Development 검증과 실기기 QA가 남아 제품 전체 대기열 완료는 아니다.

실제 IAM 변경·배포·원격 데이터 삭제·복구 호출은 하지 않았다.
