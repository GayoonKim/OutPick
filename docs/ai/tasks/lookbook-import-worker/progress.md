# Lookbook Import Worker Progress

## 목적

Lookbook import worker 작업의 현재 상태와 상세 진행 기록의 읽는 순서를 제공하는 인덱스다.

## 현재 목표

URL 기반 브랜드/시즌 등록 파이프라인을 Cloud Run worker 구조로 전환했고, 시즌 import 병렬 fan-out/처리량/결과 재시도까지 운영 배포와 smoke QA를 완료했다. 다음 개선 축은 import 이미지 추출 정확도 개선과 Season Asset Failure Queue 기반 재시도 구조다.

## 현재 단계

- Phase 1 하네스/ADR 정렬: 완료
- Phase 1.5 하네스 문서 모듈화: 완료
- Phase 2 기존 Functions batch/retry 변경분 정리: 완료
- Phase 3 Cloud Run worker scaffold: 완료
- Phase 4 Firestore job 처리 구현: 완료
- Phase 4.5 운영 큐/상태 모델/성능 기준 재설계: 완료
- Phase 5 Cloud Tasks dispatch 연결과 task endpoint 구현: 완료
- Phase 6 Cloud Run/Cloud Tasks 운영 배포와 smoke QA: 완료
- Phase 7A lifecycle, retry 계약, URL 보안: 완료
- Phase 7B 실패 asset 복구와 관리자 현황 화면: 완료
- Phase 8 legacy import Functions 정리: 완료
- Phase 9 Playwright fallback: 운영 배포와 smoke QA 완료
- Phase 10 import 병렬 fan-out/처리량/결과 재시도 설계: 하네스 문서 생성 완료
- Phase 10A Batch Job Fan-Out: Functions 구현 및 lint/build 완료
- Phase 10B 시즌 추가 결과 화면: 구현 및 iOS build 완료
- Phase 10C Retry Routing: Functions 구현 및 lint/build 완료
- Phase 10D Worker Asset Concurrency: 구현 및 worker lint/build/test 완료
- Phase 10E Cloud Logging Observability: 구현 및 worker lint/build/test 완료
- Phase 10F 운영 설정 체크리스트/운영 배포/smoke QA: 완료
- Phase 11 import 이미지 추출 정확도: 계획 확정, 구현 전
- Phase 12 Season Asset Failure Queue 기반 재시도 구조: 계획 확정, Phase 11 이후 진행
- 다음 단계: Phase 11A worker 파서 수정본 Cloud Run 배포와 HATCHINGROOM smoke QA. 아직 진행하지 않음.

## 읽는 순서

- 현재 상태와 다음 작업: 이 문서
- Phase 1~4 상세 기록: `progress/phase-1-to-4.md`
- Phase 5~6 상세 기록: `progress/phase-5-to-6.md`
- Phase 7 상세 기록: `progress/phase-7.md`
- Phase 10 상세 기록: `progress/phase-10.md`
- Phase 11/12 예정 기록: `progress/phase-11-12.md`
- phase별 완료 기준: `plan.md`
- Playwright fallback 설계: `playwright-fallback-design.md`
- Phase 10 병렬 fan-out/처리량/결과 재시도 설계: `phase-10-design.md`
- Phase 10 결정 이유와 대안: `decisions/phase-10.md`
- 기술 결정 이유와 대안: `decisions.md`
- worker 아키텍처: `../../architecture/LOOKBOOK_IMPORT_WORKER.md`

## 완료 요약

- 앱은 Firestore job 등록과 상태 표시를 담당하고, 긴 import 작업은 Cloud Run worker가 처리하는 구조로 전환했다.
- Cloud Tasks가 Firestore import job 생성 또는 queued 전환을 감지해 worker task endpoint를 호출하도록 연결했다.
- worker는 URL 파싱, 시즌/포스트 생성, Storage thumb/detail 업로드, lifecycle/phase/status 갱신을 처리한다.
- lifecycle은 `queued`, `processing`, `succeeded`, `partialFailed`, `failed`, `cancelled`로 정리했다.
- HTML fetch 재시도 계약, URL 보안 차단, 응답 크기 제한, DNS rebinding 방어를 구현했다.
- 실패 asset만 대상으로 하는 `retrySeasonAssets` job과 관리자 현황 화면을 구현했다.
- Phase 7A/7B 운영 배포와 실제 브랜드 URL 3개 smoke QA를 완료했다.
- 앱 브랜드 관리자 화면 수동 QA를 완료했다.

