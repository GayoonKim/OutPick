# 앱 아키텍처

MVVM-C + Repository + UseCase + DI 구조를 유지한다. CompositionRoot는 앱/탭/기능 진입점과 UIKit·SwiftUI 연결을 조립한다. Container는 기능 내부 의존성과 화면 factory를 보관한다. Coordinator는 화면 전환과 사용자 흐름을 책임진다.

View는 Firebase/Repository/UseCase를 직접 생성하지 않는다. ViewModel은 생성자로 주입받은 UseCase와 Store를 사용한다. Data의 Repository 구현이 API/저장소 세부사항을 캡슐화하고 Domain은 업무 계약을 정의한다. 요청 범위 밖 리팩토링이나 불필요한 추상화를 추가하지 않는다.

앱은 Backend나 관리자 웹 checkout 없이 빌드한다. contracts/client-manifest.json은 Backend canonical 계약의 파일 해시를 고정한다. API 변경은 호환 서버 준비 후 앱 계약/소비자 변경 순서로 진행한다.

브랜드 B1의 contracts/brand-operations에는 공개 사용자 계약과 예제만 포함한다. tools/brand-operations와 준비 게이트는 독립 명세 검사이며 관리자 계약을 복사하지 않는다. B5의 실제 소비 동작은 verification/brand-operations.json의 Swift/Simulator selector와 별도 소스 검사로 확인한다. 상세 응답 스키마·실제 SDK/Development·정책 전환의 수락/미검증은 작업 하네스를 따른다.

브랜드 요청/내역은 기존 UseCase·Repository와 Container 조립을 유지한다. 완료 이동은 LoadPublicBrandUseCase로 현재 명시 public을 확인한 뒤 Coordinator로 전달한다. 목록3쿼리는 public 조건을 SDK query에 포함하고 직접 get도 상태를 확인한다. 검색의 기존20/30 계약에 필드를 임의 추가하지 않고 현재 단건 조회를 재사용한다. 내 요청 탭 전환은 소유 Task를 취소하고 세대/scope를 대조해 늦은 응답을 폐기한다. 새 영속 receipt·확인 API·범용 cache는 추가하지 않는다.

브랜드 카드/상세/공유는 이름 중심으로 표시한다. LookbookSharedContent의 저장 thumbnail 스냅샷을 보존하고 displayThumbnailPath로 브랜드의 이미지 수요만 제외한다. 시즌·포스트 공유 이미지와 공유 캐시는 유지한다. L178 사용자 승인으로 웹 전용 시즌21개 API의 iOS 전용 UI/DI/Repository·원명령 자동복원을 제거했다. 공유 큐 원기록/마이그레이션과 공개 시즌·이미지·목록 밖 권한/스타일·삭제/복구는 유지한다. 나머지 구 브랜드 UI/writer 종료는 L77의 전환 조건과 별도 적용 대상으로 남으며 소스 제거를 실제 Cloud 배포/운영 전환 완료로 읽지 않는다.
