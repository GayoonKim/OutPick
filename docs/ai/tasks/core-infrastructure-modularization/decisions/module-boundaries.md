# Module Boundary Decisions

## D1. 배포 단위 내부는 기능별 modular monolith로 구성한다

상태: 확정

결정:

- iOS, Firebase Functions, Socket 각각의 현재 배포 단위 내부를 기능별 모듈로 나눈다.
- source file 분리를 실제 dependency boundary와 함께 수행한다.
- 이번 task에서 microservice 또는 별도 Firebase codebase를 추가하지 않는다.

이유:

- 서로 다른 담당자가 같은 대형 파일을 수정하지 않고 기능 단위로 소유할 수 있어야 한다.
- 현재 규모에서 독립 서비스의 네트워크, 인증, 관측성, 분산 실패 비용보다 코드 경계 개선의 가치가 크다.
- 현재 OutPick도 iOS 앱, Functions, Socket Cloud Run이라는 서로 다른 런타임 경계를 이미 갖고 있다.

트레이드오프:

- 파일과 type 수, DI 조립 코드가 늘어난다.
- 초기 분리 과정에서 call site와 테스트 fixture 변경량이 크다.
- 배포 단위가 같으므로 한 모듈 변경이 같은 앱 또는 service 배포를 요구할 수 있다.

보류한 대안:

- functions 기능별 Firebase codebase 분리.
- Socket room/message/media/push microservice 분리.
- Kubernetes 도입.

재검토 조건:

- 기능별 독립 배포 주기가 지속적으로 필요하다.
- 특정 기능의 확장, 장애 격리, IAM 또는 비용 경계가 다른 기능과 명확히 다르다.
- 팀과 데이터 소유권이 기능별로 장기간 독립된다.
- 서비스 간 계약과 운영을 전담할 인력 및 관측성이 준비된다.

## D2. 기능별 좁은 계약과 공통 runtime core를 사용한다

상태: 확정

결정:

- iOS 소비자는 capability별 Protocol에 의존한다.
- 기능별 Client/Store가 payload mapping, domain 변환, query를 소유한다.
- 공통 CloudFunctionsTransport는 SDK 호출, region, 공통 오류만 소유한다.
- 공통 AppDatabase는 DatabasePool과 migration 실행을 소유한다.
- Functions와 Socket entrypoint는 조립과 export/registration만 소유한다.

이유:

- 파일만 나누고 giant concrete type 의존을 유지하면 변경 영향과 테스트 비용은 줄지 않는다.
- Protocol은 소비자가 필요한 계약을 드러내고 fake/spy 대체점을 제공한다.
- 공통 runtime 생성 책임을 한 곳에 두면 singleton 남용과 초기화 중복을 막을 수 있다.

트레이드오프:

- 지나치게 작은 Protocol을 만들면 이름과 조립 비용만 늘 수 있다.
- capability 경계를 잘못 잡으면 기능 간 helper 공유 또는 순환 의존이 생길 수 있다.

경계 원칙:

- 함수 하나당 Protocol 하나를 만들지 않는다.
- 같은 소비자, 데이터, 변경 이유를 공유하는 capability를 한 계약으로 묶는다.
- 기능 간 공유는 concrete type이 아니라 정말 공통인 primitive helper 또는 별도 domain service로만 승격한다.
- 횡단 transaction과 orchestration은 이를 완결할 책임을 가진 operation이 소유한다.
