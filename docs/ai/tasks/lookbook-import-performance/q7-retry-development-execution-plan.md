# Q7 처음부터 재시도 — 짧은 Development 실행안

2026-10-07. 사용자가 K/L 두 브랜드·최대8접수·20분·추가 관리US$1/누적US$10 추천안을 확정하고 구현·검사·Development 배포·실행을 승인했다. 장애 장치와 실행기를 구현하고 필수 로컬 검사를 통과했다. 실제 실행 결과는 별도로 기록하며 과거 midresume 4접수/62JPEG 산술은 사용하지 않는다.

## 추천 최소 범위

새 QA 가상 브랜드 K/L 각각 UNAFFECTED 2026SS 하나를 사용한다. 원래 A~J와 모든 기존 결과는 보존한다. 원본은 `collection/view.html?product_no=534&cate_no=88&display_group=1`; 기존 AMD64 fixture는 원본30개·커버1개·최종 JPEG62개다. 원격 검토 결과의 후보/순서/해시/버전을 fixture와 확인한 경우만 정상 승인한다.

| 조건 | 실제 동작·접수 | 합격 조건 |
|---|---|---|
| K 실제 비정상 종료1회 | 브랜드 생성/목록1 → 시즌 접수1 → 검토 승인1 → 첫 객체 업로드 후 공개 전에 지정 Worker에 고의 OOM → 실제 시스템 종료 증거 확인 → 같은 execution의 새 추출 → 필요 시 새 검토 승인1. 최대4접수 | 이전 run의 공개/늦은 쓰기 차단, 최초+새 추출 시도2/5, partial season/posts 참조 해제, 원본 재파싱/새 검토, 고유 경로 성공62JPEG, 종료 증거 원문·trace/instance/revision 일치 |
| L 소진·수동 새 시작 | 브랜드 생성/목록1 → 시즌 접수1 → 다운로드 전 지정 execution에 retryable 제어 실패5회 → 실패 목록 조회 → 맨뒤 수동 새 요청1 → 추출/검토 승인1. 최대4접수 | 원래 execution5/5·실패 문서1개, 재접수 새 execution/새5회/새 sequence, 성공 시 실패 목록 제거·원래5회 이력 보존 |

합계 새 브랜드2개·시즌2개·변경 접수 최대8회다. L의 제어 실패는 실제 네트워크 장애나 Worker 프로세스 종료5회로 표시하지 않는다. 실제 종료는 K1회만 수행하며 총5회 소진/수동 접수 API의 원격 연결은 L에서 확인한다. `재시도 안 함`의 제거·경합과 완료된 다른 시즌 보호는 필수 Emulator 결과로 구분하고 이번 원격 성공으로 표시하지 않는다.

## 고의 종료 장치 범위

- Development project/service 및 0% 전용 candidate, 지정 campaign/batch/job/execution에만 적용한다. 새 공개 관리 API·IAM·자원 증설은 추가하지 않는다.
- K는 첫 업로드 확인 직후 공개 전 원자적인 일회성 장치 소비를 기록한 뒤 동기 메모리 압박으로 실제 커널 종료를 유도하는 안이다. 정상 제품 메모리 감독의 중단·재개 실험과 분리한다. 오류5회를 실제 OOM5회로 확대하지 않는다.
- 새 실행/중복 HTTP에서 장치를 다시 소비하지 않아야 한다. K는1회, L은원래 execution의5회에만 고정하고 수동 새 execution은 대상에서 제외한다. 장치가 실제 종료/실패를 일으키지 않으면 해당 조건 미검증으로 중단한다.
- 기존 Cloud Logging provider의 정확한 플랫폼 증거만 허용한다. 요청 timeout·HTTP502·앱 기록·OOM 주입 코드 실행만으로 종료 확인을 선언하지 않는다. 로그 미확인/공유 큐 간섭/다른 revision/메모리 감독 중단/미확정 접수면 추가 투입을 중단한다.
- 자동 정산은 task 재전달에서 같은 차례를 유지한다. Cloud Tasks 재전달·종료 로그 도착이 즉시라는 보장은 없다. 시간 창이 끝나면 무단 차단 해제를 하지 않고 원본과 상태를 보존한다.

