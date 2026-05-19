import Foundation
import GRDB

// Domain Model + GRDB Record
struct UserProfile: Codable, Hashable, Equatable, FetchableRecord, PersistableRecord {
    var deviceID: String?
    var email: String
    var gender: String?
    var birthdate: String?
    var nickname: String?
    var thumbPath: String?
    var originalPath: String?
    var joinedRooms: [String]
    let createdAt: Date

    init(
        deviceID: String? = nil,
        email: String,
        gender: String? = nil,
        birthdate: String? = nil,
        nickname: String? = nil,
        thumbPath: String? = nil,
        originalPath: String? = nil,
        joinedRooms: [String] = [],
        createdAt: Date = Date()
    ) {
        self.deviceID = deviceID
        self.email = email
        self.gender = gender
        self.birthdate = birthdate
        self.nickname = nickname
        self.thumbPath = thumbPath
        self.originalPath = originalPath
        self.joinedRooms = joinedRooms
        self.createdAt = createdAt
    }

    // MARK: - GRDB
    static let databaseTableName = "userProfile"

    enum Columns: String, ColumnExpression {
        case deviceID
        case email
        case gender
        case birthdate
        case nickname
        case profileImagePath   // 레거시 컬럼(있다면), 현재 모델에 없지만 마이그레이션 호환용
        case thumbPath
        case originalPath
        case joinedRooms
        case createdAt
    }

    // Upsert-friendly
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    // MARK: - Row -> Model
    init(row: Row) {
        self.deviceID = row[Columns.deviceID]
        self.email = row[Columns.email]
        self.gender = row[Columns.gender]
        self.birthdate = row[Columns.birthdate]
        self.nickname = row[Columns.nickname]
        self.thumbPath = row[Columns.thumbPath]
        self.originalPath = row[Columns.originalPath]

        let joinedRoomsJSON: String? = row[Columns.joinedRooms]
        if let joinedRoomsJSON,
           let data = joinedRoomsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.joinedRooms = decoded
        } else {
            self.joinedRooms = []
        }

        self.createdAt = row[Columns.createdAt]
    }

    // MARK: - Model -> DB
    func encode(to container: inout PersistenceContainer) {
        container[Columns.deviceID] = deviceID
        container[Columns.email] = email
        container[Columns.gender] = gender
        container[Columns.birthdate] = birthdate
        container[Columns.nickname] = nickname
        container[Columns.thumbPath] = thumbPath
        container[Columns.originalPath] = originalPath

        // joinedRooms는 TEXT 컬럼에 JSON 문자열로 저장
        if let data = try? JSONEncoder().encode(joinedRooms),
           let json = String(data: data, encoding: .utf8) {
            container[Columns.joinedRooms] = json
        } else {
            container[Columns.joinedRooms] = "[]"
        }

        container[Columns.createdAt] = createdAt
    }
}
