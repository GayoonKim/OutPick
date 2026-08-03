# OutPick Handoff

## 1. 최종 목표

- 최근 완료한 핵심 task는 `development-production-environment-separation`이다. 현재 진행 중인 핵심 task는 없다.
- 하나의 Xcode 프로젝트와 app target을 유지하면서 Development 앱은 `GayoonKim.OutPick.dev`와 `outpick-test`, Production 앱은 `GayoonKim.OutPick`과 `outpick-664ae`를 사용한다.
- 잘못된 Bundle ID·Firebase plist/project·Socket 조합은 build-time과 runtime에서 fail closed 처리한다.
- Development 앱은 `OutPick DEV`로 표시하고 Production 앱과 같은 기기에 동시에 설치할 수 있어야 한다.
- Development는 제한 모드가 아니라 현재 앱의 수동 QA가 가능한 Functions·Rules·Indexes·Storage·Socket 기능 동등성을 목표로 한다. 외부 배포는 각 범위 감사와 사용자 승인 뒤 진행한다.
- 코드·설정·백엔드·배포 계약 기준의 Development/Production 환경 분리는 PR #3 병합, Production Worker traffic 전환과 실제 import smoke까지 완료해 종료 처리했다.

## 2. 완료한 작업

### 이전 Phase 2 변경 보존

- extraction 검토가 `correctionRequired`로 전환된 뒤 저장된 입력을 더 이상 미저장 초안으로 취급하지 않고 interactive-pop 차단을 해제했다.
- browse controller의 edge/content pop 가능 상태를 명시적으로 갱신하는 회귀 테스트를 보완했다.
- iPhone 17 Pro Max iOS 26.2 Simulator에서 다음 targeted test 12개가 통과했다.
  - `LookbookExtractionReviewViewModelTests` 9개
  - `LookbookNavigationControllerTests` 3개
- 기존 Swift 6 actor isolation, deprecated API, library search path 경고는 남아 있으나 이번 변경 관련 실패는 없었다.
- 커밋:
  - `df74e29 fix: 검토 완료 후 스와이프 복귀 허용`
  - `7496d2e test: 검토 화면 스와이프 복귀 회귀 검증`
  - `12c35cd chore: Xcode 개발 서명 설정 명시`
  - `319bbf2 docs: 환경 분리 작업을 현재 task로 전환`

### 환경 분리 읽기 전용 조사

- 현재 Xcode는 app target 1개, `OutPick` scheme 1개, `Debug`/`Release` configuration 2개다.
- 두 app configuration 모두 `GayoonKim.OutPick`을 사용하고 xcconfig 환경 분리는 없다.
- 운영 plist는 `GayoonKim.OutPick`/`outpick-664ae` 조합이다.
- 기존 실제 Firebase UI test plist는 `GayoonKim.OutPick`/`outpick-test` 조합이고 Google OAuth `CLIENT_ID`가 없다. 새 Development 앱 plist로 재사용할 수 없다.
- Firestore·Storage·Auth·Functions는 기본 `FirebaseApp`을 사용하므로 올바른 plist를 주입하면 프로젝트가 함께 분리된다.
- iOS Socket은 운영 Cloud Run URL을 하드코딩하고 Firebase ID Token을 전송한다.
- 조사 당시 scheme의 `OUTPICK_SOCKET_URL`과 코드의 `OUTPICK_DEBUG_SOCKET_URL` 이름이 달라 기존 override가 동작하지 않았다. 현재는 `AppRuntimeConfiguration`과 `RealtimeSocketService`가 `OUTPICK_SOCKET_URL`을 사용하도록 통일했다.
- 2026-08-01 Cloud Run 읽기 전용 조회 결과 `outpick-test`에는 Socket 서비스가 없고 Functions도 운영보다 오래된 일부만 존재한다.
- Socket Firebase Admin의 기본 Storage bucket이 운영 bucket으로 고정되어 있어 동일 이미지를 test project에 그대로 배포하면 안 된다.

### 사용자 확정 결정

