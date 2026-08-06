# Lookbook Extraction Issue Operations Production Rollout Progress

## 현재 상태

- 2026-08-06 `lookbook-extraction-issue-operations`를 Development 구현·QA 완료로 종료하고 Production rollout을 별도 핵심 task로 분리했다.
- Phase 1 읽기 전용 감사, Phase 2 candidate 범위 승인, Phase 3 candidate 검증과 Phase 4 Worker traffic 전환을 완료했다. backend prerequisite/Functions 배포 승인 대기다.
- Production Worker `lookbook-import-worker-00026-qes`를 source `1dbe6e1774686fe8186dc79b9551de779e7c4b60`, contract 3, traffic 100%로 전환했다. `00024-fow`를 rollback revision으로 보존했다.
- Production task/functions service account 두 리소스에 사용자 `gayunkim.1@gmail.com`의 `roles/iam.serviceAccountOpenIdTokenCreator`만 영구 부여했다. index/TTL/Functions/queue와 traffic은 변경하지 않았다.

## 완료

- task 경계, 승인 게이트, 제외 범위와 완료 기준 문서화.
- 이벤트 기반 이미지 extraction QA를 실제 결함 발생 시 운영 게이트로 분리.
- legacy callable/data cleanup을 별도 파괴 승인 작업으로 분리.
- Worker live `lookbook-import-worker-00024-fow` traffic 100%, rollback `00023-879`, Ready 상태와 runtime identity/env를 확인했다.
- live source zip을 직접 확인해 extractor `1.2.3`, Cafe24 adapter `1.0.0`, durable discovery endpoint/runtime contract/source metadata가 없는 레거시 runtime임을 확정했다.
- Production Functions에는 구 diagnostic 2개만 있고 durable discovery 7개와 issue operations 4개는 없다. 배포된 `createBrand` 소스에도 durable discovery job 생성이 없으므로 신규 11개와 `createBrand`를 합친 12개가 exact 배포 대상이다.
- Production에는 `lookbook-discovery-jobs` queue와 `seasonDiscoveryJobs`가 없고 기존 import job 3건은 모두 성공, active/pending job은 0건이다.
- local contract 대비 Firestore field index 3개와 TTL 6개가 없음을 확인했다.
- Production operator service account는 없고 compute/task/Worker IAM 현황과 Worker invoker를 확인했다.
- 2026-08-05 이후 Production Worker/Functions severity ERROR는 0건이다.
- 따라서 queue pause/drain 없이 Worker contract 3 candidate 검증·traffic 전환을 먼저 하고 durable discovery backend/Functions를 뒤에 활성화하는 순서를 확정했다.
- candidate 배포 전 Worker 115/115, lint, fixture 9/9가 통과했다. revision은 Ready이고 env/source/contract/runtime identity와 image digest를 확인했으며 신규 severity ERROR는 0건이다.
- 사용자 승인으로 Production task/functions service account 두 exact 리소스에 좁은 `roles/iam.serviceAccountOpenIdTokenCreator`를 영구 부여했다. IAM Credentials `generateIdToken` 직접 호출만 사용했으며 access token impersonation·signing·key는 만들지 않았다.
- candidate OIDC matrix는 task identity의 `/readyz` 200, import/discovery task 빈 payload 500, runtime 403과 functions identity의 runtime 200, diagnostic 빈 payload 500, import/discovery task 403으로 caller 분리를 확인했다.
- `/runtime-contract`는 Worker `00026-qes`, source `1dbe6e1`, contract 3, extractor `1.2.3`, Cafe24 `1.0.1`과 일치했다.
- 기존 Production 해칭룸 성공 import job의 실제 URL로 `seasonImageImport` smoke가 HTTP 200, 후보 12개, logic issue false, failure 0이었다.
- 기존 Production 해칭룸 archive URL의 실제 discovery diagnostic은 HTTP 200, 후보 20개·목록 대표 이미지 20개, 상세 fallback 0, `passed`, failure 0이었다.
- candidate QA 당시 caller matrix의 의도한 빈 payload 500 세 요청만 Cloud Run request ERROR로 기록됐다. 해당 시점 이후 actual smoke의 unexpected ERROR는 0건이고 import queue pending도 0건이었으며 당시 live traffic은 `00024-fow` 100%였다.
- traffic 전환 직전 candidate Ready, live `00024-fow` 100%, queue pending 0, actual smoke 이후 unexpected ERROR 0을 재확인하고 `00026-qes=100`만 적용했다.
- 전환 후 canonical service URL의 `/readyz`, `/runtime-contract`, 해칭룸 실제 `seasonImageImport` smoke가 모두 HTTP 200이었다. runtime은 `00026-qes`·source `1dbe6e1`·contract 3·extractor `1.2.3`·Cafe24 `1.0.1`, 후보 12개·logic issue false·failure 0이었다.
- 최종 traffic `00026-qes` 100%, import queue pending 0, 전환 검증 시작 이후 severity ERROR 0을 확인했다. `00024-fow`는 traffic 0% rollback으로 유지한다.

## 다음 작업

1. backend prerequisite/Functions exact mutation 범위 승인.
2. `lookbook-discovery-jobs`, Firestore field override 9개와 Production operator/minimum IAM 적용.
3. Function 12개 배포와 live contract·queue·ERROR 검증.
4. 실제 Production end-to-end smoke 대상과 데이터 정리 범위 승인.

## 현재 위험

- 신규 durable discovery Functions를 Worker contract 3보다 먼저 배포하면 호출 계약이 맞지 않으므로 순서를 바꾸면 안 된다.
- Production operator와 신규 private Functions IAM은 아직 없으므로 배포 전 exact resource binding 검증이 필요하다.
- 영구 OIDC binding은 두 exact runtime service account identity로 Worker endpoint를 호출할 수 있으므로 사용자 Google 계정 MFA/passkey와 계정 보안에 의존한다. 운영 구조가 바뀌면 전용 QA identity로 분리한다.
- legacy 데이터와 callable은 자동 정리하지 않는다.
