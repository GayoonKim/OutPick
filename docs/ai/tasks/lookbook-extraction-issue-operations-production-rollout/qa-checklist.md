# Lookbook Extraction Issue Operations Production Rollout QA Checklist

## Phase 1 읽기 전용 감사

- [ ] Production Worker live traffic과 rollback revision을 확인한다.
- [ ] Worker runtime/source/contract/extractor/adapter를 확인한다.
- [ ] Production Functions exact revision·runtime identity·environment를 확인한다.
- [ ] 필요한 Firestore index/TTL diff를 확인한다.
- [ ] Production operator/release/task/functions IAM diff를 확인한다.
- [ ] active discovery/import job과 두 queue 상태를 확인한다.
- [ ] contract cutover의 pause/drain 필요 여부를 결정한다.

## 로컬·candidate 게이트

- [ ] Functions/Worker/CLI test·lint·build와 fixture corpus가 통과한다.
- [ ] 민감 evidence redaction과 token 비로그 계약을 확인한다.
- [ ] cursor projection reconciler와 iOS wontFix/title 미체크 항목을 재분류한다.
- [ ] Worker no-traffic candidate와 rollback revision을 확보한다.
- [ ] candidate `/readyz`와 `/runtime-contract`가 일치한다.
- [ ] Functions/Task caller OIDC 경계가 기대 상태 코드를 반환한다.
- [ ] candidate actual extraction smoke가 통과한다.

## Production cutover

- [ ] 사용자에게 exact mutation 범위 승인을 받는다.
- [ ] Worker traffic/canonical contract 전환을 별도 승인받는다.
- [ ] 승인된 순서로 Functions/Worker contract를 일치시킨다.
- [ ] live traffic 100%와 runtime contract를 재확인한다.
- [ ] 실제 Production discovery smoke가 성공한다.
- [ ] queue backlog와 신규 Worker/Functions ERROR가 0건이다.
- [ ] 임시 사용자 IAM binding을 회수한다.

## 제외·후속

- [x] 기존 callable 삭제는 이번 rollout 승인에 포함하지 않는다.
- [x] legacy data cleanup은 이번 rollout 승인에 포함하지 않는다.
- [x] 과거 실패 job을 자동 재실행하지 않는다.
- [x] 실제 이미지 extraction fix loop는 결함 발생 시 이벤트 기반 QA로 실행한다.