- 이전 Phase 2는 정상 커밋으로 보존하고 별도 worktree는 사용하지 않는다.
- 환경 분리 구현은 전용 `codex/development-production-environment-separation` 브랜치에서 진행한다.
- Development backend는 Functions·Rules·Indexes·Storage·Socket 기능 동등성 모드로 진행한다.
- Simulator 환경 분리를 우선 완료하고 Development 실기기 App Attest는 Apple/Firebase 등록 가능 상태를 확인한 뒤 진행한다.
- `main` branch protection은 PR 경유·대화 해결·관리자 적용·force push/삭제 금지로 구성했다. 유료 Rulesets와 필수 CI status check, release tag 자동화, preview project, 미사용 capability는 이번 범위에서 제외한다.

### Phase 1 — Xcode 환경 골격과 fail-fast

- `OutPick-Development`, `OutPick-Production` shared scheme과 Development/Production 각각 Debug/Release configuration을 추가했다.
- `Configurations/`의 공통·환경별 xcconfig가 Bundle ID, 표시 이름, Firebase project/plist 경로, Socket URL을 제공한다.
- 실제 Firebase plist는 `LocalSecrets/Firebase/{Development,Production}/GoogleService-Info.plist`에서만 읽는다.
- Build Phase가 plist 존재 여부, `BUNDLE_ID`, `PROJECT_ID`, 환경별 Socket 조합을 검증한 뒤 앱 번들에 단일 plist만 복사한다.
- validator fixture test, Xcode scheme/configuration 조회, 양 환경 build setting 확인을 통과했다.
- Production generic Simulator build와 생성된 앱 번들 값 대조를 통과했다.
- Development generic Simulator build는 Development plist가 없어 명시적 오류로 실패했으며 운영 설정으로 fallback하지 않았다.

### Phase 2 — Firebase·Auth runtime 완료

