# ADR-008: URL 기반 시즌 import는 Firestore job queue와 Cloud Run worker로 처리한다


상태: accepted

결정:

- 앱은 브랜드 생성, 시즌 후보 선택, import job 등록, 진행 상태 표시를 담당한다.
- `seasonCandidates`와 `importJobs`는 Firestore에 저장해 앱 종료, 재진입, 실패, 재시도, 중복 방지를 견딜 수 있게 한다.
- URL 기반 시즌 import의 무거운 작업은 Cloud Run worker가 담당한다.
- Cloud Run worker는 queued import job을 가져와 URL 파싱, 이미지 후보 추출, 시즌/포스트 문서 생성, Storage thumb/detail asset sync, Firestore 상태 갱신을 처리한다.
- Firebase Functions는 긴 import 작업을 직접 수행하지 않고, Firestore trigger로 Cloud Run worker를 깨우는 wake-up 역할을 우선 담당한다.
- worker는 batch size, 동시성 제한, retry/backoff, already-synced skip 정책을 내부에서 관리한다.
- 앱은 Firestore의 job 상태와 생성된 시즌/포스트 문서를 구독하거나 재조회해 사용자에게 진행률, 실패, 재시도 진입점을 표시한다.

이유:

- Swift `Task` registry만으로는 앱 종료, 네트워크 실패, Cloud Functions 중단, 다른 기기 재진입을 견딜 수 없다.
- URL 기반 import는 서버 작업이 길고 여러 단계로 나뉘므로, Firestore job 상태가 복구 기준이 되어야 한다.
- 40개 이상의 시즌을 선택한 경우 외부 URL fetch/parse와 이미지 asset sync를 한 번의 callable timeout 안에 모두 끝내기 어렵다.
- Cloud Run은 컨테이너 기반 worker를 배포할 수 있어 URL 파싱, 이미지 처리, retry/backoff, 동시성 제한을 Functions callable보다 명확하게 제어하기 좋다.
- Functions는 wake-up만 담당하면 timeout과 부분 실패 표면을 줄이고, 앱은 기존 Firestore job 흐름을 유지할 수 있다.
- 이미지 asset sync가 중간에 멈추면 grid가 detail/remote fallback에 의존해 성능과 표시 안정성이 나빠질 수 있다.
- 이미 성공한 asset을 재생성하지 않으면 retry 비용과 실패 표면을 줄일 수 있다.

트레이드오프:

- Firestore에 임시 후보/job 문서가 남으므로 정리 정책이 필요하다.
- Cloud Run, Artifact Registry, IAM, 배포 스크립트 같은 운영 요소가 추가된다.
- Functions trigger와 Cloud Run worker 사이의 인증, 중복 wake-up, idempotency를 설계해야 한다.
- worker가 꺼져 있거나 배포 실패 상태면 import job이 queued/pending에 머물 수 있다.
- Cloud Scheduler 또는 Cloud Tasks를 바로 도입하지 않으면 장애 복구 wake-up은 별도 phase에서 보강해야 한다.
- 이미 생성된 asset이 손상된 경우 기본 skip 정책만으로는 복구할 수 없고, 추후 force 재생성 옵션이 필요할 수 있다.

재검토 조건:

- `queued`, `processing`, `pending` job이 반복적으로 장시간 남으면 Cloud Scheduler polling recovery 또는 Cloud Tasks 기반 큐를 도입한다.
- 중복 worker 실행이 Firestore write 충돌이나 중복 Storage upload를 만들면 job lease, generation, idempotency key 정책을 강화한다.
- asset 파일 손상이나 잘못된 thumb/detail 경로가 확인되면 force resync 옵션을 추가한다.
- import job과 season candidate 문서가 과도하게 쌓이면 TTL 또는 완료 후 정리 정책을 도입한다.
- worker 운영 비용, cold start, 처리 latency가 사용자 경험에 영향을 주면 min instances, batch size, 동시성, Cloud Tasks 전환을 재검토한다.

