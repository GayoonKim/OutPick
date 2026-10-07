# AD2a — 실제 자원 계측·메모리 준비 측정 결과

2026-10-04. 사용자의 “모호해서 논의 필요한 부분 없으면 진행하자”를 추천 AD2a 구현·필수 검사·로컬 준비18회 진행 지시로 적용했다. **Mac/Linux 각292개·필수184개 통과, 준비18/18회·실제 JPEG42개 검증 완료.** 전체 시즌 성능 비교·원격 다운로드·Storage/Firestore 쓰기·배포는 이번 범위에 없다. [AD2 설계](adaptive-ad2-plan.md)의 AD2b 메모리 예약 수치와 실제 R 연결은 후속이다.

## 구현과 책임

모두 `tools/lookbook-import-worker/` 안의 실험 경로다. 제품 index/server/processor, 앱·Functions·rules·DI·원격30회 계약은 이번에 수정하지 않았다.

| 파일/진입점 | 책임 |
| --- | --- |
| `src/performance/resource-feed.ts::readResourceReading/ResourceFeed` | cgroup v1/v2 누적CPU·quota/cpuset·메모리를 작은 파일 동기 읽기로 수집. 2초 CPU 창, 첫2초 미준비,100ms 표본·500ms 지연·85%1초 중단, 카운터/한도/시각 역행 검사 |
| `resource-feed.ts::OperationEvents` | queue/start/end와 성공/실패/취소, 출력pixels 단위, 소비한 완료 이벤트 재전달 방지 |
| `memory-preparation.ts::preparationPlans/measurePreparation/validatePreparationResult` | 고정5원본·18회·42변환, 실제 생산 JPEG 함수·golden SHA/bytes, 원본/메타데이터 검증, 시작/입력/변환/출력보유/참조해제/1초후 표본, 결과 재검사 |
| `memory-preparation-host.ts::runPreparationContainer/runPreparationCampaign` | 고정 이미지·1CPU/2GiB/swap추가없음/networknone 검사, 회차120초·캠페인30분, 외부 종료/OOM/누락 보존, 실패 뒤 미수행 유지. 확인된 자기 컨테이너만 정리 |
| `memory-preparation-entry.ts`, `memory-preparation-launch.ts` | 컨테이너 측정·호스트 실행 CLI. 증거는 새 경로에만 작성하며 덮어쓰기 금지 |
| `memory-preparation.test.ts`, `fixtures/performance-memory-preparation.json` | AR01~06과 원본/헤더/출력 고정 계약. fixture SHA `6f57fcafcbb3711f97504e24565768a694e3a824410a99ddd6a450d1f4196444` |

CPU 비율은 카운터 차이/경과시간/확인한 quota·cpuset 최소값으로 구한다. 실제 검증 환경은 Linux arm64 cgroup v2·1CPU/2GiB다. v1은 fake 파일의 단위·경로 검증이며 실제 v1 호스트 검증은 아니다. 지원하는 컨테이너 루트 경로와 Docker HostConfig를 확인하고 다른 cgroup 배치를 추정하지 않는다. **컨테이너 바깥의 호스트 자원 경쟁이나 숨겨진 상위 제약까지 독점1CPU로 보장하지 않는다.** 실제 제품 연결의 계측 환경 확인은 별도다.

## 필수 게이트·검사 상태

HEAD `1d67d61faa04984783083971688a7c628df74748` + 작업 트리. 기존178개에 AR01~06을 추가했다. 실패/skip/cancel/todo0, lint 오류0(경고39개), build·추출 fixture 통과다.

| 환경 | 게이트 원본 | 소스 digest / 파일 수 |
| --- | --- | --- |
| Mac Node24 | [1791104148354-ce3836a3-721f-464e-87ae-c36679294311](../../../../output/verification/1791104148354-ce3836a3-721f-464e-87ae-c36679294311/summary.json) | `27b231fea8b8dd05ed4cece6d463df73dddc683ed065a1677c2176bcf7f13638` /182 |
| Linux Node24 | [1791104215466-9101775b-19ed-4f69-ad72-6fb395721c14](../../../../output/verification/1791104215466-9101775b-19ed-4f69-ad72-6fb395721c14/summary.json) | `523c5430277ef92aeea0d2ef61eb4f1ec7e20257c301fcf8f5ba395a07dbec11` /186 |

AR01 v1/v2 단위/quota/cpuset·Linux 실제 제한, AR02 CPU 준비·역행·누락·메모리 중단, AR03 완료 이벤트·대기/실행, AR04 고정18회·입력/출력, AR05 timeout/OOM/미확인 종료·미수행, AR06 결과 위조·누락·소스/정책 변경 거부를 확인했다. Linux 실제 cgroup 검사는 skip하지 않았다. Mac에서는 파서 fake 검사만 수행한다.

```sh
node tools/verification-gate/gate.mjs --project . --config verification/lookbook-import.json
node tools/verification-gate/gate.mjs --project . --config output/lookbook-import-performance/adaptive-ad2a-linux-gate.json
```

이미지 `sha256:3ca180e92e03918d388220d3276f2d28256dc19b310f1d755f577fcda11cefe0`, Node24.21.0/sharp0.34.5/libvips8.17.3/arm64, sharp concurrency1. 기반 AD1 이미지와 ID를 대조한 로컬 태그에서 빌드했고 측정은 태그가 아닌 불변ID를 사용했다. wrapper/config/Dockerfile/image ID는 `output/lookbook-import-performance/adaptive-ad2a-*`에 보존한다.

