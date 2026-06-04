# Lookbook Import Worker Architecture

## 목적

URL 기반 브랜드/시즌 등록 파이프라인을 Firestore job queue와 Cloud Run worker 중심으로 관리하기 위한 책임 경계를 기록한다.

## 읽는 순서

- 처음 구조를 이해할 때는 이 문서의 `가치 기준`, `책임 경계`, `권장 흐름`을 먼저 본다.
- 실제 코드 진입점은 `docs/ai/entrypoints/FIREBASE.md`의 `Lookbook URL Import Worker` 섹션에서 확인한다.
- 현재 진행 중인 phase와 검증 상태는 `docs/ai/tasks/lookbook-import-worker/progress.md`를 본다.
- phase별 목표와 완료 기준은 `docs/ai/tasks/lookbook-import-worker/plan.md`를 본다.
- Phase 4.5의 Cloud Tasks, lifecycle, fallback, observability 상세 설계는 `docs/ai/tasks/lookbook-import-worker/phase-4-5-design.md`를 본다.
- 기술 선택의 이유와 대안은 `docs/ai/tasks/lookbook-import-worker/decisions.md`를 본다.
- 커밋에 포함할 하네스 문서 판단은 `docs/ai/workflows/IMPLEMENTATION.md`의 하네스 커밋 기준을 따른다.

## 가치 기준

- 서비스 핵심 가치는 사용자가 직접 많은 룩북 콘텐츠를 정리하지 않아도, 브랜드/시즌 룩북을 빠르게 탐색 가능한 앱 콘텐츠로 만나는 것이다.
- URL import worker의 핵심 가치는 URL 입력에서 등록 가능 시즌을 뽑아내고, 각 시즌의 이미지를 추출해 앱에서 탐색 가능한 콘텐츠로 등록하는 것이다.
- 기술 선택 우선순위는 추출 정확도, 처리량/속도, 대량 처리량 제어, 부분 실패 복구, 관측 가능성, 비용 순으로 본다.
- 절대 시간 목표는 네트워크 상태, 외부 사이트 응답, 이미지 크기, Cloud Run 리소스에 크게 좌우되므로 초기 기술 선택의 핵심 기준으로 삼지 않는다.

## 책임 경계

앱:

- 브랜드 생성 입력, 시즌 후보 표시, 선택한 시즌의 `importJobs` 등록, 진행 상태 표시를 담당한다.
- 앱 ViewModel이나 UseCase가 worker HTTP endpoint를 직접 알고 호출하는 구조는 우선 피한다.
- 앱은 Firestore job 등록과 상태 표시 책임에 머문다.

Firestore:

- `seasonCandidates`와 `importJobs`를 import 파이프라인의 내구성 있는 상태 저장소로 유지한다.
- 앱 종료, worker 중단, 네트워크 실패, 재시도, 중복 실행을 견디기 위한 복구 기준이다.

Firebase Functions:

- 긴 import 작업을 직접 수행하지 않는다.
- Firestore import job 생성 또는 queued 상태 변경을 감지해 Cloud Run worker를 깨우는 wake-up 역할을 우선 담당한다.
- wake-up 중복은 허용하되 worker의 claim/idempotency 정책으로 안전하게 처리한다.

Cloud Run worker:

- queued job을 가져와 URL 파싱, 이미지 후보 추출, 시즌/포스트 문서 생성, Storage thumb/detail 업로드, job 상태 갱신을 처리한다.
- batch size, 동시성 제한, retry/backoff, already-synced skip, idempotency를 내부 정책으로 관리한다.
- Cloud Run worker 예정 위치는 `tools/lookbook-import-worker/`다.
- worker는 독립 `package.json`을 가진 Node.js/TypeScript 패키지로 시작한다.
- HTTP server scaffold는 Express를 사용한다.
- Cloud Run의 외부 endpoint는 HTTPS로 노출되고, 컨테이너 내부 Express server는 `process.env.PORT`에서 plain HTTP로 listen한다.

## 권장 흐름

```text
앱 브랜드 생성/시즌 선택
→ Firestore seasonCandidates/importJobs 등록
→ Functions Firestore trigger가 Cloud Run worker wake-up
→ Cloud Run worker가 queued importJobs 처리
→ Firestore seasons/posts와 Storage thumb/detail 갱신
→ 앱이 job 상태와 생성 문서를 표시
```

## 초기 구현 원칙

- Phase 3 scaffold는 실제 Firestore write 없이 health/wake-up endpoint, env validation, Firebase Admin 초기화 경계까지만 만든다.
- `OUTPICK_FIREBASE_PROJECT_ID`는 필수 env로 둔다.
- 로컬 실행은 `GOOGLE_APPLICATION_CREDENTIALS`로 service account JSON을 주입하고, Cloud Run 실행은 attached service account와 Application Default Credentials를 사용한다.
- 코드에는 project ID 기본값, service account 파일 경로, secret을 하드코딩하지 않는다.
- batch size 기본값은 5로 시작한다.
- `/wake`는 payload에 `brandID`/`jobIDs`가 있으면 지정 job을 처리하고, 없으면 queued/retry 가능한 job을 scan한다.
- worker는 같은 job을 중복 처리하지 않도록 Firestore transaction 기반 claim과 `leaseOwner`/`leaseExpiresAt` lease를 둔다.
- lease duration은 5분으로 시작하고, 처리 중 1~2분마다 lease를 연장한다.
- Firestore claim/lease는 초기 구현이며, 대량 운영 큐 기준으로는 Cloud Tasks 기반 dispatch/retry/rate limit 도입을 우선 재검토한다.
- 현재 구현은 `importJobs.status`를 기존 iOS enum이 읽을 수 있는 `queued`, `running`, `parsed`, `success`, `failed` 범위로 유지하지만, 배포 전이라면 더 명확한 lifecycle enum으로 재설계할 수 있다.
- worker의 세부 처리 상태와 부분 실패는 `parseStatus`, `contentStatus`, `assetSyncStatus`에 기록한다.
- 이미 `thumbPath`와 `detailPath`가 있는 post asset은 기본적으로 skip한다.
- 장기 자동 retry/backoff는 초기 구현에서 보류한다.
- 이미지 fetch/upload 같은 일시 실패만 worker 내부에서 짧게 1~2회 즉시 재시도한다.
- 실패 또는 일부 실패는 top-level `status`와 세부 상태/메시지를 함께 남겨 앱 재시도 UI 대상이 되도록 한다.
- 기존 Functions 상태를 읽을 수 있게 호환하고 worker용 상태/필드를 추가한다.
- dry-run은 초기 구현에서 보류한다.
- force resync는 초기 구현에서 보류하고, asset 손상이나 잘못된 path가 확인되면 추가한다.
- 이미지 압축/변환은 처리량과 메모리 효율 때문에 `sharp`를 사용한다.
- URL 파싱은 경량 HTML 파싱을 기본으로 두고, 동적 렌더링 페이지는 Playwright fallback을 후속 후보로 둔다.

