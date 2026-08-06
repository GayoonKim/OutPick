# Lookbook Extraction Issue Operations Production Rollout Plan

## 전체 상태

- 상태: Phase 1·2 완료, Phase 3 candidate 생성 완료·OIDC QA 임시 IAM 승인 대기.
- Production mutation: Worker `00026-qes`를 traffic 0% candidate로 생성했다. live traffic·Functions·Firestore·queue·IAM은 변경하지 않았다.

## Phase 1. Production 읽기 전용 감사

목표:

- Worker traffic/revision/runtime, Functions revision/env, IAM, Firestore index/TTL, active job과 queue를 현재 시점 기준으로 확정한다.

변경 범위:

- 없음. Google Cloud/Firebase 읽기 전용 조회와 로컬 문서 기록만 수행한다.

완료 기준:

- 현재 contract, source revision, rollback revision과 exact diff가 정리된다.
- contract cutover의 mismatch window와 queue pause/drain 필요 여부가 결정 가능해진다.

검증:

- Cloud Run/Functions/IAM/index/TTL/queue/log 조회.
- 로컬 전체 test·fixture·lint/build의 최신 증거 확인.

논의 필요 사항:

- 없음. Production이 durable discovery 도입 전 레거시 상태이고 active job/queue backlog가 없어 pause/drain 불필요로 확정했다.

## Phase 2. 배포안·rollback·승인 게이트 확정

목표:

- 변경 resource, 실행 순서, rollback과 실제 smoke 대상을 사용자와 확정한다.

변경 범위:

- task 문서와 배포 체크리스트.

완료 기준:

- IAM/index/TTL/Functions/candidate 범위 승인.
- traffic/canonical contract 전환은 별도 승인 항목으로 분리.

승인 제안 범위:

1. Worker contract 3 no-traffic candidate 생성과 read-only 검증.
2. 별도 확인 뒤 live traffic을 candidate 100%로 전환하고 `00024-fow`를 rollback으로 보존.
3. `lookbook-discovery-jobs` queue, Firestore field override 9개, Production operator와 최소 IAM 생성.
   - index: `seasonDiscoveryJobs.status`, `seasonDiscoveryJobs.extractionIssueFingerprint`, `importJobs.extractionIssueFingerprint`.
   - TTL: `lookbookExtractionIssueAuditLogs.expiresAt`, `lookbookExtractionFixVerificationRuns.expiresAt`, `lookbookExtractionFixReleases.expiresAt`, `seasonDiscoveryJobs.expiresAt`, `candidates.expiresAt`, `reviews.expiresAt`.
4. 다음 Function 12개를 exact target으로 배포.
   - durable discovery: `requestSeasonDiscovery`, `retrySeasonDiscovery`, `cancelSeasonDiscovery`, `resolveSeasonDiscoveryCandidate`, `retrySeasonDiscoveryAfterExtractionFix`, `onSeasonDiscoveryQueued`, `reconcileSeasonDiscoveryJobs`.
   - issue operations: `lookbookExtractionIssueOpsRead`, `lookbookExtractionIssueOpsWrite`, `verifyLookbookExtractionFix`, `reconcileLookbookExtractionFixReleases`.
   - 기존 Function 계약 갱신: `createBrand`.
5. 별도 확정한 Production 브랜드/URL로 실제 discovery·대표 이미지 smoke.

검증:

- 명령 dry-run 또는 describe 결과와 expected diff 대조.

논의 필요 사항:

- Production mutation 승인 필수.

## Phase 3. Production no-traffic Worker candidate

상태: candidate Ready·traffic 0%·로컬 게이트 완료. OIDC caller 경계와 actual smoke는 임시 Production 토큰 생성 권한 승인 대기.

목표:

- Worker contract 3 candidate를 traffic 0%로 준비하고 기존 Production 경로 호환성을 검증한다.

변경 범위:

- 승인된 Worker candidate revision만.

완료 기준:

- candidate Ready, traffic 0%, live `00024-fow`와 rollback `00023-879` 보존.
- `/readyz`, `/runtime-contract`, task/functions caller 경계와 read-only actual smoke 통과.

검증:

- revision/env/source/contract 대조, 신규 ERROR 0.

논의 필요 사항:

- candidate 검증 실패 시 traffic 전환 금지.

## Phase 4. Worker traffic과 backend cutover

목표:

- Worker를 contract 3으로 먼저 전환한 뒤 durable discovery backend와 Functions를 활성화한다.

변경 범위:

- Worker traffic, Firestore field override, discovery queue, 최소 IAM과 승인된 Functions deployment.
- queue pause/resume은 수행하지 않는다.

완료 기준:

- live Worker traffic 100%, Functions/Worker contract 일치, active queue 정상.
- rollback 명령과 이전 revision이 유효하다.

검증:

- live runtime contract, Functions revision/env, queue와 ERROR.

논의 필요 사항:

- traffic/canonical contract 전환 직전 사용자 명시 승인.

## Phase 5. 실제 Production smoke와 종료

목표:

- 실제 대표 URL로 end-to-end 상태를 확인하고 임시 권한을 회수한다.

변경 범위:

- 승인된 smoke 데이터와 임시 IAM 정리.

완료 기준:

- 실제 discovery 결과, 대표 이미지, queue 0, 신규 ERROR 0.
- smoke 데이터 정리 범위를 확인하고 승인된 데이터만 삭제.
- 임시 사용자 IAM 회수.

검증:

- Firestore 결과, 실제 URL, Cloud Tasks, Worker/Functions logs, IAM policy.

논의 필요 사항:

- smoke 대상과 데이터 삭제는 실행 전에 확정한다.
