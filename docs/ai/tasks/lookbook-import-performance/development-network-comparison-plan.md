# Development 실제 네트워크 비교 — 최소 변경·실행 규모·비용 검토안

**최신 — Development 실제 약식5회 완료:** [실측 결과·원본·게이트·비용 추정](development-screening-results.md). 준비1회와 PP/SP/PS/SS 각1회가 모두 성공했고 실제 실행·원본 재검사 게이트를 통과했다. 전체 처리100~104초, 브랜드 순차 후보의 첫 브랜드 완료는 약10% 빨랐으나 각1회·동일 인스턴스·고정 순서이므로 채택은 미판정이다. 추가 실행/운영 반영/삭제는 하지 않았다. 아래 승인 대기·미실행 문구는 실행 전 이력이다.

실행 전 기록: **배포 전 준비:** [약식5회 실행안·현재 대상·비용·검증](development-screening-execution.md). 로컬 원 사이트 HTML7개/원본138개 검사가 통과했고 현재 설정·기존 OIDC와 서울 단가를 재확인했다. 준비 게이트2개 통과, Worker 소스 변경 없음. push/배포/Worker 실험 요청/Firebase 실험 쓰기는 아직 하지 않았다.

**최신 — 약식5회(version3) 로컬 구현·검증 완료:** [확정 조건·구현·검사·요청량](development-screening.md). 준비1회+PP/SP/PS/SS 각1회로 축소한다. 다운로드4·변환1·업로드4·재사용128MiB는 유지한다. `remote-contract.ts`의5회 계약과 `remote-report.ts`의 단일 관측 집계가 현재 기준이며, 채택/반복악화/실패율 개선 판정은 하지 않는다. Mac/AMD64 각각307개·필수199개, emulator5개와 요청량/이미지 대조 게이트를 통과했다. 실제 배포·유료 실험은 미실행이다. 아래21회 실행안·version2·과거 ‘현재/다음’ 문구는 이전 이력이며 추가 실행 권한이 아니다.

최신: [AMD64 기준 분리·필수 검증](development-amd64-golden.md). 사용자 승인에 따라 AMD64 기준을 별도로 생성했고 아래 JPEG bytes를 새 기준으로 재산출했다. [인증·배포 초안](development-amd64-readiness.md)의 대상/권한 조건을 유지하되 새 최종 이미지/digest는 기준 분리 문서를 따른다. 실제 배포·유료 실험은 미실행이다.

작성: 2026-10-04. 사용자 요청에 따라 기존 연결·실제 Development 설정·공식 요금을 읽고 정리했다. 이후 사용자가 변환 1 유지와 “그렇게 다음 핵심 작업 진행”을 지시해 **네 구조20회+연결 확인1회의 로컬 계약·실행기·집계 구현을 진행했다.** [구현·필수 검사·남은 배포 전제](development-network-implementation.md)를 따른다. 실제 배포·유료 실험 승인은 포함하지 않는다. 아래 요청량·단가는 검토 당시의 추정이다.

## 1. 목적과 범위

실제 이미지 다운로드 → 해시 중복 제거 → 썸네일/상세 JPEG 변환 → Storage 업로드 → Firestore 경로 기록을 포함해 브랜드/시즌 실행 순서와 단계별 동시성을 결정한다.

먼저 같은 단계별 제한에서 실행 순서만 비교하고, 유력 구조에서 다운로드·변환·업로드 제한을 한 축씩 조절한다. **이미지별 메모리 예약과 R 자동 조절 연결은 보류**한다. 기존 AD1/AD2a 코드·테스트·측정 결과는 보존한다. 다운로드 재사용 128MiB는 이미 구현한 실행 내 캐시이며 새 메모리 예약 제어기와 다르다.

이 비교는 한 Worker 실험 요청 안에서 실행 순서를 비교한다. 모바일 요청 → Functions → 제품 분산 큐 전체를 바꾸거나 글로벌 브랜드 FIFO를 구현하지 않는다. 실험 결과로 제품 반영안을 정한다.

