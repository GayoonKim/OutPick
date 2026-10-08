# 기술 결정

2026-10-08: 공개 iOS, 비공개 공통 Backend, 비공개 Admin-Web의 세 저장소로 분리한다. 배포 책임과 공개 범위를 분리하고 앱/웹/서버가 각각 설치·검사 가능하도록 한다. 기존 서버 API와 앱 MVVM-C 구조는 유지한다.

공용 gate와 secret scanner는 Backend가 관리하고 앱은 버전/해시 고정 사본을 사용한다. 독립 실행을 얻는 대신 사본 갱신 PR이 필요하다. 클라이언트 계약도 같은 방식으로 고정하며 server 전용 운영 계약은 공개하지 않는다.

iOS 이관 게이트는 기존 xcodebuild selector와 필수 테스트의 합집합을 실행한다. 기존 설정과 필수 ID 대응은 verification/ios-migration-map.json에 남긴다. Unicode 생성물 검사는 --consumer ios로 앱/공통 자료만 검사한다.
