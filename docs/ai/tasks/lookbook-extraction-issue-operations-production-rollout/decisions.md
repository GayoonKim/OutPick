# Lookbook Extraction Issue Operations Production Rollout Decisions

## D-001. Development 구현 task와 Production rollout을 분리한다

- `lookbook-extraction-issue-operations`는 구현과 Development QA 완료로 종료한다.
- Production 외부 상태와 승인 이력은 이 task에서 별도로 관리한다.

## D-002. Production 변경은 단계별 명시 승인을 받는다

- 읽기 전용 감사는 바로 수행할 수 있다.
- IAM/index/TTL/Functions/candidate 배포와 Worker traffic/canonical contract 전환은 감사 결과를 제시한 뒤 승인받는다.
- traffic 전환은 no-traffic candidate 검증 뒤 별도 승인한다.

## D-003. legacy 삭제와 cleanup은 rollout에 포함하지 않는다

- 기존 callable 삭제, legacy cluster/evidence/data cleanup, 과거 실패 job 재실행은 별도 승인 작업이다.
- rollout 성공을 cleanup 승인으로 해석하지 않는다.

## D-004. 이벤트 기반 이미지 extraction QA는 상시 운영 게이트다

- 실제 `seasonImageImport` 로직 결함과 상위 runtime이 생겼을 때만 `open → fixed → retry success → verified`를 실행한다.
- 시스템 QA를 위해 가짜 실패나 가짜 fixed 상태를 만들지 않는다.

## D-005. Production 인증은 key 없이 최소·임시 권한을 사용한다

- exact Production operator/service account resource에 OIDC ID token 생성에 필요한 최소 권한만 사용한다.
- 서비스 계정 key와 project-level 광범위 binding을 만들지 않는다.
- 임시 사용자 binding은 QA 종료 후 회수한다.

## D-006. contract cutover는 queue와 active job을 먼저 감사한다

- contract 2 Functions와 contract 3 Worker의 불일치 window를 임의로 허용하지 않는다.
- queue pause/drain 필요 여부와 배포 순서는 실제 Production 상태를 확인한 뒤 사용자와 확정한다.

