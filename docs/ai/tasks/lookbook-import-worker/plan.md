# Lookbook Import Worker Plan

## 목표

URL 기반 브랜드/시즌 등록 파이프라인을 Firestore job queue와 Cloud Run worker 중심으로 재정렬한다.

앱은 브랜드 생성, 시즌 후보 표시, 선택한 시즌의 `importJobs` 등록, 진행 상태 표시를 담당한다. Cloud Run worker는 queued import job을 처리해 URL 파싱, 이미지 후보 추출, 시즌/포스트 생성, Storage thumb/detail 업로드, Firestore 상태 갱신을 담당한다.

## 완료된 Phase 요약

- Phase 1 하네스/ADR 정렬: ADR-008, 진입점, 아키텍처, 구현 workflow, task 문서를 Cloud Run worker 방향으로 정렬했다.
- Phase 1.5 하네스 문서 모듈화: `ENTRYPOINTS.md`와 `CODE_ARCHITECTURE.md`를 얇게 유지하고, 세부 문서를 `docs/ai/entrypoints/`와 `docs/ai/architecture/LOOKBOOK_IMPORT_WORKER.md`로 분리했다.
- Phase 2 기존 Functions 변경분 정리: 이전 Functions batch/retry 실험성 변경을 걷어내고 문서 변경 중심 상태로 정리했다.
- Phase 3 Cloud Run worker scaffold: `tools/lookbook-import-worker/`에 Express 기반 Node.js/TypeScript worker scaffold, health/wake endpoint, env validation, Firebase Admin 초기화 경계, Dockerfile을 추가했다.
- Phase 4 Firestore job 처리 구현: worker `/wake`에서 Firestore claim/lease, URL 파싱, 시즌/포스트 생성, Storage asset sync를 연결했다.
- Phase 8 legacy import Functions 정리: Cloud Run worker가 대체한 legacy callable/trigger와 앱 래퍼를 제거했다.
- Phase 9 Playwright fallback: 동적 렌더링 URL 대응을 위한 조건부 Playwright fallback을 구현하고 운영 smoke QA를 완료했다.
- Phase 10 import 병렬 fan-out/처리량/결과 재시도: Phase 10A~10E 구현과 로컬 검증을 완료했고, Phase 10F 운영 설정 체크리스트 확정, 운영 배포, smoke QA까지 완료했다.

## 예정 Phase 요약

- Phase 11 import 이미지 추출 정확도: Cafe24 archive 상세에서 본문 룩북 이미지만 추출하도록 worker 파서를 운영 배포하고 smoke QA한다.
- Phase 12 Season Asset Failure Queue: 기존 retry import job 생성 방식 대신 `seasons/{seasonID}/assetFailures/{failureID}`를 현재 실패 asset 큐로 사용해 실패 asset만 idempotent하게 재처리한다.

## Phase 4: Firestore job 처리 구현

목표:

- queued import job claim, URL 파싱, 시즌/포스트 문서 생성, asset sync, 상태 갱신을 worker에서 처리한다.
- worker `/wake`가 지정 job 또는 queued job scan을 통해 job 하나를 끝까지 처리할 수 있게 한다.
- Phase 4의 기술 선택은 대량 룩북 이미지를 빠르게 앱 asset으로 변환하는 사용자 가치를 기준으로 평가한다.

정책:

- `/wake`는 payload에 `brandID`/`jobIDs`가 있으면 지정 job을 처리하고, 없으면 queued/retry 가능한 job을 scan한다.
- wake 한 번의 batch size 기본값은 5로 시작한다.
- Firestore transaction으로 job을 claim하고 `status`, `leaseOwner`, `leaseExpiresAt` 기반 lease를 둔다.
- lease duration은 5분으로 시작하고, 처리 중 1~2분마다 lease를 연장한다.
- Firestore claim/lease는 Phase 4 초기 구현이며, 대량 운영 큐 기준으로는 Cloud Tasks 기반 dispatch/retry/rate limit 도입을 Phase 5 또는 Phase 5.5에서 재검토한다.
- 기존 Functions 상태(`queued`, `running`, `parsed`, `success`, `failed`)를 읽을 수 있게 호환하고, worker용 상태/필드를 추가한다.
- 현재 구현은 `importJobs.status`를 기존 iOS enum이 읽을 수 있는 `queued`, `running`, `parsed`, `success`, `failed` 범위로 유지하지만, 배포 전이라면 명확한 lifecycle enum으로 재설계할 수 있다.
- 단계별 복구/디버깅 필드는 `parseStatus`, `contentStatus`, `assetSyncStatus`를 사용한다.
- 이미 `thumbPath`와 `detailPath`가 있는 post asset은 skip한다.
- 장기 자동 retry/backoff는 Phase 4에서 구현하지 않는다.
- 이미지 fetch/upload 같은 일시 실패는 worker 내부에서 짧게 1~2회 즉시 재시도한다.
- 실패 또는 일부 실패는 top-level `status`와 세부 상태/메시지를 함께 남겨 앱 재시도 UI 대상이 되도록 상태와 메시지를 남긴다.
- 이미지 압축/변환은 처리량과 메모리 효율 때문에 `sharp`를 사용한다.
- URL 파싱은 경량 HTML 파싱을 기본으로 두고, 이미지 후보 부족/실패가 반복되면 Playwright fallback을 별도 phase에서 검토한다.
- `forceResync`와 dry-run은 Phase 4에서 보류한다.

