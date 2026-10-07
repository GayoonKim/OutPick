# 룩북 성능 비교 자료 사전 조사

조사일: 2026-10-03. 이 문서는 최초 공개 HTML/HEAD 조사 기록이다. 이후 사용자 지정 UNAFFECTED의 이미지 본문·해시·브라우저 대조까지 진행한 최신 결과는 [입력 확인 결과](tasks/lookbook-import-performance/input-manifest.md)를 따른다. Storage 업로드·Firestore 쓰기·성능 실험은 수행하지 않았다. 아래 최초 정적 후보 수를 최종 추출 수로 사용하지 않는다.

## 확인 방법과 한계

현재 `tools/lookbook-import-worker/src/public-http.ts`의 public HTTP 검사와 `responseBytes`를 거쳐 최대 5MiB·15초로 HTML을 읽고, 현재 소스의 `extractImageCandidates`, `collectExpectedCountEvidence`, `detectProgrammaticGallery`를 호출했다. `node --import tsx`로 소스를 직접 읽었으며 빌드 산출물의 최신성을 가정하지 않았다. 자동 import processor 전체는 실행하지 않았다.

최초 sandbox 요청은 세 호스트 모두 DNS 조회에 실패했다. 승인된 읽기 전용 네트워크 요청으로 다시 확인한 세 HTML은 HTTP 200이었다. 이 차이를 브랜드 서버 장애로 기록하지 않는다. 웹 도구에서 Outstanding/YOUTH를 읽지 못했던 결과 역시 이후 직접 조회 200과 구분한다.

HTTP HEAD는 원격 파일의 선언된 Content-Length를 확인한 것이다. 실제 수신 바이트·해상도·디코딩 메모리·컨텐츠 중복을 검증하지 않는다. 원본 HTML과 이미지 본문은 파일로 보존하지 않았다. 실행 근거는 이 대화의 도구 응답이며 아래에는 비밀 없는 관측값만 옮겼다.

## 공개 URL 결과

| 브랜드 | 페이지 제목 | HTML 바이트 | 전략 | raw 후보 | 정적 선택 후보 | 예상 수 evidence |
| --- | --- | ---: | --- | ---: | ---: | --- |
| Hatchingroom | SUMMER 2026 Part 1. | 209641 | archiveSourceDetail | 22 | 17 | 없음 |
| Outstanding | 아웃스탠딩 | 220479 | mainContent | 113 | 9 | 없음 |
| YOUTH | Spring 26 Lookbook 'One after another' 2nd | 164587 | cafe24ProductAdditional | 3 | 1 | 없음 |

페이지 주소:

- [Hatchingroom](https://hatchingroom.com/product/archive-detail.html?cate_no=226&display_group=1&product_no=3757)
- [Outstanding](https://outstanding-co.kr/lookbook/detail.html?product_no=5151)
- [YOUTH](https://youth-lab.kr/page/collection_detail.html?product_no=6052&cate_no=25&display_group=1)

Outstanding 표본은 `/images/sub-1.jpg`, `/images/sub1-11.jpg`, `/web/popup/renewal_pop_mo.jpg`였다. 정상 시즌 이미지 집합으로 확정할 수 없으므로 성능 본 비교 자료에서 보류한다. 사이트 개편이나 URL 변경 여부는 확실하지 않음이다. 이번 성능 설계 요청을 추출 규칙 수정 승인으로 확대하지 않는다.

YOUTH 정적 후보는 `https://205company.diskn.com/youth/2026/collection/ss26_lookbook_2/001.jpg` 한 개다. 정적 분석에 이미지 생성·source 대입·append·반복 신호는 있지만 declared total evidence가 없어 현재 programmatic-gallery 판정은 false였다. 실제 페이지가 한 장이라는 뜻도, Worker가 반드시 렌더링 fallback을 한다는 뜻도 아니다. 브라우저 결과와 품질 검토 전에는 대량 이미지 성능 자료로 확정하지 않는다.

Hatchingroom도 expected-count evidence가 없으므로 정적 후보 17개를 자동 등록 통과 결과로 취급하지 않는다. 실제 결과 확인 및 기존 review 절차가 필요하다. 검토 대기 시간은 처리 시간과 분리하고, 승인 후 저장 측정과 자동 진행 경로 측정을 혼합하지 않는다.

## 이미지 HEAD 결과

Hatchingroom은 정적 후보 17개 전부 HTTP 200과 Content-Length를 확인했다.

| 항목 | 값 |
| --- | ---: |
| 후보 수 | 17 |
| Content-Length 확인 | 17/17 |
| 합계 | 17820477 bytes, 16.9949 MiB |
| 최소 | 546393 bytes |
| 최대 | 1845507 bytes |
| 평균 | 1048263.35 bytes |

Outstanding 표본 3개의 길이는 556681/353130/162524 bytes였으며 모두 HTTP 200, image/jpeg였다. YOUTH 정적 표본은 HTTP 200, image/jpeg, 1451939 bytes였다. Outstanding 전체 9개와 렌더링 후 후보 전체의 총량은 미확인이다.

Hatchingroom 17개 전체를 여섯 시즌의 동일 분포로 재현한다면 압축된 원격 파일 바이트는 약 102MiB다. 실제 여섯 시즌을 조사한 값이 아니라 실험 입력 복제 시 계산값이다. 메모리에는 디코딩·JPEG 출력·Chromium·SDK 등이 추가되므로 이 값만으로 2GiB의 충분성을 보장하지 않는다.

## 실험 자료 추천

후속 사용자 지정 자료는 [UNAFFECTED 시즌 목록](https://unaffected.co.kr/collection.html?cate_no=88)이다. 아래 추가 조사에 따라 단일 브랜드의 여러 시즌 비교에서는 이 자료를 우선한다. 기존 세 브랜드 URL은 과거 조사 기록이며 최종 입력으로 고정한 것이 아니다.

정적 추출 자료는 Hatchingroom을 우선 후보로 두고, 실제 이미지 내용·중복·해상도를 확인한 뒤 고정한다. Outstanding은 자료 교체 또는 현재 URL 확인까지 보류한다. YOUTH는 동적 페이지 확인 후보로 유지한다.

세 브랜드의 정상 자료가 확보되기 전에도 로컬 부하 형태는 합성 브랜드/시즌 ID와 고정 이미지 자료로 비교할 수 있다. 이를 실제 세 브랜드의 외부 응답 성능으로 표시하지 않는다. 같은 이미지를 한 시즌 안에 반복 넣으면 content hash dedupe로 부하가 줄어드므로, 이미지 수 확장 자료는 고유 이미지로 만들거나 asset-stage 전용 실험으로 명시한다.

실제 공개 사이트의 전체 이미지를 반복 수만큼 재수집하는 방식은 우선하지 않는다. 고정 자료 재생으로 구조·수치를 비교하고, 공개 사이트 실제 호출은 연동·렌더링·외부 응답 확인용으로 분리하는 안을 추천한다. 고정 자료 재생에서 외부 호스트의 부하 제한까지 검증했다고 주장하지 않는다.

## 조건 추천과 비용 산식

메모리 재사용과 예산별 비교, 첫 실험 규모·Development 시간/인스턴스/추정 비용 한도는 2026-10-03 사용자 확정이다. 이는 실험 설계 조건이며 최종 제품 정책이나 배포·실험 실행 승인은 아니다. 추가 제안은 아래에서 별도 표시한다.

- 브랜드별 순차 후보: 추가 5분 한도 제안은 철회했으며 시즌 job 최초 시도 포함 총 5회(추가 최대 4회)로 사용자 확정했다. 현재 구현의 task 최대 3회와 일부 다운로드 내부 최대 3회는 별도 계층이다. job 총 5회도 특정 다운로드가 항상 최대 5번만 호출된다는 뜻은 아니다. 실제 job claim 이력과 dispatch 재생성 경계를 검증해야 하며 비교 후보의 재시도 정책은 동일하게 맞춘다. 기존 총 3회 정책 그대로의 기준선도 별도 표시한다.
- 재사용: 읽기 전용 Buffer 참조 보관, 인스턴스 공용 256MiB를 초기 후보로 사용. 128/512MiB/전체 보관과 비교. 이미 점유한 입력을 추가 복사하지 않으며 중복 후보 제거 후 해제하고 변환 소비자가 끝날 때 소유권을 반환한다. 예산이 없으면 신규 바이트를 보관하지 않고 이후 필요 시 재다운로드한다.
- 초기 로컬 구조 탐색: 6구조 × 3부하 형태 × 3반복 = 54회. 최적 조합 확정 근거로 단독 사용하지 않는다.
- Development 본 비교: 기준선 + 후보 최대 2개, 3부하 형태, 각각 5반복 = 최대 45회. 최대 2시간, 동시 인스턴스 최대 3개, 각 1 vCPU/2GiB를 제안한다. 단일 인스턴스 비교와 다중 인스턴스 비교를 섞지 않는다. 시간 한도에 도달하면 남은 실행은 미수행으로 보고한다.
- 금액: 작업별 누적 추정 미화 10달러를 검토 한도로 제안한다. 빌드·보관·DB·네트워크·Tasks·로그를 합산해야 하며 청구 반영 지연으로 정확한 결제 상한을 강제한다고 보장하지 않는다. 인스턴스·실행 횟수·시간 한도도 함께 사용한다. 무료 구간 잔량은 가정하지 않는다.

2026-10-03 [Cloud Run 공식 요금](https://cloud.google.com/run/pricing)의 서울 Tier 2 및 페이지 내 리전별 데이터에서 request-based active CPU $0.0000336/vCPU-second, active memory $0.0000035/GiB-second를 확인했다. 1 vCPU/2GiB 인스턴스 3개가 각각 2시간 모두 active라는 가정이면 다음과 같다.

`3 × 7200 × (0.0000336 + 2 × 0.0000035) = $0.87696`

이는 CPU·메모리 계산 예시다. 전체 실험 비용 견적이나 청구 상한은 아니며 요청·startup boost·빌드·이미지 레지스트리·DB·Storage·로그·전송·세금·환율은 포함하지 않는다. 배포 당시 billing mode와 단가를 다시 대조한다. [Storage 요금](https://cloud.google.com/storage/pricing), [Cloud Tasks 요금](https://cloud.google.com/tasks/pricing)도 별도 항목이다.

## 실험 중단과 판정 기준

정확성 불일치·예상 밖 실패·OOM·처리되지 않은 예외·취소 후 작업 누출은 해당 후보를 중단하고 실패 근거를 남긴다. 실제 외부 호스트에서 429를 받으면 해당 호스트 신규 부하를 멈추고 Retry-After와 원인을 확인한다. CPU 100%라는 이유만으로 실패 처리하지 않는다.

메모리 감독은 컨테이너 전체 메모리 한도의 85% 이상이 1초 이상 관측될 때 해당 실험을 중단하는 것으로 사용자 확정했다. 신규 작업을 멈추고 실행 중 작업을 정리한다. 표본 간 순간 피크 차단이나 OOM 방지를 보장하지 않는다. 로컬 RSS와 컨테이너 전체 사용량은 다른 지표이므로 로컬 결과에 같은 기준을 적용했다고 기록하지 않는다. 전체 보관/전체 제출 후보가 이 조건에 걸리면 중단이며 성공 실측에서 제외하되 실패 통계에는 포함한다.

전체 10% 개선과 별도로, 첫 시즌·각 부하 형태의 완료 시간이 기준선보다 10% 이상 반복 악화되면 자동 채택을 보류하고 tradeoff를 검토하는 것으로 사용자 확정했다. 5회로 안정적인 p95나 실패 확률을 증명하지 않는다. 변동이 큰 경우는 추가 반복 또는 미확정이다. 두 보조 기준은 최적값을 실측한 결과가 아니라 실험·결과 검토 기준이다.

예상 전체 요청량·저장 용량·총비용은 자료 manifest와 실제 분기·재시도가 확정된 뒤 산출한다. 단순 예로 17개 고유 후보와 별도 커버 1개가 있는 한 시즌은 재사용 없는 정상 경로에서 이미지 GET 17+18=35회, 업로드 18×2=36파일이다. 커버가 같은 원본이고 재사용 가능하면 GET 수가 줄 수 있지만 아직 검증하지 않았다. Playwright 부가 요청·HTML·DB 호출·재시도는 이 숫자에 포함하지 않는다.

## 사용자 지정 UNAFFECTED 추가 조사

2026-10-03 사용자가 지정한 `https://unaffected.co.kr/collection.html?cate_no=88`을 공개 HTML 읽기로 조사했다. 현재 소스의 `extractSeasonCandidates`는 목록에서 29개 후보를 반환했고 아래 6개 정규 시즌을 모두 포함했다. 29는 현재 추출기의 결과이며 사이트 전체 컬렉션의 실제 총개수나 누락 없음의 증거가 아니다. 협업·에디토리얼도 목록에 있으므로 첫 비교 후보는 2024~2026년 SS/FW로 제안한다.

| 시즌 | 상세 product_no | HTML 바이트 | 정적 이미지 후보 | URL 확장자 |
| --- | ---: | ---: | ---: | --- |
| 2026 FW | 785 | 104239 | 24 | jpg 24 |
| 2026 SS | 534 | 106721 | 30 | jpg 30 |
| 2025 FW | 469 | 101826 | 14 | jpg 14 |
| 2025 SS | 128 | 102531 | 17 | jpg 17 |
| 2024 FW | 510 | 104444 | 22 | jpg 22 |
| 2024 SS | 507 | 105351 | 25 | png 21, jpg 4 |

상세 URL은 `https://unaffected.co.kr/collection/view.html?cate_no=88&display_group=1&product_no={위 ID}`다. 목록·상세 6개 모두 직접 조회 HTTP 200이며, 상세 정적 추출 전략은 `cafe24ProductAdditional`이다. 현재 소스를 `node --import tsx`로 읽었으며 코드 수정·빌드·processor 전체 실행은 하지 않았다. 최초 sandbox DNS 오류 뒤 읽기 전용 네트워크 요청으로 확인했고 일부 웹 도구 cache miss를 사이트 장애로 해석하지 않았다.

6개 시즌 정적 후보 합계는 132개(jpg 111, png 21)다. 확장자는 실제 MIME·디코딩 결과와 다를 수 있다. 이번 추가 조사에서는 이미지 본문·HEAD·해시·해상도·최종 화면을 확인하지 않았으므로 총용량과 최종 고유 이미지 수는 미확정이다. 6개 모두 `collectExpectedCountEvidence` 결과는 빈 배열이다. 따라서 정적 개수만으로 품질 통과나 무검토 자동 등록이 가능하다고 판단하지 않는다.

추천 입력은 단일 시즌 2026 SS 후보 30개와 위 6개 시즌 후보 132개다. 다음 자료 고정 단계에서 화면 대조·이미지 응답·중복·누락·용량을 확인하고 최종 manifest를 만든다. 이 한 브랜드 자료로 같은 브랜드의 시즌 병렬/순차·묶음·단계 분리를 비교할 수 있다. 합성 브랜드 ID로 스케줄러의 브랜드 간 공정성을 검증하는 것과 실제 여러 브랜드 호스트의 네트워크 비교는 구분한다. 후자는 별도 정상 브랜드 자료가 필요하다.