개발 도중 TypeScript 타입/unused import와 lint 형식 오류를 수정했다. 최초 Dockerfile에 이미지ID를 FROM 태그처럼 쓴 오류로 레지스트리 메타데이터 해석이 실패했다. 로컬 기반 태그의 ID를 검증하고 참조를 수정한 후 빌드했다. **처음부터 모든 명령이 성공하거나 빌드 준비까지 모든 네트워크 요청이0이었다고 기록하지 않는다.** 승인된18회 측정은 첫 캠페인으로 모두 완료됐고 재실행·보충은 없다. 실험 컨테이너는 모두 networknone이고 Firebase 트래픽은 발생시키지 않았다.

Functions·Firestore/emulator 코드를 바꾸지 않아 해당 게이트는 재실행하지 않았다. 이전 emulator 결과는 이번 digest의 통과로 대체하지 않는다.

## 준비 실행·원본

- [캠페인 summary](../../../../output/lookbook-import-performance/adaptive-ad2a-preparation-20261004/summary.json), 같은 폴더의 manifest·각 회차 plan/container/host-config/result/finished/log.
- [독립 집계 JSON](../../../../output/lookbook-import-performance/adaptive-ad2a-analysis.json), [재집계 코드](../../../../output/lookbook-import-performance/adaptive-ad2a-analyze.py), [소스/이미지 계약](../../../../output/lookbook-import-performance/adaptive-ad2a-source.json).
- 단일 이미지5종×3회는 두 변환을 순차 실행했고, 최대 픽셀의 독립 Buffer2개에서4변환 동시 실행×3회를 추가했다. 원본·JPEG 품질·리사이즈·출력 SHA/bytes 계약은 동일하다.
- 총18개 새 컨테이너,42개 실제JPEG, 캠페인 약76.9초. 회차 실패/중단/OOM/미수행0, 모든 회차 내부 논리 Buffer 참조0·외부 정리 확인, 잔여 컨테이너0.
- 최장 표본 간격139.407ms로500ms 한도 미만. 가장 높은 관측/커널 메모리394.75MiB(2GiB의19.27%). 입력/출력 무결성,18개 고유ID·종료/정리·HostConfig·회차당2/4출력을 독립 재집계했다.

## 관측값과 해석의 범위

각 조건3회다. 증가는 입력 직전 `memory.current` 대비 작업 구간 표본 최고값의 차이, 표본 최고는 컨테이너 전체 사용량이다. 커널 최고는 새 cgroup 시작부터의 `memory.peak`이며 sharp만의 정확한 할당량이 아니다. 변환시간은 첫 변환 시작~마지막 종료로, 워밍업·정리시간을 제외한다. 정리1초후는 참조를 비우고1초 기다린 시점이며 강제GC는 사용하지 않았다.

| 조건 | 증가 중앙값 / 최대(MiB) | 전체 표본 최고(MiB) | 커널 최고(MiB) | 변환시간 중앙값(ms) | 정리1초후 중앙값(MiB) |
| --- | --- | --- | --- | --- | --- |
| 중앙 크기 JPEG | 41.92 / 42.16 | 97.73 | 99.98 | 424.0 | 82.55 |
| 최대 픽셀 JPEG | 171.54 / 171.79 | 226.20 | 226.77 | 551.8 | 210.71 |
| 최대 파일 JPEG | 194.67 / 194.67 | 249.88 | 251.63 | 534.3 | 233.66 |
| RGBA PNG | 12.92 / 14.67 | 69.12 | 69.92 | 100.6 | 67.31 |
| 커버 | 12.43 / 12.43 | 67.52 | 67.77 | 96.5 | 64.07 |
| 최대 픽셀 2장·4변환 동시 | 336.11 / 340.35 | 394.75 | 394.75 | 1094.3 | 354.28 |

- 최대 픽셀 원본의 단순RGB 지표는62.57MiB지만 관측 증가는 최대171.79MiB였다. 이보다 픽셀이 작은 최대 파일 JPEG는194.67MiB로 더 컸다. 파일bytes나 픽셀·채널 곱 하나를 변환 메모리 상한으로 사용하면 안 된다는 근거다.
- 4변환 중첩의 관측 증가는 최대340.35MiB였다. 단일 조건의 단순 배수와 똑같다고 일반화할 수 없으며, 모든 원본 조합·연속 실행·장기 native 보유를 포괄한 상한도 아니다.
- 최대 파일 JPEG는 입력 전 약54.5MiB에서 정리1초후 중앙값233.66MiB가 남았다. 논리 Buffer 참조0과 cgroup 사용량 회복은 다른 조건이다. libvips/native allocator·파일 캐시·GC 등 원인별 분해는 이번에 하지 않았으므로 메모리 누수라고 단정하지 않는다.
- 실제 HTTP chunk/concat·Storage SDK·네트워크 속도·여러 시즌 장기 실행은 포함하지 않았다. 이18회로 P/S/R 중 승자, 실패율 개선, 최적 동시성, 정확한 E나 안전계수는 확정하지 않는다.

## 다음 AD2b

이 측정값을 바탕으로 지원 이미지별 예약 E·안전 여유, 최대 원본의 조합/잔류 메모리 압박, 예약 거절 시 대기/중단 계약을 구체화한다. 현재 제안은 `M + R + Enew <= 0.75L`의 보수적 전액 예약이며 실제 사용량과 겹치는 예약은 별도로 보고한다. **실측 최대값에 임의 계수를 곱해 승인된 최적값으로 넣지 않는다.**

75% 제동에서 신규 투입과 기예약 필수 읽기를 구분하고, 캐시 소유권·형제 drain·취소/재시도와 함께 실제 R 실행에 연결하는 것은 AD2b다. 계측 오버헤드 대조·P/S/R 동일 계측 비교는 AD2c 이후, Development 배포·실험은 대상/요청량/비용 실행안 범위 확인 후다.
