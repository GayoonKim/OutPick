# Active Task Index

## 현재 상태

- 2026-09-10 최신 결정: 현재 미디어 변경을 커밋·PR·리뷰·머지한 뒤 **미디어 버블 이미지 깜빡임 제거**를 다음 최우선 핵심 작업으로 진행한다. 사용자는 저장 공간 확보 후 70장 전송·전송 중 조작·완료 후 재입장까지 확인하고 QA 방을 삭제했다. 아래 관리자 웹 작업은 그다음 순서다.
- 미디어 신규 계약 3은 Development 배포 및 3장/70장 실제 전송 확인 완료. Production 배포·영상 실제 QA·병렬 4 대 30 비교는 미수행. 과거 아래 queued 반환/병렬 묶음 기록은 최종 공용 FIFO 1·성공 UI 반영 또는 실패 후 다음 묶음 정책으로 대체된다.

### 다음 핵심 작업: 미디어 버블 이미지 깜빡임 제거

- 현상: 이미 표시된 사진이 플레이스홀더로 바뀌었다 돌아온다.
- 근거: `ChatMessageCell.previewItemID`가 hash와 로컬/원격 경로를 포함해 확정 시 identity가 바뀐다. `ChatImagePreviewCollectionView`는 이전 ID 이미지를 제거하고 갱신마다 layout을 재생성한다. `ChatImagePreviewCell.configure`는 이미지가 nil이면 기존 이미지를 지운 뒤 비동기 재로딩한다.
- 방향: 동일 첨부의 안정적 식별자, 로컬→서버 전환 중 기존 이미지 유지, 진행률 갱신과 사진 목록 갱신 분리. 다른 사진으로 셀이 재사용될 때 잘못된 이전 이미지는 표시하지 않는다.
- 검증: 대기/진행/확정, 스크롤 재사용, 방 재입장 수동 QA 및 동일 첨부 재설정·늦은 응답 경합 회귀.
- 상태: 기록만 완료. 현재 PR에 깜빡임 수정은 포함하지 않는다.

- 2026-09-10 이번 대화 최종 승인: `chat-media-bounded-parallel-upload` 상세 설계를 확정하고 로컬 구현·검증을 진행했다. 상세 상태는 해당 [progress](chat-media-bounded-parallel-upload/progress.md)를 우선한다. 아래 관리자 웹 우선순위는 다른 대기 작업 간 순서로 유지한다.

- 2026-09-10 사용자 결정: 핵심 작업 순서는 관리자 웹 전환 → iOS 관리자 콘솔 제거다. 고객지원 페이지와 Apple 로그인은 후순위로 보류한다.
- 다음 착수 대상은 `admin-web-operations-migration`의 설계 논의다. 상세 구현 계획과 구현은 아직 승인되지 않았다.
- `chat-room-moderator-delegation`은 완료되어 직전 완료 작업으로 이동했다.
- `lookbook-discovery-learning-loop`의 후속 구현·Production rollout 완료 기록을 확인해 대기 목록에서 제외했다. 상세 연결은 해당 task의 `progress.md` 최상단을 따른다.

## 현재 핵심 작업

- `chat-media-bounded-parallel-upload` — 구현·Development 배포·사진 실전 QA 완료, 커밋/PR 리뷰·머지 진행
  - [최종 설계](chat-media-bounded-parallel-upload/design.md), [구현 계획](chat-media-bounded-parallel-upload/plan.md), [진행·검증](chat-media-bounded-parallel-upload/progress.md), [QA](chat-media-bounded-parallel-upload/qa-checklist.md)

- `admin-web-operations-migration` — 다음 착수 대상, 설계 논의 대기
  - [기존 결정](admin-web-operations-migration/decisions.md)
  - 웹 기술 스택·화면/API 범위·권한 전환·검증 기준을 논의한 뒤 구현 계획을 작성한다.

## 직전 완료 핵심 작업

