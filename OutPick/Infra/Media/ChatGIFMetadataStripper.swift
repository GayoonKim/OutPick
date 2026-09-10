import Foundation

/// 픽셀 LZW 블록과 타이밍은 그대로 두고 설명/애플리케이션 메타데이터만 제거한다.
enum ChatGIFMetadataStripper {
    static func stripped(_ input: Data) throws -> Data {
        let bytes = [UInt8](input)
        guard bytes.count >= 14,
              ["GIF87a", "GIF89a"].contains(String(bytes: bytes.prefix(6), encoding: .ascii) ?? "") else {
            throw MediaError.failedToConvertImage
        }
        var cursor = 13
        func advance(_ count: Int) throws {
            guard count >= 0, cursor + count <= bytes.count else { throw MediaError.failedToConvertImage }
            cursor += count
        }
        func blocks() throws {
            while true {
                guard cursor < bytes.count else { throw MediaError.failedToConvertImage }
                let count = Int(bytes[cursor])
                try advance(1)
                if count == 0 { return }
                try advance(count)
            }
        }
        if bytes[10] & 0x80 != 0 { try advance(3 * (1 << (Int(bytes[10] & 7) + 1))) }
        var output = Data(bytes[0..<cursor])
        while cursor < bytes.count {
            let start = cursor
            let type = bytes[cursor]
            try advance(1)
            switch type {
            case 0x3B:
                output.append(type)
                return output
            case 0x2C:
                try advance(9)
                let packed = bytes[cursor - 1]
                if packed & 0x80 != 0 { try advance(3 * (1 << (Int(packed & 7) + 1))) }
                try advance(1)
                try blocks()
                output.append(contentsOf: bytes[start..<cursor])
            case 0x21:
                guard cursor < bytes.count else { throw MediaError.failedToConvertImage }
                let label = bytes[cursor]
                try advance(1)
                let payload = cursor
                try blocks()
                let application = payload + 12 <= cursor && bytes[payload] == 11
                    ? String(bytes: bytes[(payload + 1)..<(payload + 12)], encoding: .ascii) : nil
                // Graphic Control과 루프 정보는 애니메이션 의미를 보존한다.
                if label == 0xF9 || (label == 0xFF && ["NETSCAPE2.0", "ANIMEXTS1.0"].contains(application ?? "")) {
                    output.append(contentsOf: bytes[start..<cursor])
                }
            default:
                throw MediaError.failedToConvertImage
            }
        }
        throw MediaError.failedToConvertImage
    }
}
