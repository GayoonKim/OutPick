import Foundation
import Testing
@testable import OutPick

struct ChatMediaSourceAcquisitionTests {
    @Test func providerErrorFollowedByCancellationCompletesOnlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await ChatMediaSourceAcquisition.acquire(index: 0, directory: root, isVideo: false) { complete in
                complete(nil, NSError(domain: "NSItemProviderErrorDomain", code: -1000))
                complete(nil, NSError(domain: "NSItemProviderErrorDomain", code: 3072))
                return Progress(totalUnitCount: 1)
            }
            Issue.record("첫 provider 오류가 전달되어야 한다")
        } catch {
            #expect((error as NSError).code == -1000)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func duplicateSuccessAndLateErrorPreserveFirstCopiedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("provider.jpg")
        try Data([1, 2, 3]).write(to: source)
        let result = try await ChatMediaSourceAcquisition.acquire(index: 0, directory: root, isVideo: false) { complete in
            complete(source, nil)
            complete(source, nil)
            complete(nil, NSError(domain: "NSItemProviderErrorDomain", code: 3072))
            return Progress(totalUnitCount: 1)
        }
        #expect(result.index == 0)
        #expect(try Data(contentsOf: URL(fileURLWithPath: result.path)) == Data([1, 2, 3]))
    }

    @Test func simultaneousProviderErrorsCompleteOnlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await ChatMediaSourceAcquisition.acquire(index: 0, directory: root, isVideo: false) { complete in
                DispatchQueue.concurrentPerform(iterations: 16) { _ in
                    complete(nil, NSError(domain: "NSItemProviderErrorDomain", code: -1000))
                }
                return Progress(totalUnitCount: 1)
            }
            Issue.record("provider 오류가 전달되어야 한다")
        } catch {
            #expect((error as NSError).code == -1000)
        }
    }
}
