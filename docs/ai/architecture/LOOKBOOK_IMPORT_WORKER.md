# Lookbook Import Worker Architecture

## 목적

URL 기반 브랜드/시즌 등록 파이프라인을 Firestore job queue와 Cloud Run worker 중심으로 관리하기 위한 책임 경계를 기록한다.

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
- worker는 같은 job을 중복 처리하지 않도록 claim/lease 또는 generation 정책을 둔다.
- 이미 `thumbPath`와 `detailPath`가 있는 post asset은 기본적으로 skip한다.
- 실패는 retry count, first failure, latest failure, next retry 후보를 상태에 남긴다.
- force resync는 초기 구현에서 보류하고, asset 손상이나 잘못된 path가 확인되면 추가한다.

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

인증과 프로젝트:

- worker는 Firestore/Storage에 실제 write를 수행하므로 실행 대상 프로젝트를 명시해야 한다.
- `OUTPICK_FIREBASE_PROJECT_ID`를 필수 env로 두어 실수로 운영 프로젝트에 쓰는 위험을 줄인다.
- service account JSON 경로는 코드나 Git에 남기지 않는다.
- Cloud Run에서는 key file을 배포하지 않고 attached service account를 사용한다.

## 보류한 고도화

- Cloud Scheduler polling recovery.
- Cloud Tasks 기반 큐.
- force resync API.
- min instances 기반 cold start 완화.
- job TTL 또는 완료 후 자동 정리.

## 재검토 조건

- `queued`, `processing`, `pending` job이 반복적으로 장시간 남는다.
- 중복 worker 실행이 Firestore write 충돌이나 중복 Storage upload를 만든다.
- 빠른 대량 등록에서 retry 폭주나 처리 지연이 사용자 경험에 영향을 준다.
- worker 운영 비용, cold start, 처리 latency가 제품 요구사항과 충돌한다.
