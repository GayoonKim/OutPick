# Post Deletion Audit Thumbnail Design

## 목표

포스트 삭제 요청이 영구 삭제(`purged`)된 뒤에도 운영자가 “어떤 포스트가 삭제되었는지” 식별할 수 있도록, 포스트에 한해서 감사용 저해상도 썸네일 snapshot을 남긴다.

핵심 목표는 다음과 같다.

1. 브랜드/시즌 완료 목록은 이미지 UI를 표시하지 않는 현재 정책을 유지한다.
2. 포스트 완료 목록만 감사용 저해상도 썸네일을 표시한다.
3. 원본 포스트 이미지와 기존 Storage asset은 purge 시 계속 삭제한다.
4. 감사용 썸네일은 원본 보존이 아니라 운영 이력 식별용 제한 snapshot으로 분리한다.
5. 신규 포스트 삭제 요청부터 audit thumbnail을 생성하고, 이미 purge된 기존 요청은 이미지 복원이 불가능함을 명확히 한다.

## 요구사항 정리

- 포스트 삭제 완료 목록에서 운영자가 삭제된 포스트를 시각적으로 식별할 수 있어야 한다.
- 브랜드/시즌 삭제 완료 목록은 이미지 없이 텍스트 snapshot만 표시한다.
- 포스트 삭제 완료 목록은 원본 이미지가 아니라 별도 audit thumbnail만 표시한다.
- audit thumbnail은 원본보다 작고 강하게 압축된 파일이어야 한다.
- 원본 Storage path는 purge 시 기존 정책대로 삭제한다.
- audit thumbnail은 deletion request projection과 연결되어야 한다.
- audit thumbnail이 없는 기존 요청은 이미지 없이 표시한다.
- 포스트 식별 보조 정보로 `brandName`, `seasonTitle`, `postCaption`, `postID`, 요청/완료 시각을 함께 보여준다.
- audit thumbnail 접근 권한은 삭제 요청 목록을 볼 수 있는 관리자 권한과 동일하거나 더 좁아야 한다.
- audit thumbnail 보존 기간과 자동 삭제 정책은 구현 전 확정해야 한다.

## 구현 디테일 정리

### 핵심 구조

- 삭제 요청 문서 또는 응답 projection에 `postImageAuditThumbPath`를 추가한다.
- 포스트 삭제 요청 생성 시점에 감사용 thumbnail을 별도 Storage path로 저장한다.
- Storage path 예:
  - `lookbookDeletionAuditThumbnails/{requestID}/post.jpg`
- purge 시 원본 브랜드/시즌/포스트 Storage prefix는 삭제하지만, `lookbookDeletionAuditThumbnails/` prefix는 원본 삭제 대상에서 제외한다.
- `listLookbookDeletionRequests`는 포스트 요청에 한해 `postImageAuditThumbPath`를 응답에 포함한다.
- iOS 삭제 완료 목록은 `request.status == .purged && request.targetType == .post`이고 audit thumb path가 있을 때만 이미지를 표시한다.
- 브랜드/시즌 완료 row는 계속 이미지 UI를 표시하지 않는다.

### 생성 시점

추천안:

- 포스트 삭제 요청 생성 시점에 audit thumbnail을 만든다.
- 이유:
  - purge 시점에는 원본 post 문서나 Storage asset이 이미 일부 손상/누락되었을 수 있다.
  - 요청 생성 시점이 사용자가 실제로 삭제 대상으로 선택한 상태를 가장 안정적으로 snapshot할 수 있다.
  - purge scheduler의 책임을 영구 삭제에 집중시킬 수 있다.

대안:

- purge 직전에 audit thumbnail을 만든다.
- 장점: 삭제가 실제 확정된 요청만 thumbnail이 생긴다.
- 단점: Storage 원본 누락, retry 실패, scheduler 복잡도 증가가 생긴다.

### 이미지 크기와 포맷

추천안:

- 긴 변 기준 240px 이하.
- JPEG, quality 0.55~0.65.
- 파일 크기 목표는 30KB 이하.

논의 필요:

- 최종 크기: 160px, 200px, 240px 중 선택 필요.
- 포맷: JPEG 고정 또는 WebP 지원 여부 확인 필요.
- 서버 환경에서 사용할 이미지 처리 라이브러리 선택 필요. Functions 런타임에서 `sharp` 사용 가능 여부와 배포 size 영향을 확인한다.

### 보존 기간

추천안:

- audit thumbnail은 삭제 요청 완료 이력보다 긴 운영 확인 기간을 고려해 90일 TTL로 시작한다.
- 90일 이후에는 scheduled cleanup 또는 Storage lifecycle rule 후보로 삭제한다.

논의 필요:

- 보존 기간을 30일, 90일, 180일 중 어떤 값으로 둘지 확정해야 한다.
- Storage lifecycle rule로 처리할지, scheduled function으로 request 문서와 함께 정리할지 결정해야 한다.

### 기존 데이터 처리

- 이미 purge된 기존 포스트 삭제 요청은 원본 Storage object가 없어 audit thumbnail을 생성할 수 없다.
- 기존 요청은 이미지 없이 표시한다.
- 기존 request 문서에 `postImageAuditThumbPath`가 없으면 iOS는 텍스트 snapshot만 보여준다.
- OUTSTANDING QA의 `post_0000`은 기존 purge 완료 데이터이므로 이미지 복구 대상이 아니다.

## 제약 조건 정리

- 삭제 완료 목록 표시를 위해 원본 이미지를 보존하지 않는다.
- audit thumbnail은 포스트에만 적용한다.
- 브랜드/시즌 완료 목록에는 이미지 UI를 되살리지 않는다.
- Storage rules 또는 callable proxy로 관리자 권한 경계를 명확히 해야 한다.
- Functions 변경 시 lint/build와 운영 배포 검증이 필요하다.
- Storage path 또는 Firestore schema 변경 시 `docs/ai/DATA_SCHEMA.md`, `docs/ai/entrypoints/FIREBASE.md`, `docs/ai/entrypoints/LOOKBOOK.md` 갱신이 필요하다.
- 구현 전 보존 기간, 썸네일 크기, 접근 방식은 사용자 확정이 필요하다.

## 완료 기준 정리

- 신규 포스트 삭제 요청 생성 시 audit thumbnail path가 request projection에 저장된다.
- purge 후 원본 포스트 이미지가 삭제되어도 audit thumbnail은 정해진 보존 기간 동안 남는다.
- 삭제 완료 목록에서 포스트 row만 audit thumbnail을 표시한다.
- 삭제 완료 목록에서 브랜드/시즌 row는 이미지 UI를 표시하지 않는다.
- audit thumbnail이 없는 기존 포스트 요청은 이미지 없이 깨끗하게 표시된다.
- 총 관리자와 권한 있는 브랜드 owner/admin만 audit thumbnail을 볼 수 있다.
- 관련 서버/iOS/데이터/운영 문서가 갱신된다.
- Functions lint/build, iOS generic simulator build, Storage 권한 수동 QA 계획이 포함된다.

## 구현 가능성 검증

확인한 진입점:

- `functions/src/index.ts`
  - 포스트 삭제 요청 생성 callable
  - `listLookbookDeletionRequests`
  - `purgeExpiredLookbookDeletions`
- `OutPick/Features/Lookbook/Views/Admin/AdminLookbookDeletionManagementView.swift`
- `OutPick/Features/Lookbook/ViewModels/AdminLookbookDeletionManagementViewModel.swift`
- `OutPick/Features/Lookbook/Domains/Entities/LookbookDeletionRequest.swift`
- `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsLookbookDeletionRepository.swift`
- `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`
- `firestore.rules`
- Firebase Storage rules 위치는 재확인 필요.

가능성 판단:

- 요청 projection에 기존 표시 snapshot 필드가 이미 있으므로 audit thumbnail path 추가는 자연스럽다.
- iOS row는 target type과 status에 따라 이미지 영역을 조건부 표시하도록 좁게 수정 가능하다.
- 서버에서 thumbnail 생성은 원본 Storage object 읽기와 리사이즈 라이브러리 의존성이 필요하므로 Functions build size와 런타임 권한 확인이 필요하다.

## 기술 스택 선정

- iOS: 기존 SwiftUI 관리자 화면 + MVVM + Repository 경계 유지.
- 서버: Firebase Functions callable과 scheduled function 유지.
- 데이터: `lookbookDeletionRequests` projection에 post audit thumbnail path 필드 추가.
- Storage: 별도 audit thumbnail prefix 추가.
- 이미지 처리: Functions에서 `sharp` 사용 후보. 사용 전 package/runtime 호환 확인 필요.
- 테스트: 서버 helper는 unit test 후보, Storage/권한은 수동 QA 후보, iOS는 generic simulator build와 수동 화면 QA 우선.

## 사용자 흐름 점검

### 포스트 삭제 요청 생성

