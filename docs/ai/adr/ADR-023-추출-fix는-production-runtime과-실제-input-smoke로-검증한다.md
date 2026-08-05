# ADR-023: 추출 fix는 Production runtime과 실제 input smoke로 검증한다

## 상태

accepted

## 결정

- 코드·fixture 통과나 revision 배포만으로 extraction issue를 `fixed`로 만들지 않는다.
- Production observed traffic 100%, Worker runtime/source revision과 대표 실패 job의 실제 URL read-only smoke를 모두 서버가 직접 검증한다.
- completeness 계열은 구조화된 ground truth가 없으면 fail closed한다.
- 검증 통과 뒤에만 fingerprint와 blocked runtime 경계가 정확한 job의 명시적 재시도를 연다.

## 이유

기존 시즌 이미지 diagnostic은 저장된 과거 count를 읽어 새 revision의 실제 추출 결과를 증명하지 못한다. 또한 정상 결과에서는 실패 fingerprint가 사라지므로 verifier가 선택 cluster와 대표 job을 직접 결합해야 한다. 일부 후보만 찾은 결과를 수정 성공으로 오인하지 않으려면 count/key ground truth 경계도 필요하다.

## 트레이드오프

- Production Function에 Cloud Run Viewer와 Worker Invoker 권한이 추가로 필요하다.
- 실제 URL smoke 비용과 시간이 들고, 정답을 모르는 completeness issue는 ground truth 전까지 fixed가 지연된다.
- 대신 잘못된 revision, partial rollout, stale cluster와 부분 추출 오판으로 재시도를 여는 위험을 차단한다.

## 재검토 조건

- 실제 smoke 비용이나 처리 시간이 운영 한도를 넘는다.
- fixture와 deterministic replay가 실제 URL을 대체할 정도로 충분한 원본 snapshot 계약을 갖춘다.
- 복수 Worker service 또는 다중 region traffic을 지원해야 한다.
