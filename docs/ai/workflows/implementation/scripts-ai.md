# Implementation Scripts AI

## 목적

반복되는 명령이나 검증 흐름을 `scripts/ai` 자동화 후보로 판단하는 기준을 정리한다.

## scripts/ai 자동화 기준

`scripts/ai`는 반복이 확인된 작업만 만든다.

추가 후보:

- 같은 `xcodebuild` 빌드/테스트 명령을 2~3회 이상 반복했다.
- 같은 Firebase Functions lint/build 명령을 2~3회 이상 반복했다.
- 같은 Firebase Functions 선택 배포 대상이 반복되고, 사용자와 배포 필요성이 확정됐다.
- 같은 Cloud Run worker build/deploy 명령이 반복되고, 사용자와 배포 필요성이 확정됐다.
- 같은 Firestore rules/indexes 검증 또는 배포 전 점검을 2~3회 이상 반복했다.
- 커밋 전 변경 파일 분류를 매번 수동으로 반복하고 있다.
- 공식/로컬 하네스 분리 상태 확인을 반복하고 있다.

추가하지 않을 것:

- 한 번만 필요한 임시 명령.
- 아직 명령 인자나 실행 조건이 안정되지 않은 작업.
- 사용자 승인 없이 배포, 삭제, 마이그레이션을 실행하는 흐름.
- 프로젝트 이해보다 자동화 자체가 더 복잡해지는 스크립트.

현재 배포 자동화:

- Cloud Run worker 배포 자동화는 worker scaffold와 배포 대상이 확정된 뒤 `scripts/ai`에 추가한다.
- Cloud Run 배포 스크립트도 사용자 승인 없이 운영 배포를 실행하지 않는다.

제안 형식:

```text
scripts/ai 자동화 후보:
- 반복된 명령/흐름:
- 반복 횟수:
- 스크립트로 만들면 줄어드는 비용:
- 위험 또는 승인 필요 여부:
```
