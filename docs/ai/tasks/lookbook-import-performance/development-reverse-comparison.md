# Development 역순 재확인 — 승인 범위와 구현 계획

**후속 제품 결정(2026-10-05):** 사용자는 뒤 요청의 대기를 수용하고 요청 순서·단순성을 우선해 [브랜드 요청 FIFO·내부 시즌 병렬](phase-4-brand-dispatch-design.md)을 확정했다. 아래 성능 결과와 당시 권고는 보존한다. FIFO 채택은 큰 처리량 개선 판정이 아니며 다음은 제품 연결의 세부 설계다. 제품 구현·추가 실험·운영 배포를 완료했다고 의미하지 않는다.

2026-10-04. 사용자는 이전 약식 결과의 추천 후속을 승인하고, 준비 포함 총3회(준비 PP 단일 시즌 → SP → PP)를 확정했다. 본 비교는 같은 UNAFFECTED 연도별 합성3브랜드×2시즌이다. 이번 승인에는 이 계약의 로컬 구현·필수 검사와 격리 Development 배포·3회 실행이 포함된다. 추가 보충 실행·운영 반영·삭제는 포함하지 않는다.

## 고정 조건과 완료 기준

- 기존1CPU/2GiB/min0/max1/기본트래픽0, HTTP 요청은 실험당1개씩 순차 실행한다. 다운로드4·변환1·업로드4·재사용128MiB·입력/golden/변환 구현을 유지한다.
- 준비1회 → SP1회 → PP1회만 허용하는 version4 계약이다. 기존 version3/5회 증거와 배포 이미지는 보존한다. 이전 캠페인의 순서 카운터나 완료 데이터를 수정해서 재실행하지 않는다.
- 메모리85% 1초·표본500ms·회차840초·전체2시간·추정US$10 중단, 실패/종료 미확인 후 자동 보충 금지는 유지한다.
- 각 구조는 이번에도1회 관측이다. 이전 PP→SP 쌍과 새 SP→PP 쌍을 별도로 표시한다. revision·실행 시점 차이 및 cold/warm 영향이 있어 합쳐서 통계적 우월성/실패율 개선/제품 자동 채택을 선언하지 않는다.
- 전체·첫 시즌·첫 브랜드 완료, 메모리 최대/중단·표본 간격, CPU/단계 시간, 전송량·저장 검증·비용을 보존한다. 같은 인스턴스 사용 여부를 확인하되 강제 동일성을 주장하지 않는다.

## 단계·변경 파일·검사

1. 계약·집계: `remote-contract.ts`, `remote-campaign{,-cli}.ts`, `remote-fixture.ts`, `remote-runner.ts`, `remote-report.ts`의 version/고정 순서·비교 대상을 수정한다. 시즌 실행·이미지 변환·Storage adapter·제품 큐·iOS DI/Coordinator/API는 변경하지 않는다.
2. 회귀 검증: `remote-v2.test.ts`, `remote.test.ts`, `remote-campaign.test.ts`, `scripts/remote.emulator.mjs`와 필수 게이트 ID를 갱신한다. 정확한3회·SP→PP 순서·구계약/PS/SS/초과 요청 거절·중복/경합/실패 중단·단일 관측 집계·요청량을 fake 및 emulator로 검사한다. 기존 네 구조의 시즌 스케줄러 단위 검사는 유지한다.
3. Mac/AMD64 Worker 필수 게이트와 emulator를 실행하고 새 이미지·소스 지문을 기록한다. 동작 변경 없는 앱 수동 QA는 추가하지 않는다. 배포 전 image/digest/인코더와 실제 target 자원·트래픽을 대조한다.
4. 새 캠페인·격리 revision으로 승인3회만 실행한다. 준비 검사가 실패하면 본 비교를 시작하지 않는다. 원본 재검사·이전 결과와 나란히 분석·문서 최신화까지 완료한다.

## 요청량과 비용 예상

이전 준비·SP·PP 실측 합산 기준 정상 원본 GET307회/228,156,743B, JPEG 업로드와 재검증 GET 각각610회/86,872,844B, 계측 이미지 Firestore597읽기/610쓰기다. 정상 claim/finish18읽기/18쓰기 및 result JSON3쓰기/3읽기가 추가된다. 재시도/SDK 내부 요청을 포함한 청구 상한은 아니다.

이전 서버 처리 합계249.048초(약4분9초), 동일 모델 실행비 약US$0.0196+외부 비용 여유US$0.30=약US$0.32다. 새 build/push·보관·로그·startup 등은 여유 추정이며 실제 청구액 보장이 아니다. 실측 후 journal 값으로 갱신한다.

## 구현과 검증 진행