## 2. 확인한 기존 연결과 최소 변경

| 구분 | 현재 상태 / 필요한 변경 |
| --- | --- |
| 실제 I/O | `remote-io.ts`, `remote-firebase.ts`의 원본 HTTP GET·JPEG 저장·Firestore 경로 기록·저장 결과 재검사 재사용 |
| 실행 순서 | `season-runner.ts`가 이미 parallel / serial-per-brand / serial-brands 지원. 새 스케줄러 불필요 |
| 원격 계약 | `remote-contract.ts`의 P/S·3부하·30회 하드코딩을 version2의 고정 4조합·20회와 smoke 1회로 변경. 요청 본문은 허용된 runID만 받고 임의 수치 입력 금지 |
| 원격 실행·집계 | `remote-runner.ts`의 P/S 분기를 실행 정책 매핑으로 변경. `brandMetrics`의 브랜드 순차 여부도 함께 변경. 신규 후보를 공정하게 대응 비교하는 집계 연결 |
| 경로·순서 검증 | `remote-io.ts`의 P/S 전용 경로 허용식과 `remote-store.ts`의 고정 순서 조회를 같은 version2 계약에 연결. version1 결과와 혼합 금지 |
| 유한 실행 도구 | 기존 scripts 패턴에 맞춰 회차 1개씩 인증 호출, 응답 유실 시 재실행 금지, 결과 수집·중단·요청량/추정 비용 집계를 연결. 현재 D0~D3에 완성된 캠페인 실행기는 없음 |
| 검증 | 기존 remote 계약/실행 테스트와 emulator RD01~04를 갱신하고 4조합 순서·저장/정리 후 전환·누락/중복 회차 거부·중단 후 새 요청 금지를 검사 |
| 하네스 | 최신 계약·파일 위치·필수 검사 ID를 ENTRYPOINTS/LOOKBOOK/TESTS 및 검증 설정에 반영 |

Swift/DI/Coordinator, 제품 Functions, Firestore rules/indexes, 원본 사이트 크롤러의 제품 동작은 변경 대상이 아니다. 저장 이미지도 기존의 썸네일+상세 JPEG 2개다. 원본 파일 그대로 추가 업로드하지 않는다.

후속 수치 비교에는 추가 주의가 필요하다. 현재 `SubmissionRuntime`은 기본 변환 1을 전제로 한다. 변환 2/4/제한 없음 비교 시 이 조건과 우선순위 큐를 함께 수정해야 한다. 시즌당 이미지 4개 투입 제한을 그대로 두면 “변환 제한 없음”도 그 범위 안에서만 작동한다. 결과에 실제 동시 수·대기 수를 남기고 제한을 해제했다고 과장하지 않는다.

## 3. 실행 대상과 자원

2026-10-04 gcloud 읽기 전용 조회 결과. [확인 설정·입력별 산출값·단가 증거](../../../../output/lookbook-import-performance/development-network-plan-2026-10-04/evidence.json)를 보존했다.

| 항목 | 확인 결과 / 실행 제안 |
| --- | --- |
| 프로젝트 | Development `outpick-test` |
| Worker | 서울 `asia-northeast3`, `lookbook-import-worker-development` |
| 현재 기본 트래픽 | `lookbook-import-worker-development-00012-fih` 100% |
| 현재 인스턴스 | 1 vCPU·2GiB, HTTP 동시성 2, 요청 timeout 900초, startup CPU boost on |
| 현재 스케일 설정 | 서비스 maxScale 5, 현 트래픽 리비전 maxScale 20, min 명시 없음. “인스턴스 1개로 고정되어 무료”인 설정은 아님 |
| 실험 후보 제안 | 기본 트래픽 0%인 새 tag 리비전, 1 vCPU·2GiB 유지, 후보 리비전 min0/max1, HTTP 동시성 2 유지·실험 요청은 한 번에 1개 |
| Storage | `outpick-test.firebasestorage.app`, ASIA-NORTHEAST3, REGIONAL, soft delete 7일 |
| Firestore | `(default)`, Native/Standard, asia-northeast3 |
| 실행 계정 | `outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com` |
| 인증 | 기존 지정 OIDC 호출자·canonical audience 유지. 호출자 impersonation/IAM 실제 가능 여부는 배포 전 확인 |

