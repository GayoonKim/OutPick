# Post Deletion Audit Thumbnail QA Checklist

## 설계 검증

- [ ] 포스트만 audit thumbnail을 남기는 정책이 문서화되어 있다.
- [ ] 브랜드/시즌 완료 목록은 이미지 UI를 표시하지 않는다고 문서화되어 있다.
- [ ] 원본 이미지는 purge 시 계속 삭제한다고 문서화되어 있다.
- [ ] 기존 purge 완료 포스트는 이미지 복구 대상이 아니라고 문서화되어 있다.
- [ ] 보존 기간, thumbnail 크기, cleanup 방식의 논의 필요 사항이 분리되어 있다.

## 서버 QA 후보

- [ ] 포스트 삭제 요청 생성 시 audit thumbnail이 생성된다.
- [ ] 브랜드 삭제 요청 생성 시 audit thumbnail이 생성되지 않는다.
- [ ] 시즌 삭제 요청 생성 시 audit thumbnail이 생성되지 않는다.
- [ ] audit thumbnail Storage path가 requestID 기준으로 안정적으로 생성된다.
- [ ] deletion request projection에 `postImageAuditThumbPath`가 저장된다.
- [ ] `listLookbookDeletionRequests`가 post audit thumbnail path를 반환한다.
- [ ] purge 후 원본 post Storage path는 삭제된다.
- [ ] purge 후 audit thumbnail Storage path는 정해진 보존 기간 동안 남는다.
- [ ] thumbnail 생성 실패 시 확정 정책대로 요청 생성 실패 또는 이미지 없는 요청 생성이 동작한다.
- [ ] 권한 없는 사용자가 audit thumbnail을 읽을 수 없다.

## iOS QA 후보

- [ ] 삭제 요청 처리 중 목록은 기존 이미지 표시 동작을 유지한다.
- [ ] 삭제 요청 완료 목록에서 브랜드 row는 이미지 UI를 표시하지 않는다.
- [ ] 삭제 요청 완료 목록에서 시즌 row는 이미지 UI를 표시하지 않는다.
- [ ] 삭제 요청 완료 목록에서 audit thumbnail이 있는 포스트 row만 이미지를 표시한다.
- [ ] 삭제 요청 완료 목록에서 audit thumbnail이 없는 기존 포스트 row는 이미지 UI 없이 표시된다.
- [ ] 포스트 row의 텍스트 snapshot이 브랜드명/시즌명/post caption 또는 fallback을 표시한다.
- [ ] 총 관리자 전역 완료 목록 grouping에서 포스트 audit thumbnail 표시가 깨지지 않는다.
- [ ] 브랜드 owner/admin scoped 완료 목록에서 권한 브랜드의 포스트 audit thumbnail만 표시된다.

## 권장 검증 명령

Functions 변경 시:

```sh
cd functions
npm run lint
npm run build
```

iOS 변경 시:

```sh
xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build
```

배포 전:

```sh
firebase deploy --only functions --project outpick-664ae --non-interactive
```

Storage rules 또는 lifecycle 변경이 있으면 별도 검증 명령을 구현 시점에 확정한다.

## 테스트 설계

테스트 대상:

- Functions audit thumbnail 생성 helper
- `listLookbookDeletionRequests` 응답 mapping
- `LookbookDeletionRequest` decoding
- `AdminLookbookDeletionManagementView` 표시 조건

필요한 테스트:

- post 요청에만 audit thumbnail metadata가 생성되는지 검증한다.
- audit thumbnail path가 없는 legacy 요청이 decoding되는지 검증한다.
- iOS ViewModel 또는 View helper에서 `purged + post + audit path` 조건만 이미지 표시 대상으로 분류하는지 검증한다.

수동 QA 항목:

- 실제 Storage object 생성/삭제/보존 확인.
- Firebase Storage 권한 확인.
- purge 후 완료 목록 표시 확인.

보류할 테스트와 이유:

- SwiftUI snapshot 테스트는 현재 관리자 화면 snapshot 인프라가 없으므로 1차에서는 보류한다.
- 실제 이미지 resize 품질은 자동 테스트보다 QA 데이터 수동 확인이 적합하다.

테스트 실행 여부:

- 설계 문서화 단계에서는 테스트를 실행하지 않는다.
- 구현 단계에서 Functions/iOS 변경 후 lint/build를 우선 실행한다.
