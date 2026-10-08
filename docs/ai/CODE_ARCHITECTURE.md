# 앱 아키텍처

MVVM-C + Repository + UseCase + DI 구조를 유지한다. CompositionRoot는 앱/탭/기능 진입점과 UIKit·SwiftUI 연결을 조립한다. Container는 기능 내부 의존성과 화면 factory를 보관한다. Coordinator는 화면 전환과 사용자 흐름을 책임진다.

View는 Firebase/Repository/UseCase를 직접 생성하지 않는다. ViewModel은 생성자로 주입받은 UseCase와 Store를 사용한다. Data의 Repository 구현이 API/저장소 세부사항을 캡슐화하고 Domain은 업무 계약을 정의한다. 요청 범위 밖 리팩토링이나 불필요한 추상화를 추가하지 않는다.

앱은 Backend나 관리자 웹 checkout 없이 빌드한다. contracts/client-manifest.json은 Backend canonical 계약의 파일 해시를 고정한다. API 변경은 호환 서버 준비 후 앱 계약/소비자 변경 순서로 진행한다.
