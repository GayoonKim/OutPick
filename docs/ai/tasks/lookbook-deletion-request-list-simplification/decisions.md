# Lookbook Deletion Request List Simplification Decisions

## D-001. 앱 삭제 요청 목록에는 `active/failed`만 표시한다

상태: 확정

결정:

- 총 관리자와 브랜드 owner/admin 삭제 요청 목록에는 `active`와 `failed`만 표시한다.
- `purged`, `cancelled`, `restored`는 앱 목록에서 제외한다.

이유:

- `active`는 복구 가능한 상태이고 `failed`는 운영 대응이 필요한 상태다.
- 종료된 요청은 앱에서 실행할 action이 없으므로 일상 관리 화면의 정보 밀도만 높인다.

## D-002. 총 관리자 전역 목록의 브랜드 grouping은 유지한다

상태: 확정

결정:

- 총 관리자 전역 목록은 현재처럼 브랜드별로 묶는다.
- 브랜드 row를 펼치면 브랜드/시즌/포스트 target별 처리 대상 요청을 표시한다.

이유:

- 전역 요청을 flat list로 표시하면 대상 브랜드의 맥락을 파악하기 어렵다.
- 현재 grouping은 유지하고 완료/history UI만 제거하면 변경 범위가 작고 사용자 흐름이 명확하다.

## D-003. 포스트는 복구 가능 기간에 원본 썸네일로 식별한다

상태: 확정

결정:

- 포스트에는 안정적인 제목이 없으므로 `active/failed` 요청 row에서 기존 원본 thumb path를 이용해 이미지를 표시한다.
- purge 이후 별도 이미지 snapshot을 만들거나 보존하지 않는다.

이유:

- 7일 복구 가능 기간에는 원본 Storage asset이 남아 있어 별도 파생 이미지가 필요하지 않다.
- purge 이후 요청은 앱에서 보이지 않으므로 audit thumbnail의 제품 가치가 사라진다.

## D-004. 삭제 요청 전용 완료/history API 계약을 제거한다

상태: 확정

결정:

- `listLookbookDeletionRequests` 입력의 `status`, `statusGroup`, `processedScope`, `recentProcessedDays`를 제거한다.
- 서버는 `status in [active, failed]`를 고정 적용한다.
- iOS Domain/Repository/Cloud Functions wrapper에서도 삭제 요청용 status group과 processed scope를 제거한다.

이유:

- 앱은 아직 배포되지 않아 구버전 클라이언트 호환이 필요하지 않다.
- 사용하지 않는 완료 조회 계약을 남기면 상태와 테스트 범위가 불필요하게 커진다.

주의:

- 브랜드 등록 요청의 `ProcessedRequestScope`와 보류/완료 이력 조회는 유지한다.

## D-005. 완료 projection과 감사 로그는 서버 운영 이력으로 유지한다

상태: 확정

결정:

- `purged` 상태의 `lookbookDeletionRequests` 문서와 `lookbookDeletionAuditLogs`는 이번 작업에서 삭제하지 않는다.
- 앱 UI에서 숨기는 것과 서버 감사 기록 보존을 분리한다.

이유:

- purge 실패 분석, 운영 사고 확인, 삭제 실행 추적에는 metadata 감사 기록이 필요하다.
- 이번 작업의 목적은 앱의 action 없는 완료 목록을 제거하는 것이지 운영 이력을 파기하는 것이 아니다.

재검토 조건:

- 완료 projection과 감사 로그의 보존 기간을 별도 운영 정책으로 확정할 때 TTL 또는 archive 정책을 검토한다.

## D-006. `post-deletion-audit-thumbnail` 작업을 폐기한다

상태: 확정

결정:

- `post-deletion-audit-thumbnail` task 문서와 하네스 참조를 제거한다.
- audit thumbnail 생성, Storage prefix, 권한, cleanup은 구현하지 않는다.

이유:

- 완료 요청을 앱에서 표시하지 않으므로 purge 이후 포스트 이미지를 식별할 제품 요구가 사라졌다.
- 삭제된 콘텐츠의 파생 이미지를 추가 보존하지 않아 데이터 보존 범위와 운영 복잡도가 줄어든다.

