# Development 네 구조 비교 — 로컬 구현과 검증 기록

**최신 — 약식5회(version3) 로컬 구현·검증 완료:** [확정 조건·구현·검사·요청량](development-screening.md). 준비1회+PP/SP/PS/SS 각1회로 축소한다. 다운로드4·변환1·업로드4·재사용128MiB는 유지한다. `remote-contract.ts`의5회 계약과 `remote-report.ts`의 단일 관측 집계가 현재 기준이며, 채택/반복악화/실패율 개선 판정은 하지 않는다. Mac/AMD64 각각307개·필수199개, emulator5개와 요청량/이미지 대조 게이트를 통과했다. 실제 배포·유료 실험은 미실행이다. 아래21회 실행안·version2·과거 ‘현재/다음’ 문구는 이전 이력이며 추가 실행 권한이 아니다.

후속: [AMD64 배포 전 검증·인증 수정·golden 차단](development-amd64-readiness.md). 아래302개 결과는 최초 구현 당시 기록이다. RN11~12가 추가된 최신 코드와 배포 전제는 후속 문서를 따른다.

2026-10-04. 사용자가 “다운로드4·변환1·업로드4로 구조를 먼저 비교”에 동의하고 다음 핵심 작업 진행을 지시했다. [승인 범위의 계획](development-network-comparison-plan.md)을 구현한다. 제품 배포·실제 원 사이트/Firebase 요청·유료 실험·제품 분산 큐 변경은 이번 범위가 아니다.

## 변경 범위와 계약

| 책임 | 진입점 | 구현 내용 |
| --- | --- | --- |
| 고정 계약 | `tools/lookbook-import-worker/src/performance/remote-contract.ts` | version2, smoke1+본20, PP/SP/PS/SS, 4/1/4·128MiB 유지, planDigest로 순서/정책/재시도 연결 |
| 실행 연결 | `remote-runner.ts`, `remote-store.ts` | 기존 시즌 실행 정책 매핑, 브랜드 종료 지표, claim/finish 동일 campaign 계약 확인, 실패 후 다음 회차 금지 |
| 저장 경계 | `remote-io.ts`, `remote-firebase.ts` | 허용된 runID와 campaign의 객체/문서 root가 정확히 일치해야 사용 가능 |
| 독립 재집계 | `remote-report.ts` | 결과의 version/campaign/정책·정리·원본 golden JPEG SHA/bytes·경로·브랜드 사건을 다시 대조, smoke 분리, 5쌍 비교와 반복 악화 판정 |
| 유한 실행 | `remote-campaign.ts` | 한 번에1요청, 요청 전 checkpoint, 응답 유실/손상 시 재호출 금지, 미수행과 종료 미확인 분리, 2시간/추정US$10 조건 확인 |
| 실제 대상 확인 | `remote-target.ts` | Development tag·기본 트래픽0·CPU1/2GiB·동시성2·900초·리비전 max1/min0·고정 이미지·OIDC·campaign 환경 검사 |
| CLI | `remote-campaign-cli.ts` | plan은 오프라인 출력만, run은 명시적 --execute·승인된 manifest 필요. 새 증거 폴더만 허용, 원본 JSON과 journal 보존, 배포/삭제/IAM 변경 없음 |
| 테스트 | `remote-v2.test.ts`, `remote-campaign.test.ts`, 기존 `remote.test.ts`, `scripts/remote.emulator.mjs` | RN01~10, 기존 RC 갱신, RD05 추가 |

이전 입력 파일 자체는 바꾸지 않았다. corpus digest는 `307bdf7d1b90c04fbcc8ed16307aa7e2ed559cc008207eed8fd487cece676a10`, version2 plan digest는 `4917b9bf8a57bc0f03636a8d43c8ffaaea870dae51d3e17817ab66e105b9bb7b`다. `remote-input-v1` trace 표기는 기존 입력/trace 형식이며 campaign version2와 별개다. 원격 version1 요청은 거부하고 과거 결과 파일은 보존한다.

네 실행 순서는 기존 `season-runner.ts`를 사용한다. PP=6시즌, SP=현재 브랜드의2시즌, PS=브랜드별1시즌씩3시즌, SS=1시즌이며 단계 슬롯은 모든 시즌이 공유한다. 새로운 메모리 예약/R 연결은 추가하지 않았다. iOS/DI/Coordinator·제품 Functions·rules/indexes 변경도 없다.

## 비용 추적의 범위

`externalCostUSD`는 승인될 실행 manifest에 빌드·이미지 보관·로그·시작 CPU boost·추가 제어 조회/원본 GET 헤더 송신 등의 추정치를 합쳐 넣는 항목이다. 실제 청구액으로 표시하지 않는다. 실행 비용 계산은 서울 CPU/메모리·Storage 작업/30일 보관·결과 JSON 수집·Firestore 작업에 공식 단가를 적용한다. 결과 JSON8MiB/회와 claim/finish transaction read 최대30건/회 여유를 잡는다.

다음 회차의 최대5시도 가정 추가 비용을 합쳐 US$10 이상이면 시작하지 않는다. 원본 검증 실패나 회차 실패는 이후 행렬을 멈춘다. response/evidence 유실은 예상 비용을 남기고 종료 미확인으로 분리한다. 이는 무료 차감 전 **작업 추정 비용 중단**이며 플랫폼 청구의 정확한 결제 상한은 아니다. 외부 비용 추정이 없거나 변경되면 실제 실행 manifest를 다시 확인해야 한다.

