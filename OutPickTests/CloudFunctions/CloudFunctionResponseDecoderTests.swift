import Foundation
import Testing
@testable import OutPick

struct CloudFunctionResponseDecoderTests {
    @Test func rejectsNonDictionaryTopLevelResponse() {
        #expect(throws: CloudFunctionsClientError.invalidResponse) {
            try CloudFunctionResponseDecoder.dictionary(from: ["invalid"])
        }
    }

    @Test func decodesNSNumberAndOptionalNullValues() throws {
        let decoder = CloudFunctionResponseDecoder(dictionary: [
            "bool": NSNumber(value: true),
            "int": NSNumber(value: 7),
            "double": NSNumber(value: 1.5),
            "null": NSNull()
        ])

        #expect(try decoder.bool("bool"))
        #expect(try decoder.int("int") == 7)
        #expect(try decoder.double("double") == 1.5)
        #expect(decoder.optionalString("null") == nil)
    }

    @Test func decodesMillisecondAndISO8601Dates() throws {
        let decoder = CloudFunctionResponseDecoder(dictionary: [
            "required": NSNumber(value: 2_000),
            "optional": "1970-01-01T00:00:03Z"
        ])

        #expect(try decoder.date("required") == Date(timeIntervalSince1970: 2))
        #expect(decoder.optionalDate("optional") == Date(timeIntervalSince1970: 3))
    }

    @Test func requiredFieldReportsItsKey() {
        let decoder = CloudFunctionResponseDecoder(dictionary: [:])

        #expect(throws: CloudFunctionsClientError.missingField("brandID")) {
            try decoder.string("brandID")
        }
    }
}
