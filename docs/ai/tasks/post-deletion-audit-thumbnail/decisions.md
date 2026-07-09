# Post Deletion Audit Thumbnail Decisions

## D-001. 포스트만 audit thumbnail을 남긴다

상태: 방향 확정

결정:

- 브랜드/시즌 삭제 완료 목록은 이미지 UI를 표시하지 않는다.
- 포스트 삭제 완료 목록은 감사용 저해상도 thumbnail만 표시한다.
- 원본 포스트 이미지는 purge 시 기존 정책대로 삭제한다.

이유:

- 브랜드/시즌은 이름 snapshot만으로 운영자가 대상을 식별할 수 있다.
- 포스트는 제목이 없거나 caption이 비어 있을 수 있고, 이미지가 사실상 식별자다.
- 원본 이미지를 보존하는 것은 영구 삭제 정책과 충돌할 수 있으므로, 운영 식별용 저해상도 snapshot으로 제한한다.

보류한 대안:

- 포스트도 이미지 없이 텍스트 snapshot만 표시한다.
- 이유: caption 없는 포스트는 완료 목록에서 어떤 포스트였는지 알기 어렵다.

재검토 조건:

- 개인정보/콘텐츠 삭제 정책상 audit thumbnail 보존도 허용하기 어렵다고 판단되는 경우.
- 포스트에 안정적인 텍스트 식별자나 public permalink가 생겨 이미지 없이도 충분히 식별 가능해지는 경우.

## D-002. audit thumbnail은 원본 asset prefix와 분리한다

상태: 방향 확정

결정:

- audit thumbnail은 `lookbookDeletionAuditThumbnails/{requestID}/post.jpg` 같은 별도 prefix에 저장한다.
- 브랜드/시즌/포스트 원본 Storage prefix purge 대상과 분리한다.

이유:

- 원본 삭제 정책과 감사 식별 snapshot 보존 정책을 분리해야 한다.
- purge helper가 원본 prefix 삭제를 수행해도 audit thumbnail이 함께 삭제되지 않아야 한다.

## D-003. 기존 purge 완료 포스트는 이미지 복구 대상이 아니다

상태: 확정

결정:

- 이미 purge되어 원본 Storage object가 삭제된 포스트 요청은 audit thumbnail을 backfill하지 않는다.
- 기존 요청은 텍스트 snapshot만 표시한다.

이유:

- 삭제된 Storage object는 접근할 수 없고, 캐시에 의존한 복원은 신뢰할 수 없다.
- QA용 OUTSTANDING `post_0000` 같은 기존 purge 완료 데이터는 이미지 없음이 정상이다.

## D-004. 보존 기간과 thumbnail 세부값은 구현 전 확정한다

상태: 논의 필요

결정 필요:

- 보존 기간: 30일, 90일, 180일 중 선택.
- thumbnail 크기: 긴 변 160px, 200px, 240px 중 선택.
- 포맷: JPEG 고정 또는 WebP 지원.
- cleanup 방식: Storage lifecycle rule 또는 scheduled function.

추천안:

- 90일 보존.
- 긴 변 240px 이하.
- JPEG quality 0.6.
- 초기 구현은 scheduled cleanup보다 Storage lifecycle rule 가능성을 먼저 확인한다.

이유:

- 90일은 운영 확인/CS 대응에는 충분하고, 무기한 보존보다 정책 부담이 작다.
- 240px은 포스트 식별에는 충분하면서 원본 대체물로 쓰기 어렵다.