## 필수 검증

- `verification/lookbook-import.json`: 기존 lint·전체 Node 테스트·추출 fixture, RN01~10을 필수 ID로 추가. 기존 검사를 제외하지 않았다. RC01/RC05와 자동 조절 격리 검사의 원격 계약 기대값만 승인된 version2로 변경했다.
- `verification/lookbook-remote.json`: 기존 RD01~04와 새 RD05의 실행권/21회 순서/변경된 종료 계약 거부. 로컬 demo 프로젝트·8085/9195만 사용한다.
- 새 테스트의 21회는 작은 합성 이미지 실제 JPEG 변환과 fake HTTP/Storage/Firestore를 사용한 계약 검사다. **UNAFFECTED 실제21회나 Cloud Run 성능 측정이 아니다.** Linux/x64 메타데이터 주입도 호스트 계약 검사용이며 실제 해당 환경 통과 증거가 아니다.

### 2026-10-04 실행 결과

두 게이트 모두 HEAD `1d67d61faa04984783083971688a7c628df74748`와 당시 작업 트리를 검사했다. 아래 digest는 각 게이트의 입력 범위가 달라 서로 다르다.

| 게이트 | 결과 | 코드 입력 digest | 원본 결과 |
| --- | --- | --- | --- |
| `lookbook-import.json` | 통과. lint 오류0·경고58, Node302개 실행·필수 ID194개, fixture 통과 | `aadab3bb4f270f01a3d5e38b165737b99985fdc72ca1ff7811cca0b4a0e71b81` (188파일) | [summary.json](../../../../output/verification/1791110308054-aae046f0-0cef-4a62-850c-f41de2d2d146/summary.json) |
| `lookbook-remote.json` | 통과. Worker build와 로컬 에뮬레이터5개 실행·필수 ID5개 | `929712746f2d4e9d667c2e8534b82ac2f31caa38e3ae64d65ddb5fa2170086c4` (192파일) | [summary.json](../../../../output/verification/1791110423774-8efe0e64-429d-4b35-a47b-5a08a7acdd09/summary.json) |

각 실행 폴더의 검사별 원본 로그와 Node 결과를 보존한다. 최종 두 실행의 실패·차단 항목은 없다. 최초 Worker 게이트는 sandbox의 `listen EPERM 127.0.0.1`로 기존 HTTP 서버 테스트5개가 실패했다([최초 결과](../../../../output/verification/1791110134941-5826a1ff-44cd-45de-bc0d-7eb93567a28d/summary.json)). 검사나 코드를 완화하지 않고 로컬 포트 사용 권한으로 같은 게이트를 다시 실행해 위 통과를 확인했다.

오프라인 CLI `plan` 출력도 확인했다. 이번 결과는 macOS 로컬 검사와 demo Firestore/Storage 에뮬레이터 증거다. 새 코드의 Linux/amd64 검사·실제 원 사이트 다운로드·Development 성능·실패율은 미검증이다. 이전292개 검사 결과를 새 코드의 통과 근거로 사용하지 않는다. 실제 실행의 cold/warm 시작 조건과 주변 트래픽 영향은 원본 실행 환경 기록을 함께 검토해야 하며 자동 집계만으로 동등성을 단정하지 않는다.

## 실행 도구 사용 경계

오프라인 계획 확인:

```sh
node tools/lookbook-import-worker/lib/performance/remote-campaign-cli.js plan
```

아직 실행하지 않은 유료 실험 명령 형식:

```sh
node tools/lookbook-import-worker/lib/performance/remote-campaign-cli.js run <승인된-execution.json> <새-증거-폴더> --execute
```

manifest는 `campaign`(version2/campaignID/corpusDigest/planDigest/sourceRevision/sourceDigest/expiresAtMs/runTimeoutMs), 정확한 `targetURL`, `revision`, `imageDigest`, `externalCostUSD`를 갖는다. 실제 리비전 이름이나 비용을 임의 샘플 값으로 만들어 배포하지 않는다. 저장 원본 JSON은 변조·응답 유실 분석을 위해 보존한다. 로컬 journal 재시작으로 이어 실행하지 않으며 서버 claim도 중복을 막는다.

## 남은 작업

1. 실제 배포할 Linux/amd64 이미지와 golden 무결성, 최종 코드/이미지 digest 연결을 확인한다.
2. 지정 OIDC 호출자와 로컬 결과 수집 계정의 실제 권한, 후보 리비전/tag·주변 트래픽/실험 인스턴스 총량 관찰, 실제 계측 가능성을 확인한다. CLI 설정 검사 통과가 Cloud Run cgroup 표본 검증을 대신하지 않는다.
3. 현재 URL의 저장 없는 사전 검토, 준비1+본20의 최종 manifest·추정 외부 비용·중단/정리 실행안을 제시한다. 배포·유료 실행 확인 이후 원격 smoke→본 비교를 실행한다.
4. 성능 결과로 단계 동시성 후속 비교를 정한다. 제품 기본값·분산 대기열·운영 반영은 아직 결정하지 않는다.
