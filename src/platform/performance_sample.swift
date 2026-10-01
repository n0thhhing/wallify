import Foundation

struct PerformanceSample {
    private(set) var time: Double = 0
    private var cpu: Double = 0
    private var frames: UInt64 = 0
    private var gpu: UInt64 = 0
    private(set) var cpuPercent: Double = 0
    private(set) var redraws: Double = 0
    private(set) var gpuMS: Double = 0

    mutating func update(now: Double, cpu: Double, frames: UInt64, gpu: UInt64) {
        if time > 0, now > time, cpu >= self.cpu, frames >= self.frames, gpu >= self.gpu {
            let duration = now - time, count = frames - self.frames
            cpuPercent = (cpu - self.cpu) / duration * 100
            redraws = Double(count) / duration
            gpuMS = count == 0 ? 0 : Double(gpu - self.gpu) / Double(count) / 1_000_000
        } else { cpuPercent = 0; redraws = 0; gpuMS = 0 }
        time = now; self.cpu = cpu; self.frames = frames; self.gpu = gpu
    }
}