- `outpick-test`에 `OutPick Development` / `GayoonKim.OutPick.dev` Firebase iOS 앱을 생성하고 전용 plist를 LocalSecrets에 저장했다.
- `AppRuntimeConfiguration`이 Bundle ID, Firebase project, Google callback, Kakao Native App Key/callback, Socket URL을 runtime fail-closed 검증한다.
- AppDelegate는 검증한 plist로 Firebase를 명시 구성하고 Kakao Native App Key를 환경값에서 읽는다.
- RealtimeSocketService는 하드코딩 운영 URL 대신 검증된 runtime Socket URL을 사용한다.
- 실제 Firebase UI test override 기본 경로를 새 Development plist로 전환했다.
- validator test, Production build, 환경 unit test 6개(총 12건), Production Simulator launch를 통과했다.
- Google Auth Platform 외부 테스트 구성, Development iOS OAuth client, 테스트 사용자 등록을 완료하고 새 Firebase plist의 callback 정합성을 확인했다.
- Kakao 운영 Native App Key/Bundle ID는 보존하고 Development 전용 Native App Key `f5f18b00bc7b163aa5be39fef99e646d`와 `GayoonKim.OutPick.dev`를 등록했다.
- Development xcconfig에 Google/Kakao callback 값을 연결했다.
- Phase 3 Development Socket `outpick-socket-development`를 `outpick-test`에 배포하고 Development xcconfig에 canonical URL을 연결했다.
- 전용 service account는 Firestore/FCM/Auth Viewer project 역할과 Development Storage bucket 한정 객체 역할만 사용한다.
- Socket 정적 검사·64개 테스트, `/readyz`, 배포 직후 ERROR 0건을 확인했다.
- Development generic Simulator build, Production/Development 동시 설치, Development 로그인 화면 실행을 확인했다.
- Development 테스트 ID Token으로 실제 Socket handshake와 `server:connect:ready` 수신을 확인했다.
- reset gate의 운영 project 오지정을 `outpick-test` 전용으로 교정했고 Functions 100개 테스트를 통과했다.
- Firestore/Storage Rules를 `outpick-test`에 배포하고 Rules 29개·transaction 7개 emulator 검증을 통과했다.
- 로컬 Firestore index 33개를 배포했으며 기존 레거시 Rooms index 2개를 보존하고 전체 35개 `READY`를 확인했다.
- Secret Manager/Cloud Tasks API와 Development 계정 삭제 Secret 2개를 구성했다.
- 사용자 명시 승인 후 자동 삭제 Scheduler를 포함한 비-worker Functions 53개를 배포했다. 61개 Function이 모두 `ACTIVE`이고 Scheduler 3개가 `ENABLED`다.
- 48개 callable transport를 검증하고 IAM quota로 invoker가 누락된 `exchangeKakaoToken` 하나를 복구했다. 감사 로그 제외 runtime ERROR는 0건이다.
- Development 전용 Lookbook import worker, Cloud Tasks queue와 task/worker identity를 구성하고 worker 의존 Functions 15개를 연결했다. Functions 74개가 모두 `ACTIVE`다.
- worker `lookbook-import-worker-development-00003-5kc`는 traffic 100%이며 `outpick-test` project/bucket을 명시한다. Cloud Run 비공개 IAM과 애플리케이션 OIDC 이중 검증을 사용하고 task/Functions 호출 경로를 분리한다.
- `/readyz`와 경로별 빈 payload smoke로 IAM·OIDC·routing을 확인했다. 실제 import/materialization은 실행하지 않았다.
- Phase 3 reset allowlist 실제 QA를 완료했다. `outpick-test` dry-run과 실제 reset, 비-allowlist Firestore/Auth sentinel 보존, fixture 복구, 운영 project 시작 거부를 확인했다.
- QA Kakao token은 logout API HTTP 200으로 폐기했고 token 원문이 있던 local runtime log를 삭제했다.
- `outpick-test` Google provider를 활성화하고 실제 Google OAuth callback → Firebase login → Development 온보딩 진입을 확인했다.
- `outpick-auth-functions-dev@outpick-test.iam.gserviceaccount.com`을 만들고 자기 자신에만 Token Creator를 부여했다. `exchangeKakaoToken` 한 함수만 이 계정으로 재배포했으며 `ACTIVE`와 실제 runtime identity를 확인했다.
- 인증 runtime parameter 누락·형식·프로젝트 불일치 테스트를 추가했고 Functions lint/build/test 104개가 통과했다.
- Simulator App Check debug token을 Development iOS 앱에 등록했다. 앱 재설치 뒤 기존 token을 폐기하고 새 token으로 회전했으며 token 원문은 기록하지 않았다.
- `outpick-test.styleMoods`가 0건이라 Google QA 로그아웃을 위해 임시 profile 3개 문서를 만들었고 정상 로그아웃 직후 모두 삭제했다.
- Kakao 재인증·동의 후 Development callback, custom-token Firebase 로그인과 온보딩 진입을 확인했다. Firebase Auth에 `kakao:*` 사용자가 생성됐고 callable App Check는 `VALID`, signBlob/IAM/runtime ERROR는 0건이다.
- 운영과 동일한 v1 style mood seed를 `outpick-test`에 적용했다. 무드 56개·검색어 인덱스 137개·metadata version 1/count 56이며 운영과 content hash가 같다. 사후 dry-run 변경은 0건이다.
- Kakao 신규 사용자 온보딩에서 스타일 목록 표시, 캐주얼 1개 선택, active account/public profile 저장과 메인 화면 진입을 확인했다. `completeOnboarding` ERROR는 0건이다.
- Phase 4 마감 검증에서 네 Xcode configuration build와 산출물 환경 대조, validator/runtime test, Functions 104개, Socket 64개, worker 74개·fixture 5개, Test Admin Server build를 통과했다.
- Development Functions 74개 ACTIVE, Socket/worker Ready와 traffic 100%, queue pending 0, Socket `/readyz`와 Engine.IO handshake를 재확인했다. tracked secret과 민감 token/private-key 패턴은 발견되지 않았다.
- Production 무변경 dry-run은 `OUTPICK_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL` 누락으로 실패했다. 테스트된 resolver는 실제 Function 옵션에서 쓰이지 않고 필수 parameter가 직접 연결된 상태라 Phase 4를 완료 처리하지 않았다.
- 사용자 승인으로 Production 전용 인증 계정 `outpick-auth-functions-prod@outpick-664ae.iam.gserviceaccount.com`을 생성했다. project 역할은 없고 자기 리소스 Token Creator만 가진다.
- Firebase parameter가 Development/Production 승인 계정만 허용하도록 실제 계약 테스트를 교정하고 Production `.env`에 연결했다. Functions lint/build/test 103개와 Production non-interactive dry-run이 통과해 Phase 4 차단을 해제했다.
- dry-run만 수행했으므로 실제 Production `exchangeKakaoToken`은 기존 revision과 compute runtime identity를 유지한다. Production identity 전환 배포는 별도 승인 전에는 수행하지 않는다.
- 이후 사용자 명시 승인으로 Production `exchangeKakaoToken` 한 함수만 배포했다. revision `exchangekakaotoken-00042-geb`가 ACTIVE/Ready·traffic 100%이며 runtime identity가 Production 전용 계정으로 전환됐다.
- 빈 callable payload는 앱 계층 INVALID_ARGUMENT HTTP 400을 반환했고 배포 이후 severity ERROR 로그는 0건이다. 이후 Production Kakao 실제 로그인에서 callback, Function HTTP 200, 기존 프로필 복원과 앱 로그아웃까지 확인했다.
- 미사용 Cloud Run `lookbook-import-worker`는 실제 요청·Functions/Cloud Tasks 참조가 없음을 감사한 뒤 사용자 승인으로 삭제했다. 정식 `lookbook-import-worker-development-00003-5kc`는 Ready·traffic 100%다.
- Google/Kakao QA Auth 2개와 연결된 사용자/profile/nickname/device/meta 데이터, 테스트 잔여 `commentDeletionLogs` 2건을 삭제했다. `uitest-*` fixture와 스타일 무드 seed는 보존했다.
- W3C 전용 sample로 Firestore trigger → Cloud Tasks → Development worker → review → materialization 실제 smoke를 완료했다. job은 `succeeded`, post 5개, asset 6/6 `ready`, worker ERROR 0건이었다.
- smoke 브랜드 tree, Storage 12개, evidence ledger/JSON과 단독 issue cluster를 삭제했고 Firestore·Storage 잔존 0건을 확인했다.
- PR #3 리뷰에서 Development에 Production Kakao 키·scheme을 함께 넣으면 기존 자기 일치 검증을 통과하는 P2를 재현했다. xcconfig와 독립된 환경별 canonical 키를 build/runtime에 고정하고 양방향 교차 테스트를 추가했다.
- Firebase validator test, `AppRuntimeConfigurationTests` 8개, Development/Production Debug·Release 네 구성을 다시 검증했고 모두 통과했다. 전체 diff 재리뷰에서 추가 차단 사항은 없었다.
- 중간 리뷰에서 구현·테스트·문서 3개 후속 커밋을 push하고 PR #3 본문에 P2 수정과 Production Kakao QA를 반영해 head `5d89377`을 Ready로 전환했다. 이후 추가 P2 보완·candidate 검증·병합 결과는 아래 최종 종료 기록이 우선한다.
- DEV 아이콘 배지는 사용자 결정으로 추가하지 않는다. `OutPick DEV` 표시 이름은 유지한다.