- `chat-room-moderator-delegation`
  - [설계](chat-room-moderator-delegation/design.md)
  - [결정](chat-room-moderator-delegation/decisions.md)
  - [Phase 계획](chat-room-moderator-delegation/plan.md)
  - [현재 상태](chat-room-moderator-delegation/progress.md)
  - [QA 기준](chat-room-moderator-delegation/qa-checklist.md)
  - 상태: 완료 — Production 반영·기능 활성화·최신 앱 QA·부모 장애 격리 수정·재검증·PR #26 자체 리뷰/머지 완료, main `a3911e32`
  - 후속: 관리자 웹 전환 설계 논의. 최소 지원 버전 상향·creatorUID 제거·외부 출시 준비는 별도 범위다.

## 구현·운영 승인 경계

- 구현 승인은 Phase 1 코드 변경 시작 권한이며 외부 배포 권한을 포함하지 않는다.
- Functions/Rules/Socket 배포는 구현·검증 후 별도 승인한다.
- Production read-only audit, ownerUID/counter backfill, 최소 지원 버전 상향, 기능 활성화, creatorUID 제거는 단계별로 각각 승인한다.
- 2026-09-02 사용자 확인상 앱 미출시·미운영이므로 최소 지원 버전 상향 없이 관리자 위임 서버·앱 flag를 활성화했고 최신 Production 빌드 임명/회수 QA를 통과했다. 부모 장애 격리 수정·재검증 후 최종 배포·커밋·PR 리뷰/머지 진행을 승인받았다.
- 고객지원 URL과 자동 의미 필터 관련 기존 App Review 1.2 외부 출시 gate는 moderator delegation이 해제하지 않는다.

## 핵심 작업 진행 순서

1. 미디어 버블 이미지 깜빡임 제거: 위 다음 핵심 작업의 범위로 진행한다.
2. `admin-web-operations-migration`: 플랫폼 총관리자 운영 기능을 localhost 관리자 웹으로 전환한다. 기존 iOS가 사용하는 권한·API의 호환과 최종 제거 시점을 먼저 설계한다.
3. `ios-admin-console-removal`: 관리자 웹의 필수 운영 기능 동등성 검증과 운영 경로 전환 후 iOS 관리자 콘솔·전용 연결을 제거한다. 일반 사용자 브랜드 요청과 채팅방 운영 기능은 유지한다.

- 문의 접수 방식·처리 이력의 구체 설계는 고객지원 작업과 함께 논의한다. 이를 관리자 웹의 다른 기능 착수 조건으로 두지 않는다.

## 추가 핵심 대기 작업

