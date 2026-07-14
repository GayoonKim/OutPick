# Deployment Boundary Decisions

## D3. 현재 배포 경계를 유지한다

상태: 확정

결정:

- Swift 모듈은 하나의 OutPick iOS 앱 target으로 빌드한다.
- Functions 모듈은 functions default codebase와 기존 flat export를 유지한다.
- Socket 모듈은 하나의 Docker image와 outpick-socket Cloud Run service로 유지한다.

이유:

- source module은 코드 소유권과 의존성 경계다.
- deployment unit은 독립 배포, 확장, 장애, IAM, 데이터 소유권 경계다.
- 이번 문제는 source/dependency 집중이며 새 runtime 경계가 필요한 근거는 아직 없다.

트레이드오프:

- 한 기능만 변경해도 같은 앱 또는 service revision을 배포할 수 있다.
- 대신 서비스 간 네트워크 호출과 분산 운영 비용을 추가하지 않는다.

배포 의미:

- 파일 수가 늘어도 iOS는 하나의 앱 바이너리다.
- Functions는 내부 .ts 파일별로 배포하지 않고 export된 Function 리소스를 codebase에서 발견한다.
- Socket은 여러 .js 파일을 Docker image 하나에 포함해 Cloud Run revision 하나로 배포한다.

재검토 조건:

- module별 독립 배포 필요가 반복적으로 확인된다.
- 특정 module만 독립 autoscaling 또는 별도 IAM이 필요하다.
- 장애 전파를 process 수준에서 막아야 한다.
- 서비스 분리에 따른 운영 비용보다 독립성 이점이 커진다.
