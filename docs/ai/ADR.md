# OutPick ADR

- 2026-10-07 제품 룩북 재시도 최종: 비정상 종료는 exact oldrun의 project/service/revision/trace/instance 시스템 증거와 현재 실행권을 재검사한 뒤 해당 시즌을 처음부터 자동 총5회 처리한다. 중간 이미지 복원은 제외한다. 승인 저장 실패 뒤 새추출은 새검토를 요구하며, 실패 목록은 브랜드+source별 하나로 최신화하고 성공/명시적 안 함에 제거한다. 수동 재시도는 맨뒤 새execution/새5회다. 기존 파일은 실행별 경로·generation으로 보호하고 미참조 정리 예약만 남긴다. K실제OOM후attempt2 성공/L총5회소진후수동새성공·124JPEG를Development에서확인했다. FIFO는접수묶음sequence기준이고검토승인은새차례다. 실제장시간/24h삭제·정식관리자웹·최적수치/장기실패율은후속미검증이다. [최종근거](tasks/lookbook-import-performance/product-queue-q7-final-results.md).

- 2026-10-05 제품 룩북 FIFO Q4 복구·보관: 재시도는 대기 없이 최초 포함 총5회로 유지한다. 종료 불명확한 head는 시간만으로 넘기지 않고 exact project/service/revision/trace/instance platform evidence와 epoch/stateRevision/report digest를 다시 확인하는 전용 recovery inspect/resume만 허용한다. recovery route는 별도 OIDC identity 환경 설정 없이는 off다. 로그·IAM을 확인할 수 없으면 차단을 유지한다. terminal 미참조 asset만24시간 후 exact generation으로 정리하고 batch/brand minimum receipt30일·resolved failure 상세30일·recovery audit90일을 보존한다. 일일 정리는 batch 300, brand receipt100, audit100 건을 우선 예약해 전체500기록/5page/120초 한도에서 한 종류가 다른 종류를 굶기지 않게 한다. 로컬 gate 통과는 Development IAM/Cloud Run log·Storage 동작 검증이 아니다. [Q4 결과](tasks/lookbook-import-performance/product-queue-q4-results.md).

- 2026-10-05 제품 큐 Q3 저장·브라우저 경계: queue-owned 이미지의 최종 경로를 실행/epoch/write별로 분리하고 두 JPEG의 Storage generation 검증 뒤 현재 owner/epoch에서만 앱 참조를 갱신한다. 활성 업로드 ledger는 삭제를 fail-closed로 막는다. 한 Worker 인스턴스의 Chromium과 이미지/hash 처리는 공용 배타 gate를 사용하며 Chromium 진입 전에 같은 batch의 재사용 원본 cache를 비운다. 이미지 단계와 브라우저 단계의 일시적 중첩을 피하고 늦은 쓰기·삭제 경합·메모리 겹침 가능성을 낮춘다. 대가는 브라우저 전환 후 재다운로드와 이전 경로의 후속 정리다. Gate는 인스턴스 내부 경계일 뿐이며 다중 Cloud Run 인스턴스의 전역 상호배제를 대신하지 않는다. Linux/실 Storage 검증, legacy direct 경로 cutover, stale ledger 복구 전에는 제품 FIFO를 활성화하지 않는다. [Q3 결과](tasks/lookbook-import-performance/product-queue-q3-results.md).

- 2026-10-05 룩북 import 처리 방향 확정: 브랜드 요청은 접수 순서(FIFO)로 처리하고 현재 브랜드의 선택 시즌은 내부 병렬로 진행한다. 저장 완료·검토 대기·최종 실패와 실행 중 작업 정리 후 다음 차례로 넘기며, 자동 재시도 중 차례 유지·시즌 최초 포함 총5회를 따른다. 뒤에 온 작은 요청의 대기를 수용하고 순서 예측 가능성·단순성을 우선한다. 브랜드 간 공정 배분 스케줄러는 도입하지 않는다. 실제 두 비교 쌍의 전체 속도 이득3.35%/0.61%를 큰 성능 개선 근거로 쓰지 않는다. 요청 묶음·추가 접수·복구/API·초기 수치는 후속 설계, 제품 구현/운영 배포는 미완료다. [확정 사항·다음 설계](tasks/lookbook-import-performance/phase-4-brand-dispatch-design.md).

