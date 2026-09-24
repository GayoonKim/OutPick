import Foundation
import Darwin

#if DEBUG
/// Development 비교 실행에서만 200ms 간격으로 측정한다. 순간 최대값을 보장하지 않는다.
final class ChatMediaQAMetrics: @unchecked Sendable {
    static let shared = ChatMediaQAMetrics()
    private let queue = DispatchQueue(label: "outpick.media-qa.metrics")
    private var timer: DispatchSourceTimer?
    private var peak = 0.0
    private var samples = 0
    private var previousCPU: Double?
    private var previousUptime: Double?
    private var peakCPU = 0.0

    func start() {
        queue.sync {
            guard timer == nil else { return }
            print("[MediaQA] event=configuration unlimitedDiskPreparation=true")
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
                let uptime = ProcessInfo.processInfo.systemUptime
                var usage = rusage()
                var cpuPercent = 0.0
                if getrusage(RUSAGE_SELF, &usage) == 0 {
                    let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
                    if let last = self.previousCPU, let time = self.previousUptime, uptime > time {
                        // 100%는 CPU 코어 하나를 계속 사용하는 양이다. 여러 코어를 쓰면 100%를 넘는다.
                        cpuPercent = max(0, (cpu - last) / (uptime - time) * 100)
                    }
                    self.previousCPU = cpu
                    self.previousUptime = uptime
                    self.peakCPU = max(self.peakCPU, cpuPercent)
                }
                if self.samples % 5 == 0 {
                    print("[MediaQA] event=resources uptime=\(uptime) memoryMiB=\(mib) peakMiB=\(self.peak) cpuPercent=\(cpuPercent) peakCPUPercent=\(self.peakCPU) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
                }
            }
            self.timer = timer
            timer.resume()
        }
    }
}
#endif
