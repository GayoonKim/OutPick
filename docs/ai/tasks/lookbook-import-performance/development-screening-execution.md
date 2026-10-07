# Development 약식5회 — 배포·실행 확인안

**최신 — Development 실제 약식5회 완료:** [실측 결과·원본·게이트·비용 추정](development-screening-results.md). 준비1회와 PP/SP/PS/SS 각1회가 모두 성공했고 실제 실행·원본 재검사 게이트를 통과했다. 전체 처리100~104초, 브랜드 순차 후보의 첫 브랜드 완료는 약10% 빨랐으나 각1회·동일 인스턴스·고정 순서이므로 채택은 미판정이다. 추가 실행/운영 반영/삭제는 하지 않았다. 아래 승인 대기·미실행 문구는 실행 전 이력이다.

실행 전 기록: 2026-10-04. [약식 계약과 로컬 검증](development-screening.md) 이후 사용자의 다음 작업 지시에 따라 읽기 전용 준비를 완료했다. **현재 상태: 배포·유료5회 실행 승인 대기.** 아래 범위는 실행할 안이며 아직 push·배포·Worker 호출·Firebase 실험 데이터 쓰기를 하지 않았다.

## 확인한 입력과 대상

- UNAFFECTED 목록1개+시즌6개 HTML을 다시 읽었다. 선택6시즌의 URL·커버 URL·본문 후보 순서가 고정 입력과 같으며 본문132개+커버6개,138개 원본의 SHA/bytes가 모두 일치했다. 수신112,771,684bytes다.
- HTML 자체의 hash는6시즌 모두 이전과 달랐다. 이미지 후보·순서·원본 bytes/hash 비교가 통과했다는 뜻이며 HTML 전체 불변을 주장하지 않는다. 기존 `needsReview(expected_count_unverified)`6건을 그대로 기록했고 제품 검토 완료/자동 등록 성공으로 처리하지 않았다.
- 원본 검사는 Mac에서 직접 다운로드했으며 Cloud Run 성능/네트워크 표본이 아니다. 이 단계의 Firebase 데이터 읽기/쓰기와 Worker 요청은0이다. 별도의 Google Cloud 제어 API 설정·IAM 조회와 OIDC 토큰 발급 확인은 수행했다.
- 서비스는 `outpick-test` / `asia-northeast3` / `lookbook-import-worker-development`. 기존 기본 트래픽은 `lookbook-import-worker-development-00012-fih`100%,1CPU/2GiB·요청동시성2·timeout900초다. 현재 서비스 max5/기존리비전 max20은 유지한다. 현재 전체 프로젝트가 인스턴스1개나 무료라는 뜻은 아니다.
- bucket `outpick-test.firebasestorage.app`과 Firestore `(default)`는 서울이다. Storage는 legacy REGIONAL(Standard에 해당), uniform access off, soft delete7일이다. Artifact Registry의 추가 취약점 자동 스캔은 비활성 상태다.
- 기존 호출자 `86635107099-compute@developer.gserviceaccount.com`의 run.invoker와 사용자 OpenIdTokenCreator 바인딩을 확인했다. 현재 코드의 generateIdToken 경로로 audience/email/만료 확인에 성공했고 토큰은 파일/로그에 남기지 않았다. 새 객체 `result.json`의 로컬 ADC 읽기 가능 여부는 실제 smoke에 남는다. 기존404 응답으로 허용을 단정하지 않는다.

## 승인받을 실행 범위

