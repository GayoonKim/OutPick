# iOS Cloud Functions Module Design

## 목표

CloudFunctionsManager 전체 의존을 기능별 좁은 Protocol/Client로 교체하고 FirebaseFunctions SDK 호출은 공통 transport 뒤에 둔다.

## 확정 목표 흐름

~~~text
UseCase / Session Store
  → 기존 Repository Protocol 또는 새 좁은 capability Protocol
  → 기능별 Cloud Functions adapter
  → CloudFunctionsTransport
  → FirebaseFunctions SDK
~~~

상세 결정은 [Phase 2 결정](../decisions/phase-2-ios-cloud-functions.md), 변경 파일과 순서는 [Phase 2 구현 계획](../phases/phase-2-ios-cloud-functions.md)을 따른다.

## 공통 transport 책임

- region별 Functions client 보관.
- 함수 이름과 payload 전달.
- 공통 invalid response 오류.
- raw dictionary 반환 또는 공통 primitive decoding.
- 테스트용 transport protocol 제공.

공통 transport에는 브랜드, 댓글, import, 삭제 같은 기능 모델과 정책을 넣지 않는다.

## Protocol과 adapter 경계

- Lookbook은 기존 Repository Protocol을 재사용한다.
- 기존 `CloudFunctions*Repository`가 feature client/adapter 역할을 직접 맡고 transport를 주입받는다.
- Auth에는 `KakaoAuthBridgeCalling`, App 관리자 Store에는 `BrandAdminCapabilitiesCalling`을 추가한다.
- 함수 하나당 Protocol을 만들거나 pass-through Repository와 Client를 중복 생성하지 않는다.
- Protocol은 소비자 단위로 좁게 유지하고 mapper 구현은 기능 응집도에 따라 공유할 수 있다.

## 현재 소비자와 경계 후보

- DefaultSocialAuthRepository: auth token exchange capability.
- BrandAdminSessionStore: brand admin capabilities capability.
- CloudFunctionsBrandStore와 관리자 Repository: brand administration capability.
- BrandRequest/Search Repository: brand request/search capability.
- engagement Repository: lookbook interaction capability.
- comment writing/safety/user block Repository: comment and safety capability.
- season import/discovery/diagnostic Repository: import capability.
- LookbookDeletionRepository: deletion lifecycle capability.

일부 Repository는 manager를 생성자 주입받지만 일부는 `CloudFunctionsManager.shared`를 직접 사용한다. 새 구조에서는 `AppCompositionRoot`와 `LookbookRepositoryProvider.live(transport:)`가 production adapter를 조립한다. 앱 전체 singleton lifecycle 제거는 범위에 포함하지 않는다.

## 현재 직접 호출 문제

RoomListsCollectionViewController.viewDidLoad가 CloudFunctionsManager.shared.callHelloUser를 직접 호출한다.

- View가 Functions wrapper를 직접 호출해 현재 아키텍처 원칙과 맞지 않는다.
- functions/src/index.ts export에는 helloUser가 확인되지 않았다.
- 사용자 승인으로 Phase 2에서 직접 호출과 `callHelloUser` API를 제거한다.

## 모델과 decoding

- 공통 `CloudFunctionResponseDecoder`는 primitive dictionary decoding만 담당한다.
- Brand, request, diagnostic, deletion, comment Domain mapping은 기능별 adapter/mapper가 소유한다.
- 모든 response에 공개 DTO를 추가하지 않는다.
- `NSNull`, NSNumber, millisecond/ISO timestamp 변환을 기존과 동일하게 유지한다.

## 확정 API 범위

- 사용 중인 callable 38개를 이전한다.
- 미사용 `discoverSeasonCandidates`, `getLatestLookbookExtractionDiagnostic` wrapper는 제거한다.
- 서버 전용 callable 3개를 iOS에 추가하지 않는다.
- Firebase 원본 오류를 wrapping하지 않는다.
- retry, timeout, actor, logging 정책을 추가하지 않는다.

## 완료 기준

- CloudFunctionsManager 전체를 주입받는 소비자가 없다.
- View/ViewController direct Functions 호출이 없다.
- 기능별 fake transport로 function name, payload, response mapping을 검증할 수 있다.
- 공통 transport가 feature domain type을 import하지 않는다.
- 사용 중인 callable 38개가 자동 테스트된다.
- 임시 façade와 `CloudFunctionsManager.swift`를 phase 종료 전에 제거한다.
