# Phase 2 iOS Cloud Functions Decisions

## 범위

2026-07-13 사용자 승인으로 Phase 2 설계 결정을 확정한다. 이 결정은 iOS source boundary만 변경하며 Firebase Functions 서버와 배포에는 영향을 주지 않는다.

## D9. 기존 Repository Protocol을 소비자 계약으로 재사용한다

상태: 확정

- Lookbook에는 이미 기능별 Repository Protocol이 존재하므로 같은 method를 가진 `*FunctionsCalling` Protocol을 중복 생성하지 않는다.
- `CloudFunctions*Repository` 구현체가 기능별 Cloud Functions client/adapter 역할을 직접 맡고 공통 transport를 주입받는다.
- Auth와 `BrandAdminSessionStore`처럼 기존 좁은 계약이 없는 소비자에만 capability Protocol을 추가한다.
- pass-through Repository와 별도 Client를 이중으로 만들지 않는다.

선택하지 않은 대안:

- 모든 Repository 뒤에 별도 `Calling Protocol → Client`를 추가하면 wire test 경계는 선명하지만 현재 pass-through 구현이 중복된다.
- manager method마다 Protocol을 만들면 변경 이유와 소비자 단위가 지나치게 잘게 쪼개진다.

## D10. Protocol과 concrete 구현의 granularity를 분리한다

상태: 확정

- 소비자는 자신이 이미 사용하는 Repository Protocol 또는 새 좁은 capability만 본다.
- 공통 primitive decoder와 기능 mapper는 반복되는 wire 변환 단위로 묶을 수 있다.
- 여러 Repository가 같은 mapper를 공유해도 Repository Protocol을 하나의 umbrella protocol로 합치지 않는다.
- 기존 `CloudFunctions*Repository` type 이름은 source churn을 줄이기 위해 유지하며 역할을 feature adapter로 명시한다.

## D11. 공통 transport는 Firebase callable와 primitive decoding만 소유한다

상태: 확정

- `CloudFunctionsTransporting`은 function name과 `[String: Any]` payload를 받아 `[String: Any]`를 반환한다.
- `FirebaseCloudFunctionsTransport`만 FirebaseFunctions SDK와 `asia-northeast3` region을 안다.
- `CloudFunctionResponseDecoder`는 String/Bool/Int/Double/Date/optional/array 같은 primitive 변환만 담당한다.
- Brand, Comment, Import, Deletion 등 Domain entity mapping은 해당 feature adapter/mapper가 담당한다.
- 모든 응답마다 공개 wire DTO를 새로 만들지 않는다.

오류 규칙:

- Firebase callable이 반환한 원본 오류는 wrapping하지 않고 그대로 throw한다.
- 로컬 response shape 오류만 `CloudFunctionsClientError.invalidResponse` 또는 `missingField`로 표현한다.
- 기존 localized description 의미를 유지한다.

## D12. production DI는 명시적으로 조립하되 앱 전체 singleton 정리는 확장하지 않는다

상태: 확정

- `AppCompositionRoot`가 production `FirebaseCloudFunctionsTransport`를 만들고 Lookbook provider와 BrandAdmin capability를 조립한다.
- `LookbookRepositoryProvider.live(transport:)`가 한 transport를 공유하는 기능 adapter들을 만든다.
- `BrandAdminSessionStore`와 `DefaultSocialAuthRepository`는 좁은 capability를 생성자 주입받는다.
- `AppCoordinator` production 경로는 Lookbook provider와 로그인 Repository를 명시적으로 받는다.
- `LoginManager.shared`, `LookbookRepositoryProvider.shared` 등 앱 전체 singleton lifecycle 제거는 이번 Phase 범위가 아니다.
- legacy/preview fallback은 명시적인 `.live()` 또는 fixture factory를 사용하고 manager singleton을 다시 만들지 않는다.

트레이드오프:

- 앱 전체 service locator 정리는 남지만 Cloud Functions giant concrete dependency와 숨은 method-level `.shared` 사용은 제거된다.
- `LoginManager.shared` 전체를 바꾸면 앱 전역 60여 참조가 연쇄 변경되므로 별도 task 근거가 생길 때 재검토한다.

## D13. 사용 중인 iOS callable 38개만 이전한다

상태: 확정

- `discoverSeasonCandidates`, `getLatestLookbookExtractionDiagnostic` manager wrapper는 현재 직접 소비자가 없어 새 adapter에 복제하지 않는다.
- 서버 export는 유지한다.
- 서버에만 있는 `listBrandRequests`, `updateBrandRequestStage`, `resolveBrandRequest`를 iOS에 새로 추가하지 않는다.
- `callHelloUser`와 화면의 직접 호출을 제거한다.
- `defaultFunctions`와 사용되지 않는 transport override도 제거한다.

## D14. wire 계약은 전체 method 기준으로 자동 검증한다

상태: 확정

- 사용 중인 callable 38개의 function name과 payload를 모두 fake transport로 검증한다.
- optional key 생략과 명시적 `NSNull`을 구분해 검증한다.
- 복잡한 Domain mapping, pagination cursor, diagnostic/deletion response를 검증한다.
- Firebase 원본 `NSError`가 wrapping 없이 전달되는지 검증한다.
- transport에 retry, timeout, logging, actor 또는 새 cancellation 정책을 추가하지 않는다.
- 인증·권한·신고·차단·삭제가 포함되므로 Phase 2 완료 전에 targeted tests와 iOS build를 실제 실행한다.

## 범위 밖

- Firebase Functions TypeScript와 callable export 변경.
- Functions 배포 또는 emulator 신규 구축.
- `LoginManager.shared`와 `LookbookRepositoryProvider.shared` lifecycle 전면 제거.
- `CloudFunctionsUserBlockRepository`의 Firestore read 책임 분리.
- ViewModel/UseCase/navigation/UI 구조 변경.
- retry, timeout, 로깅, analytics, 새로운 오류 문구 추가.

## 재논의 조건

- 구현 중 현재 workspace에서 찾지 못한 manager wrapper 소비자가 확인된다.
- 기존 Repository Protocol로 표현할 수 없는 실제 wire-only 재사용 요구가 생긴다.
- Firebase SDK error를 wrapping해야만 하는 제품 요구가 새로 생긴다.
- Phase 2 범위를 넘는 singleton lifecycle 변경 없이는 compile 가능한 DI를 만들 수 없음이 확인된다.