| 항목 | 구체 실행안 |
| --- | --- |
| 이미지 | 검증된 로컬 linux/amd64 runtime `sha256:7e97ef277b2e19c09c99baf6afa767c322daa552c3747001f7cfe81f7ae5fb05`를 기존 registry에 push. Cloud Build 재빌드 없음 |
| registry tag | `asia-northeast3-docker.pkg.dev/outpick-test/cloud-run-source-deploy/lookbook-import-worker-development:screen5-20261004` |
| Cloud Run tag / revision | `screen5-20261004` / `lookbook-import-worker-development-screen5-20261004`. 조회 시 충돌 없음; 생성 직전 재확인 |
| 격리·자원 | 새 revision 기본트래픽0%, min0/max1,1CPU/2GiB,concurrency2,timeout900초,요청 기반. 기존 tag/기본100%트래픽/IAM 유지 |
| 요청 | 한 번에1개. 준비 `smoke-PP-single-1` → `PP-synthetic-three-1` → `SP-synthetic-three-1` → `PS-synthetic-three-1` → `SS-synthetic-three-1`, 최대5회 |
| 실행 정책 | 다운로드4·변환1·업로드4·경로저장 무제한,실행 내 원본 재사용128MiB. 각 본 비교는 동일6시즌/합성3브랜드×2시즌 |
| 저장 | Storage `lookbook-import-performance/{campaignID}/{runID}/`; Firestore 실험 runs/campaigns/control 컬렉션. 제품 게시물/시즌 등록 없음 |
| 기록 | 원본 결과 JSON·로컬 journal·첫브랜드/전체/첫시즌 시간·메모리·CPU/단계 지표·실패/재시도·전송량·작업별 비용 추정 보존 |
| 회차 중단 | 원본 변화·golden 오류·메모리85%1초·표본간격500ms 초과·실패/종료미확인 시 다음 회차 금지. 현재 작업의 정리 확인,자동 재호출/보충 없음 |
| 시간·비용 | 회차840초·실험창2시간. 기존 누적 추정US$10 중단 유지. 첫5회 이후 자동 추가 없음. 추정 중단은 실제 청구 상한이 아님 |
| 제외 | 운영 배포, 제품 분산 큐 변경, IAM 변경, 데이터 삭제, 추가 회차, 자동 채택/정리 |

manifest는 version3, plan digest `0ead82ab8e323d8cd7b15bd1f7e5ab76a75256856f52e29c35283ef46295011b`, corpus digest `49671fbcd756f733e034bc079cc6911fa6ef18184e9e6206f3c1d0d475fa8f15`다. sourceRevision은 HEAD `1d67d61faa04984783083971688a7c628df74748`, 작업 트리는 통과한 Mac 게이트 sourceDigest `c68068fc5e5feef261398bc165255017088ea10ec88873f2e249dd17c073b212`와 compiled284개 대조로 연결한다. 코드를 변경하면 이 검증을 새 상태로 재사용하지 않는다.

[execution-proposal.json](../../../../output/lookbook-import-performance/screening-readiness/execution-proposal.json)은 **실행 전 검토 자료**다. CLI가 바로 받아 실행하는 manifest가 아니다. 승인된 시작 시점에 고유 campaignID·2시간 만료시각과 push 후 확인한 원격 digest를 묶어 새 execution.json을 만든다. 새 revision의 실제 설정·기본트래픽0·digest·OIDC env를 기존 `assertRemoteTarget`으로 재검사한 뒤 CLI를 실행한다. 새 환경에서 cgroup이 보이지 않거나 golden/결과 수집이 실패하면 smoke에서 중단한다.

## 5회 정상 요청량과 비용

재시도 없는 정상 처리 가정이다. 이미 마친 로컬 사전 확인138개와 구분한다.

| 항목 | 실행5회 예상량 |
| --- | ---: |
| 원본 다운로드 GET | 583~1,137회 / 약0.454~0.900GB |
| JPEG 업로드 | 1,158개 /171,392,080bytes |
| JPEG 검증 읽기 | 1,158개 /같은171,392,080bytes |
| result.json | 쓰기5개+로컬읽기5개 /최대40MiB |
| Storage 정상 쓰기/읽기 | 각각1,163건 |
| Firestore read/write | 1,163 /1,188건 |

2026-10-04 공식 HTML 안의 **서울 리전 표**를 추출해 단가를 재확인했다([표 원본](../../../../output/lookbook-import-performance/screening-readiness/seoul-price-tables.json)). USD·무료 차감 전·세금/환율/할인 제외다. 잔여 무료량은 확인하지 않았다.

