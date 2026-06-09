# Phase 11/12 Decisions

## D-023: import 정확도 고정을 retry 구조 개편보다 먼저 진행한다

결정:

- Phase 11은 worker 파서 정확도 개선과 Cloud Run 배포로 둔다.
- Phase 12는 Season Asset Failure Queue 기반 재시도 구조로 둔다.

이유:

- 파서가 잘못된 이미지를 계속 post로 만들 수 있으면, 실패 asset queue를 먼저 도입해도 queue 대상의 정확성이 보장되지 않는다.
- 먼저 새 import가 정확한 post만 생성하도록 고정한 뒤, 부분 실패/재시도 구조를 정리하는 순서가 안전하다.

## D-024: 기존 HATCHINGROOM 데이터 정리 phase는 두지 않는다

결정:

- 사용자가 기존 HATCHINGROOM 관련 Firestore/Storage 데이터를 삭제했으므로 별도 데이터 정리 phase는 두지 않는다.
- Phase 11 검증은 새 import 기준 smoke QA로 진행한다.

이유:

- 남은 오염 데이터가 없다면 dry-run/삭제 스크립트는 불필요한 운영 표면을 만든다.
- 현재 필요한 것은 새 import가 정확한 룩북 이미지만 생성하는지 검증하는 것이다.

## D-025: 실패 asset 재시도는 season 하위 failure queue를 기준으로 한다

결정:

- 새 `retrySeasonAssets` import job 문서를 만들지 않는다.
- `seasons/{seasonID}/assetFailures/{failureID}`를 현재 실패 asset 큐로 사용한다.
- `failureID`는 `postID_mediaIndex_remoteURLHash`처럼 deterministic하게 만든다.
- 성공하면 failure 문서를 삭제하고, 실패하면 같은 문서의 `attemptCount`, `lastErrorMessage`, `lastAttemptAt`을 갱신한다.

이유:

- 사용자는 retry job 이력이 아니라 시즌 이미지가 정상 반영됐는지만 중요하다.
- deterministic failure 문서는 중복 재시도에도 문서가 계속 늘지 않는 idempotent 구조를 만든다.
- 실제 콘텐츠 source of truth인 posts의 `thumbPath/detailPath`와 failure queue가 직접 연결된다.

## D-026: 가져오기 현황은 시즌 단위 상태를 보여준다

결정:

- 가져오기 현황 목록은 원본 `importSeasonFromURL` job만 표시한다.
- 제목은 `seasonTitle/sourceTitle` 또는 실제 season 문서의 `displayTitle`을 우선 사용하고, `targetSeasonID`는 최후 fallback으로만 사용한다.
- 남은 `assetFailures` 개수 기준으로 “이미지 일부 실패 n개”와 재시도 상태를 표시한다.

이유:

- job ID는 관리자에게도 의미가 낮고, 같은 시즌 재시도 이력이 여러 행으로 늘어나는 UX는 혼란스럽다.
- 사용자가 인지해야 할 단위는 “이 시즌 import가 성공했는지, 일부 이미지가 실패했는지”다.
