# Development 약식 5회 비교

**최신 — Development 실제 약식5회 완료:** [실측 결과·원본·게이트·비용 추정](development-screening-results.md). 준비1회와 PP/SP/PS/SS 각1회가 모두 성공했고 실제 실행·원본 재검사 게이트를 통과했다. 전체 처리100~104초, 브랜드 순차 후보의 첫 브랜드 완료는 약10% 빨랐으나 각1회·동일 인스턴스·고정 순서이므로 채택은 미판정이다. 추가 실행/운영 반영/삭제는 하지 않았다. 아래 승인 대기·미실행 문구는 실행 전 이력이다.

실행 전 기록: **배포 전 준비:** [약식5회 실행안·현재 대상·비용·검증](development-screening-execution.md). 로컬 원 사이트 HTML7개/원본138개 검사가 통과했고 현재 설정·기존 OIDC와 서울 단가를 재확인했다. 준비 게이트2개 통과, Worker 소스 변경 없음. push/배포/Worker 실험 요청/Firebase 실험 쓰기는 아직 하지 않았다.

2026-10-04. 사용자가 준비 확인1회+네 구조 각1회로 시작하고 결과 분석 후 필요한 비교만 추가하는 추천안을 확정했다. 이번 구현 범위는 실행 계약·집계·문서·로컬 필수 검사다. 실제 배포·원 사이트/Firebase 실험 실행은 별도 실행안 확인 뒤 진행한다.

## 확정 조건

- 순서: `smoke-PP-single-1` → `PP-synthetic-three-1` → `SP-synthetic-three-1` → `PS-synthetic-three-1` → `SS-synthetic-three-1`. 총5회, 요청은 한 번에1개다.
- 준비 확인은2026SS, 본 비교는 기존 UNAFFECTED6시즌을 연도별 합성3브랜드×2시즌으로 구성한다. PP=브랜드/내부시즌 모두병렬, SP=브랜드순차/내부병렬, PS=브랜드병렬/내부순차, SS=모두순차다.
- 다운로드4·변환1·업로드4·경로저장 제한 없음, 실행 내 원본 재사용128MiB, 커버 준비/변환 정책·AMD64 입력과 golden을 유지한다.
- 시즌 최초 포함 총5시도와 다운로드 내부 최대3시도는 기존 조건이다. 실험 회차 반복과 구분한다. 실패·계측 미검증·정확성 오류·종료 미확인은 후속 회차를 중단하고 자동 보충하지 않는다.
- 기존2시간·추정US$10 중단은 비상 중단 기준으로 유지한다. 5회 이후 자동 증량하지 않으며 남은 종전45회 한도를 실행 권한으로 쓰지 않는다. 비용 추정은 청구 상한 보장이 아니다.

## 해석과 추가 비교

1회 관측값과 PP 대비 전체/첫시즌/첫브랜드 완료 시간 차이만 표시한다. 메모리·단계 지표·실패/재시도·요청/bytes·비용 추정 원본을 보존한다. smoke는 후보 비교에서 제외한다. 누락·실패·종료 미확인은 별도 분모로 남기며 해당 쌍을 비교하지 않는다. 환경 metadata 불일치도 비교하지 않는다. 같은 metadata가 네트워크나 cold/warm 조건 동일성을 보장하지는 않는다.

약식 결과에서 최적 구조·실패율 개선·중앙값10%개선·5쌍 반복 악화를 판정하지 않는다. 고정 순서의 시점/cold-start 영향과 작은 표본 한계를 함께 분석한다. 기존5쌍 기준은 충분한 후속 비교를 별도로 설계할 때 검토하며 단일 회차 기준으로 완화하지 않는다.

추가 비교는 실제 결과를 보고 유력 후보와 PP 등 필요한 대조군을 정하고 요청량·예상 비용·회차 순서를 먼저 제시한다. 이번 계약은 추가 회차를 받지 않는다. 후속 계약과 별도 승인이 필요하며 자동 재시작/자동 보충/자동 제품 채택을 추가하지 않는다.

## 구현 단계와 검사