## 기술 선택

Express:

- Cloud Run worker는 복잡한 웹 API 서버가 아니라 Functions trigger, Scheduler, Tasks 후보가 깨울 수 있는 작은 HTTP endpoint다.
- Express는 Cloud Run 예제와 운영 사례가 많고, JSON parsing, health check, error handling scaffold가 단순하다.
- Fastify보다 framework 성능은 낮을 수 있지만, 현재 예상 병목은 HTTP framework가 아니라 URL fetch, HTML parsing, 이미지 처리, Firestore/Storage I/O다.
- Node 기본 HTTP는 의존성은 적지만 routing, body parsing, error handling을 직접 관리해야 하므로 초기 worker scaffold에는 비용 대비 이점이 작다.

독립 package:

- Cloud Run worker는 Firebase Functions와 배포 단위, runtime, 의존성이 달라질 수 있으므로 `tools/lookbook-import-worker/`에 독립 package로 둔다.
- `sharp`, HTML parsing, retry 관련 라이브러리처럼 worker 전용 의존성이 Functions package에 섞이지 않게 한다.
- 중복 의존성은 생길 수 있지만, 필요가 확인되면 추후 `packages/lookbook-import-core` 같은 shared package로 공통화한다.

이미지 변환:

- `sharp`는 libvips 기반이라 Node.js 이미지 변환에서 처리량과 메모리 효율이 좋은 편이고, Cloud Run worker에서 thumb/detail asset을 병렬 생성하기에 적합하다.
- 원본 이미지만 저장하는 방식은 구현이 단순하지만 앱 grid 로딩, 네트워크 비용, Storage 비용에 불리하다.
- ImageMagick/GraphicsMagick CLI는 기능은 강하지만 컨테이너 시스템 의존성과 운영 복잡도가 커진다.
- 실제 병목은 변환보다 remote fetch 또는 Storage upload일 수 있으므로 Phase 4.5 이후 처리 시간 분해 관측이 필요하다.

큐/dispatch:

- Firestore transaction lease는 Phase 4 초기 구현의 중복 처리 방지 장치다.
- 대량 이미지 import가 제품 핵심 가치라면 Cloud Tasks를 dispatch/retry/rate limit 계층으로 두고 Firestore는 durable state ledger로 사용하는 구조를 우선 재검토한다.
- Redis lock은 빠르지만 별도 인프라와 Firestore 상태/lock 상태 불일치 위험이 있어 현재 우선순위는 낮다.

HTML 파싱:

- 경량 HTML 파싱은 빠르고 저렴하지만, JavaScript가 실행된 뒤 이미지 DOM이 생기는 동적 렌더링 페이지에서는 실제 사용자가 보는 이미지를 놓칠 수 있다.
- Playwright 기본 사용은 정확도를 높일 수 있지만 Cloud Run CPU/메모리/시간 비용이 커 대량 처리에 불리하다.
- 경량 파싱 실패 또는 저신뢰 케이스만 Playwright fallback을 사용하는 방식이 후속 후보로 적합하다.

인증과 프로젝트:

- worker는 Firestore/Storage에 실제 write를 수행하므로 실행 대상 프로젝트를 명시해야 한다.
- `OUTPICK_FIREBASE_PROJECT_ID`를 필수 env로 두어 실수로 운영 프로젝트에 쓰는 위험을 줄인다.
- service account JSON 경로는 코드나 Git에 남기지 않는다.
- Cloud Run에서는 key file을 배포하지 않고 attached service account를 사용한다.

## 보류한 고도화

- Cloud Scheduler polling recovery.
- Cloud Tasks 기반 dispatch/retry/rate limit.
- Playwright 기반 동적 렌더링 fallback.
- force resync API.
- min instances 기반 cold start 완화.
- job TTL 또는 완료 후 자동 정리.

## 재검토 조건

- `queued`, `processing`, `pending` job이 반복적으로 장시간 남는다.
- 중복 worker 실행이 Firestore write 충돌이나 중복 Storage upload를 만든다.
- 빠른 대량 등록에서 retry 폭주나 처리 지연이 사용자 경험에 영향을 준다.
- worker 운영 비용, cold start, 처리 latency가 제품 요구사항과 충돌한다.
- 대표 URL 샘플에서 원격 이미지 fetch, 이미지 변환, Storage upload 중 특정 단계가 사용자 흐름을 반복적으로 지연시킨다.
