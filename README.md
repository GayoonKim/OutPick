# OutPick

패션 콘텐츠와 커뮤니티를 위한 iOS 앱입니다. Swift 앱과 테스트, Xcode 설정, 클라이언트 계약을 관리합니다.

공통 서버와 보안 규칙은 비공개 OutPick-Backend, 관리자 웹은 비공개 OutPick-Admin-Web에서 관리합니다. 서버 코드의 과거 공개 Git 이력은 이관으로 삭제되지 않습니다.

개발은 Xcode의 OutPick-Development scheme을 사용합니다. Firebase 설정 파일은 로컬 LocalSecrets/Firebase/Development/GoogleService-Info.plist에 준비합니다. 실제 설정은 커밋하지 않습니다.

Kakao 키는 LocalSecrets/Kakao/{Development,Production}.xcconfig에 OUTPICK_KAKAO_NATIVE_APP_KEY로 설정합니다. 실제 키는 저장소에서 제외합니다. 앱과 빌드 스크립트는 환경별 SHA-256 지문 및 callback 일치를 검사합니다. 단위 테스트는 가상 키, 번들 검사는 실제 로컬 Development 설정을 사용합니다.

코드 진입점은 [docs/ai/ENTRYPOINTS.md](docs/ai/ENTRYPOINTS.md), 구조는 [CODE_ARCHITECTURE.md](docs/ai/CODE_ARCHITECTURE.md), 검증은 [verification/README.md](verification/README.md)를 참고합니다.
