# OutPick iOS 작업 지침

모든 답변과 주석은 한국어로 작성한다. 모호한 요구사항·API·데이터·화면·권한·완료 기준은 구현 전에 사용자와 논의한다. 새 기능과 큰 수정은 docs/ai를 먼저 읽고 요구사항·설계·단계별 구현·필수 검증 계획을 사용자와 검토한 뒤 승인받아 구현한다.

이 저장소는 공개 iOS 앱만 소유한다. 공통 서버·Functions·Rules·운영 CLI는 비공개 OutPick-Backend, 관리자 웹은 비공개 OutPick-Admin-Web이 소유한다. 형제 checkout을 앱 빌드나 테스트의 필수 의존성으로 만들지 않는다. 실제 계정·인증정보·env·Firebase plist·운영 로그는 커밋하지 않는다.

MVVM-C + Repository + UseCase + DI를 유지한다. View는 렌더링과 이벤트 전달, ViewModel은 주입받은 UseCase/Store, Coordinator는 화면 전환, Container/CompositionRoot는 조립을 담당한다. 서버 변경은 Repository 계약으로 접근한다. 파일·계약 변경 시 docs/ai/ENTRYPOINTS.md와 관련 하네스를 갱신한다.

수동 수정은 apply_patch를 사용한다. 사용자의 변경을 되돌리지 않는다. 큰 작업은 phase별 목표·범위·완료 기준·검증·논의 사항으로 나누고 순차 통합한다. 모델은 사용자가 직접 선택한다. 계획과 결과 분석은 사용자 설정 High, 승인된 구현과 게이트 실행은 Light 흐름을 따른다. 현재 설정을 임의로 단정하지 않는다.

필수 검사는 verification/README.md의 프로그램적 게이트로 실행한다. 실제 로그와 HEAD/digest를 기록한다. 실패·skip·0건·환경 미준비는 통과가 아니다. 수동 QA와 자동 검사를 구별한다. 완료 전 임의 커밋을 만들지 않으며 git add . 대신 파일 목록을 지정한다. 운영 배포·데이터 삭제·이력 재작성은 별도 사용자 승인 범위다.
