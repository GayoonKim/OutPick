# Lookbook Import Worker Decisions

## 목적

Lookbook import worker 작업에서 확정한 결정의 인덱스다. 결정의 이유, 대안, 트레이드오프, 재검토 조건은 phase별 상세 문서에서 확인한다.

## 읽는 순서

- Phase 10 import 병렬 fan-out/처리량/결과 재시도: `decisions/phase-10.md`
- Phase 11/12 import 정확도와 asset failure queue: `decisions/phase-11-12.md`
- 현재 lifecycle, URL 보안, retry 계약: `decisions/phase-7.md`
- Cloud Tasks 목표 구조와 성능/관측 기준: `decisions/phase-4-5-to-6.md`
- worker 도입 배경과 초기 구현 선택: `decisions/phase-1-to-4.md`
- 현재 진행상태와 다음 작업: `progress.md`
- phase별 완료 기준: `plan.md`

## 결정 지도

### 초기 구조와 Phase 1-4

상세: `decisions/phase-1-to-4.md`

- D-001: URL 기반 시즌 import는 Cloud Run worker 중심으로 전환한다.
- D-002: Cloud Tasks는 초기 구현에서 보류한다.
- D-003: 하네스 문서는 인덱스와 필요한 세부 문서로 최소 분리한다.
- D-004: worker scaffold는 Express 기반 독립 TypeScript package로 시작한다.
- D-005: worker 인증은 env와 ADC를 사용하고 프로젝트 ID를 필수로 둔다.
- D-006: 초기 job 처리는 Firestore claim/lease로 구현하고 운영 큐는 Cloud Tasks를 재검토한다.
- D-007: 이미지 변환은 처리량과 메모리 효율 때문에 `sharp`를 선택한다.
- D-008: 경량 HTML 파싱을 기본으로 두고 동적 렌더링 fallback은 후속 검토한다.
- D-009: 배포 전에는 기존 앱 호환성보다 명확한 job lifecycle을 우선 검토한다.

### Phase 4.5-6 운영 설계

상세: `decisions/phase-4-5-to-6.md`

- D-010: 성능 기준은 절대 시간 목표보다 핵심 가치 적합성과 병목 관측으로 둔다.
- D-011: Cloud Tasks, lifecycle/phase 분리, 조건부 Playwright, 요약 관측성을 운영 구조 기준으로 둔다.

### Phase 7 운영 계약

상세: `decisions/phase-7.md`

- D-012: 앱 미배포 상태이므로 기존 lifecycle 호환성을 유지하지 않는다.
- D-013: 공개 인터넷 URL은 허용하되 내부 네트워크 접근은 차단한다.
- D-014: HTML fetch의 일시적 오류만 Cloud Tasks 장기 재시도 대상으로 둔다.

### Phase 10 import 처리량과 결과 재시도

상세: `decisions/phase-10.md`

- D-015: Job 생성은 Functions에서 제한 병렬 fan-out으로 처리한다.
- D-016: 결과 화면은 시즌 단위 성공/실패와 재시도만 보여준다.
- D-017: 실패 재시도는 full import 또는 asset retry로 내부 routing한다.
- D-018: 진행률은 asset 단위가 아니라 시즌 job 완료 단위로 계산한다.
- D-019: Asset concurrency는 Cloud Run env로 조절한다.
- D-020: 성능 계측은 Cloud Logging에만 남긴다.
- D-021: 첫 운영 처리량은 보수적으로 올리고 로그로 추가 상향을 판단한다.
- D-022: Functions worker URL/audience는 기존 결정적 URL을 유지한다.

### Phase 11/12 import 정확도와 asset failure queue

상세: `decisions/phase-11-12.md`

- D-023: retry 구조 개편보다 import 이미지 추출 정확도 고정을 먼저 진행한다.
- D-024: 기존 HATCHINGROOM 관련 Firestore/Storage 데이터는 사용자가 삭제했으므로 별도 데이터 정리 phase를 두지 않는다.
- D-025: 실패 asset 재시도는 새 retry import job 문서가 아니라 `seasons/{seasonID}/assetFailures/{failureID}` 현재 실패 큐를 기준으로 처리한다.
- D-026: 가져오기 현황은 원본 import job만 표시하고, 제목은 job ID가 아니라 시즌 이름을 우선 사용한다.

## 참조 원칙

- 결정 번호를 알고 있으면 위 결정 지도에서 상세 문서를 찾는다.
- 현재 코드와 충돌하는 과거 결정은 삭제하지 않고, 후속 결정이 대체했음을 상세 문서에서 확인한다.
- 여러 기능에 반복 적용되는 결정은 `docs/ai/ADR.md` 또는 `docs/ai/architecture/`로 승격한다.
