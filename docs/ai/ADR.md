# OutPick ADR

## 목적

중요한 기술 결정과 그 이유를 기록한다.

이 파일은 ADR 인덱스다. 상세 본문은 `docs/ai/adr/` 아래 개별 문서를 확인한다.

## 작성 기준

ADR에 기록할 것:

- 기술 스택 선택
- 아키텍처 패턴 선택 또는 변경
- 저장소, 서버, Firebase, Cloud Functions, Firestore rules 관련 중요한 결정
- 사용자 흐름이나 데이터 구조에 큰 영향을 주는 결정
- 앱 실행 중 상태 동기화, 캐시, invalidation stream처럼 여러 화면의 정합성에 영향을 주는 결정
- 기존 결정을 바꾼 이유

ADR에 기록하지 않을 것:

- 단순 UI 문구 변경
- 작은 버그 수정
- 파일명 변경만 있는 작업
- 일회성 로그나 임시 디버깅 메모

## 인덱스

| ID | 상태 | 핵심 결정 | 상세 |
| --- | --- | --- | --- |
| ADR-001 | accepted | OutPick은 기존 MVVM-C + Repository + UseCase + DI 흐름을 우선한다. | [상세](adr/ADR-001-outpick은-기존-mvvm-c-repository-usecase-di-흐름을-우선한다.md) |
| ADR-002 | accepted | UIKit 앱 수명주기 위에 SwiftUI 기능 화면을 점진 연결한다. | [상세](adr/ADR-002-uikit-앱-수명주기-위에-swiftui-기능-화면을-점진-연결한다.md) |
| ADR-003 | accepted | 공식 하네스와 로컬 하네스를 분리한다. | [상세](adr/ADR-003-공식-하네스와-로컬-하네스를-분리한다.md) |
| ADR-004 | accepted | 새 기능/수정은 하네스 문서를 먼저 보고 필요한 코드만 탐색한다. | [상세](adr/ADR-004-새-기능-수정은-하네스-문서를-먼저-보고-필요한-코드만-탐색한다.md) |
| ADR-005 | accepted | 모호한 제품/기술 결정은 구현 전에 사용자와 논의한다. | [상세](adr/ADR-005-모호한-제품-기술-결정은-구현-전에-사용자와-논의한다.md) |
| ADR-006 | accepted | Firebase/Firestore 운영 변경은 명시 승인과 검증 절차를 우선한다. | [상세](adr/ADR-006-firebase-firestore-운영-변경은-명시-승인과-검증-절차를-우선한다.md) |
| ADR-007 | accepted | 좋아요 탭은 상호작용 Store 기반으로 앱 실행 중 상태를 반영한다. | [상세](adr/ADR-007-좋아요-탭은-상호작용-store-기반으로-앱-실행-중-상태를-반영한다.md) |
| ADR-008 | accepted | URL 기반 시즌 import는 Firestore job queue와 Cloud Run worker로 처리한다. | [상세](adr/ADR-008-url-기반-시즌-import는-firestore-job-queue와-cloud-run-worker로-처리한다.md) |
| ADR-009 | accepted | 앱 미배포 기간에는 불필요한 하위 호환성을 유지하지 않는다. | [상세](adr/ADR-009-앱-미배포-기간에는-불필요한-하위-호환성을-유지하지-않는다.md) |
| ADR-010 | accepted | OutPick은 다크 전용 디자인 시스템을 사용한다. | [상세](adr/ADR-010-outpick은-다크-전용-디자인-시스템을-사용한다.md) |
| ADR-011 | accepted | 룩북 채팅 공유는 snapshot 렌더링과 상세 비동기 최신화를 분리한다. | [상세](adr/ADR-011-룩북-채팅-공유는-snapshot-렌더링과-상세-비동기-최신화를-분리한다.md) |
| ADR-012 | accepted | 룩북 공유 메시지는 새 소켓 이벤트로 전송하고 기존 메시지 스트림으로 수신한다. | [상세](adr/ADR-012-룩북-공유-메시지는-새-소켓-이벤트로-전송하고-기존-메시지-스트림으로-수신한다.md) |
| ADR-013 | accepted | 룩북 채팅 공유는 Chat 접합부를 먼저 만들고 거대 ViewController에 직접 붙이지 않는다. | [상세](adr/ADR-013-룩북-채팅-공유는-chat-접합부를-먼저-만들고-거대-viewcontroller에-직접-붙이지-않는다.md) |
| ADR-014 | accepted | 운영 소켓 서버의 Firebase Admin 키는 커밋하지 않는다. | [상세](adr/ADR-014-운영-소켓-서버의-firebase-admin-키는-커밋하지-않는다.md) |
| ADR-015 | accepted | 여러 Phase 작업은 병렬 조사와 충돌 기준 구현 분기를 사용한다. | [상세](adr/ADR-015-여러-phase-작업은-병렬-조사와-충돌-기준-구현-분기를-사용한다.md) |
| ADR-016 | accepted | 채팅 미디어 업로드는 얇은 reservation과 메시지 ready projection으로 처리한다. | [상세](adr/ADR-016-채팅-미디어-업로드는-얇은-reservation과-메시지-ready-projection으로-처리한다.md) |
| ADR-017 | accepted | 이미지 확대 viewer는 Infra 공용 UIKit viewer로 통일한다. | [상세](adr/ADR-017-이미지-확대-viewer는-infra-공용-uikit-viewer로-통일한다.md) |

## 새 ADR 추가 절차

1. `docs/ai/adr/ADR-XXX-title.md` 파일을 만든다.
2. 제목은 `# ADR-XXX: 제목` 형식을 사용한다.
3. 본문에는 `상태`, `결정`, `이유`, `트레이드오프`, `재검토 조건`을 필요한 범위로 기록한다.
4. 이 인덱스에 한 줄을 추가한다.