### 환경 분리 최종 종료

- PR #3 리뷰에서 Socket canonical origin, Kakao canonical key, Firebase project, Functions identity, Worker OIDC caller·Storage bucket 교차 경계를 exact contract로 보완했다.
- Worker는 최종 83개 테스트·fixture 5개, Functions 104개, iOS `AppRuntimeConfigurationTests` 13개, 배포 계약 테스트를 통과했다.
- 첫 Production candidate 배포에서 Cloud Run service명+traffic tag 46자 제한을 발견했다. revision 생성 전 안전하게 중단된 뒤 `cand-YYYYMMDD-HHMMSS`와 결합 길이 회귀 테스트로 수정했다.
- PR #3 head `5a61d1f`의 candidate `lookbook-import-worker-00024-fow`를 traffic 0%로 검증했다. canonical task `/readyz` 200, task 빈 import 500, Functions 빈 diagnostic 500, Functions→import 403을 확인했다.
- PR #3은 기능·테스트·백엔드·문서·배포 계약의 16개 작업 단위 커밋을 보존한 merge commit `7383a0e`로 병합했다. main tree와 candidate source가 동일함을 확인한 뒤 Production traffic을 `00024-fow` 100%로 전환했다. rollback은 `00023-879`이다.
- Production W3C import smoke는 trigger → Cloud Tasks → Worker → review → materialization에서 `succeeded/completed`, season 1개, post 5개, asset 6/6 `ready`로 완료됐다.
- smoke Firestore tree·Storage 12개·evidence ledger/JSON·단독 issue cluster를 삭제했다. 전환 후 Worker ERROR, queue pending, smoke 데이터 잔존은 모두 0건이다.
- 운영 결과는 문서 전용 PR #4의 커밋 `6a88016`과 merge commit `9d6a7db`로 `main`에 반영했다.