## 요청·전송량 계획

fixture 기반 미디어 계산이며 HTML/브라우저/목록 커버 탐색/SDK 재전송은 별도 계측한다. 현재 사이트가 같은 입력이라는 보장은 없으므로 실제 검토 결과가 다르면 중단·재산정한다.

- 시즌 원본 해시30 GET = 2,499,444 B; 저장 때 원본30+커버1 GET = 2,613,375 B; 성공62 JPEG = 2,353,608 B.
- K 최초 추출+부분 저장+새 추출+최종 저장을 각 전체 입력으로 잡고 L 성공1회를 더하면 시즌 원본 GET 최대183회·15,338,457 B다. 목록 커버·HTML·브라우저 요청은 이 값에 포함되지 않는다.
- K 중단 쓰기를 보수적으로62개 전체 크기로 잡으면 K 최종62+L 최종62 포함 최대186 JPEG·7,060,824 B. 실제 중단 쓰기 수/bytes는 별도로 기록한다.
- 성공 산출물의 검증 body GET124회·4,707,216 B, generation metadata GET124회. 중단 원장 missing generation 확인 HEAD는 추가로 기록한다. 클라이언트로 받는 Storage bytes도 과금 검토에 포함한다.
- app callable 논리 변경8회와 조회·SDK 전송·Cloud Tasks dispatch는 별개다. polling은 기존3초/10초 규칙, 전체 실행창20분·조회 최대400회·실제 task 전달 최대20회 제안. 초과 시 새 투입 중지하며 실행 중 정리를 기다린다.
- Firestore document read/write/delete, Cloud Logging query·ingestion, Functions/Worker instance CPU·GiB-seconds·request, Cloud Build 및 Artifact Registry, Storage Class A/B·metadata/delete·보관·클라이언트 전송을 함께 기록한다. `generation` 정리를 단순 업로드량에서 누락하지 않는다.

## 배포·정리 대상·비용

실행 전 live candidate는 `00024-car`이고 새 재시도 코드는 미배포다. 새 gate 통과 snapshot으로 Development-only candidate1회와 `getSeasonImportBatch`·`getSeasonImportFailures`·`requestSeasonImportFailureRetry`·`dismissSeasonImportFailure` 4개 callable, 실패 목록/actions의 expiresAt collection-group 인덱스2개만 배포한다. 실제 URL/env/task route/canonical audience,1CPU/2GiB/min0/revisionmax1/concurrency2/900초, base100%/candidate0%와 공유 큐 비활성 상태를 readback한다. 실제 대상과 permission은 기존 승인 범위만 사용한다.

삭제 범위는 새 K의 이번 미완료 `import_{jobID}` season/posts/assetFailures·참조 해제뿐이다. 원본 실행/완료 K/L/기존 A~J·브랜드는 삭제하지 않는다. 원격 실행 전에 정확한 campaign manifest/brand/job/execution 경로를 확정한다. 파일은 현재 참조 보호·종료 확인·24시간 후 exact generation으로 정리하도록 원장에 예약한다. Development readback에서 `cleanupExpiredLookbookImportAssets`·`cleanupExpiredLookbookImportRecords`가 미배포임을 확인했다. 기존 QA 전체에 영향을 줄 수 있는 스케줄러를 이번 실험에 임의 활성화하지 않는다. 이번 짧은 검증은24시간 실제 삭제 완료로 표시하지 않고 정리 의도·보호·metadata/generation만 확인한다. 스케줄러 활성화는 대상·주기·기존 QA 보호를 점검하는 별도 배포 항목이다.

고의 장애의 root/targets 제어 문서는 서버 자격으로 기록하며 8회 제품 접수와 별도로 집계한다. 장치는 campaign UUID·revision·검증 digest·batch/job/execution이 일치할 때만 작동한다. 같은 execution의 다음 검토 승인 batch와 L의 새 수동 execution은 고의 장애 대상이 아니다.

