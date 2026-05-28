import AppKit
import SwiftUI

private enum ControlCenterTab: String, CaseIterable, Identifiable {
    case settings
    case pet
    case plugins
    case schedule
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings:
            return "General"
        case .pet:
            return "Pet"
        case .plugins:
            return "Plugins"
        case .schedule:
            return "Schedule"
        case .memory:
            return "Memory"
        }
    }

    var iconName: String {
        switch self {
        case .settings:
            return "gearshape"
        case .pet:
            return "face.smiling"
        case .plugins:
            return "puzzlepiece.extension"
        case .schedule:
            return "calendar.badge.clock"
        case .memory:
            return "brain.head.profile"
        }
    }
}

struct ControlCenterView: View {
    @ObservedObject var brain: PetBrainViewModel
    @ObservedObject var updateService: AppUpdateService
    @State private var selectedTab: ControlCenterTab = .settings
    @State private var draftName: String
    @State private var draftAPIKey: String
    @State private var draftIdleSleepDelay: String
    @State private var draftShortcutPreferences: RockyShortcutPreferences
    @State private var pluginSearchText = ""
    @Environment(\.colorScheme) private var colorScheme

    init(brain: PetBrainViewModel, updateService: AppUpdateService) {
        self.brain = brain
        self.updateService = updateService
        _draftName = State(initialValue: brain.userName)
        _draftAPIKey = State(initialValue: brain.savedAPIKey)
        _draftIdleSleepDelay = State(initialValue: String(brain.idleSleepDelaySeconds))
        _draftShortcutPreferences = State(initialValue: brain.shortcutPreferences)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar
            Divider()
            tabContent
        }
        .frame(minWidth: 720, idealWidth: 800, minHeight: 560, idealHeight: 620)
        .background(windowBackgroundColor)
        .onChange(of: brain.userName) { _, newValue in
            if draftName != newValue {
                draftName = newValue
            }
        }
        .onChange(of: brain.savedAPIKey) { _, newValue in
            if draftAPIKey != newValue {
                draftAPIKey = newValue
            }
        }
        .onChange(of: brain.idleSleepDelaySeconds) { _, newValue in
            let nextValue = String(newValue)
            if draftIdleSleepDelay != nextValue {
                draftIdleSleepDelay = nextValue
            }
        }
        .onChange(of: brain.shortcutPreferences) { _, newValue in
            if draftShortcutPreferences != newValue {
                draftShortcutPreferences = newValue
            }
        }
    }

    private var header: some View {
        HStack {
            Text(selectedTab.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(ControlCenterTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 18, weight: selectedTab == tab ? .medium : .regular))
                            .foregroundStyle(selectedTab == tab ? selectedAccentColor : Color.secondary)
                            .frame(height: 20)

                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                    }
                    .frame(width: 74, height: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedTab {
                case .settings:
                    settingsYouSection
                    settingsBehaviourSection
                    settingsUpdatesSection
                    settingsShortcutsSection
                    settingsMovementSection
                    applySettingsSection
                case .pet:
                    petSection
                case .plugins:
                    pluginsSection
                case .schedule:
                    scheduleSection
                case .memory:
                    memorySection
                }
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }

    private var settingsYouSection: some View {
        settingsSection(title: "You", subtitle: "Tell Rocky who you are and which Gemini key to use.") {
            VStack(alignment: .leading, spacing: 16) {
                settingsRow(title: "Name") {
                    inputField {
                        TextField("Your name", text: $draftName)
                            .textFieldStyle(.plain)
                    }
                }

                settingsRow(title: "Gemini API Key") {
                    inputField {
                        TextField("AIza...", text: $draftAPIKey)
                            .textFieldStyle(.plain)
                    }
                }
            }
        }
    }

    private var settingsBehaviourSection: some View {
        settingsSection(title: "Behaviour", subtitle: "Control how Rocky behaves during chat.") {
            settingsRow(title: "Speak during typing chat", alignment: .center) {
                HStack(spacing: 14) {
                    Text(brain.shouldSpeakTypedReplies ? "Typed replies include voice." : "Typed replies stay text-only.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)

                    Spacer(minLength: 0)

                    Toggle("", isOn: Binding(
                        get: { brain.shouldSpeakTypedReplies },
                        set: { brain.setShouldSpeakTypedReplies($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var settingsUpdatesSection: some View {
        settingsSection(title: "Updates", subtitle: "Check for new Rocky builds without enabling background auto-updates.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    scheduleInfoCard(
                        title: "Current Version",
                        value: updateService.versionDescription,
                        detail: "Rocky compares this build with the macOS version metadata in the updates repo."
                    )

                    scheduleInfoCard(
                        title: "Update Mode",
                        value: "Version JSON",
                        detail: "Rocky only checks for updates when you click the button."
                    )
                }

                settingsRow(title: "Status", alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(updateService.updaterStatusText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.primary)

                        Text("If a newer DMG is listed in macOS version metadata, Rocky downloads it, replaces the current app, and relaunches.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button("Check for Updates") {
                        updateService.checkForUpdates()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedAccentColor, in: Capsule())

                    Button("Open Releases") {
                        updateService.openReleasesPage()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(controlSurfaceColor, in: Capsule())
                }
                .padding(.leading, 220)
            }
        }
    }

    private var settingsShortcutsSection: some View {
        settingsSection(title: "Shortcuts", subtitle: "Choose the keyboard shortcuts Rocky listens for globally.") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(RockyShortcutAction.allCases) { action in
                    settingsRow(title: action.title, alignment: .center) {
                        HStack(spacing: 12) {
                            ShortcutRecorderField(shortcut: Binding(
                                get: { draftShortcutPreferences.shortcut(for: action) },
                                set: { updateShortcut($0, for: action) }
                            ))
                            .frame(width: 180, height: 44)

                            Text(action.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 12) {
                    Button("Reset to Defaults") {
                        draftShortcutPreferences = .defaults
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedAccentColor)

                    Text("Each shortcut needs at least one modifier key, and every action must use a unique combo.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.leading, 220)

                if let shortcutValidationError {
                    Text(shortcutValidationError)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.leading, 220)
                }
            }
        }
    }

    private var settingsMovementSection: some View {
        settingsSection(title: "Movement", subtitle: "Control how Rocky behaves when your cursor stays idle.") {
            VStack(alignment: .leading, spacing: 16) {
                settingsRow(title: "Sleep after idle") {
                    inputField {
                        HStack(spacing: 10) {
                            TextField("90", text: $draftIdleSleepDelay)
                                .textFieldStyle(.plain)
                                .onChange(of: draftIdleSleepDelay) { _, newValue in
                                    draftIdleSleepDelay = filteredSecondsInput(from: newValue)
                                }

                            Text("seconds")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                Text("By default Rocky sleeps after 90 seconds of no cursor movement.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .padding(.leading, 220)
            }
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                sectionHeader(
                    title: "Plugins",
                    subtitle: "Connect the services Rocky can use across work, planning, files, and communication."
                )

                pluginSearchField
                    .frame(width: 220)
            }

            if filteredPluginProviders.isEmpty {
                Text("No plugins match \"\(pluginSearchText)\".")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 4)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredPluginProviders) { provider in
                        pluginCard(for: provider)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var applySettingsSection: some View {
        HStack {
            Spacer()

            Button(action: applySettings) {
                Text("Apply Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasPendingSettingsChanges && shortcutValidationError == nil ? .white : Color.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        hasPendingSettingsChanges && shortcutValidationError == nil ? selectedAccentColor : controlSurfaceColor,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasPendingSettingsChanges || shortcutValidationError != nil)
        }
        .padding(.leading, 220)
    }

    private var petSection: some View {
        settingsSection(title: "Pet", subtitle: "Choose which companion is active on your desktop.") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PetCharacter.allCases) { pet in
                    Button {
                        brain.setSelectedPet(pet)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: pet == brain.selectedPet ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(pet == brain.selectedPet ? selectedAccentColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(pet.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.primary)

                                Text(pet.personalitySummary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(pet == brain.selectedPet ? selectedTabFillColor : controlSurfaceColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(pet == brain.selectedPet ? selectedTabStrokeColor : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scheduleSection: some View {
        settingsSection(
            title: "Schedule",
            subtitle: "Cloud-backed tasks, reminders, and alarms that Rocky syncs to this Mac."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    scheduleInfoCard(
                        title: "Notifications",
                        value: brain.scheduleNotificationAuthorizationState.title,
                        detail: brain.scheduleNotificationAuthorizationState == .authorized
                            ? "macOS can deliver Rocky reminders."
                            : "Enable notifications so Rocky can alert you."
                    )

                    scheduleInfoCard(
                        title: "Last Sync",
                        value: scheduleSyncLabel,
                        detail: brain.scheduleStatusText
                    )
                }

                HStack(spacing: 12) {
                    Button("Enable Notifications") {
                        brain.requestScheduleNotificationAuthorization()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(brain.scheduleNotificationAuthorizationState == .authorized ? Color.primary : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        brain.scheduleNotificationAuthorizationState == .authorized ? controlSurfaceColor : selectedAccentColor,
                        in: Capsule()
                    )

                    Button("Refresh") {
                        Task { @MainActor in
                            await brain.refreshScheduledItems()
                            await brain.refreshScheduleNotificationAuthorizationState()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(controlSurfaceColor, in: Capsule())
                }

                if brain.scheduledItems.isEmpty {
                    Text("No tasks, reminders, or alarms scheduled yet. You can ask Rocky things like “remind me to call mom at 7” or “wake me up tomorrow at 6:30.”")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(brain.scheduledItems) { item in
                        scheduleItemCard(item)
                    }
                }
            }
        }
    }

    private var memorySection: some View {
        settingsSection(
            title: "Memory",
            subtitle: "Connect Rocky's cloud memory account so the desktop pet can remember context across conversations."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    scheduleInfoCard(
                        title: "Account",
                        value: brain.isMemoryAccountConnected ? "Connected" : "Not Connected",
                        detail: brain.isMemoryAccountConnected
                            ? "Rocky can fetch cloud memory context before starting Gemini."
                            : "Connect your Rocky web account to enable memory sync."
                    )

                    scheduleInfoCard(
                        title: "Conversation",
                        value: brain.activeConversationID ?? "None yet",
                        detail: brain.memoryContextStatusText.isEmpty
                            ? "No memory status yet."
                            : brain.memoryContextStatusText
                    )
                }

                settingsRow(title: "Status", alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(brain.memoryContextStatusText.isEmpty ? "Memory is ready to connect." : brain.memoryContextStatusText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.primary)

                        Text("Once connected, Rocky fetches relevant memory before Gemini starts and syncs finished turns back into the memory service.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button(brain.isMemoryAccountConnected ? "Reconnect Memory" : "Connect Memory Account") {
                        brain.connectMemoryAccount()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedAccentColor, in: Capsule())

                    Button("Disconnect") {
                        brain.disconnectMemoryAccount()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(controlSurfaceColor, in: Capsule())
                    .disabled(!brain.isMemoryAccountConnected)

                    Button("Refresh") {
                        brain.refreshMemorySettings()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(controlSurfaceColor, in: Capsule())
                    .disabled(!brain.isMemoryAccountConnected)
                }
                .padding(.leading, 220)

                settingsRow(title: "Memory enabled", alignment: .center) {
                    Toggle("", isOn: Binding(
                        get: { brain.memorySettings.memoryEnabled },
                        set: { brain.setMemoryEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!brain.isMemoryAccountConnected)
                }

                settingsRow(title: "Profile memory", alignment: .center) {
                    Toggle("", isOn: Binding(
                        get: { brain.memorySettings.profileMemoryEnabled },
                        set: { brain.setProfileMemoryEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!brain.isMemoryAccountConnected || !brain.memorySettings.memoryEnabled)
                }

                settingsRow(title: "Project memory", alignment: .center) {
                    Toggle("", isOn: Binding(
                        get: { brain.memorySettings.projectMemoryEnabled },
                        set: { brain.setProjectMemoryEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!brain.isMemoryAccountConnected || !brain.memorySettings.memoryEnabled)
                }

                settingsRow(title: "Preference memory", alignment: .center) {
                    Toggle("", isOn: Binding(
                        get: { brain.memorySettings.preferenceMemoryEnabled },
                        set: { brain.setPreferenceMemoryEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!brain.isMemoryAccountConnected || !brain.memorySettings.memoryEnabled)
                }

                settingsRow(title: "Auto extract", alignment: .center) {
                    Toggle("", isOn: Binding(
                        get: { brain.memorySettings.autoExtractEnabled },
                        set: { brain.setAutoExtractEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!brain.isMemoryAccountConnected || !brain.memorySettings.memoryEnabled)
                }

                settingsRow(title: "Sensitive memory", alignment: .center) {
                    Toggle("", isOn: Binding(
                        get: { brain.memorySettings.sensitiveMemoryEnabled },
                        set: { brain.setSensitiveMemoryEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!brain.isMemoryAccountConnected || !brain.memorySettings.memoryEnabled)
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(title: title, subtitle: subtitle)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow<Content: View>(
        title: String,
        alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 20) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 168, alignment: .trailing)

            content()
                .font(.system(size: 13))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private func inputField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(controlStrokeColor, lineWidth: 1)
            )
    }

    private func infoField(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(controlStrokeColor, lineWidth: 1)
            )
    }

    private func pluginCard(for provider: PluginProvider) -> some View {
        let connection = brain.pluginConnection(for: provider)
        let isConnected = connection != nil
        let isConnecting = brain.connectingPluginProvider == provider
        let statusText: String
        if isConnecting {
            statusText = "Opening \(provider.title) sign-in..."
        } else if isConnected {
            statusText = "Connected"
        } else {
            statusText = "Not connected"
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(controlSurfaceColor)

                    if NSImage(named: provider.assetImageName) != nil {
                        Image(provider.assetImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: provider.iconName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isConnected ? selectedAccentColor : Color.secondary)
                    }
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(provider.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.primary)

                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isConnected ? selectedAccentColor : Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(controlSurfaceColor, in: Capsule())
                    }

                    Text(provider.shortDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(isConnected ? "Disconnect" : (isConnecting ? "Connecting..." : "Connect")) {
                    if isConnected {
                        brain.disconnectPlugin(provider)
                    } else {
                        brain.connectPlugin(provider)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isConnected ? Color.primary : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isConnected ? controlSurfaceColor : selectedAccentColor,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(isConnected ? 0.08 : 0), lineWidth: 1)
                )
                .disabled(isConnecting)
            }

            if provider == brain.connectingPluginProvider || (!brain.pluginConnectionStatusText.isEmpty && provider == brain.pluginConnectionStatusProvider) {
                Text(brain.pluginConnectionStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .padding(.leading, 62)
            }

            if provider == .linear, connection != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Teams")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 76, alignment: .leading)

                        Button(brain.linearTeams.isEmpty ? "Fetch Teams" : "Refresh Teams") {
                            brain.fetchLinearTeamsForSelection()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(controlSurfaceColor, in: Capsule())
                        .disabled(brain.isLoadingLinearTeams)

                        if brain.isLoadingLinearTeams {
                            Text("Loading...")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondary)
                        }
                    }

                    if !brain.linearTeams.isEmpty {
                        let selectedTeamID = validLinearTeamSelectionID
                        HStack(spacing: 12) {
                            Text("Default team")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 76, alignment: .leading)

                            Picker("Default team", selection: Binding(
                                get: { selectedTeamID },
                                set: { brain.selectDefaultLinearTeam(withID: $0) }
                            )) {
                                ForEach(brain.linearTeams, id: \.id) { team in
                                    Text(team.key.isEmpty ? team.name : "\(team.name) (\(team.key))")
                                        .tag(team.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                }
                .padding(.leading, 62)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(controlStrokeColor, lineWidth: 1)
        )
    }

    private var pluginSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)

            TextField("Search plugins", text: $pluginSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !pluginSearchText.isEmpty {
                Button {
                    pluginSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(controlStrokeColor, lineWidth: 1)
        )
    }

    private func scheduleInfoCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)

            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary)

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(controlStrokeColor, lineWidth: 1)
        )
    }

    private func scheduleItemCard(_ item: ScheduledItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(controlSurfaceColor)

                    Image(systemName: item.kind.iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(scheduleAccentColor(for: item.kind))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(item.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.primary)

                        Text(item.kind.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(scheduleAccentColor(for: item.kind))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(controlSurfaceColor, in: Capsule())

                        Text(item.status.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(controlSurfaceColor, in: Capsule())
                    }

                    Text(scheduleDateLabel(for: item))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary)

                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if item.status == .pending {
                    Button("Complete") {
                        brain.completeScheduledItem(item)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedAccentColor, in: Capsule())

                    Button("Snooze 10m") {
                        brain.snoozeScheduledItem(item, minutes: 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(controlSurfaceColor, in: Capsule())
                }

                Button("Delete") {
                    brain.deleteScheduledItem(item)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(controlSurfaceColor, in: Capsule())
            }
            .padding(.leading, 62)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(controlSurfaceColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(controlStrokeColor, lineWidth: 1)
        )
    }

    private var hasPendingSettingsChanges: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines) != brain.userName ||
        draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) != brain.savedAPIKey ||
        parsedIdleSleepDelaySeconds != brain.idleSleepDelaySeconds ||
        draftShortcutPreferences != brain.shortcutPreferences
    }

    private var shortcutValidationError: String? {
        if draftShortcutPreferences.hasDuplicateShortcuts {
            return "Each Rocky action needs its own unique shortcut."
        }

        if let invalidAction = RockyShortcutAction.allCases.first(where: { !draftShortcutPreferences.shortcut(for: $0).isValid }) {
            return "\(invalidAction.title) needs a letter or symbol plus at least one modifier key."
        }

        return nil
    }

    private var parsedIdleSleepDelaySeconds: Int {
        let value = Int(draftIdleSleepDelay.trimmingCharacters(in: .whitespacesAndNewlines)) ?? brain.idleSleepDelaySeconds
        return max(1, value)
    }

    private func filteredSecondsInput(from value: String) -> String {
        let filtered = value.filter(\.isNumber)
        return filtered.isEmpty ? "" : filtered
    }

    private func applySettings() {
        brain.setUserName(draftName)
        brain.setSavedAPIKey(draftAPIKey)
        brain.setIdleSleepDelaySeconds(parsedIdleSleepDelaySeconds)
        if shortcutValidationError == nil {
            brain.setShortcutPreferences(draftShortcutPreferences)
        }
        draftIdleSleepDelay = String(brain.idleSleepDelaySeconds)
    }

    private var windowBackgroundColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private func updateShortcut(_ shortcut: RockyShortcut, for action: RockyShortcutAction) {
        draftShortcutPreferences.setShortcut(shortcut, for: action)
    }

    private var controlSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var controlStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var selectedAccentColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.9) : Color.accentColor
    }

    private var filteredPluginProviders: [PluginProvider] {
        let query = pluginSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return PluginProvider.allCases
        }

        return PluginProvider.allCases.filter { provider in
            provider.title.localizedCaseInsensitiveContains(query) ||
            provider.shortDescription.localizedCaseInsensitiveContains(query)
        }
    }

    private var validLinearTeamSelectionID: String {
        if let selectedID = brain.defaultLinearTeam?.id,
           brain.linearTeams.contains(where: { $0.id == selectedID }) {
            return selectedID
        }

        return brain.linearTeams.first?.id ?? "__no_linear_team__"
    }

    private var scheduleSyncLabel: String {
        guard let date = brain.scheduleLastSyncedAt else {
            return "Not synced yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func scheduleDateLabel(for item: ScheduledItem) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current
        let base = formatter.string(from: item.effectiveTriggerDate)
        var segments = [base]
        if item.repeatRule != .none {
            segments.append(item.repeatRule.title)
        }
        if let intervalMinutes = item.intervalMinutes,
           let windowStart = item.windowStartTime,
           let windowEnd = item.windowEndTime {
            let intervalHours = intervalMinutes % 60 == 0 ? "\(intervalMinutes / 60)h" : "\(intervalMinutes)m"
            segments.append("Every \(intervalHours)")
            segments.append("\(windowStart)-\(windowEnd)")
        }
        return segments.joined(separator: " • ")
    }

    private func scheduleAccentColor(for kind: ScheduledItemKind) -> Color {
        switch kind {
        case .task:
            return colorScheme == .dark ? Color.blue.opacity(0.9) : Color.blue
        case .reminder:
            return colorScheme == .dark ? Color.orange.opacity(0.9) : Color.orange
        case .alarm:
            return colorScheme == .dark ? Color.red.opacity(0.9) : Color.red
        }
    }

    private var selectedTabFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }

private var selectedTabStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.07)
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: RockyShortcut

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onShortcutRecorded = context.coordinator.handleShortcutChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        context.coordinator.shortcut = $shortcut
        nsView.onShortcutRecorded = context.coordinator.handleShortcutChange
        nsView.shortcut = shortcut
    }

    final class Coordinator {
        var shortcut: Binding<RockyShortcut>

        init(shortcut: Binding<RockyShortcut>) {
            self.shortcut = shortcut
        }

        func handleShortcutChange(_ newShortcut: RockyShortcut) {
            shortcut.wrappedValue = newShortcut
        }
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onShortcutRecorded: ((RockyShortcut) -> Void)?
    var shortcut = RockyShortcutPreferences.defaults.quickType {
        didSet {
            updateTitle()
        }
    }

    private var isRecordingShortcut = false {
        didSet {
            updateTitle()
            needsDisplay = true
            NotificationCenter.default.post(name: .rockyShortcutRecordingDidChange, object: isRecordingShortcut)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
        bezelStyle = .regularSquare
        target = self
        action = #selector(beginRecording)
        wantsLayer = true
        layer?.cornerRadius = 10
        setButtonType(.momentaryPushIn)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let boundsPath = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        boundsPath.fill()

        let strokeColor = isRecordingShortcut ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.55)
        strokeColor.setStroke()
        boundsPath.lineWidth = 1
        boundsPath.stroke()

        super.draw(dirtyRect)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            isRecordingShortcut = false
            window?.makeFirstResponder(nil)
            return
        }

        guard let recordedShortcut = RockyShortcut.from(event: event) else {
            NSSound.beep()
            return
        }

        shortcut = recordedShortcut
        onShortcutRecorded?(recordedShortcut)
        isRecordingShortcut = false
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecordingShortcut = false
        return super.resignFirstResponder()
    }

    @objc private func beginRecording() {
        isRecordingShortcut = true
        window?.makeFirstResponder(self)
    }

    private func updateTitle() {
        let text = isRecordingShortcut ? "Press shortcut" : shortcut.displayString
        attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }
}
