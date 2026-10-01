# 다음 핵심 작업: 전송 시점 + 7일 미디어 만료

> **2026-10-01 완료 갱신:** 후속 채팅 미디어 만료 구현과 합의된 개발 QA를 완료했다. [최종 계약·검증·운영 주의사항](../../architecture/CHAT_MEDIA_RETENTION.md)을 따른다. 아래는 이전 PR에서 남긴 설계 착수 전 인계 기록이며 현재 미구현 상태를 뜻하지 않는다.


2026-09-24 사용자 확정. **이번 PR에는 만료 구현을 포함하지 않는다. 다음 작업은 설계 하네스부터 시작한다.**

## 확정한 제품 계약

- 메시지 전송 시점 + 7일이 하나의 만료 시각이다. 처음 보기/다운로드/캐시 생성/재다운로드/로그인 시각으로 연장하지 않는다. 전송 6일 뒤 처음 캐시하면 남은 1일만 유효하다.
- Storage의 해당 첨부 썸네일과 원본, 앱의 디스크 및 메모리 캐시를 동일 만료 기준으로 정리한다.
- 만료된 미디어는 캐시가 남아 있어도 표시·열기·저장에 사용하지 않는다. 실행 중 경계 도달과 다운로드/디코딩/저장 중 만료도 설계에 포함한다.
- 앱이 꺼져 있어 로컬 삭제가 불가능하면 다음 실행/복귀 시 정리한다. 서버 물리 삭제 작업이 지연돼도 접근/표시 만료를 별도로 보장하는 방식을 검토한다.
- 로그아웃/계정 전환은 미만료 계정별 원본 캐시를 보관하고, 같은 계정 로그인 시 재사용한다. 만료는 로그아웃 계정의 보관 캐시에도 적용한다.
- 사용자가 사진 앱에 직접 저장한 사본은 삭제 대상이 아니다. 이미 Photos에 제출한 작업을 되돌릴 수 있다고 약속하지 않는다.
- 용량 LRU로 7일 이전에 캐시가 퇴거될 수 있다. 7일은 보관 보장이 아니라 유효기간 상한이다.

## 다음 세션 시작 순서

1. 이 문서 → `original-media-results.md` → `docs/ai/ENTRYPOINTS.md`/`entrypoints/CHAT.md`를 읽는다.
2. 실제 서버 전송 시각/첨부 경로/로컬 DTO와 삭제 동기화 계약을 필요한 범위만 확인한다.
3. 아래 미확정 항목을 사용자와 논의한 뒤 요구사항·흐름·API·데이터·아키텍처 설계 문서를 작성한다.
4. 설계 승인 후 phase별 변경 범위/완료 기준/검증 계획을 확정한다. 이번 인계만으로 서버 삭제·마이그레이션·배포를 실행하지 않는다.

## 설계 시 결정할 항목

- 전송 기준의 권위 있는 서버 시각 필드와 `expiresAt` 계산 위치. 전송 재시도/예약/최종 확정 시각 중 실제 계약 확인 필요.
- 만료 후 채팅 메시지 자체를 유지할지, 만료 안내와 재시도/저장 버튼을 어떻게 표현할지. 텍스트·인용·공유 카드·갤러리 범위는 미확정이다.
- 기존 메시지/캐시의 만료 정보 마이그레이션, 전송 시각 없는 구캐시 처리. 원본 파일명만으로는 전송 시각을 알 수 없다.
- 서버 삭제 실행 주기/재시도/부분 실패/중복 실행, 실제 만료 후 삭제 완료까지 허용 지연.
- 오프라인·기기 시계 변경·서버 시각 오차와 만료된 다운로드 URL 접근 차단. Storage 규칙/토큰 URL의 실제 보안 계약을 별도 확인한다.
- 재생 중/확대 중/Photos 제출 직전·직후 만료의 사용자 흐름과 lease 해제 순서.
- 동일 객체를 여러 메시지가 참조할 때 삭제 소유권. 원본/썸네일 하나만 삭제된 부분 실패 복구.

## 관련 진입점

- 업로드/전송 확정: `functions/src/chat/media/{functions,contracts,orchestrationService,readyService,runtime}.ts`, `OutPick/Features/Chat/Domain/UseCases/ChatMediaUploadUseCase.swift`.
- 서버 기존 삭제: `functions/src/chat/cleanup/`, `functions/src/chat/deletion/`, `functions/src/chat/moderation/mediaStorageTargets.test.ts`. 실제 재사용 가능한 경계는 다음 설계 때 확인한다.
- 원본: `OutPick/Features/Chat/Services/OriginalMedia/ChatOriginalFile{,Store,Disk,Transport}.swift`. 계정/path/version 키, 512MiB 합산, pin·세대·삭제 tombstone. 현재 TTL/전송 시각 metadata 없음.
- 표시 캐시: `ChatAttachmentImageService`, `ImageCachePipeline`, `ImageLRUMemoryStore`, `ImageCacheDiskStore`, `ChatMediaViewportController`. 표시 캐시와 원본 저장소를 모두 다뤄야 한다.
- 삭제 연동: `ChatDeletionSyncUseCase`/`DefaultChatDeletionMediaCleaner`, `AccountDeletionLocalDataScrubber`. 만료를 사용자 메시지 삭제/탈퇴와 혼동하지 않는다.
- 소비자: `SimpleImageViewerVC`, `DefaultChatVideoPlaybackResolver`, 두 영상 VC, `DefaultPhotoLibrarySaver`, `PhotoLibraryPreparedResource`.
- 계정 연결: `AppCoordinator.showLogin/ensureChatContainer` → `ChatContainer.invalidateMessageCacheSession`.

## 검증 설계 후보

주입 가능한 시계와 fake repository/transport로 전송6일 뒤 첫 다운로드→7일 경계 만료, 재로그인/재다운로드 기한불변, 만료 중 전송 늦은 성공 차단, pin 사용 중 표시 차단/해제 후 삭제, 로그아웃 계정 정리, 서버 부분 실패/재시도/중복 실행을 검증한다. 운영 자료 삭제 대신 emulator/전용 fixture 사용 범위를 승인받는다.

현재 미디어 로딩·원본 저장·계정 재사용 결과는 `original-media-results.md`, 이번 PR 리뷰는 `review.md`에 남긴다. 기존 미디어 캐시를 임의로 전부 지워 검증하지 않는다.