현 리비전 image digest는 `sha256:42344ae960f2d837ccfee79498a0e938afb0c681c358dd029411f36531d29287`이다. 새 비교 코드는 아직 배포되지 않았다. 현재 서비스 전체 스케일이나 기존 트래픽·tag를 변경하지 않는다. 후보 max1은 스케일 설정이며 플랫폼의 일시 초과까지 절대 방지하는 장치는 아니다. 기존 실험 관련 총 인스턴스 3개 상한과 단일 회차 claim을 함께 확인한다.

저장 경계는 기존 `lookbook-import-performance/{campaignID}/{runID}/`와 `lookbookImportPerformanceRuns`, `lookbookImportPerformanceCampaigns`, `lookbookImportPerformanceControl`이다. 제품 브랜드/시즌/import job에는 쓰지 않는다.

## 4. 첫 비교 제안: 네 구조 × 5회 = 20회

입력은 UNAFFECTED 2026/2025/2024 각 FW·SS, 총 6시즌이다. 연도별로 합성 브랜드 A/B/C를 만들어 각 2시즌을 배정한다. **동일 사이트의 합성 3브랜드**이므로 서로 다른 사이트·호스트의 제한이나 네트워크 차이까지 검증하지는 않는다.

| ID | 브랜드 사이 | 브랜드 내부 시즌 | 실행기 매핑 | 최대 실행 중 시즌 |
| --- | --- | --- | --- | --- |
| PP | 병렬 | 병렬 | parallel, concurrency6 | 6 |
| SP | 순차 | 병렬 | serial-brands, concurrency6 | 2 |
| PS | 병렬 | 순차 | serial-per-brand, concurrency6 | 3 |
| SS | 순차 | 순차 | serial-brands, concurrency1 | 1 |

모든 후보의 고정 조건:

- 해시 확인과 저장용 원본 GET이 공유하는 다운로드 슬롯 4.
- **변환 슬롯 1은 JPEG 변환 1건 기준**. 이미지마다 썸네일/상세 두 변환이 슬롯을 사용한다.
- 업로드 슬롯 4도 JPEG 객체 4건 기준. 경로 저장에는 별도 슬롯 상한 없음.
- 시즌당 처리 중 이미지 4개, 빈자리 보충. 모든 시즌이 같은 단계 슬롯을 공유한다.
- 실행 내 원본 재사용 128MiB·기존 커버 선준비·준비된 작업의 시즌 순위 우선 유지.
- 순차 전환은 선택 시즌의 저장 완료/검토 대기/최종 실패와 실행 중 작업 정리 후. 시즌 최초 포함 최대 5회 재시도, 다운로드 내부 최대 3회는 별도 기록.
- 메모리 100ms 표본·간격 500ms 초과 시 환경 미검증·85% 이상 1초 시 중단 유지. CPU·메모리는 계측하며 개별 이미지 예약은 추가하지 않음.

한 반복 블록에 4후보를 한 번씩 배치하고 총 5블록을 실행한다. 제안 순서는 ① PP/SP/PS/SS ② SP/PS/SS/PP ③ PS/SS/PP/SP ④ SS/PP/SP/PS ⑤ SS/PS/SP/PP이며 manifest에 고정한다. 5회여서 위치별 횟수는 완전히 같지 않다. 매번 새 실행 ID/Runtime/캐시를 사용하며 새 Cloud Run 인스턴스나 cold start를 보장하지 않는다. 인스턴스/아키텍처/리비전/부팅 상태를 기록한다.

주 지표는 등록 시점부터의 첫 브랜드 완료·전체 완료·첫 시즌 완료, CPU·메모리 최고치, 원본 GET/재사용 hit, 각 단계 실행·대기 시간, 실패·재시도·중단·종료 미확인 수다. 처리 시간과 문서 준비/저장 결과 검증 시간을 분리하고 총 청구 추정에는 모두 포함한다.