검증 방법:

- fake Firestore/Storage boundary 또는 test project 기반 테스트.
- 기존 pending/partial job 복구 수동 QA.
- 절대 시간 목표를 두기보다 worker 처리 시간을 `remoteFetch`, `parse`, `transform`, `upload`, `firestoreWrite` 단계로 분해해 병목과 기술 선택 적합성을 확인한다.

논의 필요 사항:

- 없음. Phase 4 세부 정책은 사용자와 논의해 확정했다.

## Phase 4.5: 운영 큐/상태 모델/성능 기준 재설계

목표:

- URL 입력에서 등록 가능 시즌을 뽑고, 각 시즌의 이미지를 추출/등록하는 핵심 가치에 맞게 worker 운영 구조를 재설계한다.
- Phase 5 구현 전 queue/dispatch, job 상태 모델, fallback, 관측성 기준을 확정한다.
- 상세 설계 문서는 `docs/ai/tasks/lookbook-import-worker/phase-4-5-design.md`를 기준으로 한다.

정책:

- Queue는 Firestore scan/lease를 최종 구조로 보지 않고, Cloud Tasks 기반 dispatch/retry/rate limit 구조를 목표 후보로 설계한다.
- Phase 4.5에서는 Cloud Tasks target architecture를 확정하고, 구현은 Phase 5 또는 Phase 5.5 범위로 나눈다.
- 상태 모델은 top-level lifecycle, 현재 phase, 단계별 세부 status를 분리한다.
- 배포 전이므로 기존 iOS enum 호환성보다 명확한 job lifecycle과 사용자/운영자 가독성을 우선한다.
- 성능 기준은 50장 1분 같은 절대 수치로 두지 않는다.
- 성능/관측성은 네트워크 상태, 외부 사이트 응답, 이미지 크기, Cloud Run 리소스에 따라 달라지므로 단계별 병목을 파악하고 기술 선택을 재검토하는 기준으로 사용한다.
- URL 파싱은 경량 HTML 파싱을 기본 경로로 유지하고, 이미지 후보 0개 또는 저신뢰 케이스에만 Playwright fallback을 검토한다.
- Firestore에는 사용자/운영자가 이해할 수 있는 요약 지표와 상태만 저장하고, 상세 단계 로그는 Cloud Logging 중심으로 남긴다.

검증 방법:

- 대표 URL 샘플로 `season discovery`, `image extraction`, `asset sync` 단계별 성공/실패/소요 구간을 수동 smoke QA한다.
- benchmark는 합격/불합격 기준이 아니라 `remote fetch`, `HTML parsing`, `image transform`, `Storage upload`, `Firestore write` 중 병목 위치를 확인하는 자료로 사용한다.

논의 필요 사항:

- 없음. 사용자와 Phase 4.5 방향을 합의했다.

## Phase 5: Cloud Tasks dispatch trigger와 task endpoint

목표:

- Firestore `importJobs` 생성 또는 queued 상태 변경 시 Cloud Tasks에 job 단위 task를 enqueue한다.
- Cloud Tasks가 호출하는 Cloud Run worker task endpoint를 구현한다.

정책:

- Functions는 긴 작업을 하지 않고 Cloud Tasks enqueue만 수행한다.
- Cloud Tasks는 OIDC token으로 IAM 보호된 Cloud Run worker를 호출한다.
- 중복 enqueue는 deterministic task name으로 줄이고, 중복 dispatch는 worker claim/idempotency로 안전하게 처리한다.
- 기존 `/wake`는 수동 복구와 smoke QA용으로 유지한다.
- Phase 5에서는 기존 `queued`/`running`/`parsed`/`success`/`failed` 상태 모델을 유지하고, lifecycle 전환은 Phase 5.5 이후로 둔다.
- 기존 Functions materialize/asset sync trigger는 `dispatchMode == cloudTasks` job을 처리하지 않는다.