## 3. 완료 범위 밖 후속 후보

1. Development 실기기 App Attest는 Apple Developer Program 가입 후 외부 의존 후속 작업으로 재개한다.
2. Production Google 실제 로그인과 provider별 계정 삭제 요청·취소 재인증 smoke는 출시 전 QA로 남는다.
3. PITR·예약 백업·Storage soft delete·복구 훈련은 출시 운영 게이트로 남는다.

## 4. 수정한 파일 목록

- 이전 Phase 2 커밋 완료:
  - `OutPick/Features/Lookbook/ViewModels/LookbookExtractionReviewViewModel.swift`
  - `OutPickTests/LookbookExtractionReviewViewModelTests.swift`
  - `OutPickTests/LookbookNavigationControllerTests.swift`
  - `OutPick.xcodeproj/project.pbxproj`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/tasks/active.md`
- 환경 분리 구현·테스트·tracked 문서는 PR #3에, Production Worker 배포 결과 문서는 PR #4에 병합했다. 이 closure 갱신 전 working tree에는 `HANDOFF.md` 수정만 남아 있었다. task `progress.md`와 `qa-checklist.md`는 `.git/info/exclude` 대상 로컬 하네스다.
- `firebase-debug.log`는 Firebase CLI 인증 실패로 생성된 임시 로그라 삭제했고 커밋하지 않았다.

## 5. 중요한 아키텍처 결정

### 하나의 app target과 명시적 환경 configuration

- 선택: 프로젝트와 app target은 하나로 유지하고 Development/Production scheme과 build configuration, xcconfig로 환경을 분리한다.
- 이유: 소스와 DI graph를 복제하지 않으면서 Bundle ID와 backend 연결만 명시적으로 분리할 수 있다.
- 트레이드오프: `project.pbxproj` configuration 수와 build matrix가 늘지만 target 복제보다 drift 위험이 작다.
- 보류한 대안: Development target 복제는 build setting과 capability가 장기적으로 갈라질 위험이 커서 사용하지 않는다.

### Firebase plist fail-fast 주입

- 선택: 실제 plist는 `LocalSecrets`에 보관하고 build phase가 환경별 파일의 `BUNDLE_ID`와 `PROJECT_ID`를 검증한 뒤 결과물에 복사한다.
- 이유: 두 plist가 file-system synchronized app group에 함께 포함되는 문제와 잘못된 project 오접속을 동시에 막는다.
- 트레이드오프: 새 개발 환경마다 로컬 plist 설치가 필요하지만 누락·오조합을 빌드 시점에 바로 발견한다.

### Development backend 기능 동등성

- 선택: Firebase만 분리한 제한 앱이 아니라 현재 기능을 검증할 수 있는 Development backend를 목표로 한다.
- 이유: 현재 `outpick-test`는 최신 onboarding/profile/계정 삭제 기능과 Socket이 없어 단순 plist 교체만으로는 실제 개발 QA가 불가능하다.
- 트레이드오프: Functions/Rules/Socket 배포 감사와 Secret·scheduled trigger 관리 비용이 추가된다.
- 재검토 조건: 운영과 test의 배포 충돌이 반복되거나 여러 개발자가 동시에 backend를 변경하면 CI lock 또는 preview project를 별도 도입한다.

### 환경별 Socket fail closed

- 선택: Production URL을 공통 fallback으로 사용하지 않고 환경 설정이 없거나 잘못되면 연결을 차단한다.
- 이유: Development Firebase ID Token과 운영 Socket/Firebase Admin 경계를 섞지 않기 위해서다.
- 보류한 대안: DEBUG 환경변수 override만 유지하는 방식은 scheme key 오타와 fallback을 구조적으로 막지 못해 제외한다.

### 환경별 Kakao canonical 경계

- 선택: xcconfig는 실제 키를 제공하고, Swift runtime과 build validator는 각각 환경별 canonical Native App Key를 독립적으로 보유해 actual과 대조한다.
- 이유: 실제 키와 `EXPECTED_KAKAO_KEY`를 같은 xcconfig에 두면 두 값을 함께 잘못 바꾸는 교차 설정을 차단하지 못한다.
- 트레이드오프: 공개 Native App Key가 Swift·셸·xcconfig에 의도적으로 중복되므로 키 교체 시 세 위치와 회귀 테스트를 함께 갱신해야 한다.
- 보류한 대안: 단일 환경 manifest 생성·번들 파싱은 환경이 두 개인 현재 범위에서 구조와 검증 경로를 과도하게 늘려 도입하지 않았다.
- 재검토 조건: staging/QA 등 환경이 추가되거나 Kakao 키 회전이 반복되면 versioned environment manifest와 생성 코드로 통합한다.

### Worker 환경·배포 exact contract

- 선택: Firebase project별 Storage bucket, OIDC audience, Cloud Tasks 계정, Functions 계정을 Worker 시작 시 exact 값으로 검증하고 배포 스크립트가 같은 단일 매핑을 사용한다.
- 이유: 형식상 유효한 임의 값이나 project 기반 bucket fallback은 Development/Production 교차 배포를 막지 못한다.
- 트레이드오프: project·service account·bucket 변경 시 코드, 배포 계약과 테스트를 함께 갱신해야 하지만 잘못된 운영 기동을 시작 전에 차단한다.
- 보류한 대안: 배포자 주의와 runbook만으로 값을 관리하는 방식은 반복 가능한 안전장치가 약해 사용하지 않는다.
- 재검토 조건: 환경이 세 개 이상으로 늘면 versioned environment manifest에서 앱·Functions·Worker 배포 설정을 생성하는 구조를 검토한다.

### Candidate 검증 후 main 병합·traffic 전환

- 선택: PR head를 `--no-traffic` candidate로 검증하고, main 병합 tree가 candidate source와 동일할 때만 검증 revision을 100%로 전환한다.
- 이유: 미병합 소스가 운영 traffic을 받거나 검증하지 않은 재빌드가 운영에 진입하는 상태를 피한다.
- 트레이드오프: 배포 단계가 늘지만 rollback revision을 전환 전에 고정하고 실제 OIDC·import smoke를 수행할 수 있다.
- 보류한 대안: PR 머지 직후 검증 없이 바로 source deploy하는 방식은 Production IAM·환경값·실제 import 회귀를 사전에 차단하지 못한다.

## 6. 다시 확인해야 할 불확실한 부분

- Firebase/Google/Kakao Development 앱과 callback 등록은 완료했다.
- Development 실기기 App Attest의 Apple App ID·entitlement·Firebase provider 등록은 Apple Developer Program 가입 후 재확인한다.
- `outpick-test` Functions 74개와 scheduled trigger의 감사·승인·배포, 실제 import/materialization smoke와 smoke 데이터 정리를 완료했다.
- Production Worker `lookbook-import-worker-00024-fow` traffic 100%, rollback `00023-879`, 전환 후 ERROR·queue pending 0건을 확인했다.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. 환경 분리 작업은 종료됐으므로 추가 구현을 시작하지 않는다.
2. 다음 외부 의존 인증 작업은 Apple Developer Program 가입 후 Development 실기기 App Attest다.
3. 출시 전 별도 승인 범위에서 Production Google 로그인, provider별 계정 삭제 재인증, 백업·복구 운영 게이트를 진행한다.
