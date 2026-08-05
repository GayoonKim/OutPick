# Lookbook Extraction Issue Operations Production Rollout Design

## 1. 요구사항

- Development에서 검증한 extraction issue operations와 season discovery contract 3을 Production `outpick-664ae`에 안전하게 반영한다.
- 배포 전 현재 Production Worker·Functions·Firestore index/TTL·IAM·queue·runtime을 읽기 전용으로 감사한다.
- Worker no-traffic candidate, rollback revision, exact source/runtime contract를 확보한 뒤에만 traffic 전환을 검토한다.
- 실제 Production mutation은 범위별 사용자 명시 승인 뒤에만 수행한다.

## 2. 구현 디테일

- 이번 task는 기존 구현의 배포·환경 계약 검증이 중심이다. 읽기 전용 감사에서 코드 또는 설정 gap이 발견된 경우에만 별도 변경안을 작성하고 사용자 승인을 받는다.
- Worker는 `--no-traffic` candidate로 먼저 만들고 `/readyz`, `/runtime-contract`, OIDC caller 분리, 실제 read-only extraction smoke를 검증한다.
- Production Functions의 exact 배포 목록과 canonical season discovery contract revision은 감사 결과로 확정한다.
- contract 2 Functions와 contract 3 Worker의 전환 중 불일치 가능성을 감사한다. 필요한 경우 queue pause/drain과 active job 0 확인을 포함한 cutover choreography를 별도 승인안으로 제시한다.
- Production operator identity는 key 없이 exact service account resource의 좁은 OIDC ID token 생성 권한만 임시 사용하고 완료 후 회수하는 방향을 우선한다.

## 3. 제약 조건

- Production traffic, Functions, IAM, index/TTL, queue 상태를 사용자 승인 없이 변경하지 않는다.
- Worker traffic 전환과 Functions canonical contract 변경 사이의 불일치 window를 임의로 허용하지 않는다.
- service-account JSON, 장기 key, project-level 광범위 impersonation 권한을 만들지 않는다.
- 기존 callable 삭제, legacy cluster/evidence/data cleanup과 과거 실패 job 자동 재실행은 범위에서 제외한다.
- 기존 앱 화면, MVVM-C, Repository, UseCase, DI, Coordinator는 변경하지 않는다.

## 4. 완료 기준

- Production 사전 상태와 rollback revision, active job/queue 상태가 기록된다.
- 필요한 Worker/Functions/index/TTL/IAM diff가 exact resource 단위로 승인된다.
- Worker candidate가 no-traffic 상태에서 runtime/source/contract/OIDC/smoke 검증을 통과한다.
- 승인된 cutover 뒤 Production Worker와 Functions가 동일 contract를 사용한다.
- 실제 Production 대표 URL smoke가 성공하고 queue backlog와 신규 Worker/Functions ERROR가 0건이다.
- 임시 IAM은 회수되고 Production에 장기 key가 남지 않는다.
- legacy 삭제·cleanup은 수행하지 않았음을 명확히 기록한다.

## 5. 구현 가능성

- Development에서 Worker contract 3, Functions contract 3, 실제 시즌 상세 fallback과 목록 cover 회귀를 검증했으므로 기술적으로 배포 가능하다.
- Production은 현재 contract 2로 기록되어 있어 실제 외부 상태 재확인이 필요하다. revision, traffic, IAM, index/TTL 상태는 감사 전 `재확인 필요`다.
- contract cutover의 무중단 순서는 현재 active job과 queue 상태를 본 뒤 확정해야 한다.

## 6. 기술 스택

- Firebase Functions v2, Firestore index/TTL, Cloud Tasks.
- Cloud Run Worker, revision tag/no-traffic candidate/traffic split.
- Google IAM Credentials `generateIdToken`과 Cloud Run IAM.
- 기존 `scripts/ai/deploy-lookbook-import-worker.sh`, issue operations CLI와 배포 runbook.

## 7. 사용자·운영 흐름

1. Codex가 Production을 읽기 전용 감사한다.
2. exact diff, rollback, cutover 순서와 승인 단위를 사용자에게 제시한다.
3. 사용자가 candidate/IAM/index/Functions 배포 범위를 승인한다.
4. no-traffic candidate와 backend prerequisite를 검증한다.
5. 사용자가 Production traffic/canonical contract 전환을 별도 승인한다.
6. 실제 smoke, queue, ERROR와 rollback 가능 상태를 확인한다.
7. 임시 IAM을 회수하고 task를 종료한다.

## 8. 화면 설계

- 새 화면과 앱 UI 변경은 없다.
- 기존 앱의 `개선 대기/처리 중/다시 가져오기 가능/추가 작업 필요` 계약을 그대로 사용한다.

## 9. API 설계

- 새 API는 추가하지 않는다.
- 기존 private read/write/release Functions, Worker `/runtime-contract`, `/smoke/extraction`, task endpoint 계약을 Production에 배포·검증한다.
- callable 삭제는 이 task에 포함하지 않는다.

## 10. 데이터 설계

- 기존 `lookbookExtractionEvidence`, `lookbookExtractionIssueClusters`, audit/release/runtime registry와 job projection schema를 유지한다.
- 필요한 collection-group index와 TTL만 exact diff로 적용한다.
- legacy 데이터 backfill·migration·cleanup은 하지 않는다.

## 11. 코드 아키텍처

- Worker, Functions, CLI와 iOS의 기존 경계를 변경하지 않는다.
- 배포 orchestration은 기존 runbook과 script를 사용하며, 반복 가능한 검증 gap이 발견된 경우에만 script 보강을 검토한다.

## 12. 기술적 결정사항

- Development 구현 task와 Production rollout task를 분리한다.
- 이벤트 기반 `seasonImageImport fixed → retry → verified`는 실제 결함 발생 시 실행하는 운영 게이트로 유지한다.
- legacy callable/data cleanup은 성공한 rollout 뒤에도 자동 포함하지 않고 별도 파괴 승인 대상으로 둔다.
- Production cutover 순서는 읽기 전용 감사 전 확정하지 않는다.

## 13. 최종 문서

- 결정: `decisions.md`
- phase와 승인 게이트: `plan.md`
- 실행 상태: `progress.md`
- 검증 기준: `qa-checklist.md`
- Worker 배포: `docs/ai/runbooks/LOOKBOOK_IMPORT_WORKER_DEPLOYMENT.md`
- issue operations: `docs/ai/runbooks/LOOKBOOK_EXTRACTION_ISSUE_OPERATIONS.md`

