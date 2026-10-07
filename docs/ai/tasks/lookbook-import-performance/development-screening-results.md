# Development 약식5회 실제 실행 기록

후속 완료: [준비→SP→PP 역순3회 결과](development-reverse-comparison.md). 아래 첫5회 결과는 보존하며 후속 결과를 반영한 최종 추천은 해당 문서를 따른다.

2026-10-04. 사용자가 [배포·실행안](development-screening-execution.md)에 동의하고 실제 진행을 승인했다. 같은 이미지·5회·자원·중단 기준으로 진행하며, 추가 회차/데이터 삭제/운영 배포는 포함하지 않는다.

## 배포 준비와 변경

- 배포 직전 코드 지문은 Mac 필수 게이트의 `c68068fc5e5feef261398bc165255017088ea10ec88873f2e249dd17c073b212`(193파일), HEAD `1d67d61faa04984783083971688a7c628df74748`와 일치했다. compiled/package284개도 검증 이미지와 일치했다.
- Artifact Registry push 성공. 원격 digest는 로컬 검증 이미지와 같은 `sha256:7e97ef277b2e19c09c99baf6afa767c322daa552c3747001f7cfe81f7ae5fb05`다. Cloud Build는 사용하지 않았다.
- 최초 배포는 `screen5-20261004` 태그와 서비스 이름의 합계가 Cloud Run의46자 제한을 넘어서 거절됐다. 거절 뒤 서비스 spec·기존트래픽이 같고 후보 revision이 생성되지 않았음을 확인했다. 짧은 tag `sc5-261004`로 정정했다. revision 이름·image·실험 범위·자원은 변경하지 않았다.
- 실행 URL은 `https://sc5-261004---lookbook-import-worker-development-xyenspjiwa-du.a.run.app`, revision은 `lookbook-import-worker-development-screen5-20261004`다.
- campaignID `screen5-20261004-2bede186`, 만료2026-10-04T14:24:17.878Z, 회차840초/전체2시간, version3/5회. `externalCostUSD=0.30`은 합의한 추정 여유이며 실제 청구액이 아니다.

증거: [실행 폴더](../../../../output/lookbook-import-performance/screening-live/), [최종 manifest](../../../../output/lookbook-import-performance/screening-live/execution.json), `source-identity.json`, `push.log`, `remote-image.json`, `deploy.log`(최초 거절), `service-after-rejected-deploy.json`, `revisions-after-rejected-deploy.json`, `deploy-corrected-tag.log`.

## 진행 상태

격리 revision 배포와 준비1회·본4회가 모두 완료됐다. 기본트래픽0/min0/max1,1CPU/2GiB·요청동시성2·timeout900초, 기존트래픽/IAM 유지 확인 [대상 게이트 통과](../../../../output/verification/1791116976432-0a0455d6-d1c4-42da-af8a-efec6dc38229/summary.json). [실제5회 캠페인 게이트](../../../../output/verification/1791117019990-7cf02937-6ceb-4d6d-8648-9856dce9c9f5/summary.json)와 [원본 재검사·분석 게이트](../../../../output/verification/1791117574565-1c5fb8ed-fdc5-4418-8173-d6fb5ae5e7f6/summary.json)도 통과했다. 종료 후 `service-final.json`에서 기존 revision의 기본트래픽100%와 기존 태그 보존을 확인했다. `request-logs.json`에는 실험 요청5개가 모두 HTTP200으로 기록됐다.

## 실측 결과와 해석

다운로드4·변환1·업로드4·재사용128MiB를 고정했다. 본 비교는 연도별 합성3브랜드×2시즌이며 본문131개+커버6개를 처리했다. 시간은 준비·사후 검증을 제외한 이미지 처리 구간이다. 첫 시즌은 첫 선택 시즌, 첫 브랜드는 첫 등록 브랜드의 완료 시간이다.

| 구조 | 전체 처리(초) | 첫 시즌(초) | 첫 브랜드(초) | 메모리 최대 |
|---|---:|---:|---:|---:|
| PP: 브랜드 병렬·시즌 병렬 | 103.832 | 39.508 | 44.763 | 75.48% |
| SP: 브랜드 순차·시즌 병렬 | 100.355 | 34.827 | 40.034 | 86.69% |
| PS: 브랜드 병렬·시즌 순차 | 101.916 | 35.561 | 41.344 | 73.56% |
| SS: 브랜드 순차·시즌 순차 | 102.519 | 34.605 | 40.201 | 76.69% |

- 준비 단일 시즌 PP는6.283초, 메모리 최대11.62%였다. 전체5회에서 JPEG golden·저장 경로·업로드·정리 검사가 통과했고 명시적 재시도/실패/중단은0이다. 실패율 개선을 입증한 결과는 아니다.
- PP 대비 SP 전체 시간은3.35%, 첫 브랜드는10.57% 짧았다. SS는 전체1.27%, 첫 브랜드10.19% 짧았다. 전체 완료10% 개선 조건에는 도달하지 않았다. 단일 관측이므로 중앙값/반복 악화/자동 채택 판정은 하지 않는다.
- SP의86.69%는 순간 최대치다. 합의한85% 1초 지속 중단 조건에는 도달하지 않았다. 최대 표본 간격291.424ms로500ms 기준 이내였다. 기준을 완화하지 않았다.
- 본 비교의 변환 누적 시간은95.0~98.6초, 프로세스 CPU 시간은101.8~105.8초였다. 변환 동시성은1이다. 이 입력·자원에서는 변환/CPU 비중이 큰 것으로 해석할 수 있다. 다운로드·업로드 제한을 높이는 효과나 다른 변환 동시성은 이번에 검증하지 않았다. 단계별 누적 시간은 서로 겹치므로 더해서 전체 시간을 계산하면 안 된다.
- 5회 모두 같은 instanceID `c581b416-4651-4335-9128-25165f703e3b`에서 준비→PP→SP→PS→SS 순서로 실행됐다. 회차별 시작 native allocator 메모리를 별도 분리하지 않았으므로 최대 메모리 차이를 구조의 인과 효과로 단정할 수 없다. 캐시/워밍·순서 영향도 남는다.
- 본 비교 재사용 hit131/miss0/rejected0. 재사용 보관 최대치는 PP111,028,402B/SP53,579,032B/PS80,035,201B/SS51,079,588B이며 종료 시 모두0이다. 보관량 감소가 프로세스 전체 메모리 감소를 보장하지는 않는다.

