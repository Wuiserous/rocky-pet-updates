import AVFoundation
import Foundation

final class AudioPlaybackService {
    var onPlaybackStarted: (() -> Void)?
    var onPlaybackFinished: (() -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private var scheduledBuffers = 0
    private var finishWorkItem: DispatchWorkItem?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ pcmData: Data) {
        guard let buffer = makeBuffer(from: pcmData) else { return }

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            return
        }

        finishWorkItem?.cancel()
        finishWorkItem = nil
        scheduledBuffers += 1
        onPlaybackStarted?()

        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.scheduledBuffers = max(0, self.scheduledBuffers - 1)
                if self.scheduledBuffers == 0 {
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self, self.scheduledBuffers == 0 else { return }
                        self.onPlaybackFinished?()
                    }
                    self.finishWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
                }
            }
        }

        if !player.isPlaying {
            player.play()
        }
    }

    func stop() {
        finishWorkItem?.cancel()
        finishWorkItem = nil
        player.stop()
        scheduledBuffers = 0
        onPlaybackFinished?()
    }

    private func makeBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }

        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let destination = buffer.audioBufferList.pointee.mBuffers.mData else {
            return nil
        }

        data.withUnsafeBytes { source in
            if let baseAddress = source.baseAddress {
                destination.copyMemory(from: baseAddress, byteCount: data.count)
            }
        }

        return buffer
    }
}