- `chat-media-bounded-parallel-upload`: 미디어 묶음의 제한된 병렬 전송 리팩토링
  - 2026-09-10 상세 논의 후 사용자가 구현을 승인해 현재 작업으로 승격했다. 이 항목의 이전 사용자별 슬롯/terminal 대기안은 최종 설계로 대체한다.
  - 목표: 현재 미디어 종류별 한 묶음 실행을 서버 예약 기반의 제한된 병렬 실행으로 확장해 대량 선택 시 전송 시간을 개선한다. 속도·안정성·대규모 사용자 적합성은 검증 대상으로 두며, 최적 구조로 검증됐다고 간주하지 않는다.
  - 확정 분할 정책: 선택 순서를 유지하면서 묶음당 150MiB를 넘기지 않는 범위에서 최대 30장으로 나눈다. 다음 사진을 넣으면 용량 또는 장수 제한을 넘는 시점에 분할하며, 용량을 채우기 위한 재정렬은 하지 않는다. 기존 `ChatMediaSelectionChunker`가 이미 이 정책을 구현한다.
  - 확정 실행 방향: 기기의 원본 확보·준비·업로드를 제한 병렬로 실행하고 queued 접수 직후 업로드 차례를 반환한다. 서버 사용자별 2/1 제한을 제거하고 전체 execution 제한은 유지한다. 구버전 서버의 슬롯 부족은 제한 빈도 대기로 호환한다.
  - 확정 공개 정책: 묶음 내부 사진 선택 순서는 유지하지만 묶음 간 선택 순서는 보장하지 않는다. 먼저 성공한 묶음부터 공개하며, 앞 묶음의 처리·실패 때문에 성공한 뒤 묶음을 대기시키지 않는다. 실패는 해당 묶음에만 적용하고 수동 재시도 성공 시 최신 메시지로 공개한다.
  - 선택 이유·대안: 현재 1개씩 처리하는 방식은 단순하지만 업로드와 서버 처리를 겹치지 못한다. 병렬 처리 후 선택 순서대로 공개하는 대안은 사용자 결정으로 채택하지 않는다. 완료 순서 공개를 선택해 기존 서버의 처리 완료 시 메시지 생성·seq 부여 계약을 유지하고 별도 공개 대기 상태를 추가하지 않는다.
  - 최종 기술·복구 정책: async/await+제한 TaskGroup, actor FIFO, GRDB 원본/outbox 소유권, Socket/status 성공 수렴. 전체 원본 확보 전 무표시, 정상 최종 묶음만 표시, 중단 후 미분할 원본만 대표 실패 복원, 수동 retry는 뒤에 접수한다. 미확정 서버 결과와 local 실패 UI를 분리한다.
  - 검증 후보: 동시 1개/2개의 전체·첫 묶음 표시 시간, 용량·장수 분할, 완료 역전, 일부 실패·재시도, 슬롯 부족·취소 경합, 중복·누락, 여러 사용자 동시 전송 시 대기·서버 부하.
  - 코드 진입점: `ChatMediaSelectionChunker.swift`, `ChatMediaUploadTurnQueue.swift`, `ChatMediaUploadUseCase.swift`, `ChatViewControllerExtension.swift`, `Socket/src/media/mediaUploadService.js`, `functions/src/chat/media/readyService.ts`. 기존 계약은 `chat-ugc-safety-room-moderation/decisions.md`의 Phase 7 미디어 정책을 참고한다.
  - 문서화: 실제 대안 비교·선택 이유·단점·재검토 조건을 설계 결정에 남긴다. 당시 actor 대안 비교 근거가 없는 부분은 현재 분석과 구분한다.

## 후순위·보류 작업

- `customer-support-https-page`: 공개 문의·제한 이의제기·신고 처리·개인정보·계정 삭제 경로 준비
  - 2026-09-10 사용자 결정: 관리자 웹 관련 작업보다 후순위로 미룬다. 외부 운영·출시 준비 전에 재검토한다.
  - 고객지원 경로 준비 전 실제 계정 제한·정지 운영과 외부 배포를 보류하는 기존 결정은 유지한다. 관리자 웹 구현·내부 QA는 진행할 수 있다.
- `sign-in-with-apple-account-lifecycle`: Apple 로그인·재인증·계정 삭제·재가입 principal 복원 설계
  - 2026-09-10 사용자 결정: 아직 App Store 출시 계획이 없어 후순위로 보류한다. 출시 준비 시점에 재검토한다.

## 별도 후속 범위

- 최소 지원 버전 상향과 `creatorUID` 제거: 관리자 위임 완료 범위와 분리해 진행한다.
- App Review 외부 출시 준비: 고객지원 URL과 자동 의미 필터 관련 기존 출시 gate를 확인한다. 관리자 위임 완료로 해제되지 않는다.

## 문서 관리 규칙

1. 이 문서에는 현재 핵심 작업 한 건과 직전 완료 작업만 상세 링크로 유지한다.
2. 오래된 완료 이력은 각 task의 `progress.md`와 `docs/ai/ADR.md`에서 확인한다.
3. 코드 진입점이 바뀌면 `docs/ai/ENTRYPOINTS.md`와 관련 `entrypoints/*.md`를 함께 갱신한다.
4. 외부 배포·운영 데이터 변경·파괴 작업은 사용자 명시 승인 없이 진행하지 않는다.
