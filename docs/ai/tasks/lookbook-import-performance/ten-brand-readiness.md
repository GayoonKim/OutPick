# A~J Development 배포 전 최종 확인·분석

**후속 실행 결과:** [2026-10-05 실측·T2 중단·남은 U8](ten-brand-results.md). 아래는 배포 전 확인 당시 기록이다.

2026-10-05. 이번 요청은 배포 대상·입력·비용 확인과 분석이다. 읽기 전용 사전 확인을 완료했고 기존 8회 범위를 변경할 사유는 발견하지 못했다. 이미지 push·배포·Worker 실험 호출·Firestore 쓰기는 이번에 하지 않았다. 새 revision에서의 실측 검증 완료를 뜻하지 않는다.

## 1. 배포 대상과 격리

| 항목 | 확인값·실행안 |
|---|---|
| 프로젝트 / 리전 | `outpick-test` / `asia-northeast3` |
| 서비스 | `lookbook-import-worker-development` |
| 기본 트래픽 | 현재 `lookbook-import-worker-development-00012-fih` 100% |
| 새 revision 후보 | `lookbook-import-worker-development-aj8-261005` |
| 새 tag 후보 | `aj8-261005`, 기존 revision·서비스 tag·registry tag 충돌 없음 |
| 실험 자원 | 1CPU / 2GiB / min0 / revision max1 / HTTP concurrency2 / timeout900초 |
| 실제 제출 | 한 번에 Worker HTTP 요청 1개, 새 tag만 호출, 새 revision 기본 트래픽0% |
| Storage / Firestore | `outpick-test.firebasestorage.app` / `(default)`, 둘 다 서울 |
| 실행 서비스 계정 | `outpick-lookbook-worker-dev@outpick-test.iam.gserviceaccount.com` |
| OIDC 호출 계정 | 기존 compute 서비스 계정, 기존 invoker/OpenIdTokenCreator 권한 사용 |

현재 서비스 전체 maxScale은 **5**다. 이번 revision만 max1로 설정하는 것이며 다른 Development revision의 실행·비용까지 제한하지 않는다. 현재 기본 revision도 1CPU/2GiB지만 새 revision의 실제 자원·환경·traffic·digest는 배포 후 `remote-target.ts::assertRemoteTarget`으로 검사해야 한다. 기존 기본 트래픽·IAM은 변경 범위에 없다.

기존 OIDC 발급과 audience/email/유효기간 확인 통과. 토큰은 파일이나 로그에 저장하지 않았다. 새 revision HTTP 호출 검증은 아직 하지 않았다. 실험 제어 문서 `lookbookImportPerformanceControl/active` 1건을 읽어 `activeRun=null`을 확인했다. 실행 직전 다시 확인하며 자동 해제/인계하지 않는다.

배포할 로컬 runtime 이미지 ID는 `sha256:dfc4f4793b49e0081db1ed22b271446d78eaec3dda212d50ca151cb3472eb723`이다. registry 후보 경로는 `asia-northeast3-docker.pkg.dev/outpick-test/cloud-run-source-deploy/lookbook-import-worker-development:aj8-261005`. **push 후 실제 AMD64 manifest digest는 아직 미확정**이다. 로컬 이미지 ID를 원격 배포 digest로 대신 쓰지 않는다. 새 이미지 빌드 대신 검증한 로컬 이미지를 올리는 계획으로 Cloud Build 실행은 없다.

## 2. 입력과 최소 8회

[확정 실행안](ten-brand-execution-proposal.md)의 A8/B2/C~J각1, 총18시즌과100ms 간격(A0~J900ms)을 유지한다. UNAFFECTED 2026FW/2026SS/2025FW/2025SS/2024FW/2024SS를 순환 배정해 각 원본을3번씩 사용한다. 가상 브랜드/시즌 ID·저장 경로·재사용 범위는 분리한다.

2026-10-05 13:18 KST에 원 사이트 HTML7개와 후보132개+커버6개를 Mac에서 직접 읽었다. **URL·후보 순서·커버·이미지138개의 바이트 수/SHA가 고정 입력과 일치**했다. 총112,771,684B를 받았다. 시즌별 후보 수는24/30/14/17/22/25이며2025SS의 중복1개를 제외한 본문 고유 이미지는131개다.

시즌 HTML 해시는 달라졌지만 추출 입력은 일치했다. 추출 품질은6시즌 모두 `needsReview/expected_count_unverified`다. 고정한 성능 실험 자산의 검증이며 제품 자동등록 검토를 통과시킨 것이 아니다. 실제 실행도 이미지 다운로드→변환→Storage→Firestore를 비교하며, iOS10개 요청/분산 Functions 대기열을 재현하는 시험은 아니다.