| 단계 | 목표·변경 범위 | 완료 기준·검증 | 논의 사항 |
| --- | --- | --- | --- |
| S1 계약 | `remote-contract.ts`, fixture/runner/campaign/CLI를 version3로 통일. 이전 version2/21회 plan digest 거부 | RN01/RC01: 정확한5회·이전계약·추가회차 거부·요청량 | 없음: 승인된5회 적용 |
| S2 집계 | `remote-report.ts`: 각1관측과 변화율, 채택/반복악화/실패율 개선은 not-assessed | RN03/05/06/08: smoke 제외·환경차이·실패/미확인·초과 실행 없음 | 후속 표본 선정은 실제 결과 이후 |
| S3 연결 검증 | 관련 테스트·필수ID 갱신, 문서/진입점 갱신 | Mac/AMD64 Worker 필수 게이트, emulator RD01~05. 새 Docker 이미지·코드 상태 기록 | 실제 클라우드 성능/비용은 미검증 |

기존 `season-runner.ts`와 Storage/Firestore adapter·실행권 구조를 재사용한다. iOS/DI/Coordinator·Functions·rules/indexes·제품 큐 변화는 없다. 자동 테스트는 fake HTTP/Storage/Firestore와 합성 JPEG로 계약을 검사하고 emulator로5회 실행권/종료/추가회차 거부를 확인한다. 실제 클라우드 CPU의 golden 일치·cgroup·결과 수집은 후속 smoke에 남는다.

## 요청량과 비용 범위

아래는 기존 AMD64 fixture의 재시도 없는 정상 처리 산술이다. 재시도/SDK 추가 요청을 포함한 상한이 아니다.

| 항목 | 총5회 |
| --- | ---: |
| 원본 GET (재사용 모두 hit / 모두 miss) | 583 / 1,137 |
| 원본 수신 bytes (hit / miss) | 453,700,111 / 900,313,163 |
| JPEG 업로드 및 검증 GET | 각각1,158개·171,392,080bytes |
| 경로 저장 대상 | 579 |
| Firestore 문서 read / write | 1,163 / 1,188 |
| result.json 업로드·로컬수집 | 각각5개·합계최대40MiB |
| 결과 포함 정상 Storage write / read | 각각1,163 |

로컬 URL 사전 확인은 별도 HTML7회+원본최대138회/112,771,684bytes다. 기존 [21회 비용 모델](development-network-comparison-plan.md)의 Worker CPU/메모리 활성시간, Storage 작업/보관/검증읽기, Firestore, registry·로그·추가 제어 요청을 그대로 포함한다. 이미지 업로드량만으로 비용을 판단하지 않는다. 원격 실제 시간이 없으므로 축소된 총 청구액을 확정하지 않는다. 고정 비용 때문에 총 비용이 회차 수에 비례해 줄어든다고 단정하지 않는다.

## 검증 결과

**로컬 구현·검증 완료:** Mac/Linux AMD64 Worker 각각307개·필수199개, 로컬 emulator5개, 요청량/이미지 대조 게이트 모두 통과했다. 최종 실행의 실패·차단은 없다. 이전 코드의 결과를 새 코드 통과로 재사용하지 않았다. 배포·유료 실험은 미실행이다.

계약/결과/CLI/journal은 version3다. 새 plan digest는 `0ead82ab8e323d8cd7b15bd1f7e5ab76a75256856f52e29c35283ef46295011b`, corpus digest는 기존 AMD64 `49671fbcd756f733e034bc079cc6911fa6ef18184e9e6206f3c1d0d475fa8f15`다. 이전21회 digest/version2는 거부하며 저장된 과거 증거는 그대로 보존한다.

HEAD `1d67d61faa04984783083971688a7c628df74748` + 작업 트리 상태로 검사했다. 각 게이트의 입력 범위가 달라 source digest도 다르다. 검사별 원본 stdout/stderr/Node 결과는 summary와 같은 실행 폴더에 보존한다.

| 검사 | 결과 | source digest / 원본 |
| --- | --- | --- |
| Mac Worker | passed. lint0오류/75경고,307개·필수199개·fixture | `c68068fc5e5feef261398bc165255017088ea10ec88873f2e249dd17c073b212` / [summary](../../../../output/verification/1791114295615-2bca845e-ab41-4361-a303-56766986751e/summary.json) |
| Linux AMD64 Worker | passed. lint0오류/75경고,307개·필수199개·fixture | `ab67fe0c4a4cf6e4e2c15ee005cf5e7f38dc9d1d88d930fca0899fededb0238a` / [summary](../../../../output/verification/1791114353804-9df66acd-aaa9-4a3c-a482-fbc2783d93c6/summary.json) |
| 로컬 emulator | passed. build·RD01~05 총5개 | `c9e4881a7d569f308a44c91fd2ce6c95de8983e5dcdd0ba908b82ceb9448d308` / [summary](../../../../output/verification/1791114437956-9478e1c5-1327-4e32-8558-e4e40d5b139a/summary.json) |
| 요청량·이미지 바인딩 | passed. 산술과284개 compiled/package 파일·양쪽 이미지5회 CLI 계획·플랫폼/인코더 일치 | `b798806faa525846b1eed9de2135cfd84efac91a0298d2f3e3161c5039644aea` / [summary](../../../../output/verification/1791114426203-e30028b4-6a0a-4479-a9bd-f4700d67b997/summary.json) |

