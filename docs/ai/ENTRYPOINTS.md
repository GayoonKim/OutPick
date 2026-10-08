# iOS 코드 진입점

| 범위 | 확인 위치 |
| --- | --- |
| 앱 조립·실행 | OutPick/App, OutPick.xcodeproj, Configurations |
| 기능 구현 | OutPick/Features/{Login,Chat,Lookbook,MyPage,Profile,Moderation}, OutPick/DB, OutPick/Infra |
| 실제 기능별 경로 탐색 | rg --files OutPick에서 기능 이름 검색, CompositionRoot/Container/Coordinator 순서 확인 |
| 앱 테스트 | OutPickTests, OutPickUITests |
| 환경 설정 검사 | scripts/build/validate-and-copy-firebase-config.sh, test-validate-and-copy-firebase-config.sh |
| Kakao 실제 키 제외·환경 검사 | Configurations/Kakao.example.xcconfig, ignored LocalSecrets/Kakao, OutPick/App/Firebase/AppRuntimeConfiguration.swift, OutPickTests/AppRuntimeConfigurationTests.swift |
| 클라이언트 계약 | contracts/client-manifest.json, contracts/chat-search, contracts/lookbook-import-queue-v1.json, contracts/chat-moderation-v1.json |
| 필수 검증 | verification/README.md, ios-migration-all.json, ios-migration-map.json |
| 고정 공용 도구 | tools/verification-gate/upstream.json, tools/security/upstream.json, tools/repository-integrity/check.mjs |

서버 API 구현은 비공개 Backend가 소유한다. 앱이 사용하는 Repository DTO/UseCase와 안전한 계약 사본만 이 저장소에 유지한다.
