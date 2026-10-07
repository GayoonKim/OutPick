# Q7 K/L Development — 실제 종료·처음부터 재시도 검증 완료

## 최종 실제 결과(2026-10-07)

원래3접수를보존한이어실행이completed/passed다. 추가5/전체8accepted·새6/누적24task전달,108.957초. K의old25/epoch49 실제종료증거로 제품이같은execution의attempt2/5를새파싱했고새검토승인후저장성공했다. L의원래총5회제어실패→실패목록1개→맨뒤수동새execution/새5회→attempt1성공→목록제거/원본이력유지를확인했다. 최종124JPEG4,707,216B의hash/generation/현재공개원장이일치하고queue idle/head null이다. old원장6건은unpublished/cleanup pending·새참조와경로가겹치지않는다. 실제24h삭제는검증하지않았다.

새6요청:NodeCPU18.01초,메모리최고47.1109%,최대표본공백238.070ms,이미지GET122/10,225,638B·정상업로드124/4,707,216B. 기존OOM요청의최종계측/원래실제조회수는불명확이며통계성능판정/실제청구확정은아니다. [전체Q7최종정리](product-queue-q7-final-results.md), `continuation-metrics-summary.json`/`report.json`/`K-termination-evidence.json`/`L-retry-evidence.json`에근거를기록했다.

새후보00026-zip0%/base12 100%·1CPU2GiB/max1/concurrency2/900을확인했고추가IAM·자원증설·Production변경0이다. image0b1ddb5c...의574,343,286B·build239.420초로보정한기존전체K/L관리추정약USD0.396(청구상한아님),기존1USD/누적10유지. 새L전용faultcampaign completed,추가OOM0. 아래배포중/미완료문구는시점별과거이력이다.

## 이어 실행 구현·현재 필수 검사(2026-10-07)

사용자 승인으로 K/L 각 흐름을 한 번 확인하며 기존K3건·남은5접수·새20분창·추가OOM0·조건부같은Ktask1회·추가10/누적30전달·기존전체비용한도를 고정했다. 기존task만료/0개, old25요청18전달·Kactive/attempt1/5/epoch49를 읽기 전용 확인했다. 신규 원격 접수는 아직 없다.

`q7-retry-{contract,runner}.mjs`와 `q7-journal.mjs`는 동일3accepted만 이어가며 원본자료 배타적 저장, UID/head/oldrevision·실제종료증거·미공개원장검사, L전용새faultcampaign, 조건부task1개·불확정재전송금지, revision별 계측/원래조회수미확정표시를 연결했다. 실제K자료로 같은 계약검사도 읽기 전용 통과했다. 원본 `continuation-predeploy-contract-readback.json`.

| 검사 | 실행ID | 결과 |
|---|---|---|
| Q7 verifier | `1791350705468-a622bcfb-7122-4c77-83d2-b5f4cbfcc93a` | 40 passed |
| Worker/lint/fixture/deploy | `1791350924548-fb884600-16d2-4ce6-a7d1-6a6584747dcf` | 362 passed |
| Functions/lint/build | `1791350768254-4fb5aafc-8c63-4052-9c91-52d3dde93644` | 324 passed |
| Firestore·Storage | `1791350834823-04879ad1-a8c9-4b27-bf8c-7cab285725ea` | 131 passed |
| Linux 실제 자원·OOM | `1791350929505-833392b6-f2b8-4f63-9d72-2e6c01116b90` | 2 passed |
| 제품 대기열/빌드2 | `1791351062534-a659aa8e-fd95-46ea-8615-b03ed12fee38` | 96 passed |

현재 Wdigest `87c232ee179117b8fd1efcd94a0b8c3ffe9eb487570f1a2e07c1852aa52fda91`. 각 source digest·원본 summary는 `continuation-local-gates.json`으로 연결했다. 최초W검사 `1791350767093-51988eb8-c5b0-47f9-87cc-ed81079a8174`는sandbox의 Chromium MachPort permission denied/HTTP listen EPERM으로9실패했으며 기준·소스 변경 없이 필요한 로컬 실행 환경에서 같은 검사를 통과했다. 실패 원본은 보존한다.

새 후보는 검증된 snapshot으로 Development0%에 배포 중이다. 새Lfaultcampaign `d4db3b5b-00c0-4384-b412-cc16a24f5254`; 기존Kfault는 보존하며 추가OOM대상이 없다. 실제 설정readback/로그인/새창/동일K재전달/L접수·124JPEG검사 전이므로 Q7 완료로 표시하지 않는다. 아래는 원래실행 결과다.

2026-10-07. campaign `845dae34-7aac-4108-a613-3944bcf44d6b`. 사용자 승인한 새K/L·제품최대8접수·20분·추가관리USD1/누적10 범위로 실행했다. **Q7 미완료**이며 자동 종료 정산·새 추출/재검토·수동 재시도·최종124JPEG는 아직 원격 통과가 아니다.