| 항목 | 모델 가정과 추정USD |
| --- | --- |
| Worker CPU+메모리 | 1CPU/2GiB, CPU0.0000336/초+메모리0.0000035/GiB초. 누적 활성30분0.07308 /60분0.14616 /120분0.29232 |
| Storage 작업 | A0.005/천건·B0.0004/천건. 정상 각각1,163건 합계 약0.00628 |
| Firestore read/write | 0.038/십만·0.115/십만. 정상 합계 약0.00181 |
| JPEG+최대 결과JSON 보관 | 서울0.000031507/GiB시간,30일 가정 약0.00451 |
| 결과JSON 인터넷 전송 | 최대40MiB·0.12/GiB 가정 약0.00469. JPEG를 Mac으로 재다운로드하지 않음 |
| HTTP 요청 | 5회·0.40/백만,약0.000002 |
| 외부 비용 여유 | manifest `externalCostUSD=0.30` 제안: 새 registry1GiB/30일0.10 +로그100MiB0.05 +시작 boost·제어/추가 네트워크·문서/인덱스 보관 등0.15. 실측값/상한이 아님 |

**위 가정의 합계는 활성30/60/120분에 약US$0.39/0.46/0.61**이다. [계산 원본](../../../../output/lookbook-import-performance/screening-readiness/cost-estimate.json)을 보존한다. 이는 실제 소요 시간을 예측한 범위나 US$0.61 이하 보장이 아니다. 재시도·SDK 추가 호출·로그·이미지 보관량·보관 기간이 가정에서 벗어나면 추가 비용이 발생한다. Cloud Build는 실행하지 않는 안이며, 기존 프로젝트의 다른 사용량은 이번 작업 추가 비용과 구분한다.

실행기에는 각 회차의 준비/검증까지 포함한 시간과 실제 계측 요청량을 합산한다. 표의 정상량보다 제어 read 여유가 있는 기존 비용 모델을 유지하고, 다음 회차의 재시도 가정 비용까지 더해 중단을 판단한다. 저장물 자동 삭제는 하지 않으므로30일 이후 보관 비용은 계속 발생할 수 있다. 무료 차감·정확한 결제 상한은 보장하지 않는다.

공식 근거: [Cloud Run](https://cloud.google.com/run/pricing), [Storage](https://cloud.google.com/storage/pricing), [Firestore](https://cloud.google.com/firestore/pricing), [Artifact Registry](https://cloud.google.com/artifact-registry/pricing), [Logging](https://cloud.google.com/products/observability/pricing). 서울 같은 리전의 Worker↔Storage 전송 조건과 인터넷으로 수집하는 결과 전송을 구분했다.

## 프로그램적 확인과 남은 항목

- 입력 preflight 게이트: [passed](../../../../output/verification/1791115435609-29ba8c36-2d48-4bb3-a0fc-1ac207df3855/summary.json). HTML7개·원본138개 exact 비교. [상세](../../../../output/lookbook-import-performance/screening-readiness/preflight.json). 별도 원본 재저장/Firestore 쓰기 없음.
- 대상 snapshot·입력·계획·가격 산술 게이트: [passed](../../../../output/verification/1791115605247-ee693604-e2be-457d-90d4-5e1414c7ad90/summary.json). 이 검사는 아직 존재하지 않는 후보 revision 배포 성공을 의미하지 않는다.
- 실제 조회 snapshot·IAM/OIDC 증거는 [준비 폴더](../../../../output/lookbook-import-performance/screening-readiness/)에 보존했다. 토큰은 없다.
- 제품/Worker 소스는 이번 단계에서 변경하지 않았다. 이전 [Mac/Linux307개·emulator5개](development-screening.md)의 코드 상태가 유지돼 전체 회귀 검사를 불필요하게 반복하지 않았다.
- 남은 확인: push 후 remote digest, 새 revision 실제 설정, Cloud Run CPU golden exact 일치, cgroup 계측, 새 result.json 로컬 수집, 실제 시간/전송/비용. 배포·최대5회 유료 실행 승인 뒤 확인한다.

추가 비교는 결과 분석 후 별도 회차/비용을 제시한다. 이번5회로 최적 구조·낮은 실패율을 확정하거나5쌍 반복 악화 규칙을 적용하지 않는다.
