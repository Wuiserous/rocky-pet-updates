import Foundation

enum GeminiLiveEvent {
    case connected
    case setupComplete
    case toolCall(GeminiToolCall)
    case inputTranscript(String)
    case outputTranscript(String)
    case audio(Data)
    case interrupted
    case turnComplete
    case disconnected
    case error(String)
}

struct GeminiToolCall {
    let id: String
    let name: String
    let args: [String: Any]
}

struct GeminiFunctionDeclaration {
    let name: String
    let description: String
    let parameters: [String: Any]
}

final class GeminiLiveService: NSObject {
    var onEvent: ((GeminiLiveEvent) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var isConnected = false
    private var pendingMessages: [String] = []
    private var petCharacter: PetCharacter = .golemMale
    private var shouldRequestAudioResponses = true
    private var additionalFunctionDeclarations: [GeminiFunctionDeclaration] = []
    private var additionalInstructionText: String?

    func connect(
        apiKey: String,
        petCharacter: PetCharacter,
        shouldRequestAudioResponses: Bool,
        additionalFunctionDeclarations: [GeminiFunctionDeclaration] = [],
        additionalInstructionText: String? = nil
    ) {
        disconnect()
        self.petCharacter = petCharacter
        self.shouldRequestAudioResponses = shouldRequestAudioResponses
        self.additionalFunctionDeclarations = additionalFunctionDeclarations
        self.additionalInstructionText = additionalInstructionText

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
        pendingMessages.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    func sendSetup() {
        let generationConfig: [String: Any]
        if shouldRequestAudioResponses {
            generationConfig = [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": [
                            "voiceName": petCharacter.voiceName
                        ]
                    ]
                ]
            ]
        } else {
            generationConfig = [
                "responseModalities": ["TEXT"]
            ]
        }

        let additionalInstructionParts: [[String: Any]] = additionalInstructionText.map {
            [["text": $0]]
        } ?? []

