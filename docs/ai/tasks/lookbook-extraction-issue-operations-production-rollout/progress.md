# Lookbook Extraction Issue Operations Production Rollout Progress

## 현재 상태

- 2026-08-06 `lookbook-extraction-issue-operations`를 Development 구현·QA 완료로 종료하고 Production rollout을 별도 핵심 task로 분리했다.
- Phase 1 Production 읽기 전용 감사를 완료했고 Phase 2 exact mutation 승인 대기다.
- Production mutation, candidate 배포, IAM/index/TTL/Functions 변경과 traffic 전환은 수행하지 않았다.

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

## 다음 작업

1. Worker no-traffic candidate 생성·검증 범위 승인.
2. candidate 성공 뒤 Worker traffic 전환 별도 승인.
3. backend prerequisite/Functions와 실제 smoke 범위 승인.

## 현재 위험

- 신규 durable discovery Functions를 Worker contract 3보다 먼저 배포하면 호출 계약이 맞지 않으므로 순서를 바꾸면 안 된다.
- Production operator와 신규 private Functions IAM은 아직 없으므로 배포 전 exact resource binding 검증이 필요하다.
- legacy 데이터와 callable은 자동 정리하지 않는다.
