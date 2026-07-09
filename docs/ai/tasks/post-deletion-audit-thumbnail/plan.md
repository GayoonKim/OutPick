# Post Deletion Audit Thumbnail Plan

## Phase 1. 설계 확정과 하네스 정리

목표:

- 포스트 audit thumbnail 정책을 다음 핵심 작업으로 등록한다.
- 보존 범위, UI 노출 범위, 구현 전 논의 필요 사항을 문서화한다.

변경 범위:

- `docs/ai/tasks/post-deletion-audit-thumbnail/design.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/decisions.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/qa-checklist.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/progress.md`
- `docs/ai/tasks/active.md`
- `docs/ai/ENTRYPOINTS.md`
- `HANDOFF.md`

완료 기준:

- 다음 핵심 작업이 `post-deletion-audit-thumbnail`로 기록된다.
- 구현 전 확정이 필요한 항목이 분리되어 있다.
- 코드 수정 없이 설계 문서가 생성된다.

검증 방법:

- `git diff --check`
- `git status --short`

논의 필요 사항:

- audit thumbnail 보존 기간.
- thumbnail 크기와 포맷.
- Storage 접근 방식과 cleanup 방식.

## Phase 2. 서버 audit thumbnail 생성

목표:

- 신규 포스트 삭제 요청 생성 시 audit thumbnail을 생성하고 deletion request projection에 저장한다.

예상 변경 범위:

- `functions/src/index.ts`
- `functions/package.json`
- `functions/package-lock.json`
- 필요 시 `firestore.rules`
- 필요 시 Storage rules 파일
- `docs/ai/DATA_SCHEMA.md`
- `docs/ai/entrypoints/FIREBASE.md`

완료 기준:

- 포스트 삭제 요청 생성 시 audit thumbnail path가 저장된다.
- 브랜드/시즌 삭제 요청은 audit thumbnail을 생성하지 않는다.
- thumbnail 생성 실패가 삭제 요청 생성 전체를 실패시킬지, 이미지 없이 진행할지 정책이 구현되어 있다.
- purge helper가 audit thumbnail prefix를 원본 asset 삭제 대상으로 포함하지 않는다.

검증 방법:

- Functions `npm run lint`
- Functions `npm run build`
- 신규 포스트 삭제 요청 생성 smoke QA
- Storage path 생성 확인

논의 필요 사항:

- thumbnail 생성 실패 시 요청 생성 실패 vs 경고 로그 후 진행.
- `sharp` 도입 여부와 Functions 배포 크기/호환성.

## Phase 3. 목록 API와 iOS entity 반영

목표:

- 삭제 요청 목록 응답과 iOS 도메인에 audit thumbnail path를 반영한다.

예상 변경 범위:

- `functions/src/index.ts`
- `OutPick/Features/Lookbook/Domains/Entities/LookbookDeletionRequest.swift`
- `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
- `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`
- 관련 테스트 파일

완료 기준:

- `listLookbookDeletionRequests` 응답에 post audit thumbnail path가 포함된다.
- iOS entity/repository가 해당 필드를 decoding한다.
- 기존 요청처럼 path가 없는 경우도 호환된다.

검증 방법:

- Functions lint/build
- iOS generic simulator build
- 가능하면 repository decoding unit test

## Phase 4. iOS 완료 목록 UI 반영

목표:

- 삭제 완료 목록에서 포스트 row만 audit thumbnail을 표시한다.

예상 변경 범위:

- `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`
- 필요 시 `LookbookAssetImageView.swift`
- `docs/ai/entrypoints/LOOKBOOK.md`

완료 기준:

- `purged + post + postImageAuditThumbPath 존재` 조건에서만 이미지가 표시된다.
- `purged + brand/season`은 이미지 UI가 표시되지 않는다.
- `purged + post + audit thumbnail 없음`은 이미지 UI가 표시되지 않는다.
- 처리 중 목록의 기존 이미지 표시 동작은 유지된다.

검증 방법:

- iOS generic simulator build
- 총 관리자/브랜드 owner/admin 수동 QA

## Phase 5. 보존/cleanup 정책 반영과 배포

목표:

- audit thumbnail 보존 기간과 cleanup 방식을 운영에 반영한다.

예상 변경 범위:

- Storage lifecycle 설정 또는 scheduled cleanup function
- `functions/src/index.ts`
- `docs/ai/DATA_SCHEMA.md`
- `docs/ai/entrypoints/FIREBASE.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/progress.md`

완료 기준:

- 보존 기간이 문서와 운영 설정에 반영된다.
- 만료된 audit thumbnail cleanup 경로가 있다.
- 운영 배포 명령과 결과가 기록된다.

검증 방법:

- Functions lint/build
- Storage lifecycle dry-run 가능 여부 확인
- Firebase deploy는 사용자 명시 승인 후 진행

## Phase 6. 최종 QA와 문서 갱신

목표:

- 신규 포스트 삭제 요청부터 purge 완료 목록까지 audit thumbnail 흐름을 검증한다.

예상 변경 범위:

- `docs/ai/tasks/post-deletion-audit-thumbnail/progress.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/qa-checklist.md`
- `docs/ai/ENTRYPOINTS.md`
- `HANDOFF.md`

완료 기준:

- 신규 포스트 삭제 요청에서 audit thumbnail이 생성된다.
- purge 후 원본 이미지는 삭제되고 audit thumbnail은 남는다.
- 완료 목록에서 포스트만 audit thumbnail이 표시된다.
- 기존 purge 완료 포스트는 이미지 없이 정상 표시된다.

검증 방법:

- Functions lint/build
- iOS generic simulator build
- 운영/QA 데이터 수동 smoke QA
