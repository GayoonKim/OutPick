//
//  PreparedImage.swift
//  OutPick
//
//  채팅 전송을 위한 이미지 가공 결과 모델
//  - UI/업로드/소켓 전송 계층이 공통으로 쓰도록 표준화
//

import Foundation

struct PreparedImage: Sendable {
    let index: Int

    /// 앱이 소유한 임시 폴더로 복사된 원본 파일 URL (콜백 이후에도 안전)
    let originalFileURL: URL

    /// 전송/캐시용 썸네일 JPEG 데이터
    let thumbData: Data

    /// 원본 픽셀 크기
    let originalWidth: Int
    let originalHeight: Int

    /// 원본 파일 크기(bytes)
    let bytesOriginal: Int

    /// 파일 내용 기반 SHA-256 (중복 제거/캐시 키/스토리지 파일명용)
    let sha256: String

    /// 스토리지/캐시 키로 쓰기 쉬운 베이스 이름(현재는 sha256)
    var fileBaseName: String { sha256 }
}
