# Phase 2 iOS Cloud Functions Test Plan

## 목적

사용 중인 callable 38개의 wire 계약과 mapper 동작을 fake transport로 고정한다. Firebase 운영 서버를 호출하지 않고 함수명, payload, response와 오류 전달을 결정적으로 검증한다.

## 예상 테스트 파일

기준 디렉터리: `OutPickTests/CloudFunctions/`

| 파일 | 검증 범위 |
| --- | --- |
| `TestDoubles/CloudFunctionsTransportSpy.swift` | function name, payload 기록, response/error 주입 |
| `CloudFunctionResponseDecoderTests.swift` | primitive/NSNumber/`NSNull`/date/missing field |
| `CloudFunctionsKakaoAuthBridgeClientTests.swift` | `exchangeKakaoToken` 1개 |
| `BrandAdminCapabilitiesCloudFunctionsClientTests.swift` | 관리자 capability 1개와 기본값 mapping |
| `CloudFunctionsBrandRepositoryTests.swift` | brand store 5개 + search 1개 |
| `CloudFunctionsBrandRequestRepositoryTests.swift` | 요청/목록/group/cursor mutation 6개 |
| `CloudFunctionsEngagementRepositoryTests.swift` | brand/post/season/comment 4개 |
| `CloudFunctionsCommentRepositoryTests.swift` | write 3개 + report 1개 + block/hidden 2개 |
| `CloudFunctionsSeasonImportRepositoryTests.swift` | import/retry/job/diagnostic 4개 |
| `CloudFunctionsLookbookDeletionRepositoryTests.swift` | 삭제/복구/list/retry 10개 |

합계 38개 사용 callable의 function name과 payload를 적어도 한 번씩 검증한다.

## 모든 callable 검증 기준

- 정확한 function name.
- required key와 값.
- optional nil일 때 key 생략 또는 `NSNull` 사용 여부.
- ID value와 enum raw value 변환.
- Firebase transport error identity/`NSError` domain·code 보존.

## decoder와 mapper 기준

- required field 누락 시 `missingField`.
- top-level dictionary가 아니면 `invalidResponse`.
- NSNumber → Bool/Int/Double.
- millisecond timestamp와 ISO-8601 optional date.
- pagination cursor와 optional nested response.
- diagnostic/deletion batch의 nested array와 default enum fallback.

## 추가하지 않는 테스트

- UI snapshot: 화면 변경이 아니다.
- Firebase emulator integration: fixture/config가 준비돼 있지 않다.
- 서버 callable smoke test: 서버 코드와 배포를 바꾸지 않는다.
- retry timing 신규 테스트: BrandAdmin 기존 retry 동작을 변경하지 않는다. 필요하면 capability spy 호출 횟수만 검증한다.

## 정적 검증

```bash
rg -n "CloudFunctionsManager|callHelloUser" OutPick OutPickTests
rg -n "Functions\.functions|httpsCallable" OutPick -g '*.swift'
```

첫 검색은 결과가 없어야 한다. 두 번째 검색은 concrete transport 파일만 반환해야 한다.

## targeted test 명령

실행 시 사용 가능한 Simulator ID를 확인한 뒤 다음 test class만 지정한다.

```bash
xcodebuild -project OutPick.xcodeproj -scheme OutPick \
  -destination 'platform=iOS Simulator,id={available-simulator-id}' test \
  -only-testing:OutPickTests/CloudFunctionResponseDecoderTests \
  -only-testing:OutPickTests/CloudFunctionsKakaoAuthBridgeClientTests \
  -only-testing:OutPickTests/BrandAdminCapabilitiesCloudFunctionsClientTests \
  -only-testing:OutPickTests/CloudFunctionsBrandRepositoryTests \
  -only-testing:OutPickTests/CloudFunctionsBrandRequestRepositoryTests \
  -only-testing:OutPickTests/CloudFunctionsEngagementRepositoryTests \
  -only-testing:OutPickTests/CloudFunctionsCommentRepositoryTests \
  -only-testing:OutPickTests/CloudFunctionsSeasonImportRepositoryTests \
  -only-testing:OutPickTests/CloudFunctionsLookbookDeletionRepositoryTests
```

## build 명령

```bash
xcodebuild -project OutPick.xcodeproj -scheme OutPick \
  -destination 'generic/platform=iOS Simulator' build
```

## 수동 QA

- Kakao 로그인과 기존 로그인 복원.
- 관리자 capability와 writable brand 노출.
- 브랜드 생성/수정/logo/manager 변경과 검색.
- 브랜드 요청 제출·내 요청·관리자 group 처리.
- 브랜드/시즌/포스트/댓글 좋아요와 포스트 저장.
- 댓글/답글/삭제/신고/차단과 hidden author filtering.
- 시즌 URL import, candidate diagnostic/job, asset retry.
- 브랜드/시즌/포스트 삭제·복구·목록·failed retry.
- 채팅방 목록 진입 시 불필요한 hello 호출이 없는지 확인.

## 실행 정책

- Phase 2 구현 완료 후 targeted tests와 build를 실제 실행한다.
- 실패한 test는 해당 feature adapter 단계에서 해결하고 다른 phase로 넘기지 않는다.
- 수동 QA 미수행 항목은 이유와 함께 progress에 기록한다.

## 실행 결과 — 2026-07-13

- targeted test: 위 9개 test type 전체 통과, `** TEST SUCCEEDED **`.
- destination: iPhone 15 Pro Simulator `5A3BB941-9538-4DD9-93C2-F18ACCFB03B9`.
- generic Simulator build: 통과, `** BUILD SUCCEEDED **`.
- 정적 검색: `CloudFunctionsManager|callHelloUser` 결과 0건.
- SDK 경계 검색: `Functions.functions|httpsCallable`은 `FirebaseCloudFunctionsTransport.swift`만 반환.
- 수동 QA: 미수행. Kakao 자격 증명, 관리자 권한, 운영 데이터 변경이 필요한 흐름이므로 자동 계약 테스트와 compile 검증까지만 수행했다.
