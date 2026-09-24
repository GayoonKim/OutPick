# ③ 캐시 재사용·취소·파일 수명 — 세부 구현 계획

> Phase3·4 구현 및 자동83개 통과, 실기기 QA 대기. [최신 결과](original-media-results.md).

> 2026-09-24 Phase3 구현 재개 승인. 원본은 계정별 보관/같은 계정 재로그인 재사용으로 사용자 확정. 로그아웃은 소비자·세대 무효화, 새 원본 namespace의 전체 계정 합산 QA 기본 예산은 512MiB. 7일 만료 연결은 별도 후속이다. 아래 과거의 정리만/구현 전 상태보다 이 기록이 우선한다.

> 최신 상태: Phase1·2와 추가 표시 준비 개선은 구현/최종 실기기 QA 완료. 다음은 Phase3·4 및 관련 통합 QA다. [새 스레드 인계](original-media-handoff.md)를 우선 읽는다. 표시 예산은 메모리/디스크 각1GiB(디스크 trim900MiB), 현재 메시지 전체 디스크 준비·직접 decode/IO 동시 제한 기본 해제가 확정됐으므로 아래 초기 수치 미정/상한 보존 문구보다 최신 인계가 우선한다. 원본 파일 예산은 별도 재확인 대상. 사용자 현재 요청은 정리만이며 이 턴에서는 후속 구현하지 않는다.

2026-09-22 사용자 요청으로 작성. **2026-09-23 사용자 승인으로 Phase1 원인 계측→Phase2 캐시 재사용 개선 착수.** 기존 사용자 동작·계정별 보존 정책을 바꿔야 하는 발견은 해당 부분 구현 전에 논의한다.② 필수 잔여 검증은 완료됐다. Phase3~5 전체 구현 완료를 뜻하지 않는다.

## 범위와 확정 계약

- 전송 직후와 원격 수신의 표시 캐시 재사용을 안정화하고 원본 파일의 저장 공간·소비자 수명을 분리한다. 서버 API/Storage 업로드 규격/DTO는 이번 기본 범위에서 변경하지 않는다.
- 현재 업로드와 수신1024px decode를 출발점으로 유지한다. 업로드 해상도 변경, 표시 파일 추가 재인코딩, 메모리 크기 버킷, 캐시 용량의 최적값은 실기기 QA 결과로 결정한다. 구조 개선 효과와 수치 변경 효과를 섞지 않는다.
- 디스크 표시 파일은 단일 큰 사진 버블의 화질을 만족하는 공통 기준을 검토한다. 작은 묶음용 별도 디스크 파일은 기본 범위에 없다.
- 표시 실패는 실제 이탈 후 재등장/방 재진입 시 재시도한다. 화면 재설정만으로 자동 재시도하지 않는다.
- 사진 원본은 현재 페이지 및 바로 앞뒤 각1페이지의 정적 사진만 요청한다. GIF/영상 페이지를 건너뛰어 더 먼 사진까지 범위를 넓히지 않는다. GIF/영상 원본은 실제로 열 때만 요청한다.
- 저장은 원본 파일 사용, 실패 시 명시적 재시도. **확대 화면을 닫으면 저장 소비자의 다운로드·준비 작업을 취소하고 완료/실패 안내를 하지 않는다.** 다른 소비자가 있는 공유 전송은 유지한다. Photos API에 이미 제출된 취소 불가능한 작업 또는 완료된 저장은 되돌릴 수 있다고 약속하지 않는다. 제출 직전 취소/세대 검사로 경계를 좁힌다.
- 영상은 전체 파일 수신을 기다리지 않고 재생을 시작한다. 기존 캐시가 있으면 파일을 재사용한다. 원격 스트리밍과 별도 전체파일 다운로드를 자동으로 동시에 시작하지 않는 구조를 우선 검토한다. 스트리밍 바이트의 완전 병합을 요구하는 custom resource loader는 기본 범위에 넣지 않는다.
- 준비된 표시 이미지의 캐시 쓰기는 셀 이탈과 독립적으로 소유한다. 단, 메시지 삭제·계정 세대 무효화는 늦은 저장도 차단한다. 앱 종료 후 완료 보장은 없다.

