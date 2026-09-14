# Active Task Index

## 현재 상태

- 2026-09-14 `chat-media-concurrency-qa-rollout`: 구현·iPhone41개/Socket124개·Development 배포·3장/70장 정상 전송/재입장·네트워크 실패 후 재시도 실기기 QA 완료. QA 계측 해제, 최종 정책 유지. [완료 근거](chat-media-concurrency-qa-rollout/progress.md). 남은 것은 커밋·PR·리뷰·머지, Production은 별도 대기. 아래 QA 대기 문구는 해소됐다.

- 2026-09-14 최종 조합3장+70장 Development 정상 QA 통과. 서버70장30/30/10·seq58~60·계약3 ready 및전체조회 확인, 사용자 전송/스크롤/입력/재입장 확인. 실기기 실패버블 복구 항목만 확인 중. [진행](chat-media-concurrency-qa-rollout/progress.md). 커밋/PR/Production 미수행.

- 2026-09-14 승인된 Development Socket `concurrency-all-0914`100% 반영 및 최신DEV 앱 설치·실행 완료. 원본4/준비전체/PUT4 기본값 확인, 서버 조회·서명·취소 정리 전체 실행 이미지 배포. `미디어 QA`3장 smoke 사용자 응답 대기,70장 결합 QA 미완료. [현재 진행](chat-media-concurrency-qa-rollout/progress.md). Production 미변경.

- 2026-09-14 구현 승인 후 `chat-media-concurrency-qa-rollout` Phase1~2 로컬 구현 완료. 원본4/준비전체/PUT4, 계약3 서버 조회·서명·취소 정리 전체 실행. iPhone41개/4 suites·Socket check/124개 통과. [진행](chat-media-concurrency-qa-rollout/progress.md). Development 서버 배포·실제 결합 QA·커밋/PR 미수행. 아래 구현 승인 전 문구는 이전 이력이다.

- 2026-09-14 최종 방향과 [세부 구현 계획](chat-media-concurrency-qa-rollout/plan.md) 작성 완료. 원본 확보4 유지, 계약3 서버 metadata 조회·URL 서명·취소 정리 모두 요청 대상 전체 실행으로 사용자 확정. FIFO1·준비전체·PUT4 유지. 남은 설계 선택 없음, 코드 구현 승인 전이며 배포 미착수.

- 2026-09-14 원본 확보4/전체 실기기 비교 완료: 4→all→4→all, 원본 확보1.630/0.411/0.505/0.437초. 매회70장·3묶음 앱 성공 및 사용자 조작 확인, 서버 문서 별도 감사 미수행. 반복4 대비 차이는 약0.07~0.09초로 체감 개선 입증 아님. 원본 확보 최종값은 추가 논의 대기, 실험 설정 해제·기본4 복원. [결과](chat-media-preview-continuity/acquisition-diagnosis.md). 정식 적용 구현 계획은 아직 미확정.

- 2026-09-14 `chat-media-concurrency-qa-rollout`: 사용자와 적용 방향 확정. 묶음 FIFO1·원본 확보4·이미지 준비 연속 사진 전체·파일 업로드4·서버 metadata 요청 내 전체 파일 조회, 영상 정책 유지. 방향 확정과 기록까지 완료했으며 정식 코드 반영·최종 결합 QA는 아직 미수행이다.

- 2026-09-12 미디어 동시성 개별 비교 완료. 사용자 요청으로 결과 적용·Development 검증·커밋/PR/리뷰/머지는 아래 핵심 대기 작업으로 **기록만** 한다. 이번 기록 요청으로 추가 구현·배포·커밋·PR·머지를 실행하지 않는다.

- 2026-09-11 현재 대화: `chat-message-cache-sync` — 완료. 합의된 QA·최종48개 회귀·iPhone14 개발 앱 설치/실행·3개 커밋·PR #29 자체 리뷰 및 main 머지 완료(`143544e5`). VoiceOver 제외·실기기 장시간 보류 유지. [진행](chat-message-cache-sync/progress.md).

- `shared-image-viewer-editorial` — 구현·빌드·자동 회귀12개·렌더링 및 이번 범위 실기기 QA 완료. 사용자 나머지 항목 모두 확인, 큰 글씨·VoiceOver는 명시적으로 QA 제외(미검증). [최종 기록](shared-image-viewer-editorial/implementation-plan.md). 커밋/PR 미수행. 기존 이미지 깜빡임/300MB 작업은 완료 상태 유지.

