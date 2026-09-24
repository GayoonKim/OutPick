# ① 구현 계획

② 다운로드 병목 해소는 별도 [세부 구현 계획](download-bottleneck-plan.md)을 따른다. 아래 자동 테스트 미실시 상태는① 구현 초기 이력이며,① 실제 결과는 [검증 기록](qa-results.md)을 우선한다.

상태: 2026-09-21 사용자 구현 승인 후 Phase 1~3 로컬 통합 구현, Phase 4 테스트 작성·빌드 검증 진행. 자동 테스트 실행/실기기 QA는 미실시. 아래는 승인된 구현 계획이며 실제 결과·차이는 progress에 기록한다.

## 세부 계획 진입점

| 순서 | 상세 문서 | 구현 산출물 |
| --- | --- | --- |
| 1 | [수요·재시도·취소 계약](plan/phase-1-demand.md) | 정책 입력/출력, 상태 소유, 서비스 우선순위, 경합 테스트 |
| 2 | [개별 이미지·화면 수명](plan/phase-2-surfaces.md) | 셀 표시 바인딩, 공용 frame 계산, 화면 이벤트, DI |
| 3 | [일괄 다운로드 제거](plan/phase-3-integration.md) | 초기/수신/스크롤 우회 제거, 썸네일 경계, 미사용 API 정리 |
| 4 | [검증·QA·인계](plan/phase-4-validation.md) | 자동 테스트/실기기 행렬, 계측, 수치 평가, 하네스 갱신 |

Phase 1→2→3은 동일 protocol·VC·DI에 의존한다. Phase 2의 새 연결과 Phase 3의 기존 경로 제거를 통합하기 전에는 앱 개선 완료나 QA 완료로 간주하지 않는다. 각 상세 문서의 파일/메서드 이름은 변경 후보이고 최종 코드 위치는 구현 시 참조 검색으로 확인한다.

## 순서와 의존성

①를 아래 네 phase로 구현한다.②와③은① 결과 확인 뒤 상세 설계한다. 같은 attachment protocol, VC/셀, Container/Coordinator를 바꾸므로 메인 작업에서 순차 진행한다. 신규 이름은 후보다. 새 작업/서브 에이전트는 만들지 않는다.

### Phase 1 — 수요·재시도·취소 계약

- 목표: 표시 회차와 요청 수명을 분리하고 visible/prefetch 우선순위를 서비스까지 전달.
- 변경 범위: 새 `Services/ImageLoading/ChatMediaViewportPolicy.swift`, `ChatMediaViewportController.swift`; 기존 `ChatAttachmentImageLoading.swift`, `ChatAttachmentImageService.swift`; 관련 fake/spy와 새 viewport tests.
- 완료 기준: 보이는 항목 전부+주변24, 고유 경로 합류,300ms 해제, 재등장당 한 번 재시도, 마지막 소비자 취소/늦은 응답 차단. 기존 소비자의 API가 컴파일됨.
- 검증 방법: 제어 가능한 sleep/continuation·spy 기반 정책/비동기 테스트 작성; Development Simulator 앱/테스트 target 빌드.
- 논의 필요: 현재 없음. 새 캐시 정책·서버 계약 요구가 생기면 이 단계에서 임의로 추가하지 않음.

### Phase 2 — 사진별 표시·화면 수명 연결

- 목표:30장 묶음과 공유 카드가 실제 화면 위치 기준으로 요청하고 모든 셀 우회를 닫음.
- 변경 범위: `ChatImagePreviewCollectionView.swift`, `Cell/ChatImagePreviewCell.swift`, `Cell/ChatMessageCell.swift`, `LookbookShareMessageContentView.swift`, 필요 시 `Cell/ChatMessageCell+LookbookShare.swift`; 신규 공용 묶음 layout helper; VC의 viewport 연결용 별도 extension; `ChatContainer.swift`, `ChatCoordinator.swift`의 화면 조정자 조립.
- 완료 기준: 내부 collection의 화면 밖 사진 요청 없음, 재사용/경로 변경 stale 차단, 업로드 확정 사진 유지, 완전 가림/백그라운드 즉시 해제와 복귀, 다른 소비자의 공유 다운로드 보존.
- 검증 방법: 실제 UIKit 중첩 layout+spy 검증 및 기존 `ChatImagePreviewContinuityTests` 확장. 현재/주변 프레임을 바꾸는 재등장 테스트. 빌드.
- 논의 필요: 현재 없음. partial sheet의 실제 기존 전환에 새 제품 정책이 필요하면 근거와 함께 제시.