[요청량 원본](../../../../output/lookbook-import-performance/screening/request-volume.json), [이미지 대조](../../../../output/lookbook-import-performance/screening/image-binding.json). 새 로컬 test 이미지 `sha256:5e01f36c7e1dc4037e64e629ea0c9c18ed620aee9ba368a5626fb1b073b3ab24`, runtime 이미지 `sha256:7e97ef277b2e19c09c99baf6afa767c322daa552c3747001f7cfe81f7ae5fb05`. 변환 구현·의존성·golden fixture는 변경하지 않았다. 이전 이미지의274개 golden 검사를 새 runtime에서 다시 수행했다고 표시하지 않는다. 실제 Cloud Run 출력의 exact 일치는 여전히 후속 smoke에서 확인한다.

최초 Mac 게이트는 테스트307개는 통과했지만 추가한 두 줄의 max-len 오류로 실패했다([원본](../../../../output/verification/1791114083017-7a024413-fff1-440d-9336-c560a4a043ef/summary.json)). 같은 오류가 있는 최초 AMD64 검사는 불필요한 실행을 피하려 에이전트가 SIGTERM으로 중단했고 성공으로 계산하지 않는다([원본](../../../../output/verification/1791114174377-11ff5cae-0c28-44a2-81f9-86e63460fa24/summary.json), 게이트의 일반 ‘사용자 취소’ 분류는 이 수동 중단을 뜻한다). 서식만 수정한 뒤 새 이미지로 필수 게이트 전체를 다시 실행했다. 검사/합격 조건은 완화하지 않았다.

이미지 대조 첫 시도는 현재 소스에 없는 오래된 host 산출물 `lib/extraction/adapters/registry.test.js`와 `.map` 때문에 불일치했다. 현재 소스에 대응하는284개 파일 전부를 대조하고 이2개는 `staleHostFiles`에 기록했다. Docker에는 두 파일이 없고 기존 `scripts/run-tests.mjs`도 현재 `.test.ts`에서 실행 목록을 만들므로 실제307개 검사에는 포함되지 않는다. 해당 파일을 삭제하거나 사용자 변경을 되돌리지 않았다.

재실행은 프로젝트 루트에서 Node24 PATH로 다음 게이트를 사용한다. Docker 검사는 linux/amd64,1CPU/2GiB,noswap,network none이며 실제 네트워크 성능 표본이 아니다.

```sh
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json
node tools/verification-gate/gate.mjs --project . --config output/lookbook-import-performance/screening/gate.json
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-remote.json
node tools/verification-gate/gate.mjs --project . --config output/lookbook-import-performance/screening/evidence-gate.json
```

## 다음 실행안의 범위

대상 초안은 기존 `outpick-test`/`asia-northeast3`/`lookbook-import-worker-development`의 격리 tag, 새 revision 기본트래픽0/min0/max1,1CPU/2GiB다. [기존 읽기 전용 대상 확인](development-amd64-readiness.md)을 기준으로 하며 배포 직전에 다시 확인한다. 기존 서비스의 트래픽/설정 변경이나 제품 큐 도입은 포함하지 않는다.

새 runtime image·source digest·version3 manifest와 위5회 요청량을 사용한다. 실제 campaignID·tag 충돌 여부·유효시간·외부비용 추정은 실행안 확인 시 고정한다. 원 사이트 사전 확인 → 준비1회 → 성공 시 본4회 → 증거/비용 검토까지가 최초 원격 범위다. 추가 회차나 자동 정리는 포함하지 않는다. 새 결과 객체 읽기 권한, Cloud Run 계측 호환성, 실제 네트워크 시간/비용은 아직 미검증이다.
