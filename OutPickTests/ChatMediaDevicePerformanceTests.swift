import XCTest
import ImageIO
import UniformTypeIdentifiers
import Darwin
import UIKit
@testable import OutPick

/// 실기기에서만 수동 선택 실행하는 성능 QA. 일반 회귀 실행에는 포함하지 않는다.
final class ChatMediaDevicePerformanceTests: XCTestCase {
    func testRealMainScreenBeforeMediaQA() async throws {
        guard ProcessInfo.processInfo.environment["OUTPICK_MEDIA_DEVICE_BENCHMARK"] == "1" else {
            throw XCTSkip("실기기 Development 화면 확인 명시 실행 전용")
        }
        try await requireMainScreen()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        await attachVisibleScreen(name: "실제 Development 메인 화면 — 준비 QA 선행 확인")
    }

    func testImagePreparationSweep() async throws {
        guard ProcessInfo.processInfo.environment["OUTPICK_MEDIA_DEVICE_BENCHMARK"] == "1" else {
            throw XCTSkip("실기기 성능 QA 명시 실행 전용")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("실제 iPhone에서 실행해야 합니다.")
        #else
        try await requireMainScreen()
        await attachVisibleScreen(name: "실제 메인 화면 — 측정 전")
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = try (0..<4).map { index in
            try autoreleasepool { try Self.makeFixture(index: index, root: root) }
        }
        let environment = ProcessInfo.processInfo.environment
        let count = Int(environment["OUTPICK_MEDIA_BENCHMARK_COUNT"] ?? "30") ?? 30
        let widths = (environment["OUTPICK_MEDIA_BENCHMARK_WIDTHS"] ?? "1,2,3,4")
            .split(separator: ",").compactMap { Int($0) }.filter { (1...4).contains($0) }
        let repeats = Int(environment["OUTPICK_MEDIA_BENCHMARK_REPEATS"] ?? "2") ?? 2
        var measurements: [[String: Any]] = []
        for repetition in 0..<repeats {
            // 역순 반복으로 실행 순서/열 누적이 특정 제한에만 유리하지 않게 한다.
            let order = repetition.isMultiple(of: 2) ? widths : widths.reversed()
            for width in order {
                try await requireMainScreen()
                var coolingSeconds = 0
                while ProcessInfo.processInfo.thermalState != .nominal && coolingSeconds < 120 {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    coolingSeconds += 5
                }
                guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
                    throw XCTSkip("기기가 serious 이상 발열 상태여서 비교를 중단합니다.")
                }
                let database = try TemporaryAppDatabase.make()
                let persistence = GRDBChatOutgoingOutboxStore(database: database)
                let repository = ChatMediaSelectionRepository(persistence: persistence, root: root.appendingPathComponent(UUID().uuidString))
                var limits = ChatMediaPipelineLimits()
                limits.imagePreparation = width
                let useCase = ChatMediaSelectionUseCase(repository: repository, limits: limits)
                let selection = ChatMediaSelection(selectionID: UUID().uuidString, roomID: "local-benchmark", senderUID: "benchmark",
                    createdAt: Date(), selectionSources: (0..<count).map {
                        .init(index: $0, path: fixtures[$0 % fixtures.count].path, isVideo: false)
                    })
                try await repository.save(selection)
                let sample = MediaDeviceSample()
                sample.start()
                let started = ProcessInfo.processInfo.systemUptime
                let firstChunk = FirstChunkClock()
                let rejected = try await useCase.process(selection, onChunk: { id, chunk in
                    guard case .images = chunk else { return }
                    await firstChunk.record(ProcessInfo.processInfo.systemUptime - started)
                    try await persistence.saveOutgoingOutboxRecord(.init(messageID: id, roomID: "local-benchmark", kind: .images,
                        stage: .needsUpload, createdAt: Date(), updatedAt: Date(), localPayloadJSON: "{}", uploadedPayloadJSON: nil, lastError: nil))
                }, onCommitted: { _ in })
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let values = sample.stop()
                XCTAssertEqual(rejected, 0)
                let row: [String: Any] = ["width": width, "repetition": repetition, "count": count,
                    "seconds": elapsed, "firstChunkSeconds": await firstChunk.value ?? elapsed,
                    "baselineMiB": values.baseline, "peakMiB": values.peak, "endMiB": values.end,
                    "cpuSeconds": values.cpu, "thermalStart": values.thermalStart, "thermalMax": values.thermalMax,
                    "coolingSeconds": coolingSeconds, "fixture": "synthetic-4032x3024-JPEG-4variants"]
                measurements.append(row)
                let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                print("MEDIA_DEVICE_BENCHMARK \(String(decoding: data, as: UTF8.self))")
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.json.identifier)
        attachment.name = "iPhone14-media-preparation.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        try await requireMainScreen()
        await attachVisibleScreen(name: "실제 메인 화면 — 측정 후")
        #endif
    }

    private enum Preconditions: Error { case mainScreenUnavailable }

    private func requireMainScreen() async throws {
        for _ in 0..<120 {
            let ready = await MainActor.run {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows).filter { $0.isKeyWindow }
                    .contains { Self.containsMainScreen($0.rootViewController) }
            }
            if ready { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        await attachVisibleScreen(name: "측정 차단 — 메인 화면 미진입")
        XCTFail("실제 인증·bootstrap을 거친 메인 화면에 진입하지 못해 성능 측정을 중단합니다.")
        throw Preconditions.mainScreenUnavailable
    }

    @MainActor private static func containsMainScreen(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        if controller.viewIfLoaded?.accessibilityIdentifier == "app.bootstrap.failure.root" { return false }
        if controller.viewIfLoaded?.accessibilityIdentifier == "app.main.root", controller.viewIfLoaded?.window != nil { return true }
        return controller.children.contains { containsMainScreen($0) }
    }

    @MainActor private func attachVisibleScreen(name: String) {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        autoreleasepool {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private static func makeFixture(index: Int, root: URL) throws -> URL {
        let width = 4032, height = 3024
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var seed = UInt32(index + 1)
        for pixel in 0..<(width * height) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let x = pixel % width, y = pixel / width
            bytes[pixel * 4] = UInt8(truncatingIfNeeded: x / 12 + Int(seed & 31))
            bytes[pixel * 4 + 1] = UInt8(truncatingIfNeeded: y / 12 + Int((seed >> 8) & 31))
            bytes[pixel * 4 + 2] = UInt8(truncatingIfNeeded: (x + y) / 24 + index * 40)
            bytes[pixel * 4 + 3] = 255
        }
        let image = try XCTUnwrap(context.makeImage())
        let path = root.appendingPathComponent("fixture-\(index).jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(path as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return path
    }
}

private actor FirstChunkClock {
    var value: Double?
    func record(_ seconds: Double) { if value == nil { value = seconds } }
}

/// 50ms 간격의 process footprint 표본이다. 순간 peak를 완전히 포착한다고 보장하지 않는다.
private final class MediaDeviceSample: @unchecked Sendable {
    private let queue = DispatchQueue(label: "outpick.media-benchmark-sample")
    private var timer: DispatchSourceTimer?
    private var peak: Double = 0
    private var baseline: Double = 0
    private var cpuStart: Double = 0
    private var thermalStart = 0
    private var thermalMax = 0
    func start() {
        queue.sync {
            baseline = Self.footprint()
            peak = baseline
            cpuStart = Self.cpuTime()
            thermalStart = ProcessInfo.processInfo.thermalState.rawValue
            thermalMax = thermalStart
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.peak = max(self.peak, Self.footprint())
                self.thermalMax = max(self.thermalMax, ProcessInfo.processInfo.thermalState.rawValue)
            }
            self.timer = timer
            timer.resume()
        }
    }
    func stop() -> (baseline: Double, peak: Double, end: Double, cpu: Double, thermalStart: Int, thermalMax: Int) {
        queue.sync {
            timer?.cancel()
            timer = nil
            let end = Self.footprint()
            return (baseline, max(peak, end), end, Self.cpuTime() - cpuStart, thermalStart, thermalMax)
        }
    }
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
    private static func cpuTime() -> Double {
        var value = rusage()
        getrusage(RUSAGE_SELF, &value)
        return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
            + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
    }
}
