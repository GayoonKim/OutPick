# Phase 2 iOS Cloud Functions Implementation Plan

## 상태

- 설계: 확정.
- 코드 구현: 완료.
- 테스트/빌드 실행: targeted test 9개 묶음과 generic Simulator build 통과.
- 서버 변경·배포: 범위 밖.

## 목표

`CloudFunctionsManager`의 사용 중인 callable 38개를 공통 transport와 기능별 adapter로 이전하고 manager 및 직접 singleton 호출을 제거한다. callable 이름, payload, response mapping, Firebase 오류 의미는 유지한다.

## 목표 흐름

```text
View / ViewModel
  → UseCase / Store
  → 기존 Repository Protocol 또는 좁은 capability Protocol
  → 기능별 CloudFunctions adapter
  → CloudFunctionsTransporting
  → FirebaseFunctions SDK
```

## 예상 변경 파일

### 1. 공통 transport/core — 새 파일

| 파일 | 책임 |
| --- | --- |
| `OutPick/DB/Firebase/CloudFunctions/Core/CloudFunctionsTransporting.swift` | fake 가능한 callable transport 계약 |
| `OutPick/DB/Firebase/CloudFunctions/Core/FirebaseCloudFunctionsTransport.swift` | `asia-northeast3` FirebaseFunctions SDK 호출과 원본 오류 전달 |
| `OutPick/DB/Firebase/CloudFunctions/Core/CloudFunctionResponseDecoder.swift` | primitive required/optional/`NSNull`/NSNumber/date decoding |
| `OutPick/DB/Firebase/CloudFunctions/Core/CloudFunctionsClientError.swift` | 로컬 invalid response와 missing field 오류 |

### 2. 인증 capability

새 파일:

- `OutPick/Features/Login/Protocols/KakaoAuthBridgeCalling.swift`
- `OutPick/Features/Login/Repository/CloudFunctionsKakaoAuthBridgeClient.swift`

수정 파일:

- `OutPick/Features/Login/Repository/DefaultSocialAuthRepository.swift`
- `OutPick/Features/Login/Presentation/LoginCompositionRoot.swift`
- `OutPick/Features/Login/Application/LoginManager.swift`
- `OutPick/Features/MyPage/Controller/MyPageViewController.swift`

규칙:

- `DefaultSocialAuthRepository`는 bridge capability를 주입받는다.
- 로그인 화면 production 경로는 `AppCoordinator`가 Repository를 전달한다.
- `LoginManager.shared` lifecycle은 유지하되 내부 live Repository 생성은 명시적 factory를 사용한다.

### 3. 앱 관리자 capability

새 파일:

- `OutPick/App/CloudFunctions/BrandAdminCapabilitiesCalling.swift`
- `OutPick/App/CloudFunctions/BrandAdminCapabilitiesCloudFunctionsClient.swift`

수정 파일:

- `OutPick/App/BrandAdminSessionStore.swift`
- `OutPick/App/AppCompositionRoot.swift`
- `OutPick/App/AppCoordinator.swift`
- `OutPick/Features/Lookbook/Views/LookbookHome/LookbookHomeView.swift`

규칙:

- `BrandAdminSessionStore`는 concrete manager 대신 capability를 받는다.
- 기존 500ms retry와 MainActor 상태 전이를 유지한다.
- preview는 live Functions 대신 명시적 preview fake를 사용한다.

### 4. Lookbook 기능 adapter — 기존 파일 수정

브랜드/요청:

- `CloudFunctionsBrandStore.swift`
- `CloudFunctionsBrandSearchRepository.swift`
- `CloudFunctionsBrandRequestRepository.swift`

상호작용:

- `CloudFunctionsBrandEngagementRepository.swift`
- `CloudFunctionsSeasonEngagementRepository.swift`
- `CloudFunctionsPostEngagementRepository.swift`
- `CloudFunctionsCommentEngagementRepository.swift`

댓글/안전:

- `CloudFunctionsCommentWritingRepository.swift`
- `CloudFunctionsCommentSafetyRepository.swift`
- `CloudFunctionsUserBlockRepository.swift`

시즌 import:

- `CloudFunctionsSeasonImportRepository.swift`
- `CloudFunctionsSeasonImportJobRequestingRepository.swift`
- `CloudFunctionsSeasonAssetRetryRepository.swift`
- `CloudFunctionsSeasonCandidateDiscoveryRepository.swift`

삭제 lifecycle:

- `CloudFunctionsLookbookDeletionRepository.swift`

모든 경로의 기준 디렉터리는 `OutPick/Features/Lookbook/Repositories/Implementations/`다. 기존 type 이름과 Repository Protocol conformances는 유지하고 manager 대신 transport를 주입한다.

### 5. Lookbook mapper — 새 파일

기준 디렉터리: `OutPick/Features/Lookbook/Repositories/Implementations/CloudFunctionsMappers/`

- `BrandCloudFunctionsMapper.swift`
- `BrandRequestCloudFunctionsMapper.swift`
- `EngagementCloudFunctionsMapper.swift`
- `CommentCloudFunctionsMapper.swift`
- `SeasonImportCloudFunctionsMapper.swift`
- `LookbookExtractionDiagnosticCloudFunctionsMapper.swift`
- `LookbookDeletionCloudFunctionsMapper.swift`

mapper는 Domain entity 변환만 담당하고 FirebaseFunctions SDK를 import하지 않는다.

### 6. Lookbook DI와 fixture — 수정 파일

- `OutPick/Features/Lookbook/Repositories/LookbookRepositoryProvider.swift`
- `OutPick/Features/Lookbook/LookbookContainer.swift`
- `OutPick/Features/Lookbook/Repositories/Implementations/LookbookUITestFixtureRepositoryProvider.swift`

규칙:

- `LookbookRepositoryProvider.live(transport:)`가 15개 adapter를 한 transport로 조립한다.
- production `AppCompositionRoot`는 live provider를 `AppCoordinator`에 명시적으로 전달한다.
- UI test fixture가 누락된 기본 인자를 통해 live Functions를 생성하지 않도록 explicit stub을 전달한다.

구현 결과는 기존 `LookbookUITestFixtureStore`가 필요한 Cloud Functions 관련 Protocol도 함께 구현하도록 확장했다. 별도 stub 파일을 만들지 않아 fixture 상태와 반환값을 한 곳에서 유지한다.

### 7. 제거 파일과 직접 호출 정리

- 삭제: `OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift`.
- 수정: `OutPick/Features/Chat/Controllers/RoomListsCollectionViewController.swift`의 `callHelloUser` 호출 제거.
- Xcode가 filesystem-synchronized root group을 사용하므로 현재 조사 기준 `OutPick.xcodeproj/project.pbxproj` 수정은 예상하지 않는다.

### 8. 문서 갱신

- `docs/ai/ENTRYPOINTS.md`
- `docs/ai/CODE_ARCHITECTURE.md`
- `docs/ai/entrypoints/FIREBASE.md`
- `docs/ai/entrypoints/TESTS.md`
- 이 task의 contracts/decisions/plan/progress/qa
- `HANDOFF.md`

코드 파일이 실제로 추가·이동·삭제되면 위 하네스 갱신까지 Phase 2 완료 범위에 포함한다.

## 테스트 계획

test double, 예상 test file 9개, callable 38개 배분, 실행 명령과 수동 QA는 [Phase 2 테스트 계획](phase-2-ios-cloud-functions-tests.md)을 따른다.

## 구현 순서

### Step 2A. 공통 core와 test double

목표: manager와 공존 가능한 transport/decoder 기반을 만든다.

1. core 4개 파일 추가.
2. `CloudFunctionsTransportSpy`와 decoder test 추가.
3. Firebase 오류를 wrapping하지 않는 transport 규칙 확인.

완료 기준: 새 adapter가 manager 없이 callable을 실행하고 fake transport로 검증 가능한 기반이 있다.

### Step 2B. Auth와 BrandAdmin

목표: 앱 시작·로그인 경로의 manager 의존을 먼저 제거한다.

1. 두 capability Protocol과 Client 추가.
2. `DefaultSocialAuthRepository`, `BrandAdminSessionStore` 주입 전환.
3. Login/App composition 연결과 preview fake 정리.
4. Auth/Admin test 추가.

완료 기준: 로그인/관리자 경로에 `CloudFunctionsManager` 참조가 없다.