### Phase 3 — 일괄 로딩 제거·수신 흐름 통합

- 목표: 진입·스크롤·수신에서 viewport 이외의 썸네일 다운로드를 없애고 메시지 표시/저장 대기 제거.
- 변경 범위: `ChatViewController.swift`의 initial warmup·수신 TaskGroup·legacy prefetch/cleanup·thumbnail fallback; `ChatInitialLoadUseCase.swift`, `Domain/Models/ChatInitialLoadModels.swift`의 warmMedia/미사용 정책; 실제 호출이 없어지는 영상 warmup API와 관련 tests/fake는 참조 검색 후 필요한 범위만 정리.
- 완료 기준: 방 전체 warmup/메시지±60 경로 제거, 이미지 네트워크를 hold해도 메시지 표시·기존 저장 경로 접수 가능, 썸네일 오류가 원본/MP4/원격 포스터 요청을 만들지 않음. 페이지 추가/검색 이동/삭제/로컬 확정 표시 정상.
- 검증 방법: hold/fail하는 썸네일 로더와 메시지 저장 spy, 초기/수신 실제 호출 경로 검증. 기존 outbox·페이지·표시 연속성 회귀 범위 대조. 빌드.
- 논의 필요: 없음. save queue·outbox/FIFO 동작까지 리팩토링하지 않음.

### Phase 4 — 통합 검증·수치 평가·하네스

- 목표: [QA](qa-checklist.md)의 필수 계약을 확인하고②에 넘길 실제 병목을 분리.
- 변경 범위: 관련 tests, 필요 최소 Debug 계측, `ENTRYPOINTS.md`·`entrypoints/CHAT.md`·`entrypoints/TESTS.md`, task progress/QA. 신규 정책 변경은 수치 조정 근거 기록 후 반영.
- 완료 기준: 화면 밖 요청/이탈 취소/재등장/표시 유지/수신 선표시 결과와 미검증 한계 기록. 새 서버 fixture·임시 코드가 생기면 정확 범위 정리.① 완료와②·③ 미해결을 구분.
- 검증 방법: 관련 자동 테스트 실행은 사용자 명시 요청 시 수행; 기존미디어 QA방 실기기 스크롤·재진입·가림/복귀·실패 복구. 통계적 최적값 주장 없음.
- 논의 필요: 실기기 QA 시나리오와 오류 주입/캐시 상태 변경이 필요하면 대상·범위 확정. 현재 데이터 변경/기기 재설치 승인 없음.

## 테스트 설계·실행 정책

- 비동기/캐시/수요 변경이므로 실패·취소·중복·재등장·경합 자동 테스트를 우선 작성한다. 단순 UI 모습과 터치는 수동 QA로 확인한다.
- 필요한 도구: 가짜 첨부 로더, 요청 기록 spy, 수동 완료/실패 barrier, 제어 가능한300ms sleep, 실제 UIKit layout harness, 메시지 저장 spy.
- 현재 테스트 실행 명시 요청은 없다. 프로젝트 정책에 따라 자동 테스트 실행은 승인 후 수행하고, 미실행이면 작성/빌드와 실행 결과를 분리한다.
- 빌드 후보: `xcodebuild -project OutPick.xcodeproj -scheme OutPick-Development -destination 'generic/platform=iOS Simulator' build-for-testing`. 실제 실행 시 로그/DerivedData 경로와 결과를 progress에 기록한다.
- 각 phase 시작 전 git 상태와 앞 phase의 protocol/DI 영향을 확인하고 사용자 기존 변경을 보존한다. 코드 수정 후 진입점 하네스를 함께 최신화한다. 임의 커밋/배포 없음.