version4·준비→SP→PP 계약과 단일 관측 집계를 구현했다. 집계는 PP/SP만 계획 대상으로 표시하며 PS/SS를 누락 실행으로 표시하지 않는다. `adaptive-controller.test.ts`의 원격 계획 기대값도 현재3회로 갱신했으며, 가변 제어 구현과 네 구조 스케줄러 검사는 변경하지 않았다.

- Mac 최종 필수 게이트 [passed](../../../../output/verification/1791120432037-48bca4dd-a022-4010-a8b9-44bdad9e6899/summary.json).
- 최종 emulator 실행권/경합/중복/순서/접근 격리5개 [passed](../../../../output/verification/1791120512916-0945ed25-8468-49e5-bba2-253496b5b473/summary.json).
- 최종 컴파일/package 이미지 대조·AMD64 인코더·계약 [passed](../../../../output/verification/1791120510826-9abeb632-44f8-47af-bdb7-4b67851c9dcb/summary.json).
- Linux 전체307개·필수199개·fixture [passed](../../../../output/verification/1791120466344-41be3999-1709-4b9f-835c-f9ad584270c0/summary.json). Mac도307개·필수199개이며 lint는 양쪽0오류/70경고다.

배포 전 최종 source digest는 `95480287649a3a66bdb707d7de8293a505987986da1be2a5abfd18063de17450`(193파일, HEAD `1d67d61faa04984783083971688a7c628df74748`+작업 트리)이며 실행 직전 재계산해 일치 확인했다. Linux 게이트의 입력 범위가 달라 digest는 `b44849f36dd0290253d1e0b060ea1fbe5ea8055cc228ea1294528f6c18df6183`이다.

최종 OCI index `sha256:3427852c6eff6191465e1c4c3295c3cf011813520939b212b9e03c0660dec8cd`를 push하고 `lookbook-import-worker-development-reverse3-20261004` revision/tag `rv3-261004`에 배포했다. 기본트래픽0/기존100%·IAM·서비스 max 유지, 후보1CPU/2GiB/min0/max1·concurrency2/timeout900초를 [대상 게이트](../../../../output/verification/1791121079783-82fad35f-af1f-4d75-8675-6453878cc94b/summary.json)로 확인했다. Cloud Run이 선택한 AMD64 manifest는 [execution.json](../../../../output/lookbook-import-performance/reverse-three/execution.json)에 고정했고 OCI index→단일 AMD64 manifest→실제 revision을 대조했다.

실행 campaign `reverse3-20261004-011b1b09`, plan digest `de594c68aec810b1ee0957ccac639941806b9a4e197bf1479e6ecca922984ad2`. 승인3회 모두 완료·성공했다. 결과·원본·배포 로그는 [reverse-three](../../../../output/lookbook-import-performance/reverse-three/)에 보존한다. 실제 AMD64 manifest는 `sha256:7fb5e894e828a5c58a6da3ff80fcdcea64c433f1a85591670ea6367b99e0446b`다.

## 실제 실행 결과

[3회 실행 게이트](../../../../output/verification/1791121093360-4f87c949-95cf-4f49-88f5-6dd49c82c50a/summary.json), [원본 재검사·두 쌍 분석 게이트](../../../../output/verification/1791121406197-f2e05800-94d7-4133-9df7-533067212a23/summary.json) 모두 passed. JPEG golden·업로드 재조회·경로·슬롯·원본 보관 정리까지 통과했다. 실패/명시적 재시도/중단/종료 미확인0, 준비를 비교에서 제외했다. 새3회 모두 동일 instance `606cb7e3-a2d9-41c7-a1c6-794c7ce508fc`였고 이전5회와는 다른 instance다.

| 비교 쌍·실행 순서 | 구조 | 전체 처리(초) | 첫 시즌(초) | 첫 브랜드(초) | 메모리 최대 |
|---|---|---:|---:|---:|---:|
| 이전 PP→SP | PP | 103.832 | 39.508 | 44.763 | 75.48% |
| 이전 PP→SP | SP | 100.355 | 34.827 | 40.034 | 86.69% |
| 이번 SP→PP | SP | 104.205 | 37.198 | 42.428 | 75.40% |
| 이번 SP→PP | PP | 104.843 | 38.723 | 44.306 | 80.85% |

준비 PP 단일 시즌은6.517초·메모리13.72%였다. 이번 본 비교 CPU 시간 SP106.27초/PP106.99초, 변환 누적99.059초/99.608초, 최대 표본 간격262.390ms/272.305ms였다. 원본 재사용은 두 본 회차 각각hit131/miss0/rejected0, 종료 보관량0이며 peak는 SP53,579,032B/PP111,028,402B였다.

### 해석과 추천