- 2026-09-11 최종: `chat-media-preview-continuity` 및 후속 사진300MB/실패 복구 작업 완료. 구현·Development 배포·사용자 실기기 QA 완료, Swift29회/Socket115개 통과. [최종 검증 범위](chat-media-preview-continuity/photo-size-failure-recovery.md).300MB 정확한 경계는 자동 테스트로 검증했고 실파일 경계 시험은 완료 조건에서 제외. 커밋/PR/머지 및 Production 배포는 미수행. 아래 깜빡임 착수/QA 대기 상태는 과거 이력이며 다음 핵심 대기는 관리자 웹 설계 논의다.

- 2026-09-10 최종: 사용자 요청으로 이번 미디어 구현·Development 배포·사진 QA·PR #27 머지 작업을 **완료** 처리했다(main `34831dfc`). Production 배포는 아래 별도 핵심 대기 작업으로 분리하며 아직 미승인·미수행이다. 다음 최우선은 이미지 깜빡임 개선이다.

- 2026-09-10 최신 결정: 현재 미디어 변경을 커밋·PR·리뷰·머지한 뒤 **미디어 버블 이미지 깜빡임 제거**를 다음 최우선 핵심 작업으로 진행한다. 사용자는 저장 공간 확보 후 70장 전송·전송 중 조작·완료 후 재입장까지 확인하고 QA 방을 삭제했다. 아래 관리자 웹 작업은 그다음 순서다.
- 미디어 신규 계약 3은 Development 배포 및 3장/70장 실제 전송 확인 완료. Production 배포·영상 실제 QA·병렬 4 대 30 비교는 미수행. 과거 아래 queued 반환/병렬 묶음 기록은 최종 공용 FIFO 1·성공 UI 반영 또는 실패 후 다음 묶음 정책으로 대체된다.

### 다음 핵심 작업: 미디어 버블 이미지 깜빡임 제거

- 2026-09-11 후속 로컬 구현 완료: 사진 본/썸네일 각각300,000,000bytes, 묶음 본파일 합계300,000,000bytes/30장, 실패 사진은 별도 실패 버블(재시도/삭제)로 보존. Swift28개 정의/29회 실행·Socket7개 통과. [현재 구현·검증](chat-media-preview-continuity/photo-size-failure-recovery.md)을 따른다. 서버 배포·새 정책 실기기 QA는 미수행.

- 2026-09-11 QA 후속: 31장 원본 확보 중 무반응 보고. index 0~17 복사 뒤 취소됐으며 사용자는 기다리다 앱·방을 이동했다고 확인했다. 최초 지연 원인은 미확정이다. 사용자 승인으로 [파일 제공/복사/대기·동시성 세부 계측](chat-media-preview-continuity/acquisition-diagnosis.md)을 진행하며 원인 확인 전 31장 깜빡임 QA는 통과 처리하지 않는다.

- 2026-09-11: 사용자 세부 계획·구현 승인 후 이미지 표시 보존 로컬 구현 완료. Development 앱 및 최종 테스트 코드 빌드 성공, 자동 테스트 실행·실기기 QA 미실시. 최신 상태는 [구현·검증 기록](chat-media-preview-continuity/implementation.md)을 따른다. 아래 기록만 완료 상태는 착수 전 이력이다.

- 현상: 이미 표시된 사진이 플레이스홀더로 바뀌었다 돌아온다.
- 근거: `ChatMessageCell.previewItemID`가 hash와 로컬/원격 경로를 포함해 확정 시 identity가 바뀐다. `ChatImagePreviewCollectionView`는 이전 ID 이미지를 제거하고 갱신마다 layout을 재생성한다. `ChatImagePreviewCell.configure`는 이미지가 nil이면 기존 이미지를 지운 뒤 비동기 재로딩한다.
- 방향: 동일 첨부의 안정적 식별자, 로컬→서버 전환 중 기존 이미지 유지, 진행률 갱신과 사진 목록 갱신 분리. 다른 사진으로 셀이 재사용될 때 잘못된 이전 이미지는 표시하지 않는다.
- 검증: 대기/진행/확정, 스크롤 재사용, 방 재입장 수동 QA 및 동일 첨부 재설정·늦은 응답 경합 회귀.
- 상태: 기록만 완료. 현재 PR에 깜빡임 수정은 포함하지 않는다.

- 2026-09-10 이번 대화 최종 승인: `chat-media-bounded-parallel-upload` 상세 설계를 확정하고 로컬 구현·검증을 진행했다. 상세 상태는 해당 [progress](chat-media-bounded-parallel-upload/progress.md)를 우선한다. 아래 관리자 웹 우선순위는 다른 대기 작업 간 순서로 유지한다.

