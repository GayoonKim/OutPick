# ADR-016: 채팅 미디어 업로드는 얇은 reservation과 메시지 ready projection으로 처리한다


상태: accepted

결정:

- 채팅 이미지/비디오 업로드는 `Rooms/{roomID}/MediaUploads/{messageID}` reservation 문서와 `Rooms/{roomID}/Messages/{messageID}` ready projection 문서로 나눈다.
- `MediaUploads` 문서는 업로드 상태 머신이 아니라 업로드 예약, finalize 검증, TTL cleanup manifest 역할만 담당한다.
- `Messages` 문서는 서버 검증이 끝난 표시 가능 메시지다. 메시지 문서가 없으면 아직 확정되지 않은 업로드로 본다.
- 메시지 문서에는 별도 `mediaStatus`를 추가하지 않는다.
- successful finalize 후 reservation 문서는 즉시 삭제한다.
- `completedAt` 문서를 남겨 TTL로 나중에 삭제하지 않는다.
- TTL cleanup은 `expiresAt`이 지난 pending reservation만 대상으로 한다.
- 이미지 메시지는 한 메시지에 여러 attachments를 허용한다.
- 클라이언트는 `PickerConst.maxImagesPerMessage` 기준으로 이미지를 청크로 나눠 메시지 여러 개로 전송한다.
- 서버는 같은 한 메시지당 attachment 상한을 검증한다. 상한 초과 payload는 조용히 자르지 않고 명시적으로 거절한다.
- 비디오 메시지는 한 메시지에 비디오 1개만 허용한다.
- 이미지와 비디오는 한 메시지에 섞지 않는다.
- `chat:mediaPreflight`는 room 참여 권한, socket join 상태, sender, `kind`, `attachmentCount`를 검증하고 final Storage prefix를 예약한다.
- `chat:mediaFinalize`는 reservation, attachment count, path prefix, contentType, size를 검증한 뒤에만 메시지 문서를 생성하고 socket broadcast를 수행한다.
- duplicate finalize는 idempotent하게 처리한다. 이미 `Messages/{messageID}`가 있으면 기존 메시지를 성공 ACK로 반환한다.
- 전체 Storage sweep은 기본 cleanup 전략으로 사용하지 않고, 운영/성장 이후 dry-run audit 후보로만 둔다.

이유:

- 클라이언트가 final Storage path에 직접 업로드하더라도, 서버 검증 전 파일을 사용자에게 노출하지 않아야 한다.
- 메시지 문서 생성 자체를 ready 상태로 보면 채팅 렌더링 모델이 단순해지고 `uploading/failed/expired` 같은 전송 상태가 서버 메시지 도메인에 섞이지 않는다.
- 성공한 reservation을 즉시 삭제하면 대량 트래픽에서 불필요한 Firestore 문서와 인덱스 항목이 쌓이지 않는다.
- TTL은 정상 성공 경로를 정리하는 장치보다 앱 종료, 네트워크 실패, finalize 미호출 같은 비정상 경로의 안전망으로 쓰는 편이 명확하다.
- 서버가 초과 attachments를 조용히 잘라내면 일부 파일만 메시지에 연결되고 나머지는 Storage 고아 파일로 남을 수 있다.
- 클라이언트 제한은 UX를 위한 것이고, 서버 제한은 보안과 정합성 계약이다.

트레이드오프:

- preflight/finalize 계약에 `attachmentCount`와 path 검증이 추가되어 서버 검증 로직이 조금 복잡해진다.
- Swift와 Socket 서버의 한 메시지당 이미지 상한값을 완전히 공유하기 어렵기 때문에 문서와 테스트로 계약을 고정해야 한다.
- successful reservation을 즉시 삭제하면 완료 이력은 남지 않는다. finalize 디버깅은 socket 로그, message 문서, 실패 reservation 로그를 기준으로 한다.
- 메시지 문서가 생성되기 전 업로드 진행 상태는 서버 메시지 목록이 아니라 로컬 pending/outbox UI가 담당한다.

재검토 조건:

- 비디오 트랜스코딩, 바이러스/정책 스캔, HLS 산출물 생성처럼 서버 처리 단계가 길어지면 `MediaUploads`를 상태 머신 또는 별도 `MediaAssets` 모델로 확장한다.
- 미디어가 채팅 외 도메인에서 재사용되기 시작하면 공용 `MediaAssets` 문서를 도입할지 검토한다.
- 대량 Storage cleanup이 Functions scheduler 범위를 넘어서면 Cloud Run worker 또는 dry-run audit job을 검토한다.
- 운영 디버깅에서 successful upload 이력이 반복적으로 필요해지면 completed reservation 단기 보관 또는 별도 관측 로그를 검토한다.

