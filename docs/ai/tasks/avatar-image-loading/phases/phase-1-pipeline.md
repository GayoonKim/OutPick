# Phase 1 — 공용 비저장 요청과 디스크 승격

## 목표·선행 조건

Phase0 계약 확정 후 아바타가 공용 제한을 유지하면서 원본을 캐시 없이 반환하고, 메모리 썸네일을 영속 보관으로 승격할 수 있게 한다.

## 변경 파일 후보

- OutPick/Infra/Cache/ImageCache/{ImageCachePipeline,ImageLoadCoordinator,ImageRequest,ImagePipelineProcessor,ImageCachePersistence,ImageCacheDiskStore}.swift
- 필요한 경우 새 정책/승격 소유권 파일을 위 폴더에 분리한다. 확정한 표현·저장 계약을 최소 API로 노출한다.
- OutPickTests/{ImageLoadCoordinatorTests,ImageCacheRevisionTests,ImagePipelineResourcesTests}.swift 및 새 ImageCacheStorePolicyTests.swift 후보.

## 구현 순서

1. 기본 memoryAndDisk 호출 호환을 유지하고 비저장 요청의 cache read/write 차단·identity를 정의한다. storesOnDisk 하나만으로 원본 미저장을 표현하지 않는다.
2. 메모리 hit는 화면에 즉시 반환하면서 승격 작업을 단일화한다. Phase0에서 합의한 payload 생성/예산만 사용하고 표시를 디스크 쓰기 완료에 묶지 않는다.
3. 원본 비저장도 processor/resources·SDK 취소를 사용한다. 완료·실패·마지막 소비자 취소에서 payload/임시 파일/permit을 정확히 반환한다.
4. remove/clear/세션 변경이 승격·지연 쓰기보다 우선하도록 세대 검사한다. 작업 중 정책 합류와 완료 후 승격을 모두 다룬다.

## 완료 기준·검증

- memory-only 신규 쓰기0·기존 disk 읽기 허용, memoryAndDisk 승격, 비저장 원본 cache read/write0.
- 같은 호환 요청20개 단일 fetch, 소비자 일부 취소는 나머지 유지, 마지막 취소 실제 transport 해제.
- 메모리 hit 표시가 저장 작업을 기다리지 않음. 승격 중 remove/전체 clear 후 재저장0.
- 새 정책 fake 테스트와 기존 공용 경합 회귀 실행·Development build-for-testing 통과. 기존 룩북 HTTP 경로 기본값 회귀 확인.

## 논의 필요 사항·충돌

Phase0 승격 방식/한도 결정 선행. 공용 기반 변경이므로 룩북·Room·첨부 서비스까지 영향을 줄 수 있다. 동일 파일을 병렬 구현하지 않고 이 phase를 완료한 뒤 서비스 확장한다.