| 회차 | 브랜드 처리 | Worker 합산 시즌 한도 | 다운로드/변환/업로드 |
|---|---|---|---|
| smoke | 기존2026SS 단일 | 6 | 4/1/4 |
| S6 | 순차 | 6 | 4/1/4 |
| Sall | 순차 | 해제 | 4/1/4 |
| P6 | 병렬 | 6 | 4/1/4 |
| Pall | 병렬 | 해제 | 4/1/4 |
| D8 | 순차 | 6 | 8/1/4 |
| T2 | 순차 | 6 | 4/2/4 |
| U8 | 순차 | 6 | 4/1/8 |

128MiB 재사용·시즌별 이미지4개 빈자리 보충·경로 저장 제한 없음은 공통이다. 제한 해제의 실제 범위는 순차에서 현재 브랜드 최대8시즌, 병렬에서 도착한 전체 최대18시즌이다. 모든 요청은 한 실험 Worker 안에서 예정 시각에 도착한다. 미도착 브랜드는 다운로드를 시작하지 않는다.

각 설정1관측이므로 후보 선별과 동작 확인에 사용한다. S6 대비 전체/첫 브랜드/각 브랜드 접수 후 대기·완료 시간, 단계별 실제 최고 동시성·대기, 메모리/CPU/전송량/재시도/중단을 함께 분석한다. 낮은 부하로8슬롯을 채우지 못하면 한도8이 효과 없다고 단정하지 않는다. 순서·워밍·공통 원본 사이트의 캐시 영향을 기록하고 최적값·실패율 개선·10% 채택 기준 충족을 선언하지 않는다. 자동 추가 회차는 없다.

## 3. 요청량과 비용

재시도 없는 준비1+18시즌7회의 고정 입력 산술이다. 재사용 all-hit이면 원본 GET2,929회/2,370,818,739B(약2.37GB), 전부 miss이면 GET5,710회다. 이미지 내부·시즌 재시도와 SDK 호출은 더 늘릴 수 있으므로 최대 청구량은 아니다.

| 항목 | 산술 |
|---|---:|
| 썸네일·상세 JPEG 업로드 | 5,816객체 / 889,805,586B(약0.890GB) |
| 저장 이미지 검증 읽기 | 5,816객체 / 같은 바이트 수 |
| 결과 JSON | 8회 쓰기+8회 로컬 읽기, 최대 합계64MiB 가정 |
| Storage 쓰기/읽기 합계 | 각각5,824회 |
| Firestore 정상 논리 읽기 | 5,737회(이미지5,689+실행권48) |
| Firestore 비용 모델 읽기 | 5,929회(제어/재확인 여유 포함) |
| Firestore 쓰기 | 5,864회(이미지5,816+실행권48) |

2026-10-05 공식 가격 HTML에서 **서울 단가**를 추출했다. 무료 사용량·크레딧·약정 할인은 차감하지 않는다. 계정에 남은 무료량과 실제 청구액은 이번에 확인하지 않았으므로 추가 요금0원을 보장하지 않는다.

