# 채팅 검색 v2 공통 자료

- 최종 규격: docs/ai/architecture/CHAT_MESSAGE_SEARCH.md.
- normalization-v2.json: 수기로 고정한 25개 fixture. 기대값을 구현 함수로 생성하지 않는다. 공식 corpus에서 발견한 한글 NFC 경계 2건도 포함한다.
- unicode/: Unicode 15.1.0 공식 원본과 라이선스, 파일별 SHA-256 manifest. 정규화 corpus는 두 언어 테스트가 직접 읽는다.
- generate-unicode.mjs: 같은 원본에서 Swift/JS case-folding 1,530개와 제거할 결합 발음 기호 707개의 런타임 표를 생성한다. 서비스 실행 중 자료 다운로드나 파싱은 없다.

    node contracts/chat-search/generate-unicode.mjs
    node contracts/chat-search/generate-unicode.mjs --check

두 번째 명령은 파일을 수정하지 않고 생성 자료가 원본과 일치하는지 확인한다. Node 필수 테스트에도 포함한다. 원본 자료·매핑·fixture를 바꾸면 인덱스 버전과 저장/조회 호환성을 함께 검토한다.

Xcode의 OutPickTests Resources에 이 폴더를 연결했다. 제품 앱에는 원본 corpus를 넣지 않으며 런타임은 생성된 Swift/JS 상수만 사용한다. 라이선스는 생성 소스와 앱 Resources에도 보존한다. 테스트는 원본 SHA-256, 전체 매핑, 정규화 corpus, 고정 token·문자소 포함 기대값을 확인한다.

서버 helper는 messagePayload/sequenceStore에 연결됐고 앱은 v2 후보 페이지를 조회한다. 인덱스 필드가 없는 기존 메시지는 서버 검색에 나타나지 않는다. 기존 자료 backfill은 이번 범위에서 제외했으므로 다른 환경 배포 시 writer·인덱스 준비와 기존 데이터 처리 방침을 함께 확인한다.

공식 원본: https://www.unicode.org/Public/zipped/15.1.0/UCD.zip
라이선스: unicode/LICENSE.txt (https://www.unicode.org/license.txt).
