import Combine
import Foundation

@MainActor
final class PetBrainViewModel: ObservableObject {
    @Published private(set) var petState: PetState = .idle
    @Published private(set) var brainState: PetBrainState = .idle
    @Published private(set) var statusText = "Idle"
    @Published private(set) var latestUserTranscript = ""
    @Published private(set) var latestAITranscript = ""
    @Published private(set) var isTranscriptVisible = false

    private let gemini = GeminiLiveService()
    private let capture = AudioCaptureService()
    private let playback = AudioPlaybackService()
    private var userSelectedState: PetState?

    init() {
        gemini.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleGeminiEvent(event)
            }
        }

        capture.onAudioData = { [weak self] data in
            self?.gemini.sendAudio(data)
        }

        playback.onPlaybackStarted = { [weak self] in
            Task { @MainActor in
                self?.setBrainState(.speaking)
            }
        }

        playback.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.setBrainState(self.brainState == .idle ? .idle : .listening)
            }
        }
    }

    func toggleConversation() {
        switch brainState {
        case .idle, .error:
            startConversation()
        case .connecting, .listening, .thinking, .speaking:
            stopConversation()
        }
    }

    func startConversation() {
        guard let apiKey = GeminiSettings.requestAPIKeyIfNeeded() else {
            setBrainState(.idle)
            return
        }

        latestUserTranscript = ""
        latestAITranscript = ""
        isTranscriptVisible = false
        setBrainState(.connecting)
        gemini.connect(apiKey: apiKey)
    }

    func stopConversation() {
        capture.stop()
        playback.stop()
        gemini.endAudioStream()
        gemini.disconnect()
        setBrainState(.idle)
    }

    func setManualState(_ state: PetState) {
        userSelectedState = state
        setPetState(state)
    }

    func setDragState(_ state: PetState) {
        setPetState(state)
    }

    func endDrag() {
        if let userSelectedState {
            setPetState(userSelectedState)
        } else {
            syncPetStateWithBrain()
        }
    }

    func clearAITranscriptAfterDelay() {
        let textToClear = latestAITranscript
        guard !textToClear.isEmpty else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if self.latestAITranscript == textToClear, self.brainState == .listening {
                self.isTranscriptVisible = false
                try? await Task.sleep(for: .milliseconds(450))
                if self.latestAITranscript == textToClear {
                    self.latestAITranscript = ""
                }
            }
        }
    }

    private func beginMicCapture() {
        capture.requestPermission { [weak self] granted in
            guard let self else { return }

            DispatchQueue.main.async {
                guard granted else {
                    self.statusText = "Microphone permission denied"
                    self.setBrainState(.error)
                    return
                }

                do {
                    try self.capture.start()
                    self.setBrainState(.listening)
                } catch {
                    self.statusText = error.localizedDescription
                    self.setBrainState(.error)
                }
            }
        }
    }

    private func handleGeminiEvent(_ event: GeminiLiveEvent) {
        switch event {
        case .connected:
            statusText = "Connected"
        case .setupComplete:
            statusText = "Listening"
            beginMicCapture()
        case .inputTranscript(let text):
            append(text, to: \.latestUserTranscript)
            setBrainState(.thinking)
        case .outputTranscript(let text):
            append(text, to: \.latestAITranscript)
            isTranscriptVisible = true
        case .audio(let data):
            playback.play(data)
        case .interrupted:
            playback.stop()
            setBrainState(.listening)
        case .turnComplete:
            if brainState != .speaking {
                setBrainState(.listening)
            }
        case .disconnected:
            capture.stop()
            playback.stop()
            setBrainState(.idle)
        case .error(let message):
            statusText = message
            capture.stop()
            playback.stop()
            setBrainState(.error)
        }
    }

    private func setBrainState(_ state: PetBrainState) {
        brainState = state
        userSelectedState = nil

        switch state {
        case .idle:
            statusText = "Idle"
        case .connecting:
            statusText = "Connecting"
        case .listening:
            statusText = "Listening"
        case .thinking:
            statusText = "Thinking"
        case .speaking:
            statusText = "Speaking"
        case .error:
            if statusText.isEmpty {
                statusText = "Error"
            }
        }

        syncPetStateWithBrain()
    }

    private func syncPetStateWithBrain() {
        switch brainState {
        case .idle:
            setPetState(.idle)
        case .connecting, .thinking:
            setPetState(.thinking)
        case .listening:
            setPetState(.listening)
        case .speaking:
            setPetState(.thinking)
        case .error:
            setPetState(.sad)
        }
    }

    private func setPetState(_ state: PetState) {
        petState = state
    }

    private func append(_ text: String, to keyPath: ReferenceWritableKeyPath<PetBrainViewModel, String>) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if self[keyPath: keyPath].isEmpty {
            self[keyPath: keyPath] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self[keyPath: keyPath] += text
        }

        if self[keyPath: keyPath].count > 360 {
            self[keyPath: keyPath] = String(self[keyPath: keyPath].suffix(360))
        }
    }
}