## 실제 수행·보존한 범위

- Worker `00025-nog`, image `sha256:bd9743f14dd86067dff21bc22c4cbaba5a3c1aebb3dbc48e6b554457c846a608`, 당시passed snapshot digest `d08b1647e3ef3be4c00e90c27a8b0d5dc1d5db06c2ef3976f983a9ee8c45b315`, candidate0%·base00012-fih100%,1CPU2GiB/min0/revisionmax1/concurrency2/900초를 확인했다. 4callable ACTIVE 및 expiry field index2개를 선택 배포했다. Production/IAM/자원증설/기존A~J 삭제 없음.
- 논리 접수는 **3건**이다: K브랜드 생성·목록, K2026SS 추출, K검토 승인. L은 생성/접수하지 않았다. 최초 준비 중단은 검토 대조용 jobID 누락이었다. 문서 경로ID를 연결하고 QV11 검사 뒤 같은2접수·같은실행창으로만 이어갔다. 서버 요청을 재전송하지 않았다.
- K브랜드 `ec9729848df2c4d4b5f73ba096efe0597515653ca8e73599ddd602fc12056c7f`; job `84e02140109a44db6d810ce90dfb962229c35568a3a729492980ae4180a98270`; execution `e4c6813a2ebc18339185f41903a032ad9bbfdf6631629c900c38641375f9b777`; 종료 승인batch `143c4aed5d47feb65aa733d3ba0a68cfe04aa81c6483794df37e9ccf4f445b30`, run=`batch-49`이다. job source/검토30후보/순서·해시는 기존fixture와 일치한 뒤 승인했다.
- 첫 커버thumb upload generation `1791346178310788`·9,981B를 소비한 일회성장치가 실제 OOM을 발생시켰다. 시스템 원문은 `Memory limit of 2048 MiB exceeded with 2248 MiB used.`와 `Container terminated on signal 9.`이다. trace `d1eceed3f19593c2db4e28b4f58da293`의 요청 로그가 같은 instance에 유일하게 연결됐다. 종료 insertID `6ac5c60d0003292fa07e15bf`를 읽기 전용 대조했다.
- 중단 readback: queue/batch/execution은active, attemptCount1·run1, 이전 run의 terminalConfirmed/inFlight를 임의 수정하지 않았다. exact execution 하위 writes6개(당시unpublished4/uploading2), 실제 객체12개·384,872B metadata/generation을 확인했다. posts30개는 준비됐으나 cover 공개경로는null이다. 완료된 룩북/성공124JPEG로 표시하지 않는다. 부분 파일/원장·브랜드·기존A~J는 보존한다.

## 자동 정산을 막은 결함과 수정

Cloud Logging의 logName은 URL 인코딩된 LOG_ID를 사용한다. 기존 provider의 `logName:"varlog/system"`은 실제K시스템로그0건을 반환했다. exact `logName="projects/outpick-test/logs/run.googleapis.com%2Fvarlog%2Fsystem"`은4건 중 실제종료2건을 반환했다. [공식LogEntry계약](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry).

`queue/cloud-logging-evidence.ts`를 exact 인코딩된 시스템로그로 수정하고 KR20을 필수로 추가했다. 실제코드를 기존 gcloud운영자 인증으로 실행해 exact old revision/trace/instance/insertID 플랫폼증거를 읽기 전용으로 얻었다. 로컬ADC로 최초조회한 `CLOUD_LOGGING_QUERY_FAILED` 원인과 Runtime 인증 성공을 같은 것으로 간주하지 않는다. 운영자조회는 Worker 자동정산을 수행한 것이 아니다. 수정코드는 아직새candidate에배포하지 않았다.

실행기 회귀는 QV11(jobID·확정2건만복원·미확정/만료차단)과 QV12(문서가없는assets부모 아래writes도정확execution범위에서조회)를 연결했다. SDK의 `assets.get()`은 부모문서없는하위writes를 놓치므로 bounded `listDocuments()`를 사용한다. 기존K종료후이어실행3건계약은 아직제안이며 현행 `--resume=true`는 승인전2건상태만허용한다.

클라이언트 신규투입을중지했고 서버task/queue/run을삭제·조작하지않았다. 중지신호 전에 메모리에 있던 최신조회수를저장하지못해 actualPollCount는미확정이다. manifest에남은6회는전체조회수로표시하지않는다. 기존Cloud Tasks 재전달은서버에서계속될수있으며HTTP503이시즌새시도1회와같은뜻이아니다. 정확한종료증거를처리하기전까지FIFO차단을유지한다.

## 배포·비용 원본