- SP 전체 처리 개선은 이전3.35%, 이번0.61%다. 이 자원·입력에서 브랜드 순차화로 전체 처리10% 이상 개선한다는 근거는 확보하지 못했다.
- 첫 브랜드는 두 쌍 모두 SP가 먼저 끝났지만 개선 폭은10.57%→4.24%로 달랐다. 먼저 등록한 브랜드를 우선 완료한다는 사용자 흐름의 장점 후보이며, 안정적인10% 성능 개선으로 보지 않는다.
- 이전 SP86.69% 순간 메모리는 이번75.40%로 재현되지 않았다. 각 쌍의 두 번째 본 회차가 더 높은 최대 메모리를 보였으므로 순서/allocator 잔류 영향 가능성이 있다(추측). 원인을 분리하는 실험은 아니므로 인과 결론은 유보한다.
- 변환 동시성1에서 약99초 변환 누적·약107CPU초가 전체 처리 약104초와 가까워 이번에도 CPU/변환 비중이 큰 것으로 해석한다. 다운로드·업로드 제한 증량 효과는 검사하지 않았다.
- **추천: 이번 유료 비교를 종료하고, 성능만을 이유로 제품 전체의 브랜드 순차 대기열을 추가하지 않는다.** 기존 제품 흐름을 유지한다. 브랜드 순차는 ‘먼저 등록한 브랜드 우선 완료’를 제품 요구사항으로 선택할 경우 검토할 수 있지만 이번 결과를 큰 처리량 개선의 근거로 사용하지 않는다.
- 각 구조 총2회이며 서로 다른 시점/revision이다. 중앙값10%·5쌍 반복 악화·실패율 개선·통계적 유의성·자동 채택은 미판정이다. 승인 범위 밖 추가 실행·제품 코드 반영·데이터 정리는 하지 않았다.

### 실측 요청량과 비용

원본 GET307회/228,156,743B, JPEG 업로드·검증 GET 각각610회/86,872,844B, 이미지 흐름 Firestore597읽기/610쓰기다. 정상 claim/finish 포함 논리 합계615읽기/628쓰기이며 실제 SDK/청구 내부 요청 수를 의미하지 않는다. result JSON3개 총1,064,763B·저장3회/로컬 읽기3회로 Storage 정상 논리 합계는613쓰기/613읽기다.

서버 준비·처리·검증 합계249.586초(약4분10초), journal 추정 **US$0.3197778188**(외부 비용 여유US$0.30 포함)다. 실제 청구액·무료 여부·결제 상한은 확인하지 않았으며 그렇게 주장하지 않는다. 이미지·revision·실험 데이터는 보존한다. 일반 Development 배포 시 실험 환경변수 제거 여부를 확인해야 한다.

원본: [analysis.json](../../../../output/lookbook-import-performance/reverse-three/analysis.json), [정순/역순 개별 쌍 분석](../../../../output/lookbook-import-performance/reverse-three/paired-analysis.json), [campaign 원본3개·journal](../../../../output/lookbook-import-performance/reverse-three/campaign/). 기존5회 원본을 덮어쓰거나 version4 검사 통과로 다시 표시하지 않았다.

종료 후 `service-final.json`에서 기존 모든 traffic 항목 보존을 대조했고, `request-logs.json`의 새 revision 요청은 정확히3개·모두HTTP200이었다. `git diff --check`도 통과했다. 이번 변경은 실험 계약/집계/관련 테스트/게이트/진입점 문서에 한정되며 제품 큐·앱·Functions·보안 규칙을 변경하지 않았다.

초기 실패 기록: [첫 Mac 검사](../../../../output/verification/1791120072549-3ab99950-f723-4e58-b257-3b23df1a1f73/summary.json)는 줄 길이2건·AP08 구계약5회 기대값·sandbox 로컬 포트 EPERM으로 실패했다. [두 번째 Mac](../../../../output/verification/1791120226042-cc85afa2-7a49-4955-9ad4-638a16c6cba1/summary.json)은 AP08 후보 목록의 구계약 기대값과 들여쓰기로 실패했다. [초기 Linux](../../../../output/verification/1791120265739-c2d1d9e1-1e42-4bc9-8719-07f5ef89c871/summary.json)는 동일 오류 확인 후 에이전트가 SIGTERM으로 중단했고 수정이 겹쳐 입력 변경도 기록됐다. 게이트의 일반 ‘사용자 취소’ 분류는 이 중단이며 성공으로 계산하지 않는다. 승인된 새 계약에 맞춰 테스트 기대값·서식만 수정한 뒤 최종 코드/이미지로 전체 검사를 재실행했다. 성능·메모리·정확성 합격 기준은 완화하지 않았다.