- 2026-09-10 사용자 결정: 핵심 작업 순서는 관리자 웹 전환 → iOS 관리자 콘솔 제거다. 고객지원 페이지와 Apple 로그인은 후순위로 보류한다.
- 관리자 웹 전환은 이미지 깜빡임 개선 다음 대기 작업이며, 상세 구현 계획과 구현은 아직 승인되지 않았다.
- `chat-room-moderator-delegation`은 완료되어 직전 완료 작업으로 이동했다.
- `lookbook-discovery-learning-loop`의 후속 구현·Production rollout 완료 기록을 확인해 대기 목록에서 제외했다. 상세 연결은 해당 task의 `progress.md` 최상단을 따른다.

## 현재 핵심 작업

- `chat-media-concurrency-qa-rollout` — 적용 방향 확정, 코드 반영 전(2026-09-14)
  - 세부 계획: [Phase1~4 구현·검증 계획](chat-media-concurrency-qa-rollout/plan.md). 서버 전체 실행은 계약3 metadata 조회뿐 아니라 URL 서명·취소 정리에도 적용한다. 원본 확보4 최종 확정. 기존 계약2 동시성 설정은 유지한다.
  - 근거: [iPhone 14 동시성 비교 결과](../qa-media-upload-concurrency-2026-09-12.md). 8회·560장·24묶음 정상 저장, 사용자 매회 완료·스크롤·입력 이상 없음 확인.
  - 확정 방향: 묶음 FIFO1 유지 + 원본 확보4 + 이미지 준비 연속 사진 전체 동시 실행 + 파일 업로드4 + 서버 metadata 요청 내 전체 파일 동시 조회. 영상 정책은 유지한다. 이미지 준비는 30장으로 분할하기 전 연속 사진 구간 전체가 대상이며 30개 제한이 아니다. metadata도 고정60 제한 대신 요청 대상 전체를 조회한다. 현재 계약은 최대30장×본파일/썸네일=60파일이다. 향후 묶음 확대 후 지연·실패율 증가가 관측되면 제한 도입을 재검토한다.
  - 근거 수치: 업로드4는11.33/12.06초, 전체 동시 실행은19.33/70.15초. 준비 전체 동시 실행은3.82/3.98초(기존약6초), 관측 최고 메모리1338–1592MiB. 서버60 조회 합계0.475/0.200초(기존4는0.621–0.673초).
  - 다음 진행 순서: 확정 정책의 변경 파일·구현/검증 범위 정리 → 코드·관련 하네스 반영 및 필요한 회귀 → Development 앱/서버 반영 → 최종 결합 조합으로70장 실제 전송·메시지 순서/누락/중복·조작·메모리 확인 → 작업별 커밋 정리 → PR 생성 → 리뷰·지적사항 보완 → 검증한 head 머지. 적용 방향 확정을 배포·커밋·PR·머지 실행 승인으로 간주하지 않는다.
  - 완료 기준: 개별 측정 결과를 최종 조합 검증과 구분해 기록하고, Development 적용 상태·검증 결과·커밋·PR·리뷰·머지 근거를 남긴다. 여러 사용자 동시 부하는 미검증이므로 이번 결과를 전체 지원 기기의 최적값으로 단정하지 않는다.
  - 현재 상태: 앱 준비/업로드 기본4 및 Development 기존metadata4로 복원 완료. 서버 실험 트래픽은 `outpick-socket-development-photo300-0911`100%, 템플릿은 기존 이미지/metadata4의 `qa-restored-0912`. 비교용 코드·테스트·문서는 로컬 미커밋 상태로 보존한다.
  - 커밋 정리 시 이번 Swift 계측·설정·테스트, Socket 상한60/테스트, QA·진입점 문서를 구분한다. 기존 HANDOFF·포트폴리오·로컬 로그 등 무관 변경은 포함하지 않는다. Production 배포는 별도 대기 작업을 유지하며 이번 후속 범위에 포함하지 않는다.

- `chat-message-cache-sync` — 완료: 실기기 개발 앱 설치·PR #29 머지까지 완료. progress 참조.

- 미디어 버블 이미지 깜빡임 제거 및 사진300MB/실패 복구 — 완료. [최종 상태](chat-media-preview-continuity/photo-size-failure-recovery.md).

- `admin-web-operations-migration` — 깜빡임 개선 이후 설계 논의 대기
  - [기존 결정](admin-web-operations-migration/decisions.md)
  - 웹 기술 스택·화면/API 범위·권한 전환·검증 기준을 논의한 뒤 구현 계획을 작성한다.

## 직전 완료 핵심 작업

