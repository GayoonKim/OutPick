//
//  MediaProcessingServiceProtocol.swift
//  OutPick
//
//  PHPicker로 선택된 미디어(이미지/비디오)를 채팅 전송에 적합한 형태로 "가공"하는 서비스
//  - ChatVC/VM은 MediaManager를 직접 알 필요 없음
//  - 이후 업로드/소켓 전송 UseCase로 분리하기 쉬워짐
//

import PhotosUI

/// PHPicker로 선택된 미디어(이미지/비디오)를 채팅 전송에 적합한 형태로 가공하는 서비스
protocol MediaProcessingServiceProtocol: AnyObject {
    /// 이미지 여러 장 가공 (썸네일 + 원본 안전 URL + 메타)
    func prepareImages(_ results: [PHPickerResult]) async throws -> [ProcessedImage]

    /// 기존 채팅 방 생성/편집 경로의 ProcessedImage 기반 API.
    func preparePairs(_ results: [PHPickerResult]) async throws -> [ProcessedImage]

    /// 단일 이미지 가공. 기존 프로필/브랜드 이미지 경로에서 사용한다.
    func makePair(
        from result: PHPickerResult,
        index: Int
    ) async throws -> ProcessedImage

    /// 비디오 1개 가공 (압축 + 썸네일 + 메타)
    func prepareVideo(_ result: PHPickerResult,
                      preset: VideoUploadPreset) async throws -> PreparedVideo
}
