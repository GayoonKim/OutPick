# Phase 11/12 Progress

## 상태

- Phase 11/12는 계획 확정 상태다.
- 구현, Cloud Run 배포, 운영 데이터 삭제는 아직 진행하지 않았다.

## Phase 11: import 이미지 추출 정확도

목표:

- 새 import부터 실제 룩북 본문 이미지로만 post를 생성한다.

다음 작업:

- Phase 11A: worker 파서 수정본 Cloud Run 배포.
- Phase 11A: HATCHINGROOM `product_no=3759`, `3760`, `3761` smoke QA.
- Phase 11B: Cafe24 archive 상세 회귀 테스트를 보강한다.

확정 사항:

- 기존 HATCHINGROOM 관련 Firestore/Storage 데이터는 사용자가 삭제했으므로 별도 데이터 정리 작업은 진행하지 않는다.
- `archive-source-detail` 같은 본문 영역이 있으면 해당 영역을 최우선으로 사용한다.
- zoom/mobile/thumb/detail-info/order/payment/quantity/option 영역은 post 후보로 쓰지 않는다.
- 같은 이미지가 반복되면 canonical URL 기준으로 dedupe한다.

## Phase 12: Season Asset Failure Queue

목표:

- 실패 asset 재시도에서 새 retry import job 문서를 계속 생성하지 않는다.
- 실패 asset만 idempotent하게 재처리한다.

다음 작업:

- Phase 12A: `seasons/{seasonID}/assetFailures/{failureID}` 데이터 모델 도입.
- Phase 12B: Functions 재시도 요청을 새 import job 생성이 아닌 Cloud Task enqueue로 변경.
- Phase 12B: worker가 해당 시즌의 `assetFailures`만 읽어 누락 asset을 재처리하도록 변경.
- Phase 12C: 가져오기 현황을 원본 import job 기준으로 표시하고, 제목은 시즌 이름을 우선 사용한다.
- Phase 12D: 기존 `partialFailed` job의 failure queue는 재시도 버튼을 누르는 시점에 lazy 생성한다.

확정 사항:

- `failureID`는 `postID_mediaIndex_remoteURLHash`처럼 deterministic하게 만든다.
- 성공하면 failure 문서를 삭제한다.
- 실패하면 같은 문서의 `attemptCount`, `lastErrorMessage`, `lastAttemptAt`을 갱신한다.
- 기존 `retrySeasonAssets` 문서는 앱 미운영 상태이므로 삭제할 필요가 없다.
