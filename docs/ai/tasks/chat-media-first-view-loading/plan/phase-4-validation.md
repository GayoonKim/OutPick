# Phase 4 — 통합 검증·QA·인계

선행: Phase 1~3 통합. 상세 수동 항목은 [QA 체크리스트](../qa-checklist.md)를 사용한다.

## 검증 층과 합격 기준

| 검증 | 핵심 기준 | 방법 |
| --- | --- | --- |
| 순수 viewport 정책 | visible 무상한, offscreen 고유24, 실제 이미지 교차 | frame 입력 단위 테스트 |
| 비동기 controller | 실패 회차당1회, 재등장 허용,300ms 해제, stale 차단 | 수동 clock/완료 barrier/spy |
| 공용 pipeline 연결 | 승격 시 다운로드 재시작0, 마지막 소비자 해제만 취소 | 실제 coordinator+fake repository |
| UIKit 연결 | 내부 collection 전체가 아니라 개별 이미지 frame 사용 | 중첩 layout integration |
| 초기·수신 | 미디어 응답 전에 메시지 표시/저장 접수 | hold loader+render/save spy |
| 실제 방 | 빠른 왕복 스크롤·재진입·가림 후 표시와 취소 정상 | Development 실기기 QA |

테스트는 구현과 같은 계산을 복제한 기대값 대신 경계 위치, 실제 실행/취소 횟수, 저장 접수 등 외부 관찰 가능한 결과로 검증한다.

## QA 실행 순서

1. 현재 기기·앱 버전·방·캐시 상태를 기록한다. 기존 캐시를 임의 삭제하거나 앱을 재설치하지 않는다.
2. 기존 미디어 QA방에서 과거30장 묶음을 천천히/빠르게 양방향 스크롤한다. 화면 내 미로딩, 이미지 뒤바뀜, 재사용 깜빡임을 확인한다.
3. 실패 주입 환경에서 표시 중 실패→계속 표시→완전히 벗어남→복귀→방 재진입 순서로 요청 수를 확인한다.300ms 안 재등장과 선로딩 범위 안 재등장도 포함한다.
4. 확대 화면/완전 가림/백그라운드 전환 후 채팅 소비자 해제와 복귀를 확인한다. 다른 화면의 같은 resource 요청은 살아 있어야 한다.
5. 대량 새 메시지 수신과 로컬 전송 확정을 확인한다. thumbnail을 지연시켜도 메시지는 먼저 표시되고 기존 저장 흐름에 들어가야 한다.
6. 검색 이동·과거 페이지 prepend·회전·키보드·삭제 상태에서 요청 영역과 표시 연속성을 확인한다.
7. GIF/영상/공유 카드를 별도 확인한다. 조사 당시 해당 방에는 남아 있는 GIF/영상이 없어 사진 QA만으로 통과 처리하지 않는다. 새 fixture 전송/오류 주입/캐시 변경이 필요하면 정확한 대상과 범위를 먼저 정한다.

## 최소 계측과 수치 조정

기존 Debug 계측을 우선 사용한다. 부족한 경우 session/item/resource의 비식별 식별자, 요청 우선순위, 시작·완료·취소·실패·재시도 계기, 현재 희망 요청 수만 추가한다. 원본 URL의 인증 토큰/본문/사용자 메시지는 로그에 남기지 않는다.

- visible과 offscreen 희망 수요, 유예 중 소비자, 실제 다운로드 활성 수를 각각 측정한다.24는 동시 다운로드 상한이 아니다.
-1.5/0.5화면·24개·300ms는 한 번에 하나씩 조정하고 기기/스크롤/캐시 조건을 기록한다.
- 응답 시간의 임의 목표를 새 완료 기준으로 만들지 않는다. 화면 밖 불필요한 시작, 취소 후 재시작 낭비, visible 대기와 placeholder 체류를 비교한다.
- 여전히 남은 다운로드 직렬화·큰 thumbnail 바이트·원본 관리 문제는②/③ 후속으로 기록한다.①가 이 문제까지 해결한 것으로 해석하지 않는다.

## 실행 정책과 명령 후보

현재는 문서 작성 단계여서 빌드/테스트/기기 QA를 실행하지 않는다. 구현 시 프로젝트 지침에 맞춰 빌드하고, 자동 테스트 실행은 사용자의 명시 요청이 있을 때 수행한다. 실제 scheme/destination은 실행 전에 확인한다.

```sh
xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'generic/platform=iOS Simulator' build-for-testing
```

실행 가능한 Simulator ID를 확인한 뒤 관련 test class만 `-only-testing:OutPickTests/<실제 클래스명>`으로 지정한다. `generic` destination으로 test 실행하지 않는다. 실제 명령·로그·결과 bundle 경로·실패 원인을 progress에 남긴다.

## 변경 문서와 종료 조건

- 코드 변경과 함께 `docs/ai/ENTRYPOINTS.md`, `docs/ai/entrypoints/CHAT.md`에 새 viewport 진입점/DI/요청 수명을 기록한다.
- 테스트 추가 시 `docs/ai/entrypoints/TESTS.md`에 fake와 경합 시나리오 진입점을 남긴다.
- task progress/QA에는 작성·빌드 성공·테스트 실행 성공·수동 QA를 구분한다. 미실행 검증을 완료로 체크하지 않는다.
- 최종 보고는 변경 파일, 합의 정책, 검증 결과/미검증 한계,②/③ 남은 범위로 구성한다. 사용자 기존 HANDOFF/미추적 파일은 보존하고 임의 커밋하지 않는다.
- phase 종료 시 추가 설계 쟁점이 없으면 검증 결과를 정리한다.②는 공용 network/I/O 경계와 다른 화면의 영향을 확인한 뒤 별도 세부 설계를 진행한다.