추천 후속은 제품 구조 확정에 앞서 PP/SP를 역순으로 소수 재확인해 첫 브랜드 이득과 SP 메모리 순간 상승이 반복되는지 보는 것이다. SS도 첫 브랜드 결과가 비슷한 후보로 남긴다. 이는 추가 실행 제안이며 이번에 추가 회차를 실행하지 않았다.

## 실제 요청량·비용 추정·남은 자원

- 원 사이트 이미지 GET583회, 수신453,700,111B.
- JPEG 업로드1,158회·171,392,080B, 업로드 결과 검증 GET1,158회·같은 bytes.
- 이미지 흐름의 계측 Firestore 읽기1,133회/쓰기1,158회. 정상 claim/finish30읽기+30쓰기를 더한 논리 요청은1,163읽기/1,188쓰기다. SDK/transaction 내부 요청까지 실제 청구 건수와 같다는 뜻은 아니다.
- 결과 JSON5개 총2,025,425B, 저장5회·로컬 수집5회. 정상 Storage 논리 합계는 읽기/쓰기 각각1,163회다.
- 서버 측 준비·처리·검증 합계486.160초(약8분6초). 배포/startup 및 로컬 인증·결과 수집의 전체 경과시간과는 다르다.
- journal 누적 비용 모델은 **US$0.3373102051**이며 외부 비용 여유US$0.30을 포함한다. 실제 Google 청구액이 아니다. 모델은 결과 JSON 회차당 최대8MiB와30일 저장을 가정하며 registry/log/startup/control 비용은 여유분으로 다룬다. 무료 또는 정확한 결제 상한을 보장하지 않는다.
- 실험 데이터·이미지·revision은 보존했다. 삭제/운영 배포/제품 구조 자동 채택은 하지 않았다. 후보 revision max1이며 서비스 전체 max5/기존 revision max20 설정은 유지됐다. 전체 프로젝트가1인스턴스로 제한됐다는 뜻은 아니다.
- 이후 일반 Development 배포에서는 실험 전용 `OUTPICK_IMPORT_REMOTE_CAMPAIGN` 환경변수를 제거하는지 확인해야 한다. 이번 실행 후 임의 배포/설정 변경은 하지 않았다.

수치 원본: [analysis.json](../../../../output/lookbook-import-performance/screening-live/analysis.json), [campaign journal·5회 JSON](../../../../output/lookbook-import-performance/screening-live/campaign/). 검사 구성과 실행기는 같은 실행 폴더의 `analysis-gate.json`/`analyze.mjs`, 배포 전후 설정과 HTTP 로그도 보존했다.

## 준비 중 실패와 정정 이력

Cloud Run은 업로드한 OCI index `7e97ef…`에서 linux/amd64 manifest `sha256:eb99d730e69ee7e48dfebd097dc48374903da37b52118fffd94aaa9fa9eb934f`를 선택했다. 최초 대상 검사는 index와 실제 플랫폼 digest를 같은 값으로 예상해 [실패](../../../../output/verification/1791116835324-cdc1dd2b-0b6c-4b01-96ed-74f7d8505407/summary.json)했다. 고정 index의 원격 manifest 조회로 AMD64항목이 하나이며 Cloud Run digest와 같음을 확인했고, raw manifest SHA도 정확히 대조했다. 최종 execution.json은 실제 AMD64 digest를 사용한다. 이미지/Worker 코드/검사 함수의 엄격 일치 조건은 변경하지 않았다.

대조 보조 스크립트의 다음 시도에서는 Docker의 `Id`를 config digest로 잘못 가정해 [실패](../../../../output/verification/1791116950678-3942adc6-818e-4e58-a6d3-06cbcd215c70/summary.json)했다. 실제 inspect가 OCI index descriptor를 반환하므로 index→AMD64 manifest→Cloud Run의 관계로 정확히 비교하도록 수정했다. `image-index-verbose.json`, `local-image-inspect.json`과 최종 대상 게이트에 증거를 보존한다. `buildx --raw` 조회가 임시 Docker config에서 지원되지 않아 Docker 기본 `manifest inspect --verbose`를 사용했다. 이 조회 과정에서 이미지 변경/재배포/실험 요청은 없었다.

실제 캠페인 첫 시작 명령은 PATH에서 Node24보다 Homebrew Node가 먼저 선택돼 [환경 검사에서 차단](../../../../output/verification/1791117006688-8d9a6519-408d-43f1-960c-24077187e1b3/summary.json)됐다. 이 시점의 Worker 실험 요청은0이다. Node24 경로를 우선한 뒤 캠페인 게이트를 실행했고, 결과 원본과 journal은 [campaign 폴더](../../../../output/lookbook-import-performance/screening-live/campaign/)에 보존한다.
