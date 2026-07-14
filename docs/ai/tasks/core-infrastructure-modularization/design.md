# Core Infrastructure Modularization Design

## 목적

OutPick의 네 개 대형 인프라 진입점을 기능 책임과 소비자 계약 기준으로 분리한다.

- iOS Cloud Functions 호출: OutPick/DB/Firebase/CloudFunctions/CloudFunctionsManager.swift
- iOS 로컬 데이터베이스: OutPick/DB/GRDB/GRDBManager.swift
- Firebase Functions: functions/src/index.ts
- Socket Cloud Run 서버: Socket/index.js

이번 작업의 목표는 파일 수를 줄이는 것이 아니다. 여러 개발자가 서로 다른 기능을 담당해도 자신이 소유한 기능 계약과 구현만 이해하고 변경할 수 있도록 공개 표면, 의존 방향, 조립 지점을 좁히는 것이다.

## 처음 읽을 순서

1. 이 문서에서 공통 목표와 제약을 확인한다.
2. 구현 대상에 맞는 상세 설계를 하나만 읽는다.
3. decisions.md에서 확정/승인 대기 상태를 확인한다.
4. plan.md와 progress.md에서 현재 단계와 다음 작업을 확인한다.

## 상세 설계

| 영역 | 설계 |
| --- | --- |
| iOS Cloud Functions | [기능별 Protocol/Client와 공통 transport](designs/ios-cloud-functions.md) |
| iOS GRDB | [기능별 Store와 공통 AppDatabase](designs/grdb.md) |
| Firebase Functions | [기능별 handler/service와 flat export](designs/functions.md) |
| Socket Cloud Run | [기능별 handler/service와 server bootstrap](designs/socket.md) |

## 핵심 문제

- 서로 다른 비즈니스 기능이 하나의 대형 concrete type 또는 entrypoint에 모여 있다.
- 소비자가 필요한 기능보다 훨씬 넓은 객체에 의존한다.
- 공통 런타임과 기능 로직, payload 변환, 저장소 쿼리, 이벤트 등록이 섞여 있다.
- 한 기능 변경이 대형 파일 충돌과 광범위한 회귀 검토를 유발한다.
- 담당자가 파일 전체를 읽어야 transaction 또는 wire contract를 찾을 수 있다.

현재 파일 규모:

- CloudFunctionsManager.swift: 약 1,629줄
- GRDBManager.swift: 약 1,721줄
- functions/src/index.ts: 약 7,809줄
- Socket/index.js: 약 1,414줄

줄 수는 분리의 유일한 근거가 아니다. 독립적으로 변경되는 책임과 외부 계약을 여러 개 포함한다는 점이 핵심 근거다.

## 합의된 목표 구조

각 배포 단위 안에서는 기능별 모듈을 분리하되, 현재 배포 경계는 유지한다.

~~~text
iOS 앱
  ├── 기능별 Protocol
  ├── 기능별 Cloud Functions Client / GRDB Store
  ├── 공통 CloudFunctionsTransport / AppDatabase
  └── CompositionRoot / Container 조립

Firebase Functions codebase
  ├── 기능별 callable / trigger 모듈
  ├── 기능별 service / mapper / validation
  ├── 공통 Firebase Admin / runtime bootstrap
  └── index.ts flat export

Socket Cloud Run service
  ├── 기능별 handler / service
  ├── 공통 auth / runtime state / Firebase Admin
  └── index.js server bootstrap
~~~

이번 작업에서 Firebase codebase 분리, Socket microservice 추가, Kubernetes 도입, 데이터베이스 분리는 하지 않는다.

## 요구사항

- 기존 사용자 기능과 운영 기능의 동작을 유지한다.
- iOS 소비자는 필요한 기능만 표현하는 Protocol에 의존한다.
- 기능별 Client/Store/handler/service가 payload 변환, query, 기능 orchestration을 소유한다.
- 공통 Firebase Functions 호출 transport와 공통 GRDB DatabasePool은 한 곳에서 생성하고 주입한다.
- Firebase Functions index.ts는 flat export, Socket index.js는 생성과 조립 및 시작만 담당한다.
- 한 기능 변경이 unrelated feature 파일 수정으로 확산되지 않게 한다.
- 테스트에서 실제 SDK/runtime를 불필요하게 직접 사용하지 않도록 fake/spy 경계를 제공한다.

## 비목표

- 새 사용자 기능, 화면 또는 사용자 흐름.
- Firestore/GRDB schema, Storage path, callable payload/response 변경.
- Firebase Functions 리소스 이름 변경 또는 삭제.
- Socket event 이름, payload, ACK 형식 변경.
- Firebase Functions를 여러 codebase나 독립 서비스로 분리.
- Socket room/message/media를 별도 Cloud Run 서비스로 분리.
- Docker orchestration 변경 또는 Kubernetes 도입.
- 요청 범위 밖 View/ViewModel/Coordinator 리팩터링.

