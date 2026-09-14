import Foundation

#if DEBUG
/// Development 비교 실행에서만 200ms 간격으로 측정한다. 순간 최대값을 보장하지 않는다.
final class ChatMediaQAMetrics: @unchecked Sendable {
    static let shared = ChatMediaQAMetrics()
    private let queue = DispatchQueue(label: "outpick.media-qa.metrics")
    private var timer: DispatchSourceTimer?
    private var peak = 0.0
    private var samples = 0

    func start() {
        queue.sync {
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                var info = task_vm_info_data_t()
                var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
                let result = withUnsafeMutablePointer(to: &info) { pointer in
                    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                    }
                }
                guard result == KERN_SUCCESS else { return }
                let mib = Double(info.phys_footprint) / 1_048_576
                self.peak = max(self.peak, mib)
                self.samples += 1
                if self.samples % 5 == 0 {
                    print("[MediaQA] event=resources uptime=\(ProcessInfo.processInfo.systemUptime) memoryMiB=\(mib) peakMiB=\(self.peak) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
                }
            }
            self.timer = timer
            timer.resume()
        }
    }
}
#endif
