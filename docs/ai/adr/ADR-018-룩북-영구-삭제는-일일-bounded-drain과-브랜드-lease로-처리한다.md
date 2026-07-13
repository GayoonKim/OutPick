# ADR-018: 룩북 영구 삭제는 일일 bounded drain과 브랜드 lease로 처리한다

상태: accepted

결정:

- `purgeExpiredLookbookDeletions`는 `Asia/Seoul` 기준 매일 04:00 실행을 유지한다.
- 20개는 active/failed 각각의 query page 크기이며 함수 한 번의 전체 처리량 상한으로 사용하지 않는다.
- `active`와 `failed`는 서로 다른 cursor를 사용한다.
- active query는 `status`, `targetType`, `purgeAfter <= now`를 사용한다.
- failed query는 `status = failed`, `autoRetryEligible = true`, `targetType`, `purgeAfter <= now`, `retryAfter <= now`를 Firestore에서 함께 필터링한다.
- target type은 `brand -> season -> post` 세 pass로 처리한다.
- 같은 target type에서는 `purgeAfter -> requestID` 오름차순으로 처리한다.
- page 요청은 `brandID`별 순차 queue로 묶고 서로 다른 브랜드만 최대 3개 병렬 처리한다.
- 같은 브랜드의 scheduled/manual purge 상호 배제는 `lookbookDeletionPurgeLeases/{brandID}` 15분 lease를 유지한다.
- 실행 후 7분부터 신규 purge claim을 시작하지 않고 이미 시작한 purge는 완료를 기다린다.
- cursor 미소진, 시간 예산 종료 또는 lease skip이 있으면 `hasRemainingCandidates = true`로 보수적으로 기록한다.
- 별도 Cloud Tasks 또는 Cloud Run purge worker는 이번 구조에 추가하지 않는다.

이유:

- 전체 20개 고정 상한은 함수 시간과 처리 여력이 남아 있어도 21번째 요청을 다음 날까지 지연시킨다.
- failed 문서를 limit 후 메모리에서 `retryAfter`로 거르면 미래 retry 문서가 뒤의 eligible 문서를 가릴 수 있다.
- 브랜드, 시즌, 포스트 Storage prefix는 계층적으로 겹치므로 같은 브랜드의 purge를 병렬 실행하면 중복 삭제와 finalize 경쟁 위험이 있다.
- 부모 target을 먼저 purge하면 같은 범위의 하위 요청을 `purged`로 닫아 불필요한 cascade 삭제를 줄일 수 있다.
- 초기 운영 규모에서는 일일 scheduler와 Functions 내부 bounded worker가 별도 queue 인프라보다 단순하다.

트레이드오프:

- 브랜드 요청이 많으면 부모 우선 정책 때문에 더 오래된 시즌/포스트 요청이 다음 실행으로 밀릴 수 있다.
- active/failed query를 target type별로 실행하므로 빈 queue에서도 여러 개의 작은 Firestore query가 발생한다.
- 7분 cutoff는 신규 작업 시작만 막으며 단일 대형 purge의 실제 종료 시간을 보장하지 않는다.
- lease skip은 이번 실행에서 기다리지 않으므로 해당 요청은 manual 실행 완료 또는 다음 일일 scheduler가 이어받는다.
- 합성 QA는 실제 대규모 브랜드의 최악 처리 시간을 완전히 재현하지 못한다.

재검토 조건:

- `hasRemainingCandidates`가 반복적으로 true이거나 backlog가 다음 날까지 남으면 scheduler 주기와 동시 브랜드 수를 재검토한다.
- 실제 대형 브랜드 purge가 540초 timeout에 근접하면 Cloud Tasks, Cloud Run worker, target 단위 checkpoint를 검토한다.
- Firestore read/index 비용이 의미 있게 증가하면 query pass와 index 순서를 Query Explain으로 재검토한다.
- 정확히 7일 경과 시점에 가까운 영구 삭제가 제품 요구가 되면 일일 04:00 스케줄을 재검토한다.

구현·검증 진입점:

- scheduler/query/lease 연결: `functions/src/index.ts`
- 순수 drain orchestration: `functions/src/lookbookDeletionPurgeDrain.ts`
- drain 단위 테스트: `functions/src/lookbookDeletionPurgeDrain.test.ts`
- lease 정책과 테스트: `functions/src/lookbookDeletionPurgeLease.ts`, `functions/src/lookbookDeletionPurgeLease.test.ts`
- query index: `firestore.indexes.json`
- 구현·운영 QA 기록: `docs/ai/tasks/lookbook-deletion-purge-drain/progress.md`, `qa-checklist.md`
