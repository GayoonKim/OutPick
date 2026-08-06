# Lookbook Extraction Issue Operations Production Rollout Decisions

## D-001. Development 구현 task와 Production rollout을 분리한다

- `lookbook-extraction-issue-operations`는 구현과 Development QA 완료로 종료한다.
- Production 외부 상태와 승인 이력은 이 task에서 별도로 관리한다.

## D-002. Production 변경은 단계별 명시 승인을 받는다

- 읽기 전용 감사는 바로 수행할 수 있다.
- IAM/index/TTL/Functions/candidate 배포와 Worker traffic/canonical contract 전환은 감사 결과를 제시한 뒤 승인받는다.
- traffic 전환은 no-traffic candidate 검증 뒤 별도 승인한다.

## D-003. legacy 삭제와 cleanup은 rollout에 포함하지 않는다

- 기존 callable 삭제, legacy cluster/evidence/data cleanup, 과거 실패 job 재실행은 별도 승인 작업이다.
- rollout 성공을 cleanup 승인으로 해석하지 않는다.

## D-004. 이벤트 기반 이미지 extraction QA는 상시 운영 게이트다

- 실제 `seasonImageImport` 로직 결함과 상위 runtime이 생겼을 때만 `open → fixed → retry success → verified`를 실행한다.
- 시스템 QA를 위해 가짜 실패나 가짜 fixed 상태를 만들지 않는다.

## D-005. Production 인증은 key 없이 exact resource의 최소 권한을 사용한다

- exact Production operator/service account resource에 OIDC ID token 생성에 필요한 최소 권한만 사용한다.
- 서비스 계정 key와 project-level 광범위 binding을 만들지 않는다.
- 1인 운영자인 사용자 `gayunkim.1@gmail.com`에는 반복 QA를 위해 task/functions service account 두 리소스의 `roles/iam.serviceAccountOpenIdTokenCreator`만 영구 유지한다.
- 이 역할은 `generateIdToken` 직접 호출에만 사용하고 access token·signing·일반 `roles/iam.serviceAccountTokenCreator`로 확장하지 않는다.
- 운영자 계정 변경, 운영 인력 추가, CI 전환 또는 계정 보안 사고 시 영구 binding을 재검토한다.

## D-006. contract cutover는 queue와 active job을 먼저 감사한다

- 감사 결과 Production은 contract 2가 아니라 durable discovery 도입 전 레거시 상태다.
- discovery queue·durable job이 없고 import queue pending도 0건이므로 pause/drain은 하지 않는다.
- 기존 diagnostic/import 경로와 호환되는 Worker contract 3을 먼저 전환한 뒤 durable discovery Functions를 활성화한다.

## D-007. Phase 1 exact diff를 승인 단위로 분리한다

- Worker candidate 생성과 검증, Worker traffic 전환, backend prerequisite/Functions 배포, 실제 smoke를 각각 관찰 가능한 게이트로 둔다.
- Firestore는 local contract의 composite index 1개와 field override 9개(필드 index 3개, TTL 6개)를 exact diff로 적용한다. 최초 감사에서 누락된 `candidates(resolution, sortIndex)` composite는 실제 iOS review/published candidate 쿼리에 필수이므로 backend prerequisite에 포함한다.
- discovery queue는 Development 검증값인 동시 실행 1, 초당 1, 최대 3회, 30~300초 backoff, retry duration 1시간으로 생성한다.
- Production operator `outpick-extraction-ops-prod@outpick-664ae.iam.gserviceaccount.com`은 현재 없으므로 생성과 최소 OIDC/invoker IAM을 별도 승인 resource로 둔다.
- 신규 durable discovery/issue operations Function 11개와 초기 job 생성을 연결하는 기존 `createBrand` 재배포를 합쳐 Function 12개를 exact target으로 둔다.