## D-007. 브랜드 등록 요청 UI는 변경하지 않는다

상태: 확정

결정:

- 브랜드 등록 요청의 `새 요청`, `처리 중`, `보류`, `완료` segment와 이전 이력 조회는 유지한다.

이유:

- 브랜드 등록 요청의 완료/보류 이력은 운영 처리 결과이며 삭제 lifecycle과 제품 목적이 다르다.

## D-008. 처리 대상 목록은 하단 sentinel scroll prefetch를 사용한다

상태: 확정

결정:

- `active/failed` 요청은 50개 단위 cursor page로 조회한다.
- 전체 목록 하단의 공통 sentinel `onAppear`에서 다음 page를 자동으로 불러온다.
- 개별 요청 row나 펼친 target row에는 pagination trigger를 두지 않는다.
- append 시 `requestID` 기준으로 중복을 제거한다.
- 서버는 `limit + 1` query로 실제 다음 page가 있을 때만 `nextCursor`를 반환한다.

이유:

- 총 관리자 브랜드 grouping이 접혀 있어도 pagination이 동작해야 한다.
- 별도 `더 보기` 버튼 없이 긴 처리 목록을 자연스럽게 탐색할 수 있다.

## D-009. failed purge는 총 관리자 action으로 즉시 background 재시도한다

상태: 확정

결정:

- 총 관리자에게 `삭제 다시 시도` action을 제공한다.
- callable은 manual retry token을 transaction으로 기록하고 즉시 응답한다.
- Firestore update trigger는 token이 새 값으로 바뀌고 state가 queued일 때만 purge를 즉시 시작한다.
- queued 또는 유효 lease 중복 요청은 새 실행을 만들지 않고 duplicate receipt를 반환한다. lease가 만료된 stale running은 새 retry를 허용한다.
- 브랜드 owner/admin에는 재시도 action을 제공하지 않는다.
- 브랜드 owner/admin은 자동 재시도 대상이거나 queued/running/실행 중이면 `삭제를 다시 처리하고 있습니다.`를 본다.
- 브랜드 owner/admin은 자동/수동 재시도 대상이 아니고 실행 중도 아닌 최종 실패에서 `관리자 확인이 필요합니다.`를 본다.

이유:

- 기존 soft delete API는 대상이 이미 deleted이면 기존 requestID를 duplicate로 반환하므로 새 삭제 요청으로 failed 상태를 해결할 수 없다.
- purge가 부분 진행됐을 수 있어 일반 복구 action은 안전하지 않다.
- callable이 cascade 완료를 기다리면 앱 요청 timeout 위험이 있으므로 background trigger가 실행을 담당한다.

## D-010. scheduled/manual purge는 공통 lease로 동시 실행을 막는다

상태: 확정

결정:

- scheduled purge와 manual trigger는 같은 lease claim helper를 사용한다.
- lease는 Firestore transaction에서 획득하고 15분 동안 유효하다.
- 성공/실패 finalize는 자신의 lease token이 현재 문서 token과 같을 때만 수행한다.
- manual trigger 실패나 timeout에 대비해 `autoRetryEligible = true`, `retryAfter = now`를 기록하고 scheduler fallback을 유지한다.

이유:

- scheduled worker와 manual trigger가 같은 request를 동시에 purge하면 partial cascade와 상태 덮어쓰기 위험이 있다.
- 기존 purge target helper는 idempotent하지만 동시 실행 자체를 허용할 이유는 없다.

## D-011. 제거된 완료 조회 입력은 모든 경계에서 삭제한다

상태: 확정

결정:

- iOS, Repository, Cloud Functions wrapper, Functions parser/query에서 완료 조회 입력을 모두 제거한다.
- deprecated 입력을 별도로 감지하거나 `invalid-argument`로 거부하는 코드는 추가하지 않는다.

이유:

- 앱이 배포되지 않아 구버전 요청을 방어할 필요가 없다.
- 호출 생성부와 파싱부를 함께 제거하는 것이 가장 단순하다.
