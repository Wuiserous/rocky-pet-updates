import Foundation

enum GeminiLiveEvent {
    case connected
    case setupComplete
    case inputTranscript(String)
    case outputTranscript(String)
    case audio(Data)
    case interrupted
    case turnComplete
    case disconnected
    case error(String)
}

final class GeminiLiveService: NSObject {
    var onEvent: ((GeminiLiveEvent) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var isConnected = false

    func connect(apiKey: String) {
        disconnect()

        var components = URLComponents()
        components.scheme = "wss"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            onEvent?(.error("Invalid Gemini WebSocket URL."))
            return
        }

        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        receiveLoop()
    }

    func disconnect() {
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    func sendSetup() {
        let message: [String: Any] = [
            "setup": [
                "model": "models/gemini-3.1-flash-live-preview",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": "Iapetus"
                            ]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        [
                            "text": "You are Rocky, a tiny desktop pet. Be warm, concise, playful, and useful. Speak naturally, as if you live on the user's Mac desktop."
                        ]
                    ]
                ],
                "inputAudioTranscription": [:],
                "outputAudioTranscription": [:],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false,
                        "startOfSpeechSensitivity": "START_SENSITIVITY_HIGH",
                        "endOfSpeechSensitivity": "END_SENSITIVITY_HIGH",
                        "silenceDurationMs": 500
                    ],
                ]
            ]
        ]

        sendJSON(message)
    }

    func sendAudio(_ pcmData: Data) {
        guard isConnected else { return }

        let message: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": pcmData.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]

        sendJSON(message)
    }

    func endAudioStream() {
        sendJSON([
            "realtimeInput": [
                "audioStreamEnd": true
            ]
        ])
    }

    private func sendJSON(_ object: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let string = String(data: data, encoding: .utf8)
        else {
            onEvent?(.error("Could not encode Gemini message."))
            return
        }

        webSocket?.send(.string(string)) { [weak self] error in
            if let error {
                self?.onEvent?(.error(error.localizedDescription))
            }
        }
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }

        switch result {
            case .success(let message):
                handle(message)
                receiveLoop()
            case .failure(let error):
                isConnected = false
                onEvent?(.error(error.localizedDescription))
                onEvent?(.disconnected)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?

        switch message {
        case .string(let string):
            data = string.data(using: .utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard
            let data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        if json["setupComplete"] != nil {
            onEvent?(.setupComplete)
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Gemini Live returned an error."
            onEvent?(.error(message))
            return
        }

        guard let serverContent = json["serverContent"] as? [String: Any] else {
            return
        }

        if (serverContent["interrupted"] as? Bool) == true {
            onEvent?(.interrupted)
        }

        if (serverContent["turnComplete"] as? Bool) == true {
            onEvent?(.turnComplete)
        }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String {
            onEvent?(.inputTranscript(text))
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String {
            onEvent?(.outputTranscript(text))
        }

        guard
            let modelTurn = serverContent["modelTurn"] as? [String: Any],
            let parts = modelTurn["parts"] as? [[String: Any]]
        else {
            return
        }

        for part in parts {
            guard
                let inlineData = part["inlineData"] as? [String: Any],
                let base64 = inlineData["data"] as? String,
                let audioData = Data(base64Encoded: base64)
            else {
                continue
            }

            onEvent?(.audio(audioData))
        }
    }
}

extension GeminiLiveService: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        isConnected = true
        onEvent?(.connected)
        sendSetup()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isConnected = false
        onEvent?(.disconnected)
    }
}