검증 방법:

- Functions lint/build.
- Cloud Run worker lint/build.
- Cloud Run 배포 후 importJob 생성 smoke QA.

논의 필요 사항:

- 없음. Cloud Run IAM + Cloud Tasks OIDC 방향으로 확정했다.
- Cloud Scheduler recovery는 Phase 5 범위에서 제외한다.

## Phase 6: 배포 자동화와 운영 QA

목표:

- Cloud Run worker build/deploy 스크립트와 운영 QA 체크리스트를 정리한다.

정책:

- 반복 배포 명령이 확정되면 `scripts/ai`에 배포 스크립트를 추가한다.
- 배포 스크립트는 검증을 먼저 수행하고, 운영 배포는 사용자 승인 후 실행한다.

검증 방법:

- 신규 브랜드 생성.
- 시즌 후보 생성.
- 선택 시즌 import job 생성.
- Cloud Run worker 처리.
- 51개 이상 포스트 시즌의 thumb/detail path 생성 여부 확인.
- SeasonDetail grid에서 fallback 없이 thumb asset 기준으로 표시되는지 확인.

논의 필요 사항:

- 운영 비용과 Cloud Run min instances 설정은 실제 latency 피드백 후 결정한다.

## Phase 7A: lifecycle, retry 계약, URL 보안

목표:

- import job lifecycle을 `queued`, `processing`, `succeeded`, `partialFailed`, `failed`, `cancelled`로 정리한다.
- HTML fetch의 일시적 오류만 Cloud Tasks가 재시도하도록 worker HTTP 계약을 정리한다.
- 공개 인터넷 URL은 허용하되 내부 네트워크와 과도한 응답 크기를 차단한다.

변경 범위:

- Cloud Run worker processor/server와 단위 테스트.
- Functions import job 생성, 중복 판단, dispatch trigger.
- iOS import job entity/DTO와 진행률 집계.
- 관련 아키텍처, 결정, 진행 문서.

완료 기준:

- 신규 코드가 기존 `running`, `parsed`, `success` lifecycle을 기록하거나 호환하지 않는다.
- 일부 asset 실패는 `partialFailed`, 전체 성공은 `succeeded`로 기록된다.
- HTML fetch의 `429`, `5xx`, timeout, 일시적 네트워크 오류가 Cloud Tasks 재시도를 유발한다.
- 마지막 허용 task 시도에서도 실패하면 job이 `retryExhausted` 오류와 함께 `failed`로 닫힌다.
- 영구 실패는 Firestore `failed`로 닫히고 task는 완료된다.
- localhost, private/link-local IP, metadata endpoint, 내부 주소로 향하는 redirect가 차단된다.
- Functions와 worker lint/build, worker 분류 단위 테스트가 통과한다.

검증 방법:

- retryable/business 오류 분류 단위 테스트.
- URL/IP 차단 및 공개 URL 허용 단위 테스트.
- Functions와 worker lint/build.
- 운영 배포는 별도 사용자 승인 후 수행한다.

논의 필요 사항:

- 없음. 사용자와 lifecycle, 공개 URL 정책, retry 범위를 확정했다.

## Phase 7B: 실패 asset 복구와 관리자 현황 화면

목표:

- 브랜드 상세에서 import 진행/부분 실패를 다시 확인할 수 있게 한다.
- 실패 post/media만 대상으로 하는 별도 asset retry job과 API를 제공한다.

확정 정책:

- 성공한 시즌과 이미지는 즉시 노출한다.
- Storage asset 실패 시 기존 원격 URL fallback을 유지하고 관리자에게 실패 상태를 표시한다.
- 진입점은 브랜드 상세의 관리자 메뉴로 둔다.
- 실패 asset 복구는 원본 import job을 다시 파싱하지 않고 `retrySeasonAssets` 별도 job으로 처리한다.
- 동일 원본 job의 `queued`/`processing` retry job은 중복 생성하지 않는다.
- retry 완료 결과는 별도 retry job과 원본 import job 양쪽에 반영한다.
- 관리 화면은 최근 30개 job, 현재 phase, asset 성공/실패 수, 오류 메시지를 표시하고 활성 job이 있으면 polling한다.

완료 기준:

- `requestSeasonAssetRetry` callable이 브랜드 쓰기 권한과 원본 job 상태를 검증한다.
- Cloud Tasks trigger와 Cloud Run worker가 `retrySeasonAssets` job을 처리한다.
- 성공한 asset은 건너뛰고 실패하거나 미완료인 asset만 다시 동기화한다.
- 브랜드 관리자는 브랜드 상세에서 import 현황을 열고 실패 이미지 재시도를 요청할 수 있다.
- 동일 원본 job의 활성 retry가 있으면 서버와 앱 양쪽에서 중복 요청을 막는다.
- Functions/worker lint와 build, worker 단위 테스트, iOS 빌드가 통과한다.