PP를 구조 비교 기준선으로 삼되 현재 배포 제품 대비 개선이라고 표현하지 않는다. 정확성 유지·실패율 악화 없음·중앙값 10% 개선을 우선한다. 기존 “5쌍 중 3쌍 이상 10% 느리고 중앙값도 10% 느리면 채택 보류”를 유지한다. 5회는 큰 실패율 차이나 반복 지연을 보는 작은 표본이며 낮은 실패율의 통계적 보장은 아니다.

다음 수치 비교는 결과를 보고 유력 구조에서 다운로드 4→8, 업로드 4→8, 변환 1→2/4/제한 없음 등의 **한 축 비교**를 고른다. 이는 후보 예시이며 실행 확정이 아니다. 브랜드 순서와 단계 수치의 상호작용 때문에 수치 조정 후 기존 2위 구조와 최종 재확인이 필요할 수 있다. 이번 20회로 전역 최적값을 확정하지 않는다.

## 5. 준비와 요청량

준비 제안은 로컬의 저장 없는 URL 검토 1회와 Development 2026SS smoke 1회다. smoke는 PP 정책으로 실제 다운로드→변환→업로드→경로 기록→재검사를 확인하며 본 20회 성능 표본에서 제외한다. 기존 로컬 자료로 Linux/amd64 출력 무결성을 먼저 확인한다.

목록 URL: https://unaffected.co.kr/collection.html?cate_no=88

상세 경로는 `https://unaffected.co.kr/collection/view.html?product_no={번호}&cate_no=88&display_group=1`이다.

| 시즌 | product_no | 후보 / 중복 제거 본문 | 커버 포함 저장 이미지 | JPEG 객체 |
| --- | --- | --- | --- | --- |
| 2026FW | 785 | 24 / 24 | 25 | 50 |
| 2026SS | 534 | 30 / 30 | 31 | 62 |
| 2025FW | 469 | 14 / 14 | 15 | 30 |
| 2025SS | 128 | 17 / 16 | 17 | 34 |
| 2024FW | 510 | 22 / 22 | 23 | 46 |
| 2024SS | 507 | 25 / 25 | 26 | 52 |
| 합계 | — | 132 / 131 | 137 | 274 |

근거: `tools/lookbook-import-worker/fixtures/performance-remote-input-amd64.json`, SHA-256 `49671fbcd756f733e034bc079cc6911fa6ef18184e9e6206f3c1d0d475fa8f15`. 기존 ARM fixture와 원본 입력은 보존했다. 이번 문서 작성 중 원 사이트 이미지를 다시 GET하지 않았다. 실제 실행 전 현재 URL/후보/원본 hash를 확인하고 변경 시 중단한다. 기존 실제 추출 결과의 `needsReview(expected_count_unverified)`와 실험 저장 성공을 구분한다. HTML 추출/검토는 사전 확인이며 아래 이미지 전송 성능의 측정 구간에 포함하지 않는다.

**재시도 없는 정상 실행 예상량**:

| 항목 | 6시즌 1회 | smoke 1회 | 본20+smoke 총21회 |
| --- | ---: | ---: | ---: |
| 원본 GET, 재사용 전부 hit | 138 | 31 | 2,791 |
| 원본 GET, 저장 시 재사용 전부 miss | 269 | 61 | 5,441 |
| 원본 수신 bytes, hit / miss | 112,771,684 / 223,800,086 | 2,613,375 / 5,112,819 | 2,258,047,055 / 4,481,114,539 |
| JPEG 업로드 | 274 | 62 | 5,542 |
| JPEG 업로드 bytes | 42,259,618 | 2,353,608 | 847,545,968 |
| 저장 JPEG 검증 GET | 274 | 62 | 5,542 |
| 경로 저장 대상 | 137 | 31 | 2,771 |
| Firestore 문서 read | 274 | 67 | 5,547 |
| Firestore 문서 write | 280 | 68 | 5,668 |