        let baseFunctionDeclarations: [[String: Any]] = [
            [
                "name": "sleep",
                "description": "Put Rocky into the sleeping visual state when the user asks Rocky to sleep, nap, rest, or go to bed.",
                "parameters": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "open_link",
                "description": "Open a web link or website on the user's Mac when the user explicitly asks Rocky to open a URL, website, doc, spreadsheet, page, repo, or browser destination. Use the exact link from context when Rocky already has one, or a direct website URL such as https://mail.google.com for Gmail.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "url": [
                            "type": "string",
                            "description": "The full URL to open. Prefer absolute URLs. If the user said a bare domain like github.com, Rocky may use https://github.com."
                        ]
                    ],
                    "required": ["url"]
                ]
            ],
            [
                "name": "fetch_latest_gmail",
                "description": "Fetch recent Gmail metadata when the user asks Rocky to check Gmail, summarize unread emails, review the inbox, or answer Gmail follow-up questions. Prefer unread_only true and max_results 10 for a general inbox summary. Use query for filters like label:important, newer_than:1d, or from:person@example.com when the user asks for important emails, today's emails, or a sender-specific follow-up.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "max_results": [
                            "type": "integer",
                            "description": "How many recent emails Rocky should fetch, up to 10."
                        ],
                        "unread_only": [
                            "type": "boolean",
                            "description": "Whether Rocky should limit results to unread emails."
                        ],
                        "query": [
                            "type": "string",
                            "description": "Optional Gmail search query, such as from:person@example.com or newer_than:1d."
                        ]
                    ]
                ]
            ],
            [
                "name": "send_gmail_email",
                "description": "Send a Gmail message when the user explicitly asks Rocky to email someone. Only use this after the user has clearly provided or approved the recipient, subject, and body.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "recipient": [
                            "type": "string",
                            "description": "The main recipient email address."
                        ],
                        "subject": [
                            "type": "string",
                            "description": "The email subject line."
                        ],
                        "body": [
                            "type": "string",
                            "description": "The plain-text email body."
                        ],
                        "cc": [
                            "type": "array",
                            "description": "Optional CC email addresses.",
                            "items": ["type": "string"]
                        ],
                        "bcc": [
                            "type": "array",
                            "description": "Optional BCC email addresses.",
                            "items": ["type": "string"]
                        ]
                    ],
                    "required": ["recipient", "subject", "body"]
                ]
            ],
            [
                "name": "create_scheduled_item",
                "description": "Create a cloud-backed Rocky task, reminder, or alarm. Use an exact ISO 8601 timestamp in scheduled_at based on the user's local date and time context. For requests like every two hours from 09:00 to 17:00, set interval_minutes plus window_start_time and window_end_time using 24-hour HH:mm strings.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "A short, clear label for the task, reminder, or alarm."
                        ],
                        "kind": [
                            "type": "string",
                            "enum": ["task", "reminder", "alarm"],
                            "description": "Whether Rocky should create a task, reminder, or alarm."
                        ],
                        "scheduled_at": [
                            "type": "string",
                            "description": "The exact ISO 8601 date-time when Rocky should trigger it."
                        ],
                        "repeat_rule": [
                            "type": "string",
                            "enum": ["none", "daily", "weekdays", "weekly", "monthly"],
                            "description": "How often Rocky should repeat it."
                        ],
                        "interval_minutes": [
                            "type": "integer",
                            "description": "Optional repeating interval in minutes for schedules like every 120 minutes."
                        ],
                        "window_start_time": [
                            "type": "string",
                            "description": "Optional local start time in 24-hour HH:mm format, such as 09:00."
                        ],
                        "window_end_time": [
                            "type": "string",
                            "description": "Optional local end time in 24-hour HH:mm format, such as 12:00."
                        ],
                        "notes": [
                            "type": "string",
                            "description": "Optional extra context Rocky can show in the reminder."
                        ]
                    ],
                    "required": ["title", "kind", "scheduled_at"]
                ]
            ],
            [
                "name": "list_scheduled_items",
                "description": "List Rocky's currently scheduled tasks, reminders, and alarms when the user asks what is coming up or what Rocky has scheduled.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "status": [
                            "type": "string",
                            "enum": ["pending", "completed", "dismissed", "missed", "cancelled"],
                            "description": "Optional status filter."
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "How many items to return, up to 12."
                        ]
                    ]
                ]
            ],
            [
                "name": "complete_scheduled_item",
                "description": "Mark one of Rocky's scheduled tasks, reminders, or alarms as completed when the user asks to complete or finish it.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "item_id": [
                            "type": "string",
                            "description": "The scheduled item id Rocky wants to mark complete."
                        ]
                    ],
                    "required": ["item_id"]
                ]
            ],
            [
                "name": "snooze_scheduled_item",
                "description": "Snooze a Rocky reminder or alarm by a small number of minutes.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "item_id": [
                            "type": "string",
                            "description": "The scheduled item id Rocky wants to snooze."
                        ],
                        "minutes": [
                            "type": "integer",
                            "description": "How many minutes Rocky should snooze it for."
                        ]
                    ],
                    "required": ["item_id", "minutes"]
                ]
            ],
            [
                "name": "delete_scheduled_item",
                "description": "Delete a scheduled task, reminder, or alarm when the user explicitly asks Rocky to remove or cancel it.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "item_id": [
                            "type": "string",
                            "description": "The scheduled item id Rocky should delete."
                        ]
                    ],
                    "required": ["item_id"]
                ]
            ],
            [
                "name": "create_google_sheet",
                "description": "Create a new Google Sheet when the user asks Rocky to make a spreadsheet, tracker, table, or sheet.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "The title for the new Google Sheet."
                        ]
                    ],
                    "required": ["title"]
                ]
            ],
            [
                "name": "append_google_sheet_rows",
                "description": "Append rows into an existing Google Sheet after Rocky creates one or when the user wants data written into a known spreadsheet.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "spreadsheet_id": [
                            "type": "string",
                            "description": "The Google spreadsheet ID."
                        ],
                        "headers": [
                            "type": "array",
                            "description": "Optional column headers for the first row.",
                            "items": ["type": "string"]
                        ],
                        "rows": [
                            "type": "array",
                            "description": "The rows to append, where each row is an array of cell strings.",
                            "items": [
                                "type": "array",
                                "items": ["type": "string"]
                            ]
                        ],
                        "range": [
                            "type": "string",
                            "description": "Optional A1 range like Sheet1!A1."
                        ]
                    ],
                    "required": ["spreadsheet_id", "rows"]
                ]
            ],
            [
                "name": "search_google_drive_files",
                "description": "Search Google Drive for files when the user asks Rocky to find a doc, sheet, file, deck, or folder.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The Google Drive search phrase."
                        ],
                        "max_results": [
                            "type": "integer",
                            "description": "How many files Rocky should return, up to 8."
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "search_notion_pages",
                "description": "Search Notion pages when the user asks Rocky to look for a page, note, doc, or database item in Notion.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The Notion search phrase."
                        ],
                        "max_results": [
                            "type": "integer",
                            "description": "How many Notion pages Rocky should return, up to 8."
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "create_notion_page",
                "description": "Create a Notion page when the user gives Rocky a page title and a parent page or database ID.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "The title of the Notion page."
                        ],
                        "parent_id": [
                            "type": "string",
                            "description": "The parent page or database ID in Notion."
                        ],
                        "markdown": [
                            "type": "string",
                            "description": "Optional page content in markdown."
                        ]
                    ],
                    "required": ["title", "parent_id"]
                ]
            ],
            [
                "name": "append_notion_paragraphs",
                "description": "Append paragraph content into an existing Notion block or page when the user wants Rocky to add content.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "block_id": [
                            "type": "string",
                            "description": "The Notion block or page ID to append into."
                        ],
                        "paragraphs": [
                            "type": "array",
                            "description": "A list of paragraph strings to append.",
                            "items": ["type": "string"]
                        ]
                    ],
                    "required": ["block_id", "paragraphs"]
                ]
            ],
            [
                "name": "search_linear_issues",
                "description": "Search Linear issues when the user asks Rocky to look up tickets, tasks, bugs, or issues in Linear.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The Linear issue search phrase."
                        ],
                        "max_results": [
                            "type": "integer",
                            "description": "How many Linear issues Rocky should return, up to 8."
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "list_linear_teams",
                "description": "List available Linear teams only when the user explicitly asks which teams are available or wants to change the default Linear team. Do not call this before first trying create_linear_issue.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "max_results": [
                            "type": "integer",
                            "description": "How many Linear teams Rocky should return, up to 8."
                        ]
                    ]
                ]
            ],
            [
                "name": "list_linear_states",
                "description": "List the available workflow states for a Linear team when the user asks which statuses are available or Rocky needs to understand valid status names before updating an issue. Prefer omitting team_id so Rocky can use the default Linear team.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "team_id": [
                            "type": "string",
                            "description": "Optional Linear team ID. Omit this to use the default Linear team."
                        ],
                        "max_results": [
                            "type": "integer",
                            "description": "How many Linear workflow states Rocky should return, up to 12."
                        ]
                    ]
                ]
            ],
            [
                "name": "create_linear_issue",
                "description": "Create a Linear issue when the user gives Rocky a title. Prefer omitting team_id so Rocky can use the saved default Linear team or the backend default team automatically. Do not ask the user for a team ID unless they explicitly want to choose a different team.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "The Linear issue title."
                        ],
                        "team_id": [
                            "type": "string",
                            "description": "Optional Linear team ID. Omit this to use the default Linear team."
                        ],
                        "description": [
                            "type": "string",
                            "description": "Optional Linear issue description."
                        ],
                        "priority": [
                            "type": "integer",
                            "description": "Optional Linear priority integer."
                        ]
                    ],
                    "required": ["title"]
                ]
            ],
            [
                "name": "update_linear_issue_status",
                "description": "Update the status of an existing Linear issue when the user asks Rocky to move, mark, or change an issue to a new workflow state such as Todo, In Progress, or Done. Use the exact issue_id from prior Linear search results. Prefer omitting team_id so Rocky can use the default Linear team.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "issue_id": [
                            "type": "string",
                            "description": "The Linear issue id to update."
                        ],
                        "status": [
                            "type": "string",
                            "description": "The target Linear workflow state name, such as Todo, In Progress, or Done."
                        ],
                        "team_id": [
                            "type": "string",
                            "description": "Optional Linear team ID. Omit this to use the default Linear team."
                        ]
                    ],
                    "required": ["issue_id", "status"]
                ]
            ],
            [
                "name": "list_slack_channels",
                "description": "List Slack channels when the user asks Rocky to find or choose a channel before sending a message.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Optional channel search phrase."
                        ],
                        "max_results": [
                            "type": "integer",
                            "description": "How many Slack channels Rocky should return, up to 8."
                        ]
                    ]
                ]
            ],
            [
                "name": "send_slack_message",
                "description": "Send a Slack message when the user gives Rocky a channel name or ID and message text.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "channel": [
                            "type": "string",
                            "description": "The Slack channel name or channel ID."
                        ],
                        "text": [
                            "type": "string",
                            "description": "The Slack message text."
                        ]
                    ],
                    "required": ["channel", "text"]
                ]
            ]
        ]

        let dynamicFunctionDeclarations = additionalFunctionDeclarations.map { declaration in
            [
                "name": declaration.name,
                "description": declaration.description,
                "parameters": declaration.parameters
            ]
        }

        let message: [String: Any] = [
            "setup": [
                "model": "models/gemini-3.1-flash-live-preview",
                "generationConfig": generationConfig,
                "systemInstruction": [
                    "parts": [
                        [
                            "text": petCharacter.systemPrompt
                        ]
                    ] + additionalInstructionParts
                ],
                "tools": [
                    [
                        "functionDeclarations": baseFunctionDeclarations + dynamicFunctionDeclarations
                    ]
                ],
                "inputAudioTranscription": [:],
                "outputAudioTranscription": [:],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false,

                    ]
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

    func sendTextTurn(_ text: String) {
        guard isConnected else { return }

        sendJSON([
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            [
                                "text": text
                            ]
                        ]
                    ]
                ],
                "turnComplete": true
            ]
        ])
    }

    func endAudioStream() {
        sendJSON([
            "realtimeInput": [
                "audioStreamEnd": true
            ]
        ])
    }

    func sendToolResponse(id: String, name: String, response: [String: Any]) {
        sendJSON([
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": id,
                        "name": name,
                        "response": response
                    ]
                ]
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

        guard let webSocket else {
            pendingMessages.append(string)
            return
        }

        guard isConnected else {
            pendingMessages.append(string)
            return
        }

        webSocket.send(.string(string)) { [weak self] error in
            if let error {
                self?.pendingMessages.insert(string, at: 0)
                self?.onEvent?(.error(error.localizedDescription))
            }
        }
    }

    private func flushPendingMessages() {
        guard isConnected, let webSocket, !pendingMessages.isEmpty else { return }

        let messages = pendingMessages
        pendingMessages.removeAll()

        for message in messages {
            webSocket.send(.string(message)) { [weak self] error in
                if let error {
                    self?.pendingMessages.insert(message, at: 0)
                    self?.onEvent?(.error(error.localizedDescription))
                }
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

        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for functionCall in functionCalls {
                guard let name = functionCall["name"] as? String else {
                    continue
                }

                let id = functionCall["id"] as? String ?? name
                let args = functionCall["args"] as? [String: Any] ?? [:]
                onEvent?(.toolCall(GeminiToolCall(id: id, name: name, args: args)))
            }

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
            if let text = part["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onEvent?(.outputTranscript(text))
            }

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
        flushPendingMessages()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isConnected = false
        pendingMessages.removeAll()
        onEvent?(.disconnected)
    }
}
