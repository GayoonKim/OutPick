# 아바타 이미지 로딩 세부 구현 계획

상태: 2026-09-21 Phase0~5 완료. [최종 범위·검증·한계](progress/phase-5.md). JPEG0.8 승격, 디스크100/75MiB, 선로딩1.5/0.5·고유24·이탈300ms, 원본30초를 유지한다. VoiceOver는 사용자 명시 제외. QA 자료·임시코드 정리와 일반DEV복구 완료. 다음은 채팅방 대표 이미지 설계이며 아직 시작하지 않았다.

읽는 순서: [설계](design.md) → [결정](decisions.md) → 아래 phase → [QA](qa-checklist.md) → [현재 상태](progress.md).

| Phase | 목표 | 선행 조건 | 상세 |
| --- | --- | --- | --- |
| 0 | 실제 호출/정책 계약·검증 기준 고정 | 구현 착수 승인 | [계약 확인](phases/phase-0-contracts.md) |
| 1 | 공용 비저장·승격·경합 기반 | Phase0 기술 결정 | [공용 기반](phases/phase-1-pipeline.md) |
| 2 | 아바타 서비스·DI·수명 계약 | Phase1 | [서비스와 세션](phases/phase-2-service.md) |
| 3 | 전체 화면 표시·프로필 확대 연결 | Phase2 | [화면](phases/phase-3-surfaces.md) |
| 4 | viewport 선로딩·표시 계기 재시도 | Phase3 표시 identity | [선로딩](phases/phase-4-prefetch.md) |
| 5 | 통합 회귀·실기기 QA·수치 확정 | Phase1~4 구현 완료 | [검증](phases/phase-5-validation.md) |

## 실행과 충돌 관리

같은 pipeline/service protocol, AppCompositionRoot/Coordinator, ChatViewController를 순차적으로 바꾸므로 메인 작업에서 순차 구현한다. 병렬 구현·새 별도 작업 생성은 하지 않는다. 각 phase 시작 전 git 상태, 이전 결과, 다음 phase 변경 파일·DI·API 의존성을 다시 확인한다. 사용자 변경을 되돌리지 않는다.

신규 파일명은 계획상의 후보이며 기존 파일을 새로 존재한다고 보고하지 않는다. 불필요한 범용 추상화는 피하고 200줄 전후의 책임 혼합은 분리 후보로 검토한다. 공용 기반 기본 동작은 기존 소비자에 유지하며 아바타 정책만 명시적으로 주입한다.

## 각 phase 종료 조건

- 목표·자동 테스트 결과·미검증 항목·변경 파일을 progress/{phase}.md에 기록하고 progress 인덱스 갱신.
- 실제 진입점은 ENTRYPOINTS와 entrypoints/PROFILE·CHAT·LOOKBOOK·APP·TESTS 중 관련 문서에 반영.
- 새로운 기술 결정은 decisions 상세에 기록. 여러 후속 작업에 적용할 비저장/승격 계약은 ADR 갱신 후보로 검토.
- 합의 범위 내 구현을 진행하되 미정의 제품/데이터/성능 tradeoff 발견 시 해당 부분을 멈추고 논의한다.
- 서버 배포·운영 데이터 변경·앱 삭제·캐시 강제 초기화·커밋/PR/머지는 이번 계획 작성으로 실행하지 않는다. QA에 필요한 상태 변경은 대상과 범위를 먼저 명확히 한다.

## 이후 순서

이 작업 완료 후 채팅방 대표 이미지 → 채팅 사진·공유 카드·영상 썸네일 → GIF 원본 → 관리자 preview → 남은 외부 URL → 로컬 미디어 → 확대·저장 잔여 경로 순으로 설계한다. 각 항목은 실제 잔여 여부와 관리자 웹 전환 의존성을 먼저 확인한다. 기존 chat-media-first-view-loading은 첨부 이미지 단계의 관련 후속 문서이며 이번 아바타에 합치지 않는다. Production 미디어 배포와 관리자 웹 작업은 별도 대기 유지.
