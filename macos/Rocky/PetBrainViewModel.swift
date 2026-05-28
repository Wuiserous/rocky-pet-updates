import AppKit
import AVFoundation
import Combine
import Foundation

enum ConversationInputMode {
    case voice
    case text
}

struct GmailFollowUpAction: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
}

@MainActor
final class PetBrainViewModel: ObservableObject {
    @Published private(set) var petState: PetState = .idle
    @Published private(set) var selectedPet: PetCharacter = .golemMale
    @Published private(set) var brainState: PetBrainState = .idle
    @Published private(set) var statusText = "Idle"
    @Published private(set) var latestUserTranscript = ""
    @Published private(set) var latestAITranscript = ""
    @Published private(set) var isTranscriptVisible = false
    @Published private(set) var isPetSleeping = false
    @Published private(set) var isDraggingPet = false
    @Published private(set) var shouldSpeakTypedReplies = true
    @Published private(set) var userName = ""
    @Published private(set) var savedAPIKey = ""
    @Published private(set) var idleSleepDelaySeconds = 90
    @Published private(set) var shortcutPreferences = RockyShortcutPreferences.defaults
    @Published private(set) var pluginConnections: [PluginConnection] = []
    @Published private(set) var connectingPluginProvider: PluginProvider?
    @Published private(set) var pluginConnectionStatusProvider: PluginProvider?
    @Published private(set) var pluginConnectionStatusText = ""
    @Published private(set) var activeConversationID: String?
    @Published private(set) var memoryContextStatusText = ""
    @Published private(set) var isMemoryAccountConnected = false
    @Published private(set) var memorySettings = MemorySettingsRecord.defaults
    @Published private(set) var linearTeams: [LinearTeamSummary] = []
    @Published private(set) var defaultLinearTeam: LinearTeamPreference?
    @Published private(set) var isLoadingLinearTeams = false
    @Published private(set) var gmailFollowUpActions: [GmailFollowUpAction] = []
    @Published private(set) var scheduledItems: [ScheduledItem] = []
    @Published private(set) var scheduleNotificationAuthorizationState: ScheduleNotificationAuthorizationState = .notDetermined
    @Published private(set) var scheduleLastSyncedAt: Date?
    @Published private(set) var scheduleStatusText = ""

    private let gemini = GeminiLiveService()
    private let pluginConnectionService = PluginConnectionService()
    private let pluginToolExecutionService = PluginToolExecutionService()
    private let scheduleService = ScheduleService()
    private let memoryService = MemoryService()
    private let capture = AudioCaptureService()
    private let playback = AudioPlaybackService()
    private var sleepSoundPlayer: AVAudioPlayer?
    private let scheduleSpeechSynthesizer = NSSpeechSynthesizer()
    private var userSelectedState: PetState?
    private var ambientState: PetState?
    private var isSleeping = false
    private var shouldSendStartupGreeting = false
    private var consecutiveInterruptFrames = 0
    private let interruptVoiceFloor: Float = 0.045
    private let interruptFramesRequired = 3
    private var pendingConversationRestart = false
    private var pendingConversationRestartResetDisplayedTranscript = true
    private var isRestartingConversationInternally = false
    private var conversationInputMode: ConversationInputMode = .voice
    private var pendingTypedMessages: [String] = []
    private var hasCompletedSetup = false
    private var currentTurnUserTranscript = ""
    private var currentTurnAITranscript = ""
    private var cachedMemoryInstructionText = ""
    private var composioMetaToolMap: [String: ComposioMetaToolDefinition] = [:]
    private let typedReplySpeechDefaultsKeyPrefix = "rocky.pet.typedReplySpeech."
    private var lastScheduleDueCheckAt = Date()
    private var announcedScheduleOccurrenceKeys = Set<String>()