- `chat-media-bounded-parallel-upload` — 완료
  - [진행·검증](chat-media-bounded-parallel-upload/progress.md), [직접 업로드 구현·QA](chat-media-bounded-parallel-upload/qa/direct-upload-implementation.md)
  - 구현·Development 배포·3장/70장 실제 전송·사용자 조작/재입장 확인·5개 커밋·[PR #27](https://github.com/GayoonKim/OutPick/pull/27) 자체 리뷰/머지 완료, main `34831dfc`.
  - 최종 검증: Swift62/62, Socket113/113, Functions262/262, worker22/22, Storage5/5.
  - Production 배포·영상 실제 QA·병렬4대30 비교·최종 iOS 취소 경합 보완의 실기기 재설치는 완료 범위에서 제외하고 후속으로 유지한다.

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

- `chat-media-production-rollout`: 이번 미디어 전송 변경의 Production 배포
  - 2026-09-14 추가 기록: 기존 PR#27/#28 범위에 이번 최종 동시성 적용도 통합한다. iOS 원본4/준비전체/PUT4/FIFO1, 계약3 Socket 조회·서명·취소정리전체. 계약2 수치 설정은 유지하며 계약3은 metadata 환경 변수를 소비하지 않는다. [Development 최종 근거](../qa-media-upload-concurrency-2026-09-12.md), [운영 배포 대기 범위](../runbooks/CHAT_MEDIA_PRODUCTION_ROLLOUT.md). 실제 Production 배포는 이번 커밋/PR/머지 요청에 포함되지 않는다.
  - 상태: 사용자 요청으로 대기 목록에 기록. 실제 Production 배포 승인은 아직 없으며 배포하지 않았다. 다른 대기 작업과의 착수 순서는 추후 결정한다.
  - 기준: PR #27/main `34831dfc`와 PR #28/main `8e7d3c31`까지 포함. 2026-09-11 사용자 요청으로 이번 완료 변경의 Production 반영도 기존 대기 항목에 통합 기록했다. 실제 배포 승인은 아님. [FIREBASE 진입점](../entrypoints/FIREBASE.md)과 [Development QA 기록](chat-media-bounded-parallel-upload/qa/direct-upload-implementation.md)을 따른다.
  - PR #28 추가 범위: Socket 계약3 사진 본 파일·썸네일 각각300,000,000바이트 및 묶음 본 파일 합계300,000,000바이트/30장 정책. iOS 이미지 깜빡임 개선·실패 사진 원본 보존/재시도/삭제·다운로드 한도 정합성·공용 확대 화면 리팩토링도 Production 앱 반영 대상에 포함한다. 공용 확대 화면 자체는 서버 배포가 필요 없고, 이번 PR의 Functions/Firestore/Storage rules 변경은 없다.
  - 추가 순서/검증: Production Socket의300MB 정책 준비·검증 후 새 앱 반영. Development `outpick-socket-development-photo300-0911` 배포와 문제 사진/31장 전송·실패 복구·공용 뷰어 사용자 QA 결과를 참고하되 Production 통합 검증을 별도로 수행한다. 큰 글씨·VoiceOver는 사용자 요청으로 QA 제외,300MB 정확한 경계는 자동 테스트 검증(실파일 기기 경계 시험 미실시).
  - 사전 확인: 운영 Socket·관련 Functions·worker·규칙·인덱스의 실제 상태와 코드 차이를 확인하고 정확한 배포 목록 및 기존 revision/digest 롤백 기준을 작성한다. 기존 계약2 진행 자료 호환 경로는 임의 삭제하지 않는다.
  - 범위: Socket 계약3, 최종 버킷 환경 변수/메타데이터 병렬 설정, 최종 버킷 객체 접근·서명 IAM, ready Storage Rules, cleanup 복합 인덱스/receipt TTL, `reconcileChatMediaObjectCleanup` 및 변경된 기존 media 함수/worker의 배포 필요 여부 확인.
  - 순서: 규칙·인덱스·필요 IAM 및 서버 준비 → 후보 검증 → 트래픽 전환 → 계약3 iOS 반영 → 실제 통합 확인. 신규 앱을 계약3 미지원 서버보다 먼저 배포하지 않는다. IAM과 운영 변경은 구체 범위를 확인한 후 승인받는다.
  - 검증: 승인된 QA 방에서 본/썸네일 signed PUT·확정 전 읽기 차단·확정 후 접근, 메시지/seq/Socket 멱등성, 취소/성공 경합, 늦은 PUT 정리, 기존 정상 미디어 및 재시도를 확인한다. 미완료 영상 실전 QA의 운영 전 검증 범위도 결정한다.
  - 완료 기준: 승인 범위 배포·인덱스 READY·함수 ACTIVE·Socket readiness/오류 확인·실제 QA 결과·롤백 기준·하네스 갱신. 현재 병렬4를 최적값으로 간주하지 않는다.

### 완료 작업의 이전 설계 이력 (대기 작업 아님)

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
