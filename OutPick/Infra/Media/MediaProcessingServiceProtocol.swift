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
    func prepareImages(_ results: [PHPickerResult]) async throws -> [PreparedImage]

    /// 비디오 1개 가공 (압축 + 썸네일 + 메타)
    func prepareVideo(_ result: PHPickerResult,
                      preset: DefaultMediaProcessingService.VideoUploadPreset) async throws -> PreparedVideo
}