1. 브랜드 owner/admin 또는 총 관리자가 포스트 삭제 요청을 생성한다.
2. 서버가 기존 포스트 이미지 path를 읽는다.
3. 서버가 원본 이미지를 작은 audit thumbnail로 변환한다.
4. 서버가 `lookbookDeletionAuditThumbnails/{requestID}/post.jpg`에 저장한다.
5. 삭제 요청 projection에 `postImageAuditThumbPath`와 텍스트 snapshot을 저장한다.

### purge 완료 후 조회

1. scheduled purge가 7일 복구 가능 기간이 지난 포스트를 영구 삭제한다.
2. 원본 포스트 문서와 Storage asset은 삭제된다.
3. audit thumbnail은 별도 prefix라 삭제되지 않는다.
4. 관리자가 삭제 요청 `완료` 목록에 진입한다.
5. 포스트 row는 audit thumbnail과 텍스트 snapshot을 표시한다.
6. 브랜드/시즌 row는 텍스트 snapshot만 표시한다.

## 화면 설계

- 삭제 요청 완료 목록:
  - 브랜드 row: 이미지 없음.
  - 시즌 row: 이미지 없음.
  - 포스트 row:
    - audit thumbnail이 있으면 54x54 썸네일 표시.
    - audit thumbnail이 없으면 이미지 영역 자체를 표시하지 않음.
    - 제목은 `postCaption` 우선, 없으면 `포스트`.
    - 보조 정보에 브랜드명, 시즌명, postID 일부 또는 요청일을 표시하는 안을 검토한다.
- 처리 중 목록:
  - 기존 이미지 표시 정책을 유지한다.

## API 설계

### 삭제 요청 projection

추가 후보 필드:

- `postImageAuditThumbPath: string | null`
- `postImageAuditThumbCreatedAt: Timestamp | null`
- `postImageAuditThumbExpiresAt: Timestamp | null`

### `listLookbookDeletionRequests` 응답

- `targetType == "post"`일 때 `postImageAuditThumbPath`를 포함한다.
- 클라이언트는 `targetImagePath`보다 audit thumbnail path를 완료 목록 포스트 row에 우선 사용한다.
- 브랜드/시즌 완료 row에는 이미지 path가 있어도 표시하지 않는다.

## 데이터 설계

Firestore:

- `lookbookDeletionRequests/{requestID}`
  - 기존 snapshot 필드 유지.
  - post 요청에만 audit thumbnail metadata 추가.

Storage:

- `lookbookDeletionAuditThumbnails/{requestID}/post.jpg`
  - 원본 asset prefix와 분리한다.
  - lifecycle cleanup 대상 prefix로 별도 관리한다.

보존:

- 원본 콘텐츠 삭제 정책과 audit thumbnail 보존 정책을 분리한다.
- TTL 최종값은 구현 전 확정 필요.

## 코드 아키텍처 설계

- Functions:
  - thumbnail 생성 helper를 삭제 요청 생성 경로에서 호출한다.
  - helper는 원본 path 조회, download, resize, upload, metadata 반환을 담당한다.
  - purge helper는 audit thumbnail prefix를 삭제하지 않는다.
  - cleanup helper 또는 Storage lifecycle은 후속 phase에서 다룬다.
- iOS:
  - `LookbookDeletionRequest` entity에 audit thumbnail path를 추가한다.
  - Repository decoding과 CloudFunctionsManager mapping에 필드를 추가한다.
  - `AdminLookbookDeletionManagementView`에서 `purged + post + audit path 존재` 조건일 때만 이미지 UI를 표시한다.

## 기술적 결정사항 점검

- 확정:
  - 포스트만 audit thumbnail을 남긴다.
  - 브랜드/시즌 완료 목록은 이미지 UI를 표시하지 않는다.
  - 원본 이미지는 purge 시 계속 삭제한다.
  - 기존 purge 완료 데이터는 복원하지 않는다.
- 구현 전 논의 필요:
  - 보존 기간.
  - 썸네일 크기와 포맷.
  - Storage 접근 방식: 직접 Storage rules로 읽기 또는 callable download URL 발급.
  - cleanup 방식: Storage lifecycle rule 또는 scheduled function.

## 최종 문서 생성

이 문서는 다음 구현 전 기준 문서다.

- `docs/ai/tasks/post-deletion-audit-thumbnail/design.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/plan.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/decisions.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/qa-checklist.md`
- `docs/ai/tasks/post-deletion-audit-thumbnail/progress.md`
