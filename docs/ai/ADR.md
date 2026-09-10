# OutPick ADR

- 2026-09-10 최신 사용자 확정: 최종 미디어는 iOS에서 원해상도 본 파일/썸네일로 생성하고 최종 경로에 직접 업로드한다. 서버 내용 재검사·재가공·파일 복사·SHA-256 재계산을 제거하고 업로드 완료/현재 전송 권한/취소·멱등성만 확정 경계에서 확인한다. Socket 계약3이 메시지 확정을 소유하고 worker는 신규 경로에서 제외한다. 실제 기존 실패 자료만 재준비하며 운영 데이터·리소스 임의 삭제 없음. [상세 설계](tasks/chat-media-bounded-parallel-upload/direct-upload-detailed-design.md).

- 2026-09-10 사용자 승인으로 미디어 묶음을 공용 FIFO에서 순차 처리한다. 최종 버블을 선택 순서대로 먼저 표시하고, ready 및 정상 메시지 UI 반영 또는 일반실패 표시 이후 실행권을 반환한다. 묶음 내부 PUT/서버 처리는 제한 병렬이다. 완료 순서 예측 가능성을 위해 묶음 병렬의 처리량 이점을 포기한다. 대기 버블은 고정원형과장수로 처리중 회전과 구분한다. 실제 네트워크 장애/이탈 정책은 유지한다. [최신 설계](tasks/chat-media-bounded-parallel-upload/design.md).

- 2026-09-10 이미지 dispatcher의 성공 ACK는 worker 종료만이 아니라 ready/슬롯반환 트랜잭션 완료 뒤에 보낸다. 실제70장 QA에서 슬롯 반환 전에 다음 Task가429를 받아30초 대기한 근거에 따른 결정이다. 기존 Firestore 완료 이벤트를 같은 멱등 publisher의 복구·정리 경로로 유지하고 expected lease로 stale 실행을 차단한다. Cloud Tasks의 진짜 장애 재시도는 유지하며 video Job 실행 방식은 변경하지 않는다. [근거와 검증](tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md).

- 2026-09-10 미디어 서버 지연 개선: 정상 PUT 후 완료 확인을 finalize로 통합하고 누락 응답에만 refresh 재개를 사용한다. 서버 검증 항목은 유지하며 조회 결과를 manifest에 재사용한다. metadata와 worker 사진 처리 폭은 독립 설정·기본1로 두고 실제 동일 사진 QA로 선택한다. 순서 보존·첫 실패 drain·generation/lease 보호·사진별 임시 파일 정리를 병렬화의 전제로 둔다. [설계/검증](tasks/chat-media-bounded-parallel-upload/qa/server-pipeline-optimization.md).

- 2026-09-10 실제 미디어 QA 후 이탈 경계 보정: 방 내부 사진 보기·정보 화면은 전송을 유지하고, 실제 채팅방 route 종료·앱 백그라운드에서 중단한다. `viewWillDisappear`의 포괄 취소를 기존 route 종료 판정으로 옮겨 방 내부 화면이 실패를 유발하는 결함을 해소한다. [보정 설계](tasks/chat-media-bounded-parallel-upload/design.md), [실제 전송 근거](tasks/chat-media-bounded-parallel-upload/qa/iphone14-live-transmission.md).

- 2026-09-10 미디어 제한 병렬 전송 결정: [최종 설계와 대안](tasks/chat-media-bounded-parallel-upload/design.md). async/await 작업 수명·actor FIFO·제한 TaskGroup·기존 Combine UI·GRDB 소유권·queued 차례 반환·서버 사용자 제한 제거의 이유를 기록했다. 실기기 성능/운영 부하 결과에 따라 초기 상한을 재검토한다.

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
| ADR-018 | accepted | 룩북 영구 삭제는 일일 bounded drain과 브랜드 lease로 처리한다. | [상세](adr/ADR-018-룩북-영구-삭제는-일일-bounded-drain과-브랜드-lease로-처리한다.md) |
| ADR-019 | accepted | 핵심 인프라는 기능별 모듈러 경계와 현재 배포 단위를 유지한다. | [상세](adr/ADR-019-핵심-인프라는-기능별-모듈러-경계와-현재-배포-단위를-유지한다.md) |
| ADR-020 | accepted | Firestore 문서 identity는 문서 경로 ID를 단일 기준으로 사용한다. | [상세](adr/ADR-020-firestore-문서-identity는-문서-경로-id를-단일-기준으로-사용한다.md) |
| ADR-021 | accepted | 사용자 계정과 앱 내 공개 프로필을 분리하고 서버가 쓰기를 통제한다. | [상세](adr/ADR-021-사용자-계정과-앱내-공개-프로필을-분리한다.md) |
| ADR-022 | accepted | 브랜드·시즌·사용자는 공용 스타일 무드 ID를 사용한다. | [상세](adr/ADR-022-브랜드-시즌-사용자는-공용-스타일-무드-id를-사용한다.md) |
| ADR-023 | accepted | 추출 fix는 Production runtime과 실제 input smoke로 검증한다. | [상세](adr/ADR-023-추출-fix는-production-runtime과-실제-input-smoke로-검증한다.md) |
| ADR-024 | accepted | UGC 안전은 canonical moderation principal과 서버 capability로 통합한다. | [상세](adr/ADR-024-ugc-안전은-canonical-moderation-principal과-서버-capability로-통합한다.md) |

## 새 ADR 추가 절차

1. `docs/ai/adr/ADR-XXX-title.md` 파일을 만든다.
2. 제목은 `# ADR-XXX: 제목` 형식을 사용한다.
3. 본문에는 `상태`, `결정`, `이유`, `트레이드오프`, `재검토 조건`을 필요한 범위로 기록한다.
4. 이 인덱스에 한 줄을 추가한다.
