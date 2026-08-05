# Lookbook Extraction Issue Operations Production Rollout Plan

## 전체 상태

- 상태: Phase 1 읽기 전용 감사 대기.
- Production mutation: 미승인·미수행.

## Phase 1. Production 읽기 전용 감사

목표:

- Worker traffic/revision/runtime, Functions revision/env, IAM, Firestore index/TTL, active job과 queue를 현재 시점 기준으로 확정한다.

변경 범위:

- 없음. Google Cloud/Firebase 읽기 전용 조회와 로컬 문서 기록만 수행한다.

완료 기준:

- 현재 contract, source revision, rollback revision과 exact diff가 정리된다.
- contract cutover의 mismatch window와 queue pause/drain 필요 여부가 결정 가능해진다.

검증:

- Cloud Run/Functions/IAM/index/TTL/queue/log 조회.
- 로컬 전체 test·fixture·lint/build의 최신 증거 확인.

논의 필요 사항:

- 감사 결과에 따른 exact 배포 범위와 cutover choreography.

## Phase 2. 배포안·rollback·승인 게이트 확정

목표:

- 변경 resource, 실행 순서, rollback과 실제 smoke 대상을 사용자와 확정한다.

변경 범위:

- task 문서와 배포 체크리스트.

완료 기준:

- IAM/index/TTL/Functions/candidate 범위 승인.
- traffic/canonical contract 전환은 별도 승인 항목으로 분리.

검증:

- 명령 dry-run 또는 describe 결과와 expected diff 대조.

논의 필요 사항:

- Production mutation 승인 필수.

## Phase 3. Production prerequisite와 no-traffic candidate

목표:

- 승인된 최소 IAM/index/TTL/Functions prerequisite와 Worker candidate를 준비한다.

변경 범위:

- 승인된 Production resource만.

완료 기준:

- candidate Ready, traffic 0%, rollback revision 보존.
- `/readyz`, `/runtime-contract`, task/functions caller 경계와 read-only actual smoke 통과.

검증:

- revision/env/source/contract 대조, 신규 ERROR 0.

논의 필요 사항:

- candidate 검증 실패 시 traffic 전환 금지.

## Phase 4. Production cutover

목표:

- 별도 승인된 순서로 Worker와 Functions canonical contract를 일치시킨다.

변경 범위:

- Worker traffic과 승인된 Functions deployment.
- 필요하다고 확정된 경우에만 queue pause/resume.

완료 기준:

- live Worker traffic 100%, Functions/Worker contract 일치, active queue 정상.
- rollback 명령과 이전 revision이 유효하다.

검증:

- live runtime contract, Functions revision/env, queue와 ERROR.

논의 필요 사항:

- traffic/canonical contract 전환 직전 사용자 명시 승인.

## Phase 5. 실제 Production smoke와 종료

목표:

- 실제 대표 URL로 end-to-end 상태를 확인하고 임시 권한을 회수한다.

변경 범위:

- 승인된 smoke 데이터와 임시 IAM 정리.

완료 기준:

- 실제 discovery 결과, 대표 이미지, queue 0, 신규 ERROR 0.
- smoke 데이터 정리 범위를 확인하고 승인된 데이터만 삭제.
- 임시 사용자 IAM 회수.

검증:

- Firestore 결과, 실제 URL, Cloud Tasks, Worker/Functions logs, IAM policy.

논의 필요 사항:

- smoke 대상과 데이터 삭제는 실행 전에 확정한다.