Firestore 수에는 준비 문서·경로 저장·검증과 정상 claim/finish의 각 3문서 read/write를 포함했다. JPEG 검증 GET 바이트는 업로드와 동일하다. `result.json`은 추가 21개 업로드·최대 168MiB이며, 로컬 결과 수집 GET 21건은 별도다. 따라서 결과 포함 정상 Storage 쓰기/읽기는 각각 5,563건이다. 제어 문서 추가 조회·실험 준비 요청·transaction 재시도·HTTP redirect·실패 응답·SDK 부가 요청은 실측 별도 집계한다.

로컬 URL 사전 검토는 HTML 7회+원본 최대 138회/112,771,684bytes를 별도로 잡는다. 정상 전체 원 사이트 이미지 요청은 합계 2,929~5,579회, 약 2.37~4.59GB(십진)다. 로컬 사전 검토에는 Firebase 저장을 연결하지 않는다.

이 수치는 요청 **상한이 아니다**. 시즌 재시도와 다운로드 내부 재시도가 겹치면 더 커진다. 실제 시도 수/수신·송신 bytes를 계속 합산한다. 원본 변화·정확성 오류·메모리 중단·종료 미확인은 다음 회차를 시작하지 않고 원인을 검토한다. 실패 표본을 지우거나 자동으로 보충하지 않는다.

## 6. 비용: 무료 차감 전 계산

서울 리전을 선택한 공식 가격표를 2026-10-04 확인했다. USD·세금/환율/계약 할인 제외이며 실제 결제액 예측을 위한 **가정 견적**이다. 무료 사용량 잔여는 확인하지 않았다.

| 항목 | 확인 단가 / 이 실행안의 추정 |
| --- | --- |
| Cloud Run 요청 기반 | CPU $0.0000336/vCPU초 + 메모리 $0.0000035/GiB초. 1CPU·2GiB 합산 $0.0000406/초 |
| 누적 활성 시간 | 30분 $0.0731 / 60분 $0.1462 / 120분 $0.2923. 시작/종료·CPU boost는 추가이며 21회 실제 소요 시간은 아직 모름 |
| Storage 작업 | 단일 지역·flat namespace Standard A $0.005/1,000건, B $0.0004/1,000건. 각5,563건 약 $0.0300 |
| JPEG 보관 | 0.7893GiB × 서울 $0.000031507/GiB시간 ×30일 ≈ $0.0179. 결과 JSON 최대168MiB는 30일 약 $0.0037 추가 |
| Firestore read/write | read $0.038/10만, write $0.115/10만. 위 정상량 약 $0.0086. 제어 조회·저장 용량/인덱스 별도 |
| Cloud Build | e2-standard-2 기본 풀 $0.006/분. 빌드1회10분 가정 $0.06. 실제 machine/time에 따라 수정 |
| Artifact Registry | $0.000136986/GiB시간. 신규 이미지 총1GiB·30일 보관 가정 약 $0.10 |
| 로그 | 무료 차감 전 $0.50/GiB. 추가100MiB 가정 약 $0.049 |
| 네트워크 | 동일 서울의 Worker↔Storage/Firestore 전송은 같은 지역 요금 조건 적용. 결과 JSON만 로컬로 수집하면 최대168MiB의 Storage 인터넷 전송 약 $0.020. JPEG 전체를 로컬로 재다운로드하지 않음 |

