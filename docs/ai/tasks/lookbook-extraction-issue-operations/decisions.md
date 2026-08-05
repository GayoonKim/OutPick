# Lookbook Extraction Issue Operations Decisions

## D-001. Codex는 Firestore 대신 IAM 비공개 운영 API를 호출한다

- 상태: 확정.
- read/write/release endpoint를 분리하고 환경별 IAM allowlist를 사용한다.
- service-account JSON, 공개 endpoint, 앱 관리자 callable, 임의 Firestore path 조회는 사용하지 않는다.
- 현재 개발자 계정이 환경별 전용 operator service account를 key 없이 impersonate하고 audience가 고정된 단기 ID token을 사용한다. 사용자 계정의 일반 `gcloud` ID token은 공식 문서상 audience가 없는 개발용 token이므로 Production 운영 API에는 사용하지 않는다.

## D-002. 현재 운영 단위는 issue cluster다

- 상태: 확정.
- 같은 공통 fingerprint 발생을 하나로 합치고 Codex는 목록 요약과 최대 20개 bounded 상세를 사용한다.
- 담당자, Jira, SLA, 댓글, 보드는 실제 복수 운영자와 처리 누락 문제가 생길 때 재검토한다.

## D-003. 실패 기록은 자동이고 수정은 사용자 승인 기반 수동 개발이다

- 상태: 확정.
- 앱의 개선 요청 버튼을 제거한다.
- Codex는 사용자가 선택한 문제만 코드·fixture로 보강하며 자동 code-generation, 자동 PR/merge, 자동 Production rollout은 하지 않는다.

## D-004. Production runtime registry가 retry readiness의 기준이다

- 상태: 확정.
- Worker가 `/runtime-contract`를 제공하고 서버 전용 registry가 Production 100% traffic과 검증된 extractor 계약을 기록한다.
- 일반 extractor 개선은 Worker 배포로 처리하고, Functions는 실제 API/business contract가 바뀔 때만 함께 배포한다.
- 앱의 retry는 verifier가 live revision과 실제 URL smoke를 확인한 뒤에만 열린다.

## D-005. `fixed`와 `verified`를 분리한다

- 상태: 확정.
- `fixed`는 Production revision과 smoke를 검증해 재시도 가능한 상태다.
- `verified`는 그 revision으로 영향 job의 실제 재시도 1건이 성공한 상태다.
- 같은 fingerprint가 재발하면 `open`으로 되돌리고 recurrence를 증가시킨다.

## D-006. evidence는 크기와 운영 가치를 분리해 보존한다

- 상태: 확정.
- occurrence evidence ledger/Storage JSON은 7일이다.
- cluster별 대표 redacted evidence 한 개는 미해결 동안 유지한다.
- `verified/wontFix` 뒤 cluster와 대표 evidence는 60일 유지한 후 자동 삭제한다.
- terminal extraction job 이력도 완료·실패 후 60일 유지한다.

## D-007. 두 stage는 공통 fingerprint 계약을 사용한다

- 상태: 확정.
- `stage + platform + parserStrategy + reasons + templateSignature + extractorMajorVersion`을 사용한다.
- host는 fingerprint와 cluster 집계에서 제외한다. 영향 job/brand는 7일 occurrence ledger를 fingerprint와 runtime으로 조회한다.

## D-008. 배포 전 앱이므로 레거시 호환 계층을 만들지 않는다

- 상태: 확정.
- `improvementRequested` projection, 호환 no-op callable과 구형 UI mapping을 추가하지 않는다.
- 기존 개발 데이터 필드는 파괴적으로 일괄 삭제하지 않고 새 코드가 읽고 쓰지 않게 한다.
- 배포된 callable의 제거는 replacement 배포 확인과 사용자 배포 승인 뒤 수행한다.

## D-009. ground truth는 앱이 아니라 Codex 대화와 구조화 API로 기록한다

- 상태: 확정.
- expected count, candidate key, source classification과 bounded redacted note만 허용한다.
- 전역 issue UI와 별도 ground-truth 관리 화면은 추가하지 않는다.

## D-010. stage와 runtime version은 종류가 있는 canonical 계약을 사용한다

- 상태: 확정.
- canonical stage는 `seasonDiscovery | seasonImageImport`다. 기존 이미지 evidence의 `parsing` 전환은 Phase 2 자동 기록 접합에서 처리한다.
- `seasonDiscovery` runtime은 `contract:{revision}`, `seasonImageImport` runtime은 `extractor:{semver}` 형식이다.
- 다른 종류끼리의 비교, 잘못된 형식과 stage/runtime 불일치는 fail closed한다.

## D-011. 재발과 수동 상태 전이를 분리한다

