# Post Deletion Audit Thumbnail Progress

## 2026-07-09

- 사용자 결정으로 다음 핵심 작업을 `post-deletion-audit-thumbnail`로 등록했다.
- 배경:
  - 삭제 요청 완료 목록에서 브랜드/시즌은 이미지 없이도 이름 snapshot으로 식별 가능하다.
  - 포스트는 caption이 없을 수 있고 이미지가 사실상 식별자라, 완료 목록에서 어떤 포스트가 삭제되었는지 알기 어렵다.
- 확정 방향:
  - 브랜드/시즌 완료 목록은 이미지 UI를 표시하지 않는다.
  - 포스트 완료 목록만 감사용 저해상도 audit thumbnail을 표시한다.
  - 원본 포스트 이미지와 기존 Storage asset은 purge 시 계속 삭제한다.
  - audit thumbnail은 원본 보존이 아니라 운영 이력 식별용 제한 snapshot으로 별도 prefix에 저장한다.
  - 이미 purge된 기존 포스트 요청은 이미지 복구 대상이 아니다.
- 문서 생성:
  - `design.md`
  - `decisions.md`
  - `plan.md`
  - `qa-checklist.md`
- 구현 전 논의 필요:
  - audit thumbnail 보존 기간.
  - thumbnail 크기/포맷.
  - Storage 접근 방식.
  - cleanup 방식.
  - thumbnail 생성 실패 시 삭제 요청 생성 실패 여부.