근거: [Cloud Run](https://cloud.google.com/run/pricing?hl=en), [Storage](https://cloud.google.com/storage/pricing?hl=en), [Firestore](https://cloud.google.com/firestore/pricing?hl=en), [Cloud Build](https://cloud.google.com/build/pricing), [Artifact Registry](https://cloud.google.com/artifact-registry/pricing), [Logging](https://cloud.google.com/products/observability/pricing). 버킷의 legacy REGIONAL은 [Standard에 해당](https://docs.cloud.google.com/storage/docs/storage-classes#legacy)하므로 해당 단가를 사용했다. 실행 전 객체 클래스·namespace·추가 저장 기능도 확인한다.

위 가정의 합계는 대략 **US$0.36~0.58**이다. Firestore 문서/인덱스 보관, 빌드 소스 보관, 원 사이트 GET 요청의 작은 외부 송신량, 시작 boost·제어 요청 등의 여유를 포함해 **정상 21회와 빌드1회에 약 US$0.4~1를 잠정 견적**으로 잡는다. 이는 실제 시간·이미지 크기·로그량·재시도가 가정 내일 때의 규모이며 확정 청구액이나 최대치가 아니다.

서울 Storage는 일반 Always Free 지역에 포함되지 않는다. Cloud Run 무료량도 청구 계정의 다른 사용과 공유한다. “현재 최소 설정이라 추가 요금 없음”으로 판단하지 않는다. 버킷 soft delete는 7일이므로 추후 승인받아 삭제하더라도 보관 과금이 즉시 모두 끝나지 않는다. 삭제·정리 정책 변경은 이 실행안에 포함하지 않는다.

기존 **최대45회(준비 포함)·실험창2시간·실험 인스턴스 총3개·작업 누적 추정 US$10 중단**은 유지한다. 이번 제안은 그중 전송21회만 구체화하며 남은 횟수를 자동 사용하지 않는다. 비용 집계는 새 네트워크 비교 작업의 빌드/저장/실행/전송/로그를 포함하고, 무료 차감 전 추정치를 사용한다. 청구 지연 때문에 정확한 결제 상한 보장은 아니다.

## 7. 추천 순서와 완료 기준

1. **로컬 구현 범위 확정:** 네 구조20회+smoke1회, 다운로드4·변환1·업로드4를 유지한다. 기존30회/자원자동조절15회 제안과 동시 실행하지 않는다. 원격 실행은 별도 확인한다.
2. **최소 로컬 구현:** version2 계약·실행 매핑·유한 실행/비용 집계·4후보 결과 집계만 연결한다. 기존 필수 `verification/lookbook-import.json`, `verification/lookbook-remote.json` 게이트를 새 코드 상태로 실행하고 누락 검사 ID를 연결한다. 이전 통과 결과를 새 코드 통과로 재사용하지 않는다.
3. **배포 직전 실행 manifest:** 후보 리비전/tag·이미지 digest·Linux/amd64 무결성·OIDC 권한·리비전 min/max·실제 cgroup 가시성·실험 모드의 일반 route 차단·회차 순서·timeout·비용 중단 경로를 확인한다. 이 정보가 갖춰진 배포/유료 실행안 확인 후 배포한다.
4. **URL 사전 확인 → smoke1회 → 본20회:** smoke에서 메모리 표본과 실제 저장 검증까지 확인되면 고정 행렬을 시작한다. 완료/실패/미수행을 모두 보존하고 독립 재집계한다.
5. **단계별 동시성 조정:** 실측 병목에 근거해 다음 소규모 행렬을 정한다. 변환 제한 해제도 비교 후보에 남기되 다운로드/업로드 제한과 투입 이미지 수를 함께 명시한다.

미확인 사항은 새 리비전의 Cloud Run 계측 호환성, Linux/amd64 golden 출력, 지정 호출자 인증 가능 여부, 현재 원본 변화, 실제 소요 시간·비용이다. 현재 문서 단계에서 그 값을 임의 확정하거나 통과로 표시하지 않는다. 제품 분산 큐 선택과 운영 반영은 위 결과 이후다.

문서 검증(2026-10-04): fixture SHA-256, 원본 후보/중복 제거 bytes, golden outputs 개별 항목 합계, 21회 산술, 로컬 증거 링크, 공백 검사 통과. 추적 중인 ENTRYPOINTS/LOOKBOOK 문서의 git diff --check도 통과했다. 이번 문서 작업에서 애플리케이션 코드·테스트·배포를 변경하거나 런타임 게이트/네트워크 실험을 실행하지 않았다.
