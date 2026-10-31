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

## 브랜드 요청과 공개 탐색

공개 브랜드 계약은 contracts/brand-operations, 요청·본인 내역·현재 공개 상태 확인은 Lookbook의 Repository/UseCase/Coordinator와 Container에서 찾는다. 브랜드 카드와 공유는 이름 중심으로 표시하고 시즌·포스트 이미지는 유지한다. iOS 관리자 세션·콘솔·브랜드/스타일/시즌 운영 기능은 제거했으며 관리자 업무는 별도 웹 저장소가 소유한다.

검사는 verification/brand-operations.json, admin-season-retirement.json, ios-admin-full-retirement-source.json, ios-admin-full-retirement-ui.json과 verification/README.md를 따른다. 코드/모의 검사 결과와 실제 서버 연동·운영 배포는 구분한다.
