import Foundation

struct CloudFunctionResponseDecoder {
    let dictionary: [String: Any]

    static func dictionary(from value: Any?) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return dictionary
    }

    func nestedDictionary(_ key: String) throws -> [String: Any] {
        guard let value = dictionary[key] as? [String: Any] else {
            throw CloudFunctionsClientError.missingField(key)
        }
        return value
    }

    func dictionaries(_ key: String) throws -> [[String: Any]] {
        guard let value = dictionary[key] as? [[String: Any]] else {
            throw CloudFunctionsClientError.missingField(key)
        }
        return value
    }

    func string(_ key: String) throws -> String {
        guard let value = dictionary[key] as? String, !value.isEmpty else {
            throw CloudFunctionsClientError.missingField(key)
        }
        return value
    }

    func bool(_ key: String) throws -> Bool {
        if let value = dictionary[key] as? Bool {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.boolValue
        }
        throw CloudFunctionsClientError.missingField(key)
    }

    func int(_ key: String) throws -> Int {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.intValue
        }
        throw CloudFunctionsClientError.missingField(key)
    }

    func double(_ key: String) throws -> Double {
        if let value = dictionary[key] as? Double {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.doubleValue
        }
        throw CloudFunctionsClientError.missingField(key)
    }

    func optionalString(_ key: String) -> String? {
        guard let value = dictionary[key], !(value is NSNull),
              let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func optionalBool(_ key: String) -> Bool? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    func optionalInt(_ key: String) -> Int? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    func optionalDouble(_ key: String) -> Double? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    func date(_ key: String) throws -> Date {
        if let value = dictionary[key] as? TimeInterval {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        if let value = dictionary[key] as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue / 1_000)
        }
        throw CloudFunctionsClientError.missingField(key)
    }

    func optionalDate(_ key: String) -> Date? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        if let value = value as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue / 1_000)
        }
        if let value = value as? TimeInterval {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        if let value = value as? String {
            return ISO8601DateFormatter().date(from: value)
        }
        return nil
    }

    func stringArray(_ key: String) -> [String] {
        (dictionary[key] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