- [Cloud Run](https://cloud.google.com/run/pricing): 요청 기반 활성 CPU $0.0000336/vCPU초, 메모리 $0.0000035/GiB초. 1CPU/2GiB 합계 $0.0000406/초. 요청 $0.40/백만회.
- [Storage](https://cloud.google.com/storage/pricing): 서울 Standard $0.000031507/GiB시간, 쓰기 ClassA $0.005/천회, 읽기 ClassB $0.0004/천회. 기존 `REGIONAL` 버킷에 해당하는 일반 저장 비용으로 계산한다. 같은 서울 리전의 Worker↔Storage 전송은 무료지만 읽기·쓰기 작업과 보관 비용은 발생한다. 원본 다운로드를 인터넷 송신량으로 계산하지 않는다. 결과 JSON의 Mac 수집은 아시아 첫 구간 $0.12/GiB로 별도 포함한다.
- [Firestore](https://cloud.google.com/firestore/pricing): 서울 읽기 $0.038/10만건, 쓰기 $0.115/10만건. 문서·인덱스 저장은 기타 비용 여유에 포함한다.
- [Artifact Registry](https://cloud.google.com/artifact-registry/pricing): $0.000136986/GiB시간. 새 이미지1GiB·30일을 약$0.10으로 잡았다. 같은 리전 pull 전송은 무료, 현재 자동 취약점 스캔은 비활성이다.
- [Logging](https://cloud.google.com/products/observability/pricing): 로그 수집 $0.50/GiB,100MiB를 약$0.05로 잡았다. Registry/로그 합계 약$0.15와 시작 CPU boost·제어 요청·기타 통신/문서 보관 여유 약$0.15를 묶어 `externalCostUSD=0.30`으로 유지한다. 이는 실측 상한이 아닌 계획용 여유다.

| 비용 구성 | 8회 합계 추정 USD |
|---|---:|
| Storage 쓰기+검증 읽기 | 0.03145 |
| Firestore 읽기+쓰기 | 0.00900 |
| 이미지·결과 JSON 30일 보관 | 0.02022 |
| 결과 JSON 외부 수집 | 0.00750 |
| Cloud Run 요청8회 | 0.0000032 |
| Registry·로그·시작·기타 여유 | 0.30000 |

| 총 Worker 활성 시간 시나리오 | Worker CPU·메모리 | 위 항목 포함 합계 |
|---|---:|---:|
| 30분 | $0.07308 | **$0.44125** |
| 60분 | $0.14616 | **$0.51433** |
| 120분 | $0.29232 | **$0.66049** |

따라서 **기존 계획 범위 약US$0.5~1을 유지**한다. 위 시간은 시나리오이지 소요시간 예측이 아니다. 기존41.3분은 이전6시즌 결과를3배 한 단순 추정이므로 확정 소요시간으로 사용하지 않는다. 재시도·로그/이미지 실제 크기·보관 기간·SDK 호출·다른 작업 사용량이 달라지면 청구액도 달라진다. 세금·환율과 기존 프로젝트 비용은 표에 없다. 30일 후 자동 삭제는 없으며 보관이 이어지면 비용도 이어진다. 버킷 soft delete7일은 향후 삭제할 때 별도로 고려한다.

2시간/회차840초/메모리85%1초/표본 간격500ms/누적 추정US$10 중단은 유지한다. US$10은 실행기 추정에 의한 중단 기준이며 결제 하드캡이 아니다. 실패·입력 변동·중단·종료 미확인 시 나머지 회차를 멈추며 자동 보충하지 않는다.

## 4. 검증 증거와 다음 경계

- 원본 입력 확인 게이트: `output/verification/1791173931193-e29ad496-b156-4055-af72-10d3e27ddda9/summary.json`, passed.
- 최종 준비 대조 게이트: `output/verification/1791174322918-bf87f01c-2af7-44d5-be00-f6888f51249e/summary.json`, passed, 실패/차단0. 소스 digest `ae803a0a8c0e121b87e8d95605a2c5f6721d81b3014c17f7a06447e8b826eabd`(159파일), HEAD `1d67d61faa04984783083971688a7c628df74748`+기존 작업 트리.
- 기존 Mac/Linux316개·필수208개/emulator5개/이미지 대조 결과는 [연결 검증 기록](ten-brand-connection-results.md)에 있다. 이번에는 Worker 소스/스크립트/설정 파일 집합과 해시가 검사한 이미지 증거와 그대로 일치함을 확인했다. 전체 테스트를 새로 실행했다고 기록하지 않는다.
- planDigest `9cca98384c439d242a1af55f7ac6d54c2f557cbf7a48dcc41227838ba79aad16`, corpusDigest `49671fbcd756f733e034bc079cc6911fa6ef18184e9e6206f3c1d0d475fa8f15`.
- 원본 증거: `output/lookbook-import-performance/ten-brand-readiness/`. `snapshot.json`과8개 클라우드 응답, `connected-check.json`, `preflight.json`/원본HTML, 공식가격HTML/`seoul-price-tables.json`, `cost-estimate.json`, 비실행 제안 `execution-proposal.json`, `readiness.json`, 검사 스크립트/게이트를 보존했다.

이번 원격 작업은 설정 읽기8종·OIDC 발급1회·Firestore 제어 문서1건 읽기, 원 사이트 HTML7/이미지138개 읽기다. Firebase/Storage 쓰기·Worker 호출·배포·IAM 수정은0이다.

다음은 검증한 이미지 push→새 revision/tag 배포→실제 AMD64 digest/대상/환경/기본 트래픽 대조→입력·실행권 재확인→smoke1회이다. smoke의 계측 호환·golden·저장물·종료 확인을 통과하면 승인된 본 비교7회로 이어간다. 아직 원격 새 revision·실제 네트워크 성능·실제 청구액은 미검증이다. 추가 설계 결정은 현재 발견되지 않았으며 새 차이가 발생하면 그 사안만 논의한다.
