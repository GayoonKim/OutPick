# Lookbook Extraction Issue Operations QA Checklist

## 자동 계약 테스트

- [x] 두 stage의 로직 불충분만 issue 대상이 된다.
- [x] transient/input/permanent/identity-review/cancel/stale은 issue를 만들지 않는다.
- [x] 공통 fingerprint가 정렬·정규화·40자 hex 계약을 지킨다.
- [x] 같은 job/generation/evidence occurrence는 한 번만 집계된다.
- [x] fixed version 미만 drift와 fixed version 이상 recurrence를 구분한다.
- [x] recurrence가 terminal cluster를 open으로 되돌리고 TTL을 제거한다.

## evidence·retention

- [x] occurrence ledger/object는 7일 expiry다.
- [x] 대표 evidence는 cluster당 한 개이고 occurrence cleanup에서 제외된다.
- [x] active/fixed 대표 evidence에는 expiry가 없다.
- [x] verified/wontFix cluster·대표 evidence는 60일 뒤 함께 삭제된다.
- [x] terminal extraction job은 60일 정책을 유지한다.
- [ ] HTML/script/cookie/header/query value/token/credential이 JSON·API·로그에 없다.
- [x] 대표 evidence 복사 실패 후 다음 occurrence에서 복구된다.

## read API·CLI

- [x] 미인증, 잘못된 audience/issuer/email, 다른 환경 principal은 401/403이다.
- [x] list 기본 20·최대 50과 stable cursor가 중복/누락 없이 동작한다.
- [x] 허용되지 않은 filter/order/path/field는 거부된다.
- [x] batch 20개 상한과 요청 순서, found/missing/evidenceExpired가 유지된다.
- [x] DTO에 내부 Firestore 필드와 민감 evidence가 새어 나오지 않는다.
- [x] CLI는 environment 필수이고 arbitrary URL/Firestore access를 제공하지 않는다.
- [x] token과 Authorization header가 stdout/stderr/log에 출력되지 않는다.

## mutation·상태 전이

- [x] expectedStateVersion 불일치는 충돌로 거부된다.
- [x] 같은 request ID 재호출은 count/audit를 중복 생성하지 않는다.
- [x] 허용되지 않은 상태 전이는 거부된다.
- [x] ground truth 크기·enum·candidate key allowlist가 강제된다.
- [x] client write API로 fixed/verified/retry-ready를 만들 수 없다.
- [x] audit가 caller/action/before-after/request ID를 남기고 60일 TTL을 가진다.

## release verifier

- [x] Development project 요청은 Production fix를 만들 수 없다.
- [x] traffic 100% 미만, revision/version/source mismatch는 거부된다.
- [x] `/runtime-contract` 인증 실패와 불일치를 거부한다.
- [x] stale stateVersion, 다른 fingerprint/stage/job/runtime smoke를 거부한다. smoke는 verifier 요청 안에서 즉시 실행하므로 외부 만료 run을 받지 않는다.
- [x] 같은 stage/fingerprint와 blocked version 경계의 job만 retry-ready가 된다.
- [ ] partial projection 갱신은 cursor reconciler가 중복 없이 마무리한다.
- [x] Production fixed 뒤 자동 재실행되지 않는다.
- [x] 새 revision 실제 재시도 성공이 verified를 만들고 이후 재발은 reopen한다.

## iOS 자동 테스트

- [x] open은 waiting 상태로 매핑되고 fixed 재시도 action을 실행하지 않는다.
- [x] inProgress/needsGroundTruth는 processing 상태로 매핑되고 fixed 재시도 action을 실행하지 않는다.
- [x] fixed와 retry runtime이 함께 있을 때만 시즌 목록 재시도 action을 제공한다.
- [x] 이미지 correctionRequired도 fixed 전 즉시 재분석할 수 없다.
- [ ] wontFix는 원인별 기존 안전 action으로 연결된다.
- [ ] image import 행은 internal job ID가 아니라 시즌명을 표시한다.

## Development 수동 QA

- [x] 실제 시즌 discovery 실패가 버튼 없이 open cluster를 만든다. AMOMENTO에서 `no_candidates_found` issue와 `correctionRequired`를 확인했다.
- [ ] 실제 이미지 extraction 실패가 같은 계약으로 기록된다.
- [x] Codex CLI가 실제 Development operator identity로 목록을 민감정보 없이 요약하고 Development fixture 단일 데이터를 조회한다.
- [x] backend에서 start/needsGroundTruth/resume/wontFix/reopen, stale CAS 거부와 정확한 job projection을 실제 Development API로 확인했다. 앱 실시간 반영 수동 QA는 별도다.
- [ ] contract 2 Worker candidate와 AMOMENTO 15개 실제 URL smoke 후 verifier가 fixed를 연다.
- [ ] 관리자가 명시 재시도하고 성공 뒤 verified가 된다.
- [ ] 7일/60일 cleanup fixture가 대상 외 데이터를 삭제하지 않는다. 실제 Scheduler 수동 실행은 기존 만료 데이터도 삭제하므로 보류했고 격리 단위 테스트와 TTL ACTIVE를 확인했다.
- [x] Functions/Worker 신규 ERROR, queue backlog와 임시 fixture/evidence 잔존이 없다.

## Production 게이트

- [ ] 필요한 index/TTL/IAM diff를 사전 확인하고 별도 승인을 받았다.
- [ ] Worker no-traffic candidate와 rollback revision을 확보했다.
- [ ] 전체 fixture differential 6/6은 통과했다. Development 배포 revision의 실제 URL QA와 상태 전이는 남아 있다.
- [ ] PR 승인 뒤에만 Production traffic을 전환했다.
- [ ] Production verifier가 live 100% revision을 확인했다.
- [ ] 기존 callable 삭제와 legacy 데이터 cleanup은 각각 별도 승인받았다.