## 의존성과 변경 지도

기존 MVVM-C/Repository/UseCase/DI를 유지한다. 공용 pipeline API와 캐시 저장소 경계를 공유하므로 모든 Phase는 순차 구현한다. ② network/files/io 분리와 상한을 보존하며③에서 입장 수명을 바꿀 필요가 생기면② 계약을 먼저 재검토한다.

| 경계 | 예상 파일 | 변경 책임 |
| --- | --- | --- |
| 표시 수요·즉시 hit | `OutPick/Features/Chat/Services/ImageLoading/ChatMediaViewportController.swift`, `ChatAttachmentImageLoading.swift`, `ChatAttachmentImageService.swift`, `OutPick/Features/Chat/Controllers/ChatViewController+MediaViewport.swift` | 캐시 즉시 조회, loading 전 hit 반영, 실패 회차/세대 보존 |
| 저장·병합 | `OutPick/Infra/Cache/ImageCache/ImageCachePipeline.swift`, `ImageLoadCoordinator.swift`, `ImageCachePersistence.swift`, `ImageCacheDiskStore.swift`, `ImagePipelineProcessor.swift` | key별 pending 저장 합류, 쓰기 결과·취소·무효화 계약 |
| 원본 파일 | 채팅 서비스 아래 신규 원본 파일 store/service 및 protocol(명칭은 구현 전 확정), `ChatAttachmentImageService.swift` | 전송 병합, 파일 lease, 독립 namespace·예산·접근 시각 |
| 확대·저장 | `OutPick/Infra/Media/ImageViewer/SimpleImageViewerVC.swift`, `OutPick/Infra/Media/PhotoLibrarySaver.swift`, `OutPick/Features/Chat/Controllers/ChatViewController.swift` | ±1 수요, 원본 파일 저장, 닫기 취소·세대 차단 |
| 영상 | `OutPick/Features/Chat/Services/MediaPreview/ChatMediaPreviewServices.swift`, `OutPick/Features/Chat/Managers/Implementations/OPVideoDiskCache.swift`, `ChatVideoPlayerViewController.swift` | 원격 즉시 재생, 불필요한 detached 전체 다운로드 제거/수명 연결, 저장 소비자 |
| 조립·삭제 | `ChatContainer`, `ChatCoordinator`, `ChatDeletionSyncUseCase`, `AccountDeletionLocalDataScrubber`, 실제 계정 전환 연결부 | 공유 store 주입, 화면 수명 전달, 새 namespace 무효화 |

파일명만 표시한 항목은 ENTRYPOINTS의 현재 위치와 실제 참조를 Phase 시작 때 재확인한다. 공용 뷰어를 쓰는 룩북/아바타/갤러리에는 기존 initializer/adapter 호환을 유지하고 별도 사용자 흐름을 임의 변경하지 않는다.

## Phase 1 — 기준선과 재사용 원인 계측

- 목표: memory hit/loading, disk hit/decode 대기, 실제 재다운로드를 구분한다.
- 변경 범위: 기존 `ImageCacheMetrics` 및 viewport/service의 DEBUG 관찰 지점, 필요한 fake 기반 테스트. 원문 경로·토큰·사진 내용 로그 금지.
- 구현: 동일 resource의 저장/조회 key hash를 연결하고 source(local preserve/remote), write queued/success/failure/cancel/stale, eviction reason, read/decode wait와 실행 시간, pending 합류를 기록한다. 기존 disk key prefix hash와 resource hash의 차이를 연결 ID로 해소한다.
- 완료 기준: 한 번 표시한 사진이 왜 재로딩됐는지 저장·퇴거·조회·전송 흐름으로 설명 가능. 취소/미완료를 실패로 오집계하지 않음.
- 검증: fake 경합 검증 및280장 왕복/재진입/재실행 기준선. 기존 캐시를 임의 삭제하거나 메시지를 전송하지 않는다. 실기기 자료 접근/새 표본이 필요하면 구체 범위를 확인한다.
- 논의 필요: 크기·용량 변경 없음. 계측으로 기존 추정과 다른 원인이 나오면 후속 범위만 갱신한다.