    init() {
        shouldSpeakTypedReplies = typedReplySpeechPreference(for: selectedPet)
        userName = UserProfileSettings.userName
        savedAPIKey = GeminiSettings.apiKey ?? ""
        idleSleepDelaySeconds = UserProfileSettings.idleSleepDelaySeconds
        shortcutPreferences = UserProfileSettings.shortcutPreferences
        pluginConnections = PluginConnectionStore.loadConnections()
        defaultLinearTeam = UserProfileSettings.defaultLinearTeam
        isMemoryAccountConnected = memoryService.hasAuthenticatedSession
        Task { @MainActor [weak self] in
            await self?.refreshComposioMetaTools()
        }
        Task { @MainActor [weak self] in
            await self?.refreshLinearTeamsIfNeeded()
        }
        Task { @MainActor [weak self] in
            await self?.refreshScheduledItems()
            await self?.refreshScheduleNotificationAuthorizationState()
        }
        Task { @MainActor [weak self] in
            self?.refreshMemorySettings()
        }

        gemini.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleGeminiEvent(event)
            }
        }

        capture.onAudioData = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleCapturedAudio(data)
            }
        }

        playback.onPlaybackStarted = { [weak self] in
            Task { @MainActor in
                self?.setBrainState(.speaking)
            }
        }

        playback.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.brainState == .speaking else { return }
                self.setBrainState(self.readyBrainState)
                self.clearAITranscriptAfterDelay()
            }
        }
    }

    func toggleConversation() {
        if isSleeping {
            wakePet()
            return
        }

        switch brainState {
        case .idle, .error:
            startConversation()
        case .ready, .connecting, .listening, .thinking, .speaking:
            stopConversation()
        }
    }

    func startConversation(
        greetOnStart: Bool = false,
        inputMode: ConversationInputMode = .voice,
        resetDisplayedTranscript: Bool = true
    ) {
        setSleeping(false)
        shouldSendStartupGreeting = greetOnStart
        conversationInputMode = inputMode
        hasCompletedSetup = false

        guard let apiKey = GeminiSettings.requestAPIKeyIfNeeded() else {
            shouldSendStartupGreeting = false
            setBrainState(.idle)
            return
        }

        if resetDisplayedTranscript {
            latestUserTranscript = ""
            latestAITranscript = ""
            isTranscriptVisible = false
            gmailFollowUpActions = []
            currentTurnUserTranscript = ""
            currentTurnAITranscript = ""
        }
        setBrainState(.connecting)
        Task { @MainActor [weak self] in
            guard let self else { return }

            if self.composioMetaToolMap.isEmpty,
               self.pluginConnections.contains(where: { ($0.composioToolRouterSessionID ?? "").isEmpty == false }) {
                await self.refreshComposioMetaTools()
            }

            let additionalInstructionText = await self.combinedAdditionalInstructionText()

            self.gemini.connect(
                apiKey: apiKey,
                petCharacter: self.selectedPet,
                shouldRequestAudioResponses: self.shouldRequestAudioResponses,
                additionalInstructionText: additionalInstructionText
            )
        }
    }

    func startConversationWithGreeting() {
        guard brainState == .idle || brainState == .error else { return }
        startConversation(greetOnStart: true)
    }

    func stopConversation() {
        shouldSendStartupGreeting = false
        hasCompletedSetup = false
        pendingTypedMessages.removeAll()
        capture.stop()
        playback.stop()
        gemini.endAudioStream()
        gemini.disconnect()
        setSleeping(false)
        setBrainState(.idle)
    }

    func setManualState(_ state: PetState) {
        ambientState = nil
        setSleeping(state == .sleeping)
        userSelectedState = state
        setPetState(state)
    }

    func setSelectedPet(_ pet: PetCharacter) {
        guard selectedPet != pet else { return }

        let shouldRestartConversation = brainState != .idle && brainState != .error
        selectedPet = pet
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        shouldSpeakTypedReplies = typedReplySpeechPreference(for: pet)
        userSelectedState = nil
        syncPetStateWithBrain()

        if shouldRestartConversation {
            restartConversation(resetDisplayedTranscript: true)
        }
    }

    func setDragState(_ state: PetState) {
        guard canShowDragState else { return }
        ambientState = nil
        setPetState(state)
    }

    func setDragging(_ dragging: Bool) {
        isDraggingPet = dragging
        if dragging {
            ambientState = nil
        } else if userSelectedState == nil {
            syncPetStateWithBrain()
        }
    }

    func endDrag() {
        if let userSelectedState {
            setPetState(userSelectedState)
        } else {
            syncPetStateWithBrain()
        }
    }

    var isSleepingState: Bool {
        isSleeping
    }

    var isConversationActive: Bool {
        switch brainState {
        case .idle, .error:
            return false
        case .ready, .connecting, .listening, .thinking, .speaking:
            return true
        }
    }

    func sleepFromMenu() {
        putPetToSleep()
    }

    func wakeFromMenu() {
        wakePet()
    }

    var canPerformAmbientActions: Bool {
        !isSleeping && !isDraggingPet && (brainState == .idle || brainState == .ready) && !hasPinnedManualState
    }

    func setAmbientState(_ state: PetState) -> Bool {
        guard canPerformAmbientActions else { return false }
        guard selectedPet.availableStates.contains(state) else { return false }
        ambientState = state
        setPetState(state)
        return true
    }

    func clearAmbientState() {
        ambientState = nil
        guard !isDraggingPet else { return }

        if let userSelectedState {
            setPetState(userSelectedState)
        } else {
            syncPetStateWithBrain()
        }
    }

    func showTransientAmbientState(_ state: PetState, duration: Duration) {
        guard setAmbientState(state) else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self else { return }
            guard self.ambientState == state else { return }
            self.clearAmbientState()
        }
    }

    func clearAITranscriptAfterDelay() {
        let userTextToClear = latestUserTranscript
        let aiTextToClear = latestAITranscript
        guard !userTextToClear.isEmpty || !aiTextToClear.isEmpty else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if
                self.latestUserTranscript == userTextToClear,
                self.latestAITranscript == aiTextToClear,
                self.brainState == self.readyBrainState
            {
                self.isTranscriptVisible = false
                try? await Task.sleep(for: .milliseconds(450))
                if
                    self.latestUserTranscript == userTextToClear,
                    self.latestAITranscript == aiTextToClear
                {
                    self.latestUserTranscript = ""
                    self.latestAITranscript = ""
                    self.gmailFollowUpActions = []
                }
            }
        }
    }

    func sendTypedMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if isSleeping {
            wakePet()
        }

        conversationInputMode = .text
        capture.stop()
        if !shouldSpeakTypedReplies {
            playback.stop()
        }

        latestUserTranscript = text
        latestAITranscript = ""
        isTranscriptVisible = true
        gmailFollowUpActions = []
        currentTurnUserTranscript = text
        currentTurnAITranscript = ""
        pendingTypedMessages.append(text)

        if brainState == .idle || brainState == .error {
            startConversation(inputMode: .text, resetDisplayedTranscript: false)
        } else if hasCompletedSetup {
            setBrainState(.thinking)
            flushPendingTypedMessages()
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
            hasCompletedSetup = true
            statusText = conversationInputMode == .voice ? "Listening" : "Ready to Chat"
            if conversationInputMode == .voice {
                beginMicCapture()
            } else {
                setBrainState(.ready)
            }
            if shouldSendStartupGreeting {
                sendStartupGreetingIfNeeded()
            }
            flushPendingTypedMessages()
        case .toolCall(let toolCall):
            handleToolCall(toolCall)
        case .inputTranscript(let text):
            gmailFollowUpActions = []
            append(text, to: \.latestUserTranscript)
            append(text, to: \.currentTurnUserTranscript)
            isTranscriptVisible = true
            setBrainState(.thinking)
        case .outputTranscript(let text):
            append(text, to: \.latestAITranscript)
            append(text, to: \.currentTurnAITranscript)
            isTranscriptVisible = true
        case .audio(let data):
            if conversationInputMode == .text, !shouldSpeakTypedReplies {
                break
            }
            playback.play(data)
        case .interrupted:
            consecutiveInterruptFrames = 0
            playback.stop()
            setBrainState(readyBrainState)
            clearAITranscriptAfterDelay()
        case .turnComplete:
            consecutiveInterruptFrames = 0
            persistCompletedConversationTurnIfNeeded()
            if brainState != .speaking {
                setBrainState(readyBrainState)
                clearAITranscriptAfterDelay()
            }
        case .disconnected:
            consecutiveInterruptFrames = 0
            hasCompletedSetup = false
            capture.stop()
            playback.stop()
            setBrainState(.idle)
            if pendingConversationRestart {
                let shouldResetDisplayedTranscript = pendingConversationRestartResetDisplayedTranscript
                pendingConversationRestart = false
                pendingConversationRestartResetDisplayedTranscript = true
                isRestartingConversationInternally = false
                startConversation(
                    inputMode: conversationInputMode,
                    resetDisplayedTranscript: shouldResetDisplayedTranscript
                )
            }
        case .error(let message):
            consecutiveInterruptFrames = 0
            hasCompletedSetup = false
            if isRestartingConversationInternally {
                return
            }
            statusText = message
            capture.stop()
            playback.stop()
            pendingConversationRestart = false
            pendingConversationRestartResetDisplayedTranscript = true
            setBrainState(.error)
        }
    }

    private func handleCapturedAudio(_ data: Data) {
        guard shouldForwardCapturedAudio(data) else { return }
        gemini.sendAudio(data)
    }

    private func shouldForwardCapturedAudio(_ data: Data) -> Bool {
        guard brainState == .speaking else {
            consecutiveInterruptFrames = 0
            return true
        }

        let level = audioLevel(for: data)
        if level >= interruptVoiceFloor {
            consecutiveInterruptFrames += 1
        } else {
            consecutiveInterruptFrames = 0
        }

        return consecutiveInterruptFrames >= interruptFramesRequired
    }

    private func audioLevel(for data: Data) -> Float {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        var sumSquares: Float = 0
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Float(sample) / Float(Int16.max)
                sumSquares += normalized * normalized
            }
        }

        return sqrt(sumSquares / Float(sampleCount))
    }

    private func setBrainState(_ state: PetBrainState) {
        brainState = state
        userSelectedState = nil

        switch state {
        case .idle:
            statusText = "Idle"
        case .connecting:
            statusText = "Connecting"
        case .ready:
            statusText = "Ready to Chat"
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

        if isSleeping {
            statusText = "Sleeping"
            setPetState(.sleeping)
            return
        }

        syncPetStateWithBrain()
    }

    private func handleToolCall(_ toolCall: GeminiToolCall) {
        switch toolCall.name {
        case "sleep":
            putPetToSleep()
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "state": "sleeping"
                ]
            )
        case "open_link":
            handleOpenLinkToolCall(toolCall)
        case "fetch_latest_gmail":
            Task { @MainActor [weak self] in
                await self?.handleGmailToolCall(toolCall)
            }
        case "send_gmail_email":
            Task { @MainActor [weak self] in
                await self?.handleSendGmailToolCall(toolCall)
            }
        case "create_scheduled_item":
            Task { @MainActor [weak self] in
                await self?.handleCreateScheduledItemToolCall(toolCall)
            }
        case "list_scheduled_items":
            handleListScheduledItemsToolCall(toolCall)
        case "complete_scheduled_item":
            Task { @MainActor [weak self] in
                await self?.handleCompleteScheduledItemToolCall(toolCall)
            }
        case "snooze_scheduled_item":
            Task { @MainActor [weak self] in
                await self?.handleSnoozeScheduledItemToolCall(toolCall)
            }
        case "delete_scheduled_item":
            Task { @MainActor [weak self] in
                await self?.handleDeleteScheduledItemToolCall(toolCall)
            }
        case let name where composioMetaToolMap[name] != nil:
            Task { @MainActor [weak self] in
                await self?.handleComposioMetaToolCall(toolCall)
            }
        case "create_google_sheet":
            Task { @MainActor [weak self] in
                await self?.handleGoogleSheetsToolCall(toolCall)
            }
        case "append_google_sheet_rows":
            Task { @MainActor [weak self] in
                await self?.handleGoogleSheetsAppendRowsToolCall(toolCall)
            }
        case "search_google_drive":
            Task { @MainActor [weak self] in
                await self?.handleGoogleDriveToolCall(toolCall)
            }
        case "create_notion_page":
            Task { @MainActor [weak self] in
                await self?.handleCreateNotionPageToolCall(toolCall)
            }
        case "append_notion_paragraphs":
            Task { @MainActor [weak self] in
                await self?.handleAppendNotionParagraphsToolCall(toolCall)
            }
        case "search_notion_pages":
            Task { @MainActor [weak self] in
                await self?.handleNotionToolCall(toolCall)
            }
        case "list_github_repositories":
            Task { @MainActor [weak self] in
                await self?.handleGitHubToolCall(toolCall)
            }
        case "create_github_issue":
            Task { @MainActor [weak self] in
                await self?.handleCreateGitHubIssueToolCall(toolCall)
            }
        case "search_linear_issues":
            Task { @MainActor [weak self] in
                await self?.handleLinearToolCall(toolCall)
            }
        case "list_linear_teams":
            Task { @MainActor [weak self] in
                await self?.handleLinearTeamsToolCall(toolCall)
            }
        case "list_linear_states":
            Task { @MainActor [weak self] in
                await self?.handleLinearStatesToolCall(toolCall)
            }
        case "create_linear_issue":
            Task { @MainActor [weak self] in
                await self?.handleCreateLinearIssueToolCall(toolCall)
            }
        case "update_linear_issue_status":
            Task { @MainActor [weak self] in
                await self?.handleUpdateLinearIssueStatusToolCall(toolCall)
            }
        case "list_slack_channels":
            Task { @MainActor [weak self] in
                await self?.handleSlackChannelsToolCall(toolCall)
            }
        case "send_slack_message":
            Task { @MainActor [weak self] in
                await self?.handleSlackSendMessageToolCall(toolCall)
            }
        default:
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Unknown tool."
                ]
            )
        }
    }

    private func handleOpenLinkToolCall(_ toolCall: GeminiToolCall) {
        let rawURL = (toolCall.args["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = normalizedOpenURL(from: rawURL) else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs a valid link to open."
                ]
            )
            return
        }

        let opened = NSWorkspace.shared.open(url)
        gemini.sendToolResponse(
            id: toolCall.id,
            name: toolCall.name,
            response: [
                "success": opened,
                "url": url.absoluteString,
                "error": opened ? "" : "Rocky couldn't open that link on this Mac right now."
            ]
        )
    }

    private func normalizedOpenURL(from rawValue: String) -> URL? {
        guard !rawValue.isEmpty else { return nil }

        if let directURL = URL(string: rawValue), isSupportedOpenURL(directURL) {
            return directURL
        }

        if
            !rawValue.contains("://"),
            let httpsURL = URL(string: "https://\(rawValue)"),
            isSupportedOpenURL(httpsURL)
        {
            return httpsURL
        }

        return nil
    }

    private func isSupportedOpenURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }

        switch scheme {
        case "http", "https":
            return url.host()?.isEmpty == false
        case "mailto", "file":
            return true
        default:
            return false
        }
    }

    private func sendStartupGreetingIfNeeded() {
        guard shouldSendStartupGreeting else { return }
        shouldSendStartupGreeting = false
        setBrainState(.thinking)
        gemini.sendTextTurn(selectedPet.startupGreetingPrompt)
    }

    private func handleGmailToolCall(_ toolCall: GeminiToolCall) async {
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 10, 1), 10)
        let unreadOnly = toolCall.args["unread_only"] as? Bool ?? true
        let query = toolCall.args["query"] as? String

        guard let gmailPluginConnection = pluginConnection(for: .gmail) else {
            gmailFollowUpActions = []
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Gmail isn't connected yet. Open Plugins in Control Center and connect Gmail first.",
                    "requires_connection": true,
                    "provider": PluginProvider.gmail.rawValue,
                ]
            )
            return
        }

        do {
            let messages = try await pluginToolExecutionService.fetchLatestGmailMessages(
                connection: gmailPluginConnection,
                maxResults: maxResults,
                unreadOnly: unreadOnly,
                query: query
            )
            gmailFollowUpActions = makeGmailFollowUpActions(from: messages)
            var response: [String: Any] = [
                "success": true,
                "provider": gmailPluginConnection.provider.rawValue,
                "connection_mode": gmailPluginConnection.connectionMode.rawValue,
                "message_count": messages.count,
                "messages": messages.map(\.toolPayload),
                "summary_guidance": [
                    "Start with the unread email count.",
                    "Call out only the 2 or 3 most important emails unless the user asks for more.",
                    "Keep the summary short and easy to scan.",
                    "If useful, mention that Rocky can also filter by important, today, or sender."
                ],
                "available_filters": [
                    "important",
                    "today",
                    "sender"
                ]
            ]
            if let connectedAccountID = gmailPluginConnection.composioConnectedAccountID, !connectedAccountID.isEmpty {
                response["connected_account_id"] = connectedAccountID
            }
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: response
            )
        } catch {
            gmailFollowUpActions = []
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": error.localizedDescription,
                    "requires_connection": false,
                ]
            )
        }
    }

    private func handleSendGmailToolCall(_ toolCall: GeminiToolCall) async {
        let recipient = (toolCall.args["recipient"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = (toolCall.args["subject"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (toolCall.args["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cc = stringifyArray(toolCall.args["cc"])
        let bcc = stringifyArray(toolCall.args["bcc"])

        guard !recipient.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs the recipient email address before sending Gmail."
                ]
            )
            return
        }

        guard !subject.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs an email subject before sending Gmail."
                ]
            )
            return
        }

        guard !body.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs the email body before sending Gmail."
                ]
            )
            return
        }

        guard let gmailPluginConnection = pluginConnection(for: .gmail) else {
            sendMissingPluginConnectionResponse(for: .gmail, toolCall: toolCall)
            return
        }

        do {
            let result = try await pluginToolExecutionService.sendGmailEmail(
                connection: gmailPluginConnection,
                recipient: recipient,
                subject: subject,
                body: body,
                cc: cc,
                bcc: bcc
            )

            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": gmailPluginConnection.provider.rawValue,
                    "recipient": result.recipient,
                    "subject": result.subject,
                    "cc": result.cc,
                    "bcc": result.bcc,
                    "summary_guidance": [
                        "Confirm that the email was sent.",
                        "Mention the recipient and subject.",
                        "Keep the confirmation short unless the user asks for more detail."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleCreateScheduledItemToolCall(_ toolCall: GeminiToolCall) async {
        let title = (toolCall.args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let kindRaw = (toolCall.args["kind"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduledAtRaw = (toolCall.args["scheduled_at"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let repeatRuleRaw = (toolCall.args["repeat_rule"] as? String ?? "none").trimmingCharacters(in: .whitespacesAndNewlines)
        let intervalMinutes = toolCall.args["interval_minutes"] as? Int
        let windowStartTime = (toolCall.args["window_start_time"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let windowEndTime = (toolCall.args["window_end_time"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (toolCall.args["notes"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": "Rocky needs a clear title before creating that scheduled item."
            ])
            return
        }

        guard let kind = ScheduledItemKind(rawValue: kindRaw) else {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": "Rocky needs the kind to be task, reminder, or alarm."
            ])
            return
        }

        guard let scheduledAt = parseISODate(scheduledAtRaw) else {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": "Rocky needs an exact scheduled_at timestamp in ISO 8601 format."
            ])
            return
        }

        let repeatRule = ScheduledItemRepeatRule(rawValue: repeatRuleRaw) ?? .none

        if (windowStartTime.isEmpty && !windowEndTime.isEmpty) || (!windowStartTime.isEmpty && windowEndTime.isEmpty) {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": "Rocky needs both window_start_time and window_end_time when you use a reminder window."
            ])
            return
        }

        do {
            let item = try await scheduleService.createScheduledItem(
                CreateScheduledItemRequest(
                    title: title,
                    kind: kind,
                    scheduledFor: scheduledAt,
                    timezone: TimeZone.current.identifier,
                    repeatRule: repeatRule,
                    intervalMinutes: intervalMinutes,
                    windowStartTime: windowStartTime.isEmpty ? nil : windowStartTime,
                    windowEndTime: windowEndTime.isEmpty ? nil : windowEndTime,
                    notes: notes.isEmpty ? nil : notes
                )
            )
            await refreshScheduledItems()
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": true,
                "item": scheduleDictionary(for: item),
                "summary_guidance": [
                    "Confirm what Rocky scheduled.",
                    "Mention the date and time naturally.",
                    "Mention whether it repeats."
                ]
            ])
        } catch {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": error.localizedDescription
            ])
        }
    }

    private func handleListScheduledItemsToolCall(_ toolCall: GeminiToolCall) {
        let statusFilter = (toolCall.args["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = min(max(toolCall.args["limit"] as? Int ?? 8, 1), 12)
        let filtered = scheduledItems
            .filter { statusFilter.isEmpty || $0.status.rawValue == statusFilter }
            .sorted { $0.effectiveTriggerDate < $1.effectiveTriggerDate }
        let items = Array(filtered.prefix(limit))

        gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
            "success": true,
            "count": filtered.count,
            "items": items.map(scheduleDictionary(for:)),
            "summary_guidance": [
                "Summarize the next few scheduled items in time order.",
                "Call out alarms separately if there are any.",
                "If nothing is scheduled, say that clearly."
            ]
        ])
    }

    private func handleCompleteScheduledItemToolCall(_ toolCall: GeminiToolCall) async {
        let itemID = (toolCall.args["item_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !itemID.isEmpty else {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": "Rocky needs the item_id before completing that scheduled item."
            ])
            return
        }

        do {
            let item = try await scheduleService.completeScheduledItem(id: itemID)
            await refreshScheduledItems()
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": true,
                "item": scheduleDictionary(for: item)
            ])
        } catch {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": error.localizedDescription
            ])
        }
    }

    private func handleSnoozeScheduledItemToolCall(_ toolCall: GeminiToolCall) async {
        let itemID = (toolCall.args["item_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = max(toolCall.args["minutes"] as? Int ?? 10, 1)
        guard !itemID.isEmpty else {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": "Rocky needs the item_id before snoozing that scheduled item."
            ])
            return
        }

        do {
            let item = try await scheduleService.snoozeScheduledItem(id: itemID, minutes: minutes)
            await refreshScheduledItems()
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": true,
                "item": scheduleDictionary(for: item)
            ])
        } catch {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": error.localizedDescription
            ])
        }
    }

    private func handleDeleteScheduledItemToolCall(_ toolCall: GeminiToolCall) async {
        let itemID = (toolCall.args["item_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !itemID.isEmpty else {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": "Rocky needs the item_id before deleting that scheduled item."
            ])
            return
        }

        do {
            try await scheduleService.deleteScheduledItem(id: itemID)
            await refreshScheduledItems()
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": true,
                "deleted_item_id": itemID
            ])
        } catch {
            gemini.sendToolResponse(id: toolCall.id, name: toolCall.name, response: [
                "success": false,
                "error": error.localizedDescription
            ])
        }
    }

    private func handleComposioMetaToolCall(_ toolCall: GeminiToolCall) async {
        guard let definition = composioMetaToolMap[toolCall.name] else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky couldn't find that Composio session tool anymore."
                ]
            )
            return
        }

        do {
            let result = try await pluginToolExecutionService.executeComposioTool(
                sessionID: definition.sessionID,
                toolSlug: definition.toolSlug,
                arguments: toolCall.args
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "tool_slug": definition.toolSlug,
                    "result": result
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleGoogleSheetsToolCall(_ toolCall: GeminiToolCall) async {
        let title = (toolCall.args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs a spreadsheet title before creating a Google Sheet."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .googleSheets) else {
            sendMissingPluginConnectionResponse(for: .googleSheets, toolCall: toolCall)
            return
        }

        do {
            let spreadsheet = try await pluginToolExecutionService.createGoogleSheet(
                connection: connection,
                title: title
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "spreadsheet": [
                        "spreadsheet_id": spreadsheet.spreadsheetID,
                        "title": spreadsheet.title,
                        "url": spreadsheet.url
                    ],
                    "summary_guidance": [
                        "Confirm that the spreadsheet was created successfully.",
                        "Share the sheet title and URL if available.",
                        "Offer to help the user plan the first columns or rows next."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleGoogleSheetsAppendRowsToolCall(_ toolCall: GeminiToolCall) async {
        let spreadsheetID = (toolCall.args["spreadsheet_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let range = (toolCall.args["range"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let headers = stringifyArray(toolCall.args["headers"])
        let rows = stringifyMatrix(toolCall.args["rows"])

        guard !spreadsheetID.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs a spreadsheet_id before it can append rows to Google Sheets."
                ]
            )
            return
        }

        guard !rows.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs at least one data row before it can write to Google Sheets."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .googleSheets) else {
            sendMissingPluginConnectionResponse(for: .googleSheets, toolCall: toolCall)
            return
        }

        do {
            let result = try await pluginToolExecutionService.appendRowsToGoogleSheet(
                connection: connection,
                spreadsheetID: spreadsheetID,
                rows: rows,
                headers: headers,
                range: range.isEmpty ? nil : range
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "appended_row_count": result.appendedRowCount,
                    "included_headers": result.includedHeaders,
                    "range": result.range,
                    "summary_guidance": [
                        "Confirm that the rows were written into the sheet.",
                        "Mention how many rows Rocky added.",
                        "Offer to add more rows or refine the format if useful."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleGoogleDriveToolCall(_ toolCall: GeminiToolCall) async {
        let query = (toolCall.args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 8, 1), 8)

        guard !query.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs a Drive search phrase before looking for files."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .googleDrive) else {
            sendMissingPluginConnectionResponse(for: .googleDrive, toolCall: toolCall)
            return
        }

        do {
            let files = try await pluginToolExecutionService.searchGoogleDriveFiles(
                connection: connection,
                query: query,
                maxResults: maxResults
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "file_count": files.count,
                    "files": files.map {
                        [
                            "id": $0.id,
                            "name": $0.name,
                            "mime_type": $0.mimeType,
                            "url": $0.url
                        ]
                    },
                    "summary_guidance": [
                        "Summarize only the most relevant 2 or 3 files first.",
                        "Mention file type when it helps the user choose.",
                        "If no good match appears, say that clearly and suggest a better search phrase."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleNotionToolCall(_ toolCall: GeminiToolCall) async {
        let query = (toolCall.args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 8, 1), 8)

        guard !query.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs a Notion search phrase before looking for pages."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .notion) else {
            sendMissingPluginConnectionResponse(for: .notion, toolCall: toolCall)
            return
        }

        do {
            let pages = try await pluginToolExecutionService.searchNotionPages(
                connection: connection,
                query: query,
                maxResults: maxResults
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "page_count": pages.count,
                    "pages": pages.map {
                        [
                            "id": $0.id,
                            "title": $0.title,
                            "url": $0.url
                        ]
                    },
                    "summary_guidance": [
                        "Lead with the best matching pages.",
                        "If the titles are weak, mention that the user may want to refine the search phrase."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleCreateNotionPageToolCall(_ toolCall: GeminiToolCall) async {
        let title = (toolCall.args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parentID = (toolCall.args["parent_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let markdown = (toolCall.args["markdown"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, !parentID.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs both a Notion page title and parent_id before creating a page."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .notion) else {
            sendMissingPluginConnectionResponse(for: .notion, toolCall: toolCall)
            return
        }

        do {
            let page = try await pluginToolExecutionService.createNotionPage(
                connection: connection,
                title: title,
                parentID: parentID,
                markdown: markdown.isEmpty ? nil : markdown
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "page": [
                        "id": page.id,
                        "title": page.title,
                        "url": page.url
                    ],
                    "summary_guidance": [
                        "Confirm that the Notion page was created.",
                        "Share the page title and URL if available."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleAppendNotionParagraphsToolCall(_ toolCall: GeminiToolCall) async {
        let blockID = (toolCall.args["block_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = stringifyArray(toolCall.args["paragraphs"])

        guard !blockID.isEmpty, !paragraphs.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs a Notion block_id and at least one paragraph before appending content."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .notion) else {
            sendMissingPluginConnectionResponse(for: .notion, toolCall: toolCall)
            return
        }

        do {
            let result = try await pluginToolExecutionService.appendParagraphsToNotionPage(
                connection: connection,
                blockID: blockID,
                paragraphs: paragraphs
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "appended_paragraph_count": result.appendedParagraphCount,
                    "summary_guidance": [
                        "Confirm that the Notion content was appended successfully.",
                        "Mention how many paragraphs Rocky added."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleGitHubToolCall(_ toolCall: GeminiToolCall) async {
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 8, 1), 8)

        guard let connection = pluginConnection(for: .github) else {
            sendMissingPluginConnectionResponse(for: .github, toolCall: toolCall)
            return
        }

        do {
            let repositories = try await pluginToolExecutionService.listGitHubRepositories(
                connection: connection,
                maxResults: maxResults
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "repository_count": repositories.count,
                    "repositories": repositories.map {
                        [
                            "id": $0.id,
                            "name": $0.name,
                            "full_name": $0.fullName,
                            "url": $0.url,
                            "description": $0.description,
                            "private": $0.isPrivate
                        ]
                    },
                    "summary_guidance": [
                        "Keep the repo overview concise and scannable.",
                        "Call out a few representative repositories instead of reading every field."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleCreateGitHubIssueToolCall(_ toolCall: GeminiToolCall) async {
        let owner = (toolCall.args["owner"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = (toolCall.args["repo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (toolCall.args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (toolCall.args["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !owner.isEmpty, !repo.isEmpty, !title.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs owner, repo, and title before creating a GitHub issue."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .github) else {
            sendMissingPluginConnectionResponse(for: .github, toolCall: toolCall)
            return
        }

        do {
            let issue = try await pluginToolExecutionService.createGitHubIssue(
                connection: connection,
                owner: owner,
                repo: repo,
                title: title,
                body: body.isEmpty ? nil : body
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "issue": [
                        "id": issue.id,
                        "title": issue.title,
                        "number": issue.number,
                        "url": issue.url
                    ],
                    "summary_guidance": [
                        "Confirm that the GitHub issue was created.",
                        "Mention the issue number and URL if available."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleLinearToolCall(_ toolCall: GeminiToolCall) async {
        let query = (toolCall.args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 8, 1), 8)

        guard let connection = pluginConnection(for: .linear) else {
            sendMissingPluginConnectionResponse(for: .linear, toolCall: toolCall)
            return
        }

        do {
            let issues = try await pluginToolExecutionService.searchLinearIssues(
                connection: connection,
                query: query.isEmpty ? nil : query,
                maxResults: maxResults
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "issue_count": issues.count,
                    "issues": issues.map {
                        [
                            "id": $0.id,
                            "identifier": $0.identifier,
                            "title": $0.title,
                            "state": $0.state,
                            "url": $0.url
                        ]
                    },
                    "summary_guidance": [
                        "Mention the most relevant issues first.",
                        "Include the issue identifier when available.",
                        "If the user gave no query, frame the result as a recent issue list."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleLinearTeamsToolCall(_ toolCall: GeminiToolCall) async {
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 8, 1), 8)

        guard let connection = pluginConnection(for: .linear) else {
            sendMissingPluginConnectionResponse(for: .linear, toolCall: toolCall)
            return
        }

        do {
            let teams = try await pluginToolExecutionService.listLinearTeams(
                connection: connection,
                maxResults: maxResults
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "team_count": teams.count,
                    "teams": teams.map {
                        [
                            "id": $0.id,
                            "key": $0.key,
                            "name": $0.name
                        ]
                    },
                    "summary_guidance": [
                        "Use this team list only when the user asks which teams are available or wants to change the default team.",
                        "If the user only wants to create an issue, prefer create_linear_issue without asking for a team.",
                        "Prefer showing both team name and team key."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleLinearStatesToolCall(_ toolCall: GeminiToolCall) async {
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 8, 1), 12)
        let teamID = (toolCall.args["team_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard let connection = pluginConnection(for: .linear) else {
            sendMissingPluginConnectionResponse(for: .linear, toolCall: toolCall)
            return
        }

        do {
            let states = try await pluginToolExecutionService.listLinearStates(
                connection: connection,
                teamID: resolvedLinearTeamID(explicitTeamID: teamID),
                maxResults: maxResults
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "state_count": states.count,
                    "states": states.map {
                        [
                            "id": $0.id,
                            "name": $0.name,
                            "type": $0.type
                        ]
                    },
                    "summary_guidance": [
                        "Use this only when the user wants to know valid Linear workflow statuses or Rocky needs a status name before updating an issue.",
                        "Prefer showing the exact state names the user can say, such as Todo, In Progress, or Done.",
                        "If the user already gave a valid status, prefer update_linear_issue_status directly."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleCreateLinearIssueToolCall(_ toolCall: GeminiToolCall) async {
        let title = (toolCall.args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let teamID = (toolCall.args["team_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (toolCall.args["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = toolCall.args["priority"] as? Int

        guard !title.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs a Linear issue title before creating an issue."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .linear) else {
            sendMissingPluginConnectionResponse(for: .linear, toolCall: toolCall)
            return
        }

        do {
            let issue = try await pluginToolExecutionService.createLinearIssue(
                connection: connection,
                title: title,
                teamID: resolvedLinearTeamID(explicitTeamID: teamID),
                description: description.isEmpty ? nil : description,
                priority: priority
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "issue": [
                        "id": issue.id,
                        "identifier": issue.identifier,
                        "title": issue.title,
                        "url": issue.url
                    ],
                    "summary_guidance": [
                        "Confirm that the Linear issue was created.",
                        "Mention the issue identifier and URL if available."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleUpdateLinearIssueStatusToolCall(_ toolCall: GeminiToolCall) async {
        let issueID = (toolCall.args["issue_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let status = (toolCall.args["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let teamID = (toolCall.args["team_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !issueID.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs the exact Linear issue id before updating its status."
                ]
            )
            return
        }

        guard !status.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs the target Linear status name before updating the issue."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .linear) else {
            sendMissingPluginConnectionResponse(for: .linear, toolCall: toolCall)
            return
        }

        do {
            let issue = try await pluginToolExecutionService.updateLinearIssueStatus(
                connection: connection,
                issueID: issueID,
                status: status,
                teamID: resolvedLinearTeamID(explicitTeamID: teamID)
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "issue": [
                        "id": issue.id,
                        "identifier": issue.identifier,
                        "title": issue.title,
                        "state": issue.state,
                        "url": issue.url
                    ],
                    "summary_guidance": [
                        "Confirm that the Linear issue status was updated.",
                        "Mention the issue identifier and the new state name.",
                        "Include the issue URL if it is available."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleSlackChannelsToolCall(_ toolCall: GeminiToolCall) async {
        let query = (toolCall.args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxResults = min(max(toolCall.args["max_results"] as? Int ?? 8, 1), 8)

        guard let connection = pluginConnection(for: .slack) else {
            sendMissingPluginConnectionResponse(for: .slack, toolCall: toolCall)
            return
        }

        do {
            let channels = try await pluginToolExecutionService.listSlackChannels(
                connection: connection,
                query: query.isEmpty ? nil : query,
                maxResults: maxResults
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "channel_count": channels.count,
                    "channels": channels.map {
                        [
                            "id": $0.id,
                            "name": $0.name,
                            "is_private": $0.isPrivate
                        ]
                    },
                    "summary_guidance": [
                        "Use this to help the user choose a Slack channel.",
                        "If the user wants to post, suggest using the exact channel name from the list."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func handleSlackSendMessageToolCall(_ toolCall: GeminiToolCall) async {
        let channel = (toolCall.args["channel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (toolCall.args["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !channel.isEmpty, !text.isEmpty else {
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": false,
                    "error": "Rocky needs both a Slack channel and message text before sending."
                ]
            )
            return
        }

        guard let connection = pluginConnection(for: .slack) else {
            sendMissingPluginConnectionResponse(for: .slack, toolCall: toolCall)
            return
        }

        do {
            let message = try await pluginToolExecutionService.sendSlackMessage(
                connection: connection,
                channel: channel,
                text: text
            )
            gemini.sendToolResponse(
                id: toolCall.id,
                name: toolCall.name,
                response: [
                    "success": true,
                    "provider": connection.provider.rawValue,
                    "message": [
                        "channel": message.channel,
                        "timestamp": message.timestamp,
                        "permalink": message.permalink
                    ],
                    "summary_guidance": [
                        "Confirm that the Slack message was sent.",
                        "Repeat the target channel and share a permalink if one is available."
                    ]
                ]
            )
        } catch {
            sendPluginActionErrorResponse(toolCall: toolCall, error: error)
        }
    }

    private func sendMissingPluginConnectionResponse(for provider: PluginProvider, toolCall: GeminiToolCall) {
        gemini.sendToolResponse(
            id: toolCall.id,
            name: toolCall.name,
            response: [
                "success": false,
                "error": "\(provider.title) isn't connected yet. Open Plugins in Control Center and connect \(provider.title) first.",
                "requires_connection": true,
                "provider": provider.rawValue,
            ]
        )
    }

    private func sendPluginActionErrorResponse(toolCall: GeminiToolCall, error: Error) {
        gemini.sendToolResponse(
            id: toolCall.id,
            name: toolCall.name,
            response: [
                "success": false,
                "error": error.localizedDescription,
                "requires_connection": false,
            ]
        )
    }

    private func stringifyArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { entry in
            let text = String(describing: entry).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    private func stringifyMatrix(_ value: Any?) -> [[String]] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let entries = row as? [Any] else { return nil }
            let stringRow = entries.map { String(describing: $0) }
            return stringRow.isEmpty ? nil : stringRow
        }
    }

    private func putPetToSleep() {
        consecutiveInterruptFrames = 0
        capture.stop()
        playback.stop()
        gemini.endAudioStream()
        setSleeping(true)
        userSelectedState = .sleeping
        brainState = .idle
        statusText = "Sleeping"
        setPetState(.sleeping)
    }

    private func wakePet() {
        consecutiveInterruptFrames = 0
        setSleeping(false)
        userSelectedState = nil
        setBrainState(.idle)
    }

    private func setSleeping(_ sleeping: Bool) {
        if sleeping, !isSleeping {
            playSleepSound()
        }

        isSleeping = sleeping
        isPetSleeping = sleeping
        if sleeping {
            ambientState = nil
        }
        if sleeping {
            isTranscriptVisible = false
        } else {
            sleepSoundPlayer?.stop()
            sleepSoundPlayer = nil
        }
    }

    private func syncPetStateWithBrain() {
        if isSleeping {
            setPetState(.sleeping)
            return
        }

        if let ambientState, brainState == .idle, !isDraggingPet, !hasPinnedManualState {
            setPetState(ambientState)
            return
        }

        switch brainState {
        case .idle:
            setPetState(.idle)
        case .ready:
            setPetState(.idle)
        case .connecting, .thinking:
            setPetState(.thinking)
        case .listening:
            setPetState(.talking)
        case .speaking:
            setPetState(.talking)
        case .error:
            setPetState(.sleeping)
        }
    }

    private func setPetState(_ state: PetState) {
        petState = state
    }

    private func playSleepSound() {
        guard let url = Bundle.main.url(
            forResource: "baby-sleeping-breathing",
            withExtension: "mp3"
        ) else {
            return
        }

        do {
            sleepSoundPlayer = try AVAudioPlayer(contentsOf: url)
            sleepSoundPlayer?.volume = 0.35
            sleepSoundPlayer?.numberOfLoops = -1
            sleepSoundPlayer?.play()
        } catch {
            return
        }
    }

    private var canShowDragState: Bool {
        guard !isSleeping, brainState == .idle || brainState == .ready else { return false }
        return petState == .idle || petState == .walkingLeft || petState == .walkingRight
    }

    private var hasPinnedManualState: Bool {
        guard let userSelectedState else { return false }
        return userSelectedState != .idle
    }

    private var readyBrainState: PetBrainState {
        conversationInputMode == .voice ? .listening : .ready
    }

    func setShouldSpeakTypedReplies(_ enabled: Bool) {
        let didChange = shouldSpeakTypedReplies != enabled
        shouldSpeakTypedReplies = enabled
        UserDefaults.standard.set(enabled, forKey: typedReplySpeechDefaultsKeyPrefix + selectedPet.rawValue)
        if !enabled {
            playback.stop()
        }

        guard didChange else { return }
        guard conversationInputMode == .text else { return }
        guard brainState != .idle && brainState != .error else { return }

        restartConversation(resetDisplayedTranscript: false)
    }

    func setUserName(_ name: String) {
        userName = name
        UserProfileSettings.setUserName(name)
    }

    func setSavedAPIKey(_ key: String) {
        savedAPIKey = key
        GeminiSettings.setAPIKey(key)
    }

    func setIdleSleepDelaySeconds(_ seconds: Int) {
        let sanitized = max(1, seconds)
        idleSleepDelaySeconds = sanitized
        UserProfileSettings.setIdleSleepDelaySeconds(sanitized)
    }

    func setShortcutPreferences(_ preferences: RockyShortcutPreferences) {
        shortcutPreferences = preferences
        UserProfileSettings.setShortcutPreferences(preferences)
    }

    func refreshScheduledItems() async {
        do {
            let items = try await scheduleService.fetchScheduledItems()
                .sorted { $0.effectiveTriggerDate < $1.effectiveTriggerDate }
            scheduledItems = items
            scheduleLastSyncedAt = Date()
            scheduleStatusText = items.isEmpty ? "No tasks, reminders, or alarms scheduled yet." : "Synced \(items.count) scheduled item\(items.count == 1 ? "" : "s")."
            await scheduleService.synchronizeNotifications(for: items)
        } catch {
            scheduleStatusText = error.localizedDescription
        }
    }

    func processDueScheduledItems() {
        let now = Date()
        let lookback = min(max(now.timeIntervalSince(lastScheduleDueCheckAt), 30), 300)
        let windowStart = now.addingTimeInterval(-lookback)

        for item in scheduledItems where item.isPending {
            let dueOccurrences = scheduleService.dueOccurrences(for: item, since: windowStart, until: now)
            for occurrence in dueOccurrences {
                let occurrenceKey = scheduleOccurrenceKey(for: item, occurrence: occurrence)
                guard !announcedScheduleOccurrenceKeys.contains(occurrenceKey) else { continue }
                announcedScheduleOccurrenceKeys.insert(occurrenceKey)
                announceScheduledItemDue(item, occurrence: occurrence)
            }
        }

        lastScheduleDueCheckAt = now
    }

    func refreshScheduleNotificationAuthorizationState() async {
        scheduleNotificationAuthorizationState = await scheduleService.notificationAuthorizationStatus()
    }

    func requestScheduleNotificationAuthorization() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.scheduleNotificationAuthorizationState = await self.scheduleService.requestNotificationAuthorization()
        }
    }

    func completeScheduledItem(_ item: ScheduledItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.scheduleService.completeScheduledItem(id: item.id)
            await self.refreshScheduledItems()
        }
    }

    func snoozeScheduledItem(_ item: ScheduledItem, minutes: Int = 10) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.scheduleService.snoozeScheduledItem(id: item.id, minutes: minutes)
            await self.refreshScheduledItems()
        }
    }

    func deleteScheduledItem(_ item: ScheduledItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.scheduleService.deleteScheduledItem(id: item.id)
            await self.refreshScheduledItems()
        }
    }

    func handleScheduleNotificationAction(identifier: String, userInfo: [AnyHashable: Any]) {
        guard let itemID = scheduleService.notificationItemID(from: userInfo),
              let item = scheduledItems.first(where: { $0.id == itemID }) else {
            return
        }

        switch identifier {
        case "ROCKY_SCHEDULE_COMPLETE":
            completeScheduledItem(item)
        case "ROCKY_SCHEDULE_SNOOZE_10":
            snoozeScheduledItem(item, minutes: 10)
        default:
            break
        }
    }

    private func announceScheduledItemDue(_ item: ScheduledItem, occurrence: Date) {
        let announcement = announcementText(for: item)
        latestAITranscript = announcement
        isTranscriptVisible = true

        if canPerformAmbientActions {
            _ = setAmbientState(.happy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.clearAmbientState()
            }
        }

        scheduleSpeechSynthesizer.stopSpeaking()
        scheduleSpeechSynthesizer.startSpeaking(announcement)

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let refreshedItem = try? await self.scheduleService.markScheduledItemDelivered(item) {
                if let index = self.scheduledItems.firstIndex(where: { $0.id == refreshedItem.id }) {
                    self.scheduledItems[index] = refreshedItem
                }
            }
        }
    }

    func pluginConnection(for provider: PluginProvider) -> PluginConnection? {
        pluginConnections.first(where: { $0.provider == provider })
    }

    var isGmailPluginConnected: Bool {
        pluginConnection(for: .gmail) != nil
    }

    func connectPlugin(_ provider: PluginProvider) {
        guard connectingPluginProvider == nil else { return }

        connectingPluginProvider = provider
        pluginConnectionStatusProvider = provider
        pluginConnectionStatusText = "Opening \(provider.title) sign-in..."

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.connectingPluginProvider = nil }

            do {
                let connection = try await self.pluginConnectionService.connect(provider: provider)
                self.upsertPluginConnection(connection)
                await self.refreshComposioMetaTools()
                if provider == .linear {
                    await self.refreshLinearTeams(autoSelectIfNeeded: true)
                }
                self.pluginConnectionStatusText = "\(provider.title) connected."
            } catch {
                self.pluginConnectionStatusText = error.localizedDescription
            }
        }
    }

    func disconnectPlugin(_ provider: PluginProvider) {
        pluginConnectionService.disconnect(provider: provider)
        pluginConnections.removeAll(where: { $0.provider == provider })
        pluginConnectionStatusProvider = provider
        pluginConnectionStatusText = "\(provider.title) disconnected."
        if provider == .gmail {
            gmailFollowUpActions = []
        }
        if provider == .linear {
            linearTeams = []
            setDefaultLinearTeam(nil)
        }
        Task { @MainActor [weak self] in
            await self?.refreshComposioMetaTools()
        }
    }

    func connectMemoryAccount() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                _ = try await self.memoryService.connectAccount()
                self.isMemoryAccountConnected = true
                self.memorySettings = try await self.memoryService.fetchMemorySettings()
                self.memoryContextStatusText = "Memory account connected."
            } catch {
                self.memoryContextStatusText = error.localizedDescription
            }
        }
    }

    func disconnectMemoryAccount() {
        memoryService.signOut()
        isMemoryAccountConnected = false
        activeConversationID = nil
        cachedMemoryInstructionText = ""
        memorySettings = .defaults
        memoryContextStatusText = "Memory account disconnected."
    }

    func refreshMemorySettings() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.memoryService.hasAuthenticatedSession else {
                self.isMemoryAccountConnected = false
                self.memorySettings = .defaults
                self.memoryContextStatusText = "Memory account not connected."
                return
            }

            do {
                self.isMemoryAccountConnected = true
                self.memorySettings = try await self.memoryService.fetchMemorySettings()
                self.memoryContextStatusText = "Memory settings refreshed."
            } catch {
                self.memoryContextStatusText = error.localizedDescription
            }
        }
    }

    func setMemoryEnabled(_ value: Bool) {
        updateMemorySettings { settings in
            MemorySettingsRecord(
                userID: settings.userID,
                memoryEnabled: value,
                profileMemoryEnabled: settings.profileMemoryEnabled,
                projectMemoryEnabled: settings.projectMemoryEnabled,
                preferenceMemoryEnabled: settings.preferenceMemoryEnabled,
                sensitiveMemoryEnabled: settings.sensitiveMemoryEnabled,
                autoExtractEnabled: settings.autoExtractEnabled,
                retentionDays: settings.retentionDays
            )
        }
    }

    func setProfileMemoryEnabled(_ value: Bool) {
        updateMemorySettings { settings in
            MemorySettingsRecord(
                userID: settings.userID,
                memoryEnabled: settings.memoryEnabled,
                profileMemoryEnabled: value,
                projectMemoryEnabled: settings.projectMemoryEnabled,
                preferenceMemoryEnabled: settings.preferenceMemoryEnabled,
                sensitiveMemoryEnabled: settings.sensitiveMemoryEnabled,
                autoExtractEnabled: settings.autoExtractEnabled,
                retentionDays: settings.retentionDays
            )
        }
    }

    func setProjectMemoryEnabled(_ value: Bool) {
        updateMemorySettings { settings in
            MemorySettingsRecord(
                userID: settings.userID,
                memoryEnabled: settings.memoryEnabled,
                profileMemoryEnabled: settings.profileMemoryEnabled,
                projectMemoryEnabled: value,
                preferenceMemoryEnabled: settings.preferenceMemoryEnabled,
                sensitiveMemoryEnabled: settings.sensitiveMemoryEnabled,
                autoExtractEnabled: settings.autoExtractEnabled,
                retentionDays: settings.retentionDays
            )
        }
    }

    func setPreferenceMemoryEnabled(_ value: Bool) {
        updateMemorySettings { settings in
            MemorySettingsRecord(
                userID: settings.userID,
                memoryEnabled: settings.memoryEnabled,
                profileMemoryEnabled: settings.profileMemoryEnabled,
                projectMemoryEnabled: settings.projectMemoryEnabled,
                preferenceMemoryEnabled: value,
                sensitiveMemoryEnabled: settings.sensitiveMemoryEnabled,
                autoExtractEnabled: settings.autoExtractEnabled,
                retentionDays: settings.retentionDays
            )
        }
    }

    func setSensitiveMemoryEnabled(_ value: Bool) {
        updateMemorySettings { settings in
            MemorySettingsRecord(
                userID: settings.userID,
                memoryEnabled: settings.memoryEnabled,
                profileMemoryEnabled: settings.profileMemoryEnabled,
                projectMemoryEnabled: settings.projectMemoryEnabled,
                preferenceMemoryEnabled: settings.preferenceMemoryEnabled,
                sensitiveMemoryEnabled: value,
                autoExtractEnabled: settings.autoExtractEnabled,
                retentionDays: settings.retentionDays
            )
        }
    }

    func setAutoExtractEnabled(_ value: Bool) {
        updateMemorySettings { settings in
            MemorySettingsRecord(
                userID: settings.userID,
                memoryEnabled: settings.memoryEnabled,
                profileMemoryEnabled: settings.profileMemoryEnabled,
                projectMemoryEnabled: settings.projectMemoryEnabled,
                preferenceMemoryEnabled: settings.preferenceMemoryEnabled,
                sensitiveMemoryEnabled: settings.sensitiveMemoryEnabled,
                autoExtractEnabled: value,
                retentionDays: settings.retentionDays
            )
        }
    }

    private func flushPendingTypedMessages() {
        guard hasCompletedSetup, !pendingTypedMessages.isEmpty else { return }

        let queuedMessages = pendingTypedMessages
        pendingTypedMessages.removeAll()
        setBrainState(.thinking)

        for message in queuedMessages {
            gemini.sendTextTurn(message)
        }
    }

    private func typedReplySpeechPreference(for pet: PetCharacter) -> Bool {
        let key = typedReplySpeechDefaultsKeyPrefix + pet.rawValue
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: key)
    }

    private var shouldRequestAudioResponses: Bool {
        conversationInputMode == .voice || shouldSpeakTypedReplies
    }

    private func restartConversation(resetDisplayedTranscript: Bool) {
        pendingConversationRestart = true
        pendingConversationRestartResetDisplayedTranscript = resetDisplayedTranscript
        isRestartingConversationInternally = true
        shouldSendStartupGreeting = false
        hasCompletedSetup = false
        capture.stop()
        playback.stop()
        gemini.endAudioStream()
        gemini.disconnect()
    }

    func runGmailFollowUpAction(_ action: GmailFollowUpAction) {
        sendTypedMessage(action.prompt)
    }

    func selectDefaultLinearTeam(withID teamID: String) {
        guard let team = linearTeams.first(where: { $0.id == teamID }) else { return }
        pluginConnectionStatusProvider = .linear
        setDefaultLinearTeam(LinearTeamPreference(id: team.id, key: team.key, name: team.name))
        pluginConnectionStatusText = "Default Linear team set to \(team.name)."
    }

    func fetchLinearTeamsForSelection() {
        Task { @MainActor [weak self] in
            await self?.refreshLinearTeams(autoSelectIfNeeded: true)
        }
    }

    private func upsertPluginConnection(_ connection: PluginConnection) {
        pluginConnections.removeAll(where: { $0.provider == connection.provider })
        pluginConnections.append(connection)
        pluginConnections.sort { $0.provider.rawValue < $1.provider.rawValue }
    }

    private func refreshComposioMetaTools() async {
        guard let sessionID = pluginConnections.compactMap(\.composioToolRouterSessionID).first, !sessionID.isEmpty else {
            composioMetaToolMap = [:]
            return
        }

        do {
            let tools = try await pluginToolExecutionService.fetchComposioMetaTools(sessionID: sessionID)
            composioMetaToolMap = Dictionary(uniqueKeysWithValues: tools.map { ($0.functionName, $0) })
        } catch {
            composioMetaToolMap = [:]
        }
    }

    private func refreshLinearTeamsIfNeeded() async {
        guard pluginConnection(for: .linear) != nil else { return }
        await refreshLinearTeams(autoSelectIfNeeded: defaultLinearTeam == nil)
    }

    private func refreshLinearTeams(autoSelectIfNeeded: Bool) async {
        guard let connection = pluginConnection(for: .linear) else {
            linearTeams = []
            return
        }

        isLoadingLinearTeams = true
        defer { isLoadingLinearTeams = false }

        do {
            let teams = try await pluginToolExecutionService.listLinearTeams(connection: connection, maxResults: 8)
            pluginConnectionStatusProvider = .linear
            linearTeams = teams

            if let savedTeam = defaultLinearTeam,
               teams.contains(where: { $0.id == savedTeam.id }) == false {
                setDefaultLinearTeam(nil)
            }

            if autoSelectIfNeeded, defaultLinearTeam == nil, let team = teams.first {
                setDefaultLinearTeam(LinearTeamPreference(id: team.id, key: team.key, name: team.name))
            }

            if teams.isEmpty {
                pluginConnectionStatusText = "No Linear teams were returned."
            } else {
                pluginConnectionStatusText = "Fetched \(teams.count) Linear team\(teams.count == 1 ? "" : "s")."
            }
        } catch {
            linearTeams = []
            pluginConnectionStatusProvider = .linear
            pluginConnectionStatusText = "Rocky couldn't fetch Linear teams right now."
        }
    }

    private func setDefaultLinearTeam(_ team: LinearTeamPreference?) {
        defaultLinearTeam = team
        UserProfileSettings.setDefaultLinearTeam(team)
    }

    private func resolvedLinearTeamID(explicitTeamID: String) -> String? {
        let trimmed = explicitTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return defaultLinearTeam?.id
    }

    private var currentDateContextInstruction: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = .current
        let currentDateString = formatter.string(from: Date())
        return "The user's current local date and time is \(currentDateString). The user's timezone is \(TimeZone.current.identifier). When creating tasks, reminders, or alarms, always convert relative times into exact ISO 8601 timestamps in the scheduled_at field. For schedules like every two hours from 9 AM to 12 PM, use interval_minutes plus window_start_time and window_end_time in HH:mm 24-hour format."
    }

    private func updateMemorySettings(
        transform: @escaping (MemorySettingsRecord) -> MemorySettingsRecord
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.memoryService.hasAuthenticatedSession else {
                self.isMemoryAccountConnected = false
                self.memoryContextStatusText = "Memory account not connected."
                return
            }

            do {
                let updated = transform(self.memorySettings)
                self.memorySettings = try await self.memoryService.updateMemorySettings(updated)
                self.memoryContextStatusText = "Memory settings updated."
            } catch {
                self.memoryContextStatusText = error.localizedDescription
            }
        }
    }

    private func combinedAdditionalInstructionText() async -> String {
        let memoryInstruction = await prepareMemoryInstructionText()
        return [currentDateContextInstruction, memoryInstruction]
            .compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n\n")
    }

    private func prepareMemoryInstructionText() async -> String {
        guard memoryService.hasAuthenticatedSession else {
            isMemoryAccountConnected = false
            memoryContextStatusText = "Memory account not connected."
            cachedMemoryInstructionText = ""
            return ""
        }

        do {
            isMemoryAccountConnected = true
            let conversationID = try await memoryService.createConversation(existingConversationID: activeConversationID)
            activeConversationID = conversationID
            let context = try await memoryService.fetchConversationContext(conversationID: conversationID)
            let instruction = memoryService.buildInstructionText(from: context) ?? ""
            cachedMemoryInstructionText = instruction
            memoryContextStatusText = instruction.isEmpty
                ? "Memory connected. No relevant memory yet."
                : "Memory connected and ready."
            return instruction
        } catch {
            memoryContextStatusText = error.localizedDescription
            cachedMemoryInstructionText = ""
            return ""
        }
    }

    private func persistCompletedConversationTurnIfNeeded() {
        let userTranscript = currentTurnUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let aiTranscript = currentTurnAITranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        currentTurnUserTranscript = ""
        currentTurnAITranscript = ""

        guard memoryService.hasAuthenticatedSession else { return }
        guard !userTranscript.isEmpty || !aiTranscript.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let conversationID = try await self.memoryService.createConversation(existingConversationID: self.activeConversationID)
                self.activeConversationID = conversationID
                try await self.memoryService.appendCompletedTurn(
                    conversationID: conversationID,
                    userText: userTranscript.isEmpty ? nil : userTranscript,
                    assistantText: aiTranscript.isEmpty ? nil : aiTranscript
                )

                let context = try await self.memoryService.fetchConversationContext(conversationID: conversationID)
                self.cachedMemoryInstructionText = self.memoryService.buildInstructionText(from: context) ?? ""
                self.memoryContextStatusText = "Memory synced."
            } catch {
                self.memoryContextStatusText = error.localizedDescription
            }
        }
    }

    private func parseISODate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func scheduleDictionary(for item: ScheduledItem) -> [String: Any] {
        [
            "id": item.id,
            "title": item.title,
            "kind": item.kind.rawValue,
            "scheduled_at": ISO8601DateFormatter().string(from: item.scheduledFor),
            "effective_trigger_at": ISO8601DateFormatter().string(from: item.effectiveTriggerDate),
            "repeat_rule": item.repeatRule.rawValue,
            "interval_minutes": item.intervalMinutes ?? 0,
            "window_start_time": item.windowStartTime ?? "",
            "window_end_time": item.windowEndTime ?? "",
            "status": item.status.rawValue,
            "notes": item.notes ?? ""
        ]
    }

    private func scheduleOccurrenceKey(for item: ScheduledItem, occurrence: Date) -> String {
        "\(item.id)::\(Int(occurrence.timeIntervalSince1970 / 60))"
    }

    private func announcementText(for item: ScheduledItem) -> String {
        switch item.kind {
        case .task:
            return "\(selectedPet.displayName) says your task is due: \(item.title)."
        case .reminder:
            return "\(selectedPet.displayName) says reminder time: \(item.title)."
        case .alarm:
            return "\(selectedPet.displayName) says your alarm is going off: \(item.title)."
        }
    }

    private func makeGmailFollowUpActions(from messages: [GmailMessageSummary]) -> [GmailFollowUpAction] {
        var actions: [GmailFollowUpAction] = [
            GmailFollowUpAction(
                id: "important",
                title: "Show important",
                prompt: "Check my Gmail again and show only important unread emails."
            ),
            GmailFollowUpAction(
                id: "today",
                title: "Today only",
                prompt: "Check my Gmail again and show only today's unread emails."
            )
        ]

        if let sender = topGmailSender(from: messages) {
            actions.append(
                GmailFollowUpAction(
                    id: "sender:\(sender.lowercased())",
                    title: sender,
                    prompt: "Check my Gmail again and show emails only from \(sender)."
                )
            )
        }

        actions.append(
            GmailFollowUpAction(
                id: "action",
                title: "Needs action",
                prompt: "Check my Gmail again and tell me which unread emails need action first."
            )
        )

        return actions
    }

    private func topGmailSender(from messages: [GmailMessageSummary]) -> String? {
        let senders = messages
            .map(\.sender)
            .map { raw in
                raw
                    .components(separatedBy: "<")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                ?? raw
            }
            .filter { !$0.isEmpty && $0.lowercased() != "unknown sender" }

        guard !senders.isEmpty else { return nil }

        let counts = senders.reduce(into: [String: Int]()) { partialResult, sender in
            partialResult[sender, default: 0] += 1
        }

        return counts.max {
            if $0.value == $1.value {
                return $0.key > $1.key
            }
            return $0.value < $1.value
        }?.key
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
