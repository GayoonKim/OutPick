enum ChatMediaIndexRecordMapper {
    static func model(from record: ImageIndexRecord) -> ImageIndexMeta {
        ImageIndexMeta(
            roomID: record.roomID, messageID: record.messageID, idx: record.idx,
            thumbKey: record.thumbKey, originalKey: record.originalKey,
            thumbURL: record.thumbURL, originalURL: record.originalURL,
            width: record.width, height: record.height, bytesOriginal: record.bytesOriginal,
            hash: record.hash, isFailed: record.isFailed, localThumb: record.localThumb, sentAt: record.sentAt
        )
    }

    static func model(from record: VideoIndexRecord) -> VideoIndexMeta {
        VideoIndexMeta(
            roomID: record.roomID, messageID: record.messageID, idx: record.idx,
            thumbKey: record.thumbKey, originalKey: record.originalKey,
            thumbURL: record.thumbURL, originalURL: record.originalURL,
            width: record.width, height: record.height, bytesOriginal: record.bytesOriginal,
            duration: record.duration, approxBitrateMbps: record.approxBitrateMbps, preset: record.preset,
            hash: record.hash, isFailed: record.isFailed, localThumb: record.localThumb, sentAt: record.sentAt
        )
    }
}