## Phase 2 — 표시 캐시 hit와 독립 저장 수명

- 목표: memory hit에 불필요한 placeholder를 내보내지 않고, 저장 중 재등장으로 중복 다운로드하지 않는다.
- 변경 범위: 표시 수요/service API, 공용 coordinator/persistence/disk의 최소 계약 및 회귀 테스트.
- 구현: remote memory의 즉시 조회를 좁은 API로 노출한다. 로컬 파일 읽기를 동기 hit API에 숨기지 않는다. 준비 이미지→memory 반영→key별 제한된 비동기 저장으로 전송 확정/원격 경로의 소유권을 맞춘다. 저장 Task가 payload/lease를 소유하고 완료/실패 때 반환한다. memory miss 시 동일 key/version pending 쓰기 또는 준비 결과에 합류한 뒤 캐시를 다시 확인한다. 전역 flush를 모든 조회의 선행 조건으로 두지 않는다.
- 실패 정책: 표시 성공은 유지하며 저장 실패 사유를 반환·기록한다. 실패한 저장을 무한 반복하지 않고 다음 수요의 제한된 재시도로 복구한다. 최종 retry 횟수/간격은 QA 조정값으로 둔다.
- 완료 기준: 범위 내 memory hit는 loading 없이 표시, disk hit는 다운로드0, 저장 지연 중 재조회도 전송 중복0, 셀 이탈 후 쓰기 완료 및 삭제/세대 변경 후 부활0.
- 검증: 기존 viewport/coordinator/revision 테스트 보강. 메모리 강제 퇴거+write hold, 실패/취소, 두 소비자, 삭제 역순 도착을 deterministic barrier로 검증한다. 공용 아바타/룩북 회귀 포함.
- 논의 필요: 파일 크기 정책은 현행 유지. 저장 pending 보유는 기존 files/byte 상한을 넘지 않도록 하고 API 변경 전에 교착 경로를 검토한다.

## Phase 3 — 원본 파일 lease와 표시 캐시 분리

- 목표: 원본 요청이 표시 파일 예산을 소모하지 않고 실제 원본 파일을 재사용한다.
- 변경 범위: 원본 service/store, 채팅 Container 조립, 삭제·계정 수명 연결. 서버 계약 변경 없음.
- 구현: acquireOriginal(resource,purpose) 결과는 파일 URL과 명시적 해제 수명을 제공한다. key/version별 전송 합류, 소비자별 취소, 마지막 소비자 종료 시 전송 취소, SDK 종료 확인 후 permit 반환. 재생/저장 중 파일은 퇴거에서 제외한다. 캐시 수용 한도를 넘는 파일은 임시 사용 후 해제하는 선택지를 명시해 무제한 누적을 피한다. 실제 한도·형식별 분할은 QA 후 확정한다.
- 기존 파일: 새 저장소가 구캐시와 무제한 중복되지 않게 합산 사용량을 관측한다. 필요한 항목만 재사용하고, 축소 JPEG가 섞일 수 있는 기존 캐시를 검증 없이 원본으로 승격하지 않는다. outbox/사용자 원본 보호 파일은 캐시 정리 대상에서 제외한다.
- 완료 기준: preview가 original API로 반환되지 않음, 한 소비자 취소로 다른 소비자 파일이 사라지지 않음, 삭제·로그아웃/계정 전환 후 이전 결과 재사용0, lease 해제 후 임시파일 잔여0.
- 검증: fake transport/store의 공유·취소·실패·용량 초과·핀·세대 경합. 계정 삭제와 실제 전환 호출 지도 확인.
- 논의 필요: 예산 수치는 QA에서 조정하되 구현 시 유한 기본값을 문서화한다. 계정별 보존/정리 동작이 기존과 달라지는 경우 구현 전에 확정한다.