`output/lookbook-import-performance/product-queue-q7/845dae34-7aac-4108-a613-3944bcf44d6b/`의 report/manifest/journal, resume-original, interruption-readback, interrupted-assets-missing-parent-readback, runtime-logs-latest, termination-filter-before/after, read-only-provider-proof, deployment-service/revision, deployment-cost-inputs를 원본으로 보존했다. 제어문서 쓰기는 논리3접수와 별도다. 토큰·비밀번호는파일에저장하지않았다.

빌드실제duration Worker244.379초·공용Functions37.572초, 신규image/cache합계726,537,648B를확인했다. 무료량을차감하지않고빌드0.006/min·Artifact0.10/GiB-month·보수20분compute/기타여유로재계산하면 **약USD0.22 관리추정**이다. 실제청구액은미확정이고이미지1개월가정이다. 공유레이어·보관기간·기존무료량·SDK전송/과금사용량확정은별도다. 처음0.70은30분build·4GiB보관을둔시작전가정이며그것을실제지출로표시하지않는다.

Development cleanup asset/record스케줄러2개는미배포다.24시간실제삭제/12·14·15분경계/관리자웹화면은이번통과대상이아니다. 정리예약의서버연결도K자동재시도정산후원격확인이남았다.

## 남은 완료 조건

### 최종 수정 소스와 로컬 검사

- Worker362/lint/fixture/deploy passed `1791346980239-fa0f1f54-df09-45c1-a25f-618a41957c8d`, digest `dd843baa5ab5a8c78c165a1e14702788a40f88768e3dc95cecf85007d181e35e`; 제품96/build2 passed `1791347262222-a2a5f8a8-975d-4add-b0bd-098f17fb0b5c`, digest `a6ea775d3975b26bb73fedde2395e1d6d1fbbda53b92ebd7ad236eaf0132be96`; verifier36 passed `1791346788346-9228ec44-fbc9-45ea-99b7-2501b05fa6c7`, digest `3fd46c0643f18affea45153667f9f56c53a1aab40addffe7d10953f7d7cb0e15`.
- Functions324/lint/build 최종passed `1791348675613-84bdb833-ac0a-4e08-9c0a-931b6e9d5e2a`, digest `97b25fd0231dc3907a949b7fb5df8b845032644e70ebce31f994c1faace7fa35`; Linux실제OOM/자원2 최종passed `1791348680628-5abdcf02-8c3c-49d3-b9b9-2563446c0559`, digest `1611c26c820becefce24fe94a6442fd10eee16393f04e5b4099869577523f811`이다. Functions는verification전체, Linux는Worker전체를입력으로삼아최종소스를재검사했다. 수정후보원격배포·자동정산성공으로재사용하지않는다.
- W최초lint실패 `1791346505733-644c23e8-0b20-4c54-bd00-641c7b16d9d5`/`1791346793343-02dcab43-5796-4abe-b672-23b8b0f56502`는test one-var/quotes와production max-len을수정한뒤같은테스트362개로재검사했다. E `1791347149607-9d30eb92-3e91-43db-8365-0f6510a02884`는기존PQ03에서Emulator INVALID_ARGUMENT transaction 오류였다. 동일소스단독재검사96통과원본을보존했다.
- Rules `1791346793159-842a9bc1-9bb9-4b4f-8045-75ce71d42031`, `1791347482030-79c234e6-aed0-4953-b269-c2800edd6848`, `1791347817724-8d85732d-89a5-41e5-a316-cd57baad1eb2`는기존신고동시요청1건이 `Transaction is invalid or closed`로실패했다. 단일case1개및신고파일전체33개를새Emulator에서각각실행하면모두통과했다. 정확한내부잠금오류원인은확실하지않음이며제품신고서비스를임의수정하지않았다.
- 검사실행기 `firestore-tests/run-firestore-tests.mjs`가신고33개를새Emulator에서따로실행하고 `verification/firestore.json`에`transactions-reports`원본을추가했다. 기존rules/나머지transactions/신고전체의총131개·필수항목을유지하고suite실패·신호종료도실패로처리한다. 중간source `1791348196581-a00c7815-d649-4fcf-96b4-93bdb90d9fcb`와종료null처리보완후최종 `1791348368813-0ea75d96-5626-4314-9c04-1a4431e37c09` 모두131 passed다. 최종digest=`72c974f3208baee594ff0a56341b1670d92fc14ebdc19787278cc274f9f39eb5`. 진단통과가전체필수게이트를대체하지않는다.

수정소스필수게이트→기존K3접수에서이어가기·새revision/실행창계약확인→새0%candidate배포→old25의정확종료증거로동일execution새추출·새검토승인1→L의나머지4접수→총8접수/124JPEG/실패목록제거/원본5회이력/부분원장정리예약→문서·최종커밋이다. 원래20분창은임의연장하지않고 [이어실행안](q7-retry-development-continuation-plan.md)을제시한다. 중간이미지복원/새K브랜드/추가OOM은추가하지않는다.
