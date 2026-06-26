# ADR-014: 운영 소켓 서버의 Firebase Admin 키는 커밋하지 않는다


상태: accepted

결정:

- `Socket/*firebase-adminsdk*.json` 같은 Firebase Admin 서비스 계정 키는 커밋하지 않는다.
- `.gitignore`에 `**/*firebase-adminsdk*.json`, `Socket/node_modules/`를 보강한다.
- 소켓 서버는 서비스 계정 JSON 파일명을 직접 require하지 않고 `FIREBASE_SERVICE_ACCOUNT_JSON` env secret 또는 Application Default Credentials로 초기화한다.
- 로컬 실행은 `GOOGLE_APPLICATION_CREDENTIALS`가 가리키는 ignored local secret 파일을 사용한다.

이유:

- Firebase Admin 서비스 계정 JSON에는 private key가 포함된다.
- 키가 저장소에 올라가면 운영 데이터 접근 권한이 노출될 수 있다.

트레이드오프:

- 로컬 실행과 배포 환경 설정이 별도로 필요하다.
- 대신 저장소에서 비밀정보를 제거해 보안 리스크를 낮춘다.

