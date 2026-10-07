# Development AMD64 배포 전 준비와 차단 사항

후속 승인: 사용자가 AMD64 전용 golden 분리를 승인했다. [생성·연결·최종 검증](development-amd64-golden.md)을 따른다. 아래152개 불일치와304개 검사는 분리 전 당시 기록으로 보존한다.

2026-10-04. 사용자의 다음 작업 진행 지시에 따라 Linux/amd64 이미지, 인증, 현재 대상 설정을 확인했다. **배포·원 사이트 이미지 재다운로드·실험 객체 쓰기·본 성능 비교는 하지 않았다.** 현재 배포를 막는 항목은 기존 ARM64 JPEG golden과 AMD64 출력의 불일치다. 실패 기준을 완화하거나 fixture를 바꾸지 않았다.

## 1. 완료한 준비와 실제 네트워크 접근 범위

- 기존 Dockerfile로 `local-performance`와 `runtime`을 Linux/amd64로 로컬 빌드했다. 의존성·브라우저 다운로드는 Docker/npm/Playwright 서버를 사용했다. Cloud Build와 Artifact Registry push는 실행하지 않았다.
- Development 서비스·버킷·IAM·Artifact Registry 설정을 읽기 전용으로 재확인했다. 기존 기본 트래픽은 `lookbook-import-worker-development-00012-fih` 100%, 기존 tag 그대로다.
- 지정 호출자에 이미 `roles/iam.serviceAccountOpenIdTokenCreator`가 있지만 `getAccessToken`은 없음을 실제 permission 검사로 확인했다. 이전 CLI의 `gcloud --impersonate-service-account`는 불필요한 `getAccessToken`을 요구해 실패했다.
- `remote-auth.ts`는 현재 gcloud 사용자 자격으로 IAM `generateIdToken`을 호출한다. 지정 service account·canonical audience·includeEmail을 고정하고 취소/30초 제한/재시도 없음/인증값 비노출을 적용했다. `remote-campaign-cli.ts`에서 사용한다. 서비스 계정 access token이나 새 IAM 역할은 만들지 않았다.
- 수정된 경로로 실제 OIDC 발급 성공과 audience/email/만료를 메모리에서 확인했다. 토큰 파일·로그 저장과 Worker 호출은0회다. 공식 권한 근거: [OpenID 전용 역할](https://docs.cloud.google.com/iam/docs/service-account-permissions), [generateIdToken](https://docs.cloud.google.com/iam/docs/reference/credentials/rest/v1/projects.serviceAccounts/generateIdToken).
- 로컬 ADC의 bucket IAM `storage.objects.get` 검사는 false였고 존재하지 않는 실험 경로의 메타데이터1회 조회는404였다. 버킷은 uniform access가 꺼져 있고 기본 object ACL도 사용한다. **404만으로 앞으로 생성할 result.json 읽기 권한까지 통과로 확정하지 않는다.** 원본 `adc-object-probe.json`의 `readAuthorized:true`는 탐색 스크립트의 추론값이며 최종 판정으로 사용하지 않는다. 실제 smoke의 새 result.json 수집 성공이 남은 확인이다. 이 확인을 위해 다른 제품 객체나 이미지 본문은 읽지 않았다.

따라서 “Firebase 트래픽이 전혀 없었다”는 설명은 맞지 않다. 제어 API·권한 조회와 존재하지 않는 객체 메타데이터 조회만 있었고, 성능 실험용 다운로드/업로드·Firestore 문서 쓰기는 없었다.

원본은 [준비 증거 폴더](../../../../output/lookbook-import-performance/network-v2-amd64/)의 `service-before.json`, `service-iam.json`, `caller-iam.json`, `caller-effective-permissions.json`, `oidc-check.json`, `bucket-before.json`, `bucket-iam.json`, `adc-read-check.json`, `adc-object-probe.json`, `registry-before.json`이다.

## 2. 이미지와 코드 식별

현재 로컬 runtime 이미지 ID는 `sha256:1524ebb2ad5750673280be4bb832737e432603581e56300781e7dd8ad02d1d3d`다. linux/amd64, Docker 보고 Size573,274,533bytes다. 이는 압축된 원격 저장량이나 새 Cloud Run 리비전 digest의 확인을 대신하지 않는다. 레지스트리 업로드 전이며 Cloud Run 이미지로 확정하지 않는다.

Node24.21.0, sharp0.34.5, libvips8.17.3, mozjpeg0826579다. 원본 `runtime-final-id.txt`, `runtime-inspect.json`, `runtime-final-build.log`를 보존한다. 검증 이미지는 `image-final-id.txt`로 따로 고정하며, 테스트는1CPU/2GiB·추가 swap 없음·네트워크 없음으로 실행한다. Apple Silicon 위 AMD64 실행이므로 이 소요 시간을 Cloud Run 성능으로 해석하지 않는다.

[코드 결합 검사](../../../../output/lookbook-import-performance/network-v2-amd64/image-binding.json)에서 runtime·검증 이미지·호스트의 compiled 파일 및 package 파일280개 SHA가 모두 같고, 두 이미지의 Node/sharp 의존성 버전도 일치함을 확인했다.

## 3. 원본 통과, JPEG golden 불일치

최종 runtime 이미지에서 기존 로컬 자료를 읽어 실제 `processor.ts::jpegBytes`를 호출했다.

| 항목 | 결과 |
| --- | --- |
| 입력 fixture SHA-256 | 기존 `307bdf7d1b90c04fbcc8ed16307aa7e2ed559cc008207eed8fd487cece676a10` 그대로 |
| 원본 이미지/커버138개 | 전부 bytes·SHA 일치 |
| JPEG274개 | 기존 golden과122개 일치,152개 불일치 → **검사 실패** |
| JPEG 합계 | ARM 기준42,259,800bytes, AMD64 산출42,259,618bytes. 차이-182bytes는 합격 근거가 아님 |
| 대표3개 재현 | 같은 Node·sharp/libvips/mozjpeg 버전, 같은 함수 소스 hash·입력·설정. Linux ARM64는3개 모두 기존 golden과 일치, AMD64는3개 모두 달랐음 |

대표3개는 2026FW 본문,2026SS 본문,2025SS 커버다. 함수 hash는 양쪽 모두 `b1843e6a1ab67fff87f0593699e555d0056749e36bcae69888f7229d40de5bc1`이다. 크기·JPEG 형식은 같았고 같은 디코더로 읽은 채널 평균 절대 차이는 각각0.02767/0.00939/0.00082(0~255), 최대7/14/6이었다. 이는 차이 진단이며 전체 품질 합격 기준이나 수동 시각 검증이 아니다. 어느 SIMD/인코더 내부 단계가 원인인지는 확정하지 않았다.

[sharp 공식 문서](https://sharp.pixelplumbing.com/api-utility/#simd)는 resize 등이 CPU의 Intel SSE/ARM NEON을 사용하는 SIMD 경로를 지원한다고 설명한다. 이것만으로 이번 차이의 정확한 원인을 확정하지 않는다. 같은 AMD64라도 로컬 에뮬레이션과 Cloud Run CPU 실행 경로의 동등성은 아직 검증되지 않았으므로 별도 golden을 만들더라도 실제 smoke의 엄격 검사를 유지한다.

[274개 검사](../../../../output/lookbook-import-performance/network-v2-amd64/golden-result.json), [ARM64 대표](../../../../output/lookbook-import-performance/network-v2-amd64/architecture-arm64.json), [AMD64 대표](../../../../output/lookbook-import-performance/network-v2-amd64/architecture-x64.json), [대표 픽셀 차이](../../../../output/lookbook-import-performance/network-v2-amd64/sample-pixel-comparison.json)에 원본을 남겼다. 기존 golden이 들어간 현재 이미지로 원격21회를 실행하면 엄격한 출력 검증에서 실패하므로 배포 준비 완료로 선언하지 않는다.

## 4. 다음 결정과 추천안

**추천: Linux/amd64 전용 golden을 별도 생성·검증하고 원격 입력 계약에 명시한다.** 기존 ARM64 fixture·결과는 보존하고 혼합하지 않는다. 원본 URL/bytes/SHA·순서·중복 제거·변환 크기/품질 정책은 그대로 유지한다. AMD64 전체274개를 전수 디코딩·치수/방향 검사하고 고정 이미지에서 반복 산출 hash가 같은지 확인한 후, 확인된 AMD64 golden에 대해 다시 exact SHA/bytes 검사를 유지한다. 기존 실패를 통과로 바꾸거나 SHA 검사를 제거하는 안이 아니다. 새 기준 채택은 사용자 결정 후 진행한다.

대안은 모든 플랫폼의 변환 바이트가 일치하도록 인코딩 경로를 바꾸는 것이다. 공통 golden은 유지할 수 있지만 제품 변환/성능에 영향을 줄 수 있는 추가 조사·변경이며 현재 구조 비교 범위가 커진다. 단지 실험을 통과시키려고 SIMD 등을 임의로 끄지 않는다.

## 5. 배포·실행안 초안 — 아직 실행 불가

| 항목 | 준비한 구체 범위 |
| --- | --- |
| 프로젝트/서비스 | outpick-test / asia-northeast3 / lookbook-import-worker-development |
| 레지스트리 | 기존 `asia-northeast3-docker.pkg.dev/outpick-test/cloud-run-source-deploy/lookbook-import-worker-development` |
| 이미지 전달 | golden 정리 후 검증한 로컬 AMD64 이미지를 push하는 안. Cloud Build 재빌드 없이 검증한 이미지와 동일하게 연결. 원격 digest는 push 후 대조 |
| 후보 tag/리비전 | `netv2-20261004` / `lookbook-import-worker-development-netv2-20261004` 제안. 생성 전 충돌 확인, 기존 tag와 기본100% 트래픽 보존 |
| 자원 | 후보1vCPU/2GiB, min0/max1, HTTP concurrency2, timeout900초, 요청 기반. 서비스 전체 scale 변경 없음 |
| 실행 | 실험 요청은 한 번에1개. smoke PP-2026SS 1회 → 고정4구조×5회. 다운로드4/변환1/업로드4,128MiB 유지 |
| 인증 | 기존 호출자 OIDC/canonical audience 유지. IAM 변경 없음. 로컬 ADC의 실제 결과 수집은 smoke에서 확인 |
| 격리 | 실험 모드 일반 route 차단. Storage는 해당 campaign 경로, Firestore는 실험3컬렉션만 사용 |
| timeout | 회차840초 제안, HTTP900초. 실행창2시간·누적 추정US$10 중단·실험 관련 인스턴스 총3개 한도 유지 |
| 만료 | 실제 시작 직전에 campaignID/시각/2시간 만료를 고정. 지금 임의 만료로 실행 가능한 manifest를 만들지 않음 |
| 중단/정리 | 정확성·메모리·증거 유실 시 새 회차 금지. 실패 표본 보존, 자동 보충 없음. 멈춘 뒤 실행 중 요청 정리를 확인. 이번 준비에서 객체/문서/리비전 삭제 없음 |

소스 식별은 git HEAD만 쓰지 않고 게이트의 작업 트리 digest와 이미지 안 compiled 파일 무결성을 함께 묶어야 한다. golden 계약 변경 후 최종 이미지/digest/입력/정책을 다시 고정한다. 실제 Cloud Run cgroup 가시성·cold/warm·인스턴스 수·주변 트래픽은 배포 후 smoke 전후에 확인하며 현재 로컬 검증으로 대체하지 않는다.

정상21회의 수량은 이미지 원본 GET2,791~5,441, JPEG5,542개 업로드·동일 개수 검증 GET, result.json21개, 경로2,771건이다. 저장 없는 사전 검토 HTML7회+원본 최대138회는 추가다. HTML/원본 최신 확인은 아직 실행하지 않았다. JPEG bytes·비용 입력은 AMD64 golden 채택 후 다시 계산해야 한다. 기존 [요청량·요금 가정](development-network-comparison-plan.md)의 정상21회 약US$0.4~1 견적은 참고치이며 무료 보장/상한이 아니다. 로컬 빌드를 사용하면 제안된 Cloud Build1회 비용은 발생시키지 않는 안이다. 예상 외부 비용 manifest 값은 새 golden·push 후 저장 크기와 함께 확정한다.

## 6. 필수 게이트

- Mac: [1791111175170-f877139a-23ce-4bcf-9af5-f5b2102c426b](../../../../output/verification/1791111175170-f877139a-23ce-4bcf-9af5-f5b2102c426b/summary.json), passed. lint 오류0/경고58, 전체304개·필수196개 및 fixture. digest `9c4aee1958a2e73801f3d839b7899c79e1c012854a493f8059e03eec6dd40bc2`,190파일.
- Emulator: [1791111355624-39350e5a-d381-44b6-afaf-bfa4ce74fefc](../../../../output/verification/1791111355624-39350e5a-d381-44b6-afaf-bfa4ce74fefc/summary.json), passed. build·RD01~05 총5개. digest `38fe3557e571cc565a94f8d1623168f4774011cf4549de40da54f5560d6e1d4d`,194파일.
- Linux/amd64 최종: [1791111268740-4042e6c9-5b75-4d47-9459-3ae5f812f283](../../../../output/verification/1791111268740-4042e6c9-5b75-4d47-9459-3ae5f812f283/summary.json), passed. lint·전체304개/필수196개·fixture 통과, 실패/차단0. digest `29f8c7db18993f08dae95ca8e1345c1c2eecd5963a635e489aee6c348a01ec9d`,193파일. 고정 검증 이미지 `sha256:475a6ee08f6a4e75ea0bd330e3e6502fc5accd5b41239657510588d950400482`. golden152개 불일치의 별도 실패는 그대로 유지한다.
- 중간 AMD64 검사 [1791110815284-5df6cf17-d0f1-41ad-8f4c-a3ce3ac32089](../../../../output/verification/1791110815284-5df6cf17-d0f1-41ad-8f4c-a3ce3ac32089/summary.json)는 인증 수정 전 이미지였다. 수정된 코드로 다시 검사하기 위해 중단했고 테스트 누락·소스 변경으로 blocked를 보존했다. 최종 통과로 사용하지 않는다.

RN11/RN12는 지정 OIDC 요청과 취소·실패·잘못된 응답·토큰 비노출을 검사한다. 이전302개 통과를 수정된304개 코드의 결과로 재사용하지 않았다. 제품 Functions·Swift·rules/indexes·IAM·배포 설정은 수정하지 않았다.