### 2026-10-07 실행 전 보수 비용 산식

Cloud Billing 공식 SKU API의 USD 단가와 실제 Seoul/Standard Firestore/REGIONAL Storage 설정을 읽었다. 무료 잔여량은 차감하지 않는다. 아래는 실측 청구액이 아니라 시작 전 관리 추정이며 빌드 완료 뒤 실제 machine·duration·새 image 크기로 다시 점검한다.

| 항목 | 사용량 가정·유료 단가 | 추정 USD |
|---|---|---:|
| Worker | 1CPU·2GiB×1,200초, CPU0.0000336/s·메모리0.0000035/GiB-s |0.04872|
| Functions | 합계1CPU·0.25GiB×1,200초 여유 |0.04137|
| 시작 CPU 증가 여유 | 추가120 CPU초 |0.00404|
| Firestore | read10,000×0.00000038, write4,000×0.00000115, delete500×0.00000013 |0.00847|
| Cloud Build | 신규 전체 빌드 합계30분×0.006/min(e2-standard-2, 완료 후 실제 확인) |0.18|
| Artifact Registry | 새 레이어/이미지 합계4GiB·1개월×0.10/GiB-month |0.40|
| Logging | 신규20MiB×0.50/GiB |0.00977|
| Storage·전송·Tasks·요청 여유 | JPEG7.1MB 보관, 검증 GET/metadata124, ClassA/B, APAC 전송0.12/GiB, 요청/dispatch |0.01|
| 합계 | 실제 빌드·이미지·기간 확인 전 가정 |약0.70|

Cloud Run SKU085C-A237-027A/600C-3782-6708, Firestore157A-FD73-0D3D/BC76-86BE-E758/B836-9EB1-482A, Storage4DBF-185F-A415/7870-010B-2763/59CF-0E01-97FE/1F8B-71B0-3D1B, BuildA464-9020-6404, Artifact8502-299A-ABAF, Logging143F-A1B0-E0BE를 사용했다. 원본 catalog는 `/tmp/outpick-q7-retry-skus-*.json`에 보존하고 최종 결과에 선택 단가와 실제 사용량을 남긴다. 청구 지연과 공유 레이어·기존 무료량 때문에 정확 결제 상한은 보장하지 않는다.

제안 관리 예산은 추가 US$1·기존 누적 US$10 이내, 실행창20분이다. **총 실제 요금은 확실하지 않음**: 무료 잔여량/정확한 지역 SKU/청구 지연·빌드 캐시·다른 작업 사용량을 확인하지 않아 정확한 결제 상한이나 전체 가격을 보장하지 않는다. 실행 전 실제 설정의 단가×계측량 추정이 관리 예산을 넘으면 시작하지 않고 재논의한다. 이미지7MB만으로 총액을 추정하지 않는다.

2026-10-07 확인한 공식 과금 근거: [Cloud Run](https://cloud.google.com/run/pricing), [Cloud Storage](https://cloud.google.com/storage/pricing), [Firestore](https://cloud.google.com/firestore/pricing), [Cloud Tasks](https://cloud.google.com/tasks/pricing). Worker/Functions의 실제 billing 모드·지역과 전체 사용량을 적용해야 하며 웹 페이지 기본 지역 단가를 서울 단가로 쓰지 않는다.

## 순서·필수 증거

승인된 장애 주입 방법/8회 규모 → 최소 Development 전용 장치·실행기 연결 → 새 필수 게이트 → snapshot 배포/readback → K → 종료·정리 확인 → L → 공개 원장/파일 hash/generation 대조 → 결과·실패 원본·하네스 → 최종 커밋이다. 이전 중간 resume endpoint를 K에서 사용하지 않는다.

새 원격 실행의 성공은 기존 A~J 성능 결과와 구분한다. 실제12/14/15분 플랫폼 경계, 다중 브랜드 active 도착 시점 및 실제24시간 삭제는 후속 미검증으로 남긴다. 실패한 실행 원본과 프로그램적 gate source digest·원본 로그를 보존한다.
