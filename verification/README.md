# OutPick 게이트 설정

프로젝트 루트에서 작업에 합의된 설정을 실행한다. 기본 설정 통과가 다른 설정의 통과를 대신하지 않는다.

```sh
node tools/verification-gate/gate.mjs --project . --config verification/gate.json
```

| 설정 | 범위 | 준비 조건 |
| --- | --- | --- |
| `gate.json` | 공용 자체 검사, Firebase 환경 shell 검사, Socket 구문·테스트 | Node 22 이상, Socket 의존성 |
| `functions.json` | Functions lint·빌드·테스트 | PATH의 Node 24, Functions 의존성 |
| `firestore.json` | Firestore/Storage Emulator·트랜잭션·seed 검사 | PATH의 Node 24, Java, Firebase CLI, Functions 및 rules 테스트 의존성, 로컬 포트 접근 |
| `ios.json` | Development Simulator 빌드와 AppRuntimeConfigurationTests 13개 | Xcode, iPhone 17 Pro/iOS 26.2 Simulator, 프로젝트의 로컬 Development 설정 |

Node 24를 사용하도록 PATH를 준비한 후 위 명령의 설정 파일을 바꾼다. 설치된 Node 버전이 다르면 게이트가 차단한다. 의존성·Simulator·로컬 Firebase 설정을 준비하지 않은 clone은 통과로 기록하지 않는다. 비밀 설정과 실행 로그는 저장소에 커밋하지 않는다.

프로젝트의 `inputs`는 관련 테스트·설정·실행 스크립트·의존 코드를 포함해야 한다. 입력 경로나 필수 테스트를 추가/제거하는 변경은 해당 작업의 계획에서 검토한다. Node 필수 ID는 초기 연결 확인용 기준이며 새로운 기능의 요구사항을 자동 검증하지 않는다. iOS 설정은 명시한 13개만 검증한다. 제품 UI/실기기/운영 배포 검사는 별도 연결 대상이다.

공용 원본과 설치 방법은 [실행기 설명](../tools/verification-gate/README.md), 실행 결과와 남은 범위는 [진행 기록](../docs/ai/tasks/programmatic-verification-gates/progress.md)을 따른다.