### Step 2C. Brand와 Brand Request

목표: brand mapper와 cursor가 있는 요청 계약을 이전한다.

1. Brand/BrandRequest mapper 추가.
2. BrandStore/Search/Request adapter 전환.
3. `updateLogoPaths` method-level `.shared` 제거.
4. 12개 callable test 추가.

완료 기준: 브랜드 관리·검색·요청 adapter가 transport만 의존한다.

### Step 2D. Engagement와 Comment/Safety

목표: 상호작용과 신뢰 기능 계약을 이전한다.

1. Engagement/Comment mapper 추가.
2. 7개 adapter 전환.
3. 10개 callable test 추가.

완료 기준: 좋아요/저장/댓글/신고/차단 경로에 manager 참조가 없다.

### Step 2E. Import와 Deletion

목표: nested mapping과 실패 비용이 큰 운영 기능을 마지막 기능 묶음으로 이전한다.

1. Import/Diagnostic/Deletion mapper 추가.
2. import 4개와 deletion adapter 1개 전환.
3. 14개 callable test 추가.
4. 미사용 wrapper를 복제하지 않았는지 확인.

완료 기준: import와 삭제 계약 14개가 fake transport test로 고정된다.

### Step 2F. DI, fixture와 giant façade 제거

목표: production/preview/UI test 조립을 명시화하고 manager를 제거한다.

1. `LookbookRepositoryProvider.live(transport:)`와 App composition 연결.
2. UI test fixture의 live fallback 제거.
3. `callHelloUser` 제거.
4. `CloudFunctionsManager.swift` 삭제.
5. direct reference/static search 수행.

완료 기준: `CloudFunctionsManager`, `callHelloUser`, feature adapter의 direct FirebaseFunctions SDK 사용이 0이다.

### Step 2G. 검증과 하네스 최신화

1. Cloud Functions targeted tests 실행.
2. iOS generic simulator build 실행.
3. 대표 수동 QA.
4. ENTRYPOINTS/FIREBASE/TESTS/CODE_ARCHITECTURE/task/HANDOFF 갱신.

## 검증 계획

- 정적 reference/SDK boundary 검색.
- test plan의 targeted test 9개 class 실행.
- generic iOS Simulator build.
- 로그인·관리자·룩북 대표 수동 QA.

상세 명령과 시나리오는 [Phase 2 테스트 계획](phase-2-ios-cloud-functions-tests.md)을 따른다.

## 완료 기준

- 사용 중인 38개 callable의 wire 동작이 유지된다.
- `CloudFunctionsManager.swift`와 직접 참조가 없다.
- FirebaseFunctions SDK 접근은 `FirebaseCloudFunctionsTransport`에만 있다.
- 기능 adapter는 기존 Repository Protocol 또는 새 좁은 capability만 구현한다.
- production DI, preview와 UI test fixture가 live fallback 없이 의도를 드러낸다.
- targeted tests와 iOS build가 통과한다.
- 수동 QA 결과와 미수행 항목이 progress에 기록된다.
- 서버 코드, Firebase 배포와 데이터 계약은 변경하지 않는다.

## 구현 중 중단 조건

- 새로운 manager wrapper 소비자가 발견된다.
- 기존 callable payload/response를 바꿔야만 compile되는 상황이 생긴다.
- 앱 전체 singleton lifecycle 변경 없이는 DI를 연결할 수 없다.
- 서버 변경이나 배포가 필요해진다.

중단 조건이 발생하면 임의로 범위를 넓히지 않고 사용자에게 선택지와 추천안을 보고한다.

## 구현 결과

- Step 2A~2G 코드·자동 검증 완료.
- 사용 중인 callable 38개를 기능별 adapter/capability로 이전했다.
- `CloudFunctionsManager.swift`와 `callHelloUser`를 제거했다.
- FirebaseFunctions SDK 접근은 `FirebaseCloudFunctionsTransport.swift` 한 파일로 제한됐다.
- 서버 코드, API/데이터 계약, 배포 설정은 변경하지 않았다.
- 실제 로그인·관리자·삭제 운영 수동 QA는 자격 증명과 운영 상태 변경이 필요해 이번 구현에서는 수행하지 않았다.