## 남은 핵심 작업

- Phase 11A: worker 파서 수정본을 Cloud Run에 배포하고 HATCHINGROOM `3759`, `3760`, `3761` URL smoke QA를 수행한다.
- Phase 11B: Cafe24 archive 상세 파서 회귀 테스트를 보강한다.
- 기존 HATCHINGROOM 관련 Firestore/Storage 데이터는 사용자가 삭제했으므로 별도 데이터 정리 작업은 진행하지 않는다.
- Phase 12A-D: `seasons/{seasonID}/assetFailures/{failureID}` 기반 실패 asset 재시도 구조로 리팩토링한다.
- `requestSeasonCandidateImportsAndProcess` 이름 정리는 현재 우선순위에서 제외한다.

## 현재 working tree 참고

- 문서 인덱싱 전 `git status --short`는 깨끗했다.
- 이전 Functions batch/retry 실험성 변경은 Phase 2에서 걷어냈다.
- 현재 이 문서와 `progress/` 상세 문서 변경은 하네스 정리 작업이다.

## 검증 상태 요약

- Phase 7B 후 worker `npm test`, `npm run lint`, `npm run build` 통과.
- Phase 7B 후 Functions `npm run build`, `npm run lint` 통과.
- Phase 7B 후 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- Phase 7A/7B 운영 배포와 Cloud Tasks/Cloud Run smoke QA 완료.
- 실제 브랜드 URL 3개 운영 smoke QA 완료.
- 앱 브랜드 관리자 화면 수동 QA 완료.
- Phase 8 후 Functions `npm run lint`, `npm run build` 통과.
- Phase 8 후 `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- Phase 8 후 운영 legacy 함수 6개 삭제 완료.
- Phase 8 후 신규 import job smoke QA와 asset retry smoke QA 통과.
- Phase 8 smoke 테스트 Firestore 문서와 Storage prefix 정리 완료.
- Phase 9 후 worker `npm run lint` 통과.
- Phase 9 후 worker `npm test` 통과. 테스트 11개 통과.
- Phase 9 `npm test`가 `npm run build`를 포함해 TypeScript build도 통과.
- Phase 9 Cloud Build로 Dockerfile 빌드 가능성 확인 완료.
- Phase 9 Cloud Build에서 Playwright Chromium dependency 설치 통과.
- Phase 9 확인용 Artifact Registry image 삭제 완료.
- Phase 9 Cloud Run `lookbook-import-worker-00006-lsr` 배포 완료. 100% 트래픽 전환.
- Phase 9 정적 smoke URL `https://www.w3.org/` 성공. fallback 미사용, asset 16/0.
- Phase 9 동적 smoke URL `https://thisisneverthat.com/collections/editorial` 성공. Playwright fallback 사용, asset 6/0.
- Phase 9 smoke 테스트 Firestore 문서와 Storage prefix 정리 완료.
- Phase 9 Cloud Tasks queue 잔여 작업 0개 확인.
- Phase 10 상세 검증과 배포/smoke 기록은 `progress/phase-10.md`에 분리했다.

## 남은 위험

- 운영에는 `requestSeasonImport`, `requestSeasonCandidateImportsAndProcess`, `requestSeasonAssetRetry`, `onSeasonImportQueued`와 Cloud Run worker가 남아 있다.
- Playwright fallback은 Chromium runtime dependency로 image size, cold start, 메모리 사용량이 늘 수 있다. 운영 로그를 보며 추후 조정한다.
- `requestSeasonCandidateImportsAndProcess`는 현재 동작상 job 생성만 하므로 이름과 책임 표현이 어긋나 있다. 앱 호출부 영향이 있어 별도 승인 후 리팩토링한다.
- Phase 10 운영 반영 후 Cloud Tasks backlog, Cloud Run timeout/error/memory, `lookbookImport.*` 로그를 확인하며 처리량을 추가 상향할지 판단한다.
