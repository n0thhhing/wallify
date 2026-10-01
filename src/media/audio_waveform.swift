import Foundation
import CoreAudio

// Each texel holds negative/positive peaks for one horizontal slice of real audio.
func waveformPixels(_ samples: UnsafeBufferPointer<Float>) -> [UInt32] {
    var pixels = [UInt32](repeating: 0xff000000, count: 64)
    guard !samples.isEmpty else { return pixels }
    let peak = samples.reduce(Float(0)) { $1.isFinite ? max($0, abs($1)) : $0 }
    // Bounded gain makes quiet playback readable without magnifying near-silence indefinitely.
    let gain = min(256, 0.9 / max(peak, 0.0001))
    for bin in 0..<64 {
        let start = bin * samples.count / 64, end = (bin + 1) * samples.count / 64
        var low: Float = 0, high: Float = 0
        for i in start..<end where samples[i].isFinite {
            low = min(low, samples[i]); high = max(high, samples[i])
        }
        pixels[bin] |= UInt32(min(255, -low * gain * 255)) | (UInt32(min(255, high * gain * 255)) << 8)
    }
    return pixels
}

final class AudioWaveform: @unchecked Sendable {
    private let lock = NSLock()
    private let control = DispatchQueue(label: "Wallify.audio.control", qos: .utility)
    private let audio = DispatchQueue(label: "Wallify.audio.samples", qos: .userInitiated)
    private var requested = false
    private var pixels: [UInt32]?
    private var timestamp: Double = 0
    private var uploadedTimestamp: Double = 0 // Scene-worker owned.
    private var message = "Starts during visible playback."
    // Tap/device ownership belongs exclusively to the serial control queue.
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?

    var status: String { lock.lock(); defer { lock.unlock() }; return message }
    private var wanted: Bool { lock.lock(); defer { lock.unlock() }; return requested }

    func update(active: Bool) {
        lock.lock()
        guard requested != active else { lock.unlock(); return }
        requested = active
        if !active { pixels = nil; timestamp = 0 }
        lock.unlock()
        control.async {
            guard #available(macOS 14.2, *) else { self.setStatus("Requires macOS 14.2 or later."); return }
            if !self.wanted {
                self.stop(); self.setStatus("Starts during visible playback."); return
            }
            guard self.tap == 0 else { return }
            do {
                self.setStatus("Requesting system audio access…")
                try self.start()
                if !self.wanted { self.stop() }
                else { self.setStatus("Capturing system audio • nothing is saved.") }
            } catch {
                self.stop()
                self.setStatus("\(error.localizedDescription) Toggle off/on to retry after granting permission.")
                NSLog("Wallify waveform: %@", error.localizedDescription)
            }
        }
    }

    private func setStatus(_ value: String) {
        lock.lock(); let changed = message != value; message = value; lock.unlock()
        if changed { refreshSettingsUI() }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Audio capture \(operation) failed (\(status))."])
        }
    }

    @available(macOS 14.2, *) private func start() throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Wallify waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted // Observe playback without changing the output.
        try check(AudioHardwareCreateProcessTap(description, &tap), "tap")
        let properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Wallify waveform",
            kAudioAggregateDeviceUIDKey: "Wallify.waveform.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                             kAudioSubTapDriftCompensationKey: true]]
        ]
        try check(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &device), "device")
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription(), size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format), "format")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mChannelsPerFrame == 1 else {
            throw NSError(domain: "Wallify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported system audio input format."])
        }
        try check(AudioDeviceCreateIOProcIDWithBlock(&io, device, audio) { [weak self] _, input, _, _, _ in
            self?.consume(input)
        }, "callback")
        try check(AudioDeviceStart(device, io), "start")
    }

    @available(macOS 14.2, *) private func stop() {
        if let io { AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io) }
        io = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }

    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        let now = monotonicTime()
        guard lock.try() else { return }
        let accept = requested && now - timestamp >= 1 / 25
        lock.unlock()
        guard accept else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let buffer = buffers.first, buffer.mNumberChannels == 1, let data = buffer.mData,
              buffer.mDataByteSize > 0, buffer.mDataByteSize % 4 == 0 else { return }
        let result = waveformPixels(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                       count: Int(buffer.mDataByteSize) / 4))
        guard lock.try() else { return }
        if requested { pixels = result; timestamp = now }
        lock.unlock()
    }

    func textureAvailable() -> Bool {
        lock.lock(); let samples = pixels, stamp = timestamp, active = requested; lock.unlock()
        guard active, let samples, monotonicTime() - stamp < 0.25 else { return false }
        if stamp != uploadedTimestamp {
            samples.withUnsafeBufferPointer { loadMetalTexture(Texture.waveform.rawValue, $0.baseAddress, 64, 1) }
            uploadedTimestamp = stamp
        }
        return true
    }
}

let audioWaveform = AudioWaveform()