검증 방법:

- worker lifecycle/URL/retry 분류 단위 테스트.
- Functions와 worker lint/build.
- iOS simulator 대상 전체 빌드.
- 운영 배포 후 실제 부분 실패 job으로 asset retry smoke QA.

논의 필요 사항:

- 없음. 구현 범위와 복구 정책을 사용자와 확정했다.

## Phase 11: import 이미지 추출 정확도

목표:

- 새 import부터 실제 룩북 본문 이미지 노출 정확도를 높인다.

변경 범위:

- Cloud Run worker 이미지 후보 추출 규칙.
- 파서 회귀 테스트.

확정 정책:

- Cafe24 `archive-detail` 페이지에서 `archive-source-detail` 같은 본문 영역이 있으면 해당 영역만 이미지 후보로 사용한다.
- `detail-info`, `order`, `payment`, `quantity`, `option`, `thumb`, `zoom`, mobile/desktop 복제 영역은 post 후보로 쓰지 않는다.
- 같은 이미지가 여러 영역에 반복되면 canonical URL 기준으로 dedupe한다.
- 기존 HATCHINGROOM 관련 Firestore/Storage 데이터는 사용자가 삭제했으므로 별도 정리 작업은 진행하지 않는다.

완료 기준:

- HATCHINGROOM `product_no=3759`, `3760`, `3761`에서 현재 파서가 본문 룩북 이미지만 추출한다.
- Cloud Run worker 수정본이 배포되어 새 import부터 정확한 post만 생성된다.

검증 방법:

- worker `npm test`.
- Cloud Run worker 배포 후 HATCHINGROOM URL smoke QA.

논의 필요 사항:

- 없음. 기존 HATCHINGROOM 데이터 정리는 사용자가 이미 완료했다.

## Phase 12: Season Asset Failure Queue 기반 실패 asset 재시도

목표:

- 실패 asset 재시도 시 새 `retrySeasonAssets` import job 문서를 계속 만들지 않는다.
- 실제 콘텐츠 source of truth인 `seasons/{seasonID}/posts/{postID}`와 현재 실패 큐인 `seasons/{seasonID}/assetFailures/{failureID}`를 기준으로 재시도한다.

변경 범위:

- `seasons/{seasonID}/assetFailures/{failureID}` 데이터 모델.
- Functions 재시도 요청/Cloud Tasks enqueue 흐름.
- Cloud Run worker 실패 asset 재처리 흐름.
- 가져오기 현황 UI.

확정 정책:

- failure 문서 ID는 deterministic하게 만든다. 예: `postID_mediaIndex_remoteURLHash`.
- asset sync 실패 시 failure 문서를 생성하거나 갱신한다.
- 성공하면 failure 문서를 삭제한다.
- 실패하면 같은 문서의 `attemptCount`, `lastErrorMessage`, `lastAttemptAt`을 갱신한다.
- 재시도 요청은 새 retry import job을 만들지 않고 `brandID + seasonID/sourceJobID` 기준 Cloud Task만 enqueue한다.
- worker는 해당 시즌의 `assetFailures`만 읽고, post의 `media.thumbPath/detailPath`, `assetSyncStatus`를 갱신한다.
- 원본 import job summary는 season/posts와 남은 failure 수 기준으로 갱신한다.
- 기존 `retrySeasonAssets` job은 앱 미운영 상태이므로 삭제 필요가 없고, UI에서도 숨긴다.
- 기존 `partialFailed` job의 failure queue는 재시도 버튼을 누르는 시점에 lazy 생성한다.

완료 기준:

- 동일 시즌을 반복 재시도해도 import job 문서가 늘지 않는다.
- 실패 asset만 재처리되고 이미 성공한 asset은 skip된다.
- 가져오기 현황은 원본 `importSeasonFromURL` job만 표시한다.
- 가져오기 현황 제목은 job ID가 아니라 `seasonTitle/sourceTitle` 또는 실제 season `displayTitle`을 우선 표시한다.
- 남은 `assetFailures` 개수 기준으로 “이미지 일부 실패 n개”와 재시도 상태를 표시한다.

검증 방법:

- Functions lint/build.
- worker lint/build/test.
- iOS build.
- 부분 실패 job으로 재시도 smoke QA.

논의 필요 사항:

- 없음. 기존 retry job 삭제는 불필요하고, 기존 partialFailed queue 생성은 lazy 생성으로 확정했다.