## Phase 4 — 확대·저장·영상 수명 연결

- 목표: 확정한 사용자 흐름을 원본 소비자 수명에 연결한다.
- 변경 범위: 공용 뷰어 adapter, 채팅 VC/Coordinator, PhotoLibrarySaving 파일 API, 영상 resolver/player.
- 구현: 현재+인접 정적 사진 원본 요청, 범위 밖 소비자 취소. GIF frame/영상 player는 활성 페이지/화면에서 해제한다. 저장은 원본 파일 준비→취소 확인→Photos 제출 순서, 뷰어 닫기는 저장 소비자를 취소하고 후속 UI를 차단한다. 이미 제출된 시스템 저장의 취소 가능성은 API 확인 후 한계를 명시한다. 원격 영상은 바로 재생하고 전체파일 캐시 miss 시 detached 다운로드를 무조건 중복 실행하지 않는다. 저장/명시적 파일 획득은 동일 파일 요청을 공유한다.
- 완료 기준: 원본 파일 저장과 GIF animation 유지, 실패 재시도, 닫기 후 안내0/불필요 소비자0, GIF/영상 주변 원본 선로딩0, 플레이어 재생 시작에 전체파일 대기 없음.
- 검증: 파일 준비 전/중/후 닫기, 공유 저장 소비자, 빠른 페이지 왕복, 취소 뒤 늦은 성공, 저장 권한/실패 fake. Photos 실제 저장·영상 시작·GIF는 실기기 QA.
- 논의 필요: 원격 스트리밍과 저장의 네트워크 바이트 완전 병합은 보장하지 않는다. 즉시 재생을 유지하면서 이를 완전히 합치는 별도 스트리밍 캐시가 필요하다고 측정되면 추가 설계한다.

## Phase 5 — 280장 QA와 정책 조정·완료 판정

- 목표: 동일 사진의 반복 수요에서 불필요한 다운로드를 없애고 디스크 재표시 지연을 줄인다.
- 변경 범위: 계측 결과/수치/표시 파일 정책과 관련 코드만 근거에 따라 조정. 업로드 변경은 자동 포함하지 않는다.
- 시나리오: 단일 큰 사진·가로 화면 화질, 작은 묶음, 실제 사진의 큰 JPEG→1024 대비 작은 JPEG 디코딩,280장 왕복·방 재진입·앱 재실행, 확대 전후 비교. memory/disk/pending/network를 별도 집계하고 실제 RSS·프레임·대기시간·저장용량을 측정한다.
- 완료 기준: 캐시 수용 범위 내 동일 key/version의 반복 수요에 불필요한 전송0. 정상 퇴거는 사유·대상으로 설명 가능. 첫 표시와 저장 완료를 분리하며 자원 누수/파일 누적/화질 회귀 없음. 모든280장의 메모리 상주나 영구 보존을 보장하는 기준은 아니다.
- 결정 항목: 원문 디스크 유지/큰 파일만 변환, 표시 상한, 묶음 메모리 버킷, NSCache/LRU, 표시/원본 예산과 합산 migration 예산. 수치는 QA 후 개선한다는 사용자 합의를 보존한다.
- 검증: 영향받은 자동 회귀 후 실기기 비교. 동일 조건 미확보/검증 불가 항목은 완료로 표시하지 않는다. 전체 캐시 삭제나 새 다운로드 표본 강제 생성은 기존 사용자 제한을 지킨다.
- 논의 필요: UX·서버·업로드 계약 변경이 필요한 결과가 나오면 근거와 대안을 사용자에게 제시한다.

## 하네스·완료 관리

각 Phase 종료 시 변경 파일·결정·실행 검증·남은 위험을 기록한다. 구현 변화마다 `docs/ai/ENTRYPOINTS.md`, `entrypoints/CHAT.md`, `entrypoints/TESTS.md` 및 데이터/API/DI 계약을 최신화한다. 사용자 변경 보존, 임의 커밋/서버 배포 없음. 이 계획의 작성은③ 구현 승인으로 취급하지 않는다.