- 2026-09-16 이미지 Phase5 최종 사용자 결정: 자동/기능 QA와 iPhone14 아모멘토 비교 결과를 근거로 network6/decode2/I/O2(write1), decode/write 각각16MiB, viewport 진행1.5/반대0.5·최대24장·이탈300ms를 채택하고 Phase5 완료. 추가 튜닝 필요성을 보여주는 뚜렷한 근거가 없어 현재값을 유지했다. 표본·캐시·수동 조작 시간의 차이는 수용하되 모든 기기의 최적값/통계적 성능 개선을 주장하지 않는다. 실제 지연·메모리 압박·더 큰 목록에서 회귀가 확인되면 해당 병목을 기준으로 재검토한다. [실측·한계·승인](tasks/image-loading-stage-concurrency/phase-5-validation.md).

- 2026-09-16 Phase 5 채팅 미디어 사용자 선택: 방의 모든 과거 사진·영상을 무제한 자동 저장하지 않고, 화면 근처 썸네일을 선로딩하며 사용자가 연 원본·영상은 용량 제한 디스크 캐시에서 재사용한다. DEV 재설치 뒤 미디어 QA방 첫 방문은 느리고 재진입은 즉시 표시됐다. 현재 chat thumb는 업로드 계약상 원본 해상도/최대300MB이며 300MB `maxBytes`가 파일 전송 중 I/O 쓰기1 슬롯을 점유시키는 병목을 발견했다. 별도 개선의 수치·legacy 폴백은 설계 후 검증하며 기존 업로드 계약을 여기서 변경하지 않는다. [Phase 5 근거](tasks/image-loading-stage-concurrency/phase-5-validation.md).

- 2026-09-16 이미지 Phase4 사용자 확정: iOS 15.6 룩북 세 화면은 카드 frame/화면 높이 관찰과 미배치 행 높이 추정으로 희망 이미지를 정한다. 진행 방향1.5화면·반대0.5화면·최대24장·이탈300ms를 초기 QA 값으로 사용한다. 화면은 수요만 관리하고 실제 메모리/디스크/네트워크/준비 동시성은 공용 pipeline이 맡는다. [구현·QA 범위](tasks/image-loading-stage-concurrency/phase-4-lookbook-screens.md).

- 2026-09-16 이미지 Phase3 사용자 확정: 룩북 외부 URL 대체 이미지는 Storage와 네트워크 한도를 공유하며 URL·Referer·maxBytes별 memory/disk body+HTTP metadata를 보관한다. 서버 max-age 최대7일/없으면24시간, no-cache 재검증 전 미표시, no-store 저장 금지, 일반 만료본 우선 표시 후 ETag/Last-Modified 확인. 401/403/404/410은 기존본 제거·자동 중단, 일시 오류는 30초/2분/10분 최대3회. [구현·범위](tasks/image-loading-stage-concurrency/phase-3-http-cache.md).


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
| ADR-025 | accepted (로컬 실행기·프로젝트 연결 완료) | 사용자가 모델을 직접 변경하고 필수 검증을 프로그램적 게이트로 실행·판정한다. GitHub CI·신규 병합 통제 인프라는 포함하지 않는다. | [상세](adr/ADR-025-검증은-프로그램적-게이트로-판정하고-필수-검사로-병합을-통제한다.md) |

## 새 ADR 추가 절차

1. `docs/ai/adr/ADR-XXX-title.md` 파일을 만든다.
2. 제목은 `# ADR-XXX: 제목` 형식을 사용한다.
3. 본문에는 `상태`, `결정`, `이유`, `트레이드오프`, `재검토 조건`을 필요한 범위로 기록한다.
4. 이 인덱스에 한 줄을 추가한다.