- 상태: 확정.
- `open/inProgress/needsGroundTruth` occurrence는 상태를 유지한다.
- `fixed/verified`는 발생 runtime이 fixed runtime 이상일 때만 `open`으로 되돌리고 recurrence를 증가시킨다.
- `wontFix`의 새 occurrence는 runtime과 무관하게 `open`으로 되돌리고 recurrence를 증가시킨다.
- 수동 `reopen`은 `needsGroundTruth/wontFix/verified → open`만 허용하며 `fixed`는 verifier와 재발 규칙으로만 전환한다.
- `stateVersion`은 상태가 실제로 바뀔 때만 증가하고 운영 mutation은 expected version CAS를 요구한다.

## D-012. 자동 issue는 추출 로직 불충분만 기록한다

- 상태: 확정.
- 이미지의 `expected_count_unverified` 단독 결과와 programmatic gallery 검토는 정상 검토 흐름이며 issue를 만들지 않는다.
- 이미지의 parse 실패, 후보 없음, expected count 불일치, 큰 rendered delta, raw candidate drop은 issue다.
- 시즌 목록의 후보 없음, 낮은 신뢰 후보, 확장 한도 도달 뒤 남은 load-more는 issue다. transient/input/identity review는 제외한다.

## D-013. cluster는 영향 brand/domain을 집계하지 않는다

- 상태: 확정.
- `affectedDomains`, `affectedDomainCount`, `sampleJobPaths`는 정확한 전체 영향 범위를 나타내지 못하므로 제거한다.
- cluster는 원인 identity, generic/platform/domain adapter scope, lifecycle, 대표 evidence만 가진다.
- 영향 job/brand가 필요할 때 occurrence ledger의 `issueFingerprint + blockedRuntimeVersion`을 기준으로 조회한다.

## D-014. 대표 evidence는 결정적 정보 점수로 선택한다

- 상태: 확정.
- 비교 tuple은 `schemaVersion → expected-count 존재 → candidate evidence 수 → structure token 수 → element 수` 순서다.
- 기존 대표가 없거나 `missing`이면 교체하고, `ready`이면 tuple이 사전식으로 더 큰 경우만 교체한다.
- 대표 object는 동시 교체 충돌을 피하도록 `fingerprint/evidenceID` 고유 경로를 사용하고 교체 성공 뒤 이전 object를 정리한다.

## D-015. Phase 3 조회 API는 영향 brand/job 목록을 제공하지 않는다

- 상태: 확정.
- `listClusters`의 `brandID` filter와 `getCluster`의 최근 occurrence brand/job 사례를 제거한다.
- read API는 cluster 원인, adapter layer, lifecycle과 대표 redacted evidence만 반환한다.
- occurrence ledger는 7일 멱등 집계와 임시 evidence 보존에만 사용하고 운영 API의 영향 목록으로 노출하지 않는다.
- 정확한 retry 대상은 Phase 4 서버가 job의 `extractionIssueFingerprint` projection으로 조회한다.

## D-016. ground truth와 wont-fix 사유는 제한 enum을 사용한다

- 상태: 확정.
- `sourceClassification`은 `completeGallery | partialGallery | nonGallery | unknown`이다.
- `wontFixReason`은 `sourceUnavailable | accessRestricted | ambiguousGroundTruth | unsupportedStructure | lowOperationalValue`다.
- candidate key는 기존 redacted 24자 lowercase hex 계약만 허용하고 note는 정제·길이 제한한다.

## D-017. Phase 3 요청량 방어는 인증과 bounded execution을 우선한다

- 상태: 확정.
- URL은 공개된다고 가정하고 IAM, OIDC audience/issuer/email, environment 일치 검증을 실제 보안 경계로 사용한다.
- `maxInstances`, page/batch/scan/evidence/응답 크기 상한을 서버에서 강제한다.
- 전역 정밀 rate limit은 Cloud Armor/API Gateway 등 배포 인프라 결정이 필요하므로 Phase 3 로컬 구현에서 제외하고 배포 전 게이트로 관리한다.

## D-018. Phase 4는 전용 read-only smoke로 실제 수정 여부를 증명한다

- 상태: 확정.
- 기존 이미지 diagnostic은 저장된 job count만 읽으므로 fix 검증에 재사용하지 않는다.
- Worker IAM 전용 `/smoke/extraction`이 대표 job의 실제 URL을 현재 runtime으로 새로 추출하되 시즌/post/job을 생성하거나 변경하지 않는다.
- verifier가 cluster와 대표 job을 서버에서 결합하므로 성공 결과에서 기존 실패 fingerprint가 사라져도 어떤 issue 검증인지 증명할 수 있다.
- parse 실패처럼 결정적으로 판정 가능한 문제는 동일 logic issue가 사라지면 통과할 수 있다.
- 후보 누락·수량·coverage 계열은 expected count 또는 candidate key ground truth 없이는 `fixed`를 열지 않는다.
- 통과한 검증 영수증은 `lookbookExtractionFixVerificationRuns`에 24시간 보존하고, release projection 진행 상태는 별도 release record로 60일 보존한다.
- verifier 한 번의 요청에서 Production traffic/runtime contract/smoke/CAS를 연속 검증하며 별도 임의 smoke run ID를 신뢰하지 않는다.