## 구현 가능성

구현 가능하다.

- Xcode는 OutPick folder synchronized group을 사용한다.
- TypeScript는 functions/src 전체를 lib 아래로 빌드하고 package main은 lib/index.js다.
- Firebase CLI는 functions codebase의 index export를 Function 리소스로 인식한다.
- Socket은 ES module import를 사용하고 Dockerfile은 Socket 디렉터리를 이미지 하나로 복사한다.
- Socket/index.js도 일부 service factory를 이미 주입 방식으로 사용한다.

## 기술 스택

새 프레임워크는 도입하지 않는다.

- iOS: Swift, protocol-based DI, async/await, GRDB, FirebaseFunctions
- Functions: TypeScript, NodeNext ES modules, Firebase Functions Gen 2, Firebase Admin
- Socket: Node.js ES modules, Socket.IO, Express, Firebase Admin
- 배포: iOS 앱, Firebase Functions default codebase, Socket Cloud Run service
- 테스트: 기존 Swift Testing/XCTest, Node built-in test 또는 현재 npm test 흐름

Socket 자동 테스트 명령 추가는 구현 전 사용자 결정이 필요하다.

## 공통 의존성 방향

허용:

~~~text
View / ViewModel
  → UseCase / Repository Protocol
  → Repository implementation
  → capability Protocol
  → Client / Store
  → shared Transport / Database
  → SDK
~~~

금지:

- View/ViewController에서 Firebase Functions 또는 GRDB 직접 호출.
- 기능별 Client/Store가 singleton concrete dependency를 새로 생성.
- 기능 A가 기능 B의 concrete Client/Store를 직접 참조.
- Functions handler가 다른 handler를 직접 호출.
- Socket handler가 index.js module global에 암묵적으로 의존.
- migration과 runtime query가 같은 대형 파일에 다시 누적.

## 사용자·화면·API·데이터 범위

- 새 화면과 navigation은 없다.
- 리팩터링 전후 loading/error 문구와 사용자 흐름은 같아야 한다.
- 외부 API를 새로 설계하지 않는다.
- 기본 제안은 callable/trigger/Socket wire contract와 GRDB schema를 유지하는 것이다.
- 구조 분리 중 schema/API 변경 필요가 발견되면 구현을 멈추고 별도 설계를 작성한다.

대표 회귀 흐름:

- Kakao 로그인과 Firebase custom token 교환
- 브랜드 관리자 권한, 브랜드/시즌 관리
- 좋아요/저장, 댓글/답글, 신고/차단
- 시즌 import/진단/재시도
- 룩북 삭제 요청/복구/재시도
- 채팅방 목록/입장/검색
- 텍스트/이미지/비디오/룩북 공유 메시지
- 채팅방 나가기/닫기와 로컬 데이터 정리

## 배포 설계

- Swift 파일은 하나의 iOS 앱 바이너리에 포함된다.
- Functions 모듈은 default codebase로 빌드되고 기존 Function export를 유지한다.
- Socket 모듈은 Docker image 하나와 outpick-socket Cloud Run service로 배포된다.
- 소스 파일 수 증가는 배포 서비스 수 증가를 의미하지 않는다.

## 완료 기준

- 네 대형 파일이 얇은 entrypoint/core 책임만 가지거나 제거된다.
- 소비자는 필요한 capability Protocol만 받는다.
- 공통 transport/database/runtime는 한 곳에서 생성되고 주입된다.
- 승인된 composition/bootstrap 지점 외 singleton concrete 접근이 남지 않는다.
- Functions index.ts는 flat export, Socket index.js는 server bootstrap 중심이다.
- GRDB migration과 transaction 경계가 보존된다.
- 기존 wire/data contract가 보존되거나 승인된 변경만 반영된다.
- 각 기능 모듈의 테스트와 검증 진입점이 문서화된다.
- 관련 ENTRYPOINTS, CODE_ARCHITECTURE, ADR가 실제 새 구조를 가리킨다.

## 구현 전 필요한 결정

1. 네 영역의 구현 순서.
2. 기존 CloudFunctionsManager/GRDBManager 임시 façade 허용과 제거 시점.
3. 외부 wire/data contract 보존 수준.
4. Socket Node built-in 자동 계약 테스트 추가.
5. callHelloUser 디버그 호출 제거.

추천안은 decisions.md와 상세 결정 문서를 따른다. 이 결정이 확정되기 전에는 구현 phase를 시작하지 않는다.

## 문서 진입점

- 현재 상태: progress.md
- 제안 단계: plan.md
- 결정 상태: decisions.md
- 검증 설계: qa-checklist.md
- 장기 결정: docs/ai/adr/ADR-019-핵심-인프라는-기능별-모듈러-경계와-현재-배포-단위를-유지한다.md
