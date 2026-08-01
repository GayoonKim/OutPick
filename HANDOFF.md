# OutPick Handoff

## 1. 최종 목표

- 현재 핵심 task는 `development-production-environment-separation`이다.
- 하나의 Xcode 프로젝트와 app target을 유지하면서 Development 앱은 `GayoonKim.OutPick.dev`와 `outpick-test`, Production 앱은 `GayoonKim.OutPick`과 `outpick-664ae`를 사용한다.
- 잘못된 Bundle ID·Firebase plist/project·Socket 조합은 build-time과 runtime에서 fail closed 처리한다.
- Development 앱은 `OutPick DEV`로 표시하고 Production 앱과 같은 기기에 동시에 설치할 수 있어야 한다.
- Development는 제한 모드가 아니라 현재 앱의 수동 QA가 가능한 Functions·Rules·Indexes·Storage·Socket 기능 동등성을 목표로 한다. 외부 배포는 각 범위 감사와 사용자 승인 뒤 진행한다.

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
- 현재 scheme의 `OUTPICK_SOCKET_URL`과 코드의 `OUTPICK_DEBUG_SOCKET_URL` 이름이 달라 기존 override는 동작하지 않는다.
- 2026-08-01 Cloud Run 읽기 전용 조회 결과 `outpick-test`에는 Socket 서비스가 없고 Functions도 운영보다 오래된 일부만 존재한다.
- Socket Firebase Admin의 기본 Storage bucket이 운영 bucket으로 고정되어 있어 동일 이미지를 test project에 그대로 배포하면 안 된다.

### 사용자 확정 결정

- 이전 Phase 2는 정상 커밋으로 보존하고 별도 worktree는 사용하지 않는다.
- 환경 분리 구현은 전용 `codex/development-production-environment-separation` 브랜치에서 진행한다.
- Development backend는 Functions·Rules·Indexes·Storage·Socket 기능 동등성 모드로 진행한다.
- Simulator 환경 분리를 우선 완료하고 Development 실기기 App Attest는 Apple/Firebase 등록 가능 상태를 확인한 뒤 진행한다.
- CI lock, branch protection, release tag 자동화, preview project, 미사용 capability는 이번 범위에서 제외한다.

## 3. 아직 남은 작업

1. 깨끗한 `main`에서 `codex/development-production-environment-separation` 브랜치를 생성한다.
2. task의 `plan.md`, `qa-checklist.md`를 만들고 `design.md`, `decisions.md`, `progress.md`를 2026-08-01 확정 결정에 맞게 갱신한다.
3. Phase 1에서 두 scheme, 네 build configuration, xcconfig, Firebase plist 선택·검증·복사 build phase, `OutPick DEV` 표시 이름을 구현한다.
4. Phase 2에서 `AppEnvironment`, Firebase runtime 정합성, Google/Kakao callback 설정, 기존 실제 Firebase UI test override를 연결한다.
5. Phase 3 전에 `outpick-test` Functions·Rules·Indexes·Storage·Secrets·scheduled/destructive trigger를 감사하고 안전한 Development 배포 범위를 확정한다.
6. `outpick-test` 전용 Socket의 Firebase project, service account, Storage bucket, URL을 구성하고 Development 앱이 운영 Socket으로 fallback하지 못하게 한다.
7. 네 configuration build, 잘못된 조합 negative build, 동시 설치, Firebase/Auth/Functions/Socket smoke를 수행한다.

## 4. 수정한 파일 목록

- 커밋 완료:
  - `OutPick/Features/Lookbook/ViewModels/LookbookExtractionReviewViewModel.swift`
  - `OutPickTests/LookbookExtractionReviewViewModelTests.swift`
  - `OutPickTests/LookbookNavigationControllerTests.swift`
  - `OutPick.xcodeproj/project.pbxproj`
  - `docs/ai/entrypoints/LOOKBOOK.md`
  - `docs/ai/tasks/active.md`
- 현재 working tree 변경:
  - `HANDOFF.md`: 환경 분리 전환 상태와 다음 실행 순서 갱신
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

## 6. 다시 확인해야 할 불확실한 부분

- Firebase CLI 인증이 만료돼 `outpick-test`에 `GayoonKim.OutPick.dev` iOS 앱이 이미 등록됐는지는 확실하지 않음이다. Firebase Console 확인 또는 `firebase login --reauth`가 필요하다.
- 기존 test plist에는 Google OAuth `CLIENT_ID`가 없다. Development Google OAuth client와 reversed URL scheme을 새로 발급해야 하는지 공식 콘솔 상태 확인이 필요하다.
- Kakao Developers에 `GayoonKim.OutPick.dev` Bundle ID를 추가할 수 있는지 현재 앱 설정 확인이 필요하다.
- Development 실기기 App Attest의 Apple App ID·entitlement·Firebase provider 등록은 Simulator 완료 뒤 재확인한다.
- `outpick-test` 전체 Functions 배포는 scheduled/destructive trigger, Secret, TTL, App Check enforcement 영향을 감사하기 전에는 수행하지 않는다.

## 7. 다음 턴에서 바로 실행해야 할 작업

1. `git status --short`가 깨끗한지 확인한다.
2. `git switch -c codex/development-production-environment-separation`을 실행한다.
3. 환경 분리 task 하네스의 plan/QA/decision/progress 문서를 확정 결정에 맞게 생성·갱신한다.
4. Phase 1 변경 파일과 negative build fixture 구조를 최종 확인한 뒤 Xcode configuration 구현을 시작한다.
