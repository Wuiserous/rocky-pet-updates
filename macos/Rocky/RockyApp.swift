import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct RockyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let brain = PetBrainViewModel()
    private let appUpdateService = AppUpdateService()
    private var petWindow: NSPanel?
    private var transcriptWindow: NSPanel?
    private var quickTypeWindow: NSPanel?
    private var controlCenterWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var sleepWakeMenuItem: NSMenuItem?
    private var conversationMenuItem: NSMenuItem?
    private var typeToRockyMenuItem: NSMenuItem?
    private var checkGmailMenuItem: NSMenuItem?
    private var checkForUpdatesMenuItem: NSMenuItem?
    private var controlCenterMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var petMenuItems: [PetCharacter: NSMenuItem] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var ambientLifeTimer: Timer?
    private var cursorMonitorTimer: Timer?
    private var scheduleDueCheckTimer: Timer?
    private var scheduleRefreshTimer: Timer?
    private var movementTimer: Timer?
    private var localShortcutMonitor: Any?
    private var globalShortcutMonitor: Any?
    private var isRecordingCustomShortcut = false
    private var cursorLastMovedAt = Date()
    private var lastCursorLocation = NSEvent.mouseLocation
    private var hasShownCuriousSinceLastCursorMove = false
    private var didAutoSleepFromCursorIdle = false
    private var isAnimatingAmbientMovement = false
    private let petSize = CGSize(width: 88, height: 96)
    private let transcriptSize = CGSize(width: 284, height: 228)
    private let controlCenterSize = CGSize(width: 800, height: 620)
    private let transcriptGap: CGFloat = 8
    private let quickTypeGap: CGFloat = 12
    private let quickTypeWidth: CGFloat = 300
    private let quickTypeMinHeight: CGFloat = 64
    private let quickTypeMaxHeight: CGFloat = 220
    private let ambientLifeInterval: TimeInterval = 4
    private let cursorMonitorInterval: TimeInterval = 1
    private let scheduleDueCheckInterval: TimeInterval = 20
    private let scheduleRefreshInterval: TimeInterval = 300
    private let curiousDelay: TimeInterval = 6
    private let chaseDelay: TimeInterval = 10
    private let wanderChance = 0.34
    private let cursorChaseChance = 0.6
    private let wanderRadius: CGFloat = 120
    private let cursorFollowOffset = CGSize(width: 56, height: -12)
    private let cursorMoveThreshold: CGFloat = 10
    private let minimumMovementDuration: TimeInterval = 2.6
    private let movementPointsPerSecond: CGFloat = 65
    private let movementFramesPerSecond: TimeInterval = 30
    private var quickTypeHeight: CGFloat = 82

    private enum ShortcutAction {
        case quickType
        case checkGmail
        case openControlCenter
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        registerForLaunchAtLoginIfNeeded()
        createStatusItem()
        createPetWindow()
        createTranscriptWindow()
        createQuickTypeWindow()
        observePetAndTranscript()
        installShortcutMonitors()
        startAmbientLifeTimers()
        startScheduleDueCheckTimer()
        startScheduleRefreshTimer()
        startGreetingAfterLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ambientLifeTimer?.invalidate()
        cursorMonitorTimer?.invalidate()
        scheduleDueCheckTimer?.invalidate()
        scheduleRefreshTimer?.invalidate()
        movementTimer?.invalidate()
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
        }
        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
        }
    }

    private func createPetWindow() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        let origin = CGPoint(
            x: visibleFrame.midX - petSize.width / 2,
            y: visibleFrame.midY - petSize.height / 2
        )

        let window = NSPanel(
            contentRect: NSRect(origin: origin, size: petSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureFloatingWindow(window)
        window.contentView = hostingView(for: ContentView(brain: brain), size: petSize)
        window.orderFrontRegardless()
        petWindow = window
    }

    private func createTranscriptWindow() {
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: transcriptSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureFloatingWindow(window)
        window.ignoresMouseEvents = false
        window.contentView = hostingView(for: TranscriptPanelView(brain: brain), size: transcriptSize)
        transcriptWindow = window
        repositionTranscriptWindow()
    }

    private func createQuickTypeWindow() {
        let window = InputPanel(
            contentRect: NSRect(origin: .zero, size: currentQuickTypeSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView(
            for: makeQuickTypeBubbleView(),
            size: currentQuickTypeSize
        )
        quickTypeWindow = window
    }

    private func createControlCenterWindow() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = CGPoint(
            x: visibleFrame.midX - controlCenterSize.width / 2,
            y: visibleFrame.midY - controlCenterSize.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: controlCenterSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rocky Control Center"
        window.isReleasedWhenClosed = false
        window.setContentSize(controlCenterSize)
        window.minSize = CGSize(width: 720, height: 560)
        window.center()
        window.contentView = NSHostingView(
            rootView: ControlCenterView(brain: brain, updateService: appUpdateService)
        )
        controlCenterWindow = window
    }

    private func configureFloatingWindow(_ window: NSPanel) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.becomesKeyOnlyIfNeeded = true
        window.worksWhenModal = true
        window.animationBehavior = .none
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }

    private func hostingView<Content: View>(for view: Content, size: CGSize) -> NSHostingView<some View> {
        let hostingView = NSHostingView(
            rootView: view
                .frame(width: size.width, height: size.height)
                .background(Color.clear)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        return hostingView
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let image = NSImage(
                systemSymbolName: "pawprint.fill",
                accessibilityDescription: "Rocky"
            )?.withSymbolConfiguration(symbolConfiguration) {
                image.isTemplate = true
                button.image = image
            } else if let fallbackImage = NSImage(systemSymbolName: "message.fill", accessibilityDescription: "Rocky") {
                fallbackImage.isTemplate = true
                button.image = fallbackImage
            } else if let assetImage = NSImage(named: "Rockyicon") {
                assetImage.isTemplate = true
                assetImage.size = NSSize(width: 18, height: 18)
                button.image = assetImage
            }
            button.imagePosition = .imageOnly
            button.contentTintColor = nil
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Rocky", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)
        checkForUpdatesMenuItem = updatesItem

        let typeItem = NSMenuItem(title: "Type to Rocky", action: #selector(openQuickTypeFromMenu), keyEquivalent: "")
        typeItem.target = self
        menu.addItem(typeItem)
        typeToRockyMenuItem = typeItem

        let gmailItem = NSMenuItem(title: "Check Gmail", action: #selector(checkGmailFromMenu), keyEquivalent: "")
        gmailItem.target = self
        menu.addItem(gmailItem)
        checkGmailMenuItem = gmailItem

        let controlCenterItem = NSMenuItem(title: "Open Control Center", action: #selector(openControlCenterFromMenu), keyEquivalent: "")
        controlCenterItem.target = self
        menu.addItem(controlCenterItem)
        controlCenterMenuItem = controlCenterItem

        let conversationItem = NSMenuItem(title: "Start Listening", action: #selector(toggleConversationFromMenu), keyEquivalent: "")
        conversationItem.target = self
        menu.addItem(conversationItem)
        conversationMenuItem = conversationItem

        let sleepItem = NSMenuItem(title: "Sleep", action: #selector(toggleSleepWakeFromMenu), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)
        sleepWakeMenuItem = sleepItem

        let petsMenu = NSMenu()
        for pet in PetCharacter.allCases {
            let item = NSMenuItem(title: pet.title, action: #selector(selectPetFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.rawValue
            petsMenu.addItem(item)
            petMenuItems[pet] = item
        }
        

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)
        launchAtLoginMenuItem = launchItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Rocky", action: #selector(quitRocky), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        statusMenu = menu
        refreshStatusMenu()
    }

    private func observePetAndTranscript() {
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)
            .merge(with: NotificationCenter.default.publisher(for: .rockyPetWindowMoved))
            .sink { [weak self] notification in
                guard let self, notification.object as? NSWindow === self.petWindow else { return }
                self.repositionTranscriptWindow()
                self.repositionQuickTypeWindow()
            }
            .store(in: &cancellables)

        brain.$latestUserTranscript
            .combineLatest(brain.$latestAITranscript)
            .combineLatest(brain.$isTranscriptVisible)
            .combineLatest(brain.$isPetSleeping)
            .sink { [weak self] output in
                guard let self else { return }
                let (((latestUserTranscript, latestAITranscript), isVisible), isPetSleeping) = output
                self.repositionTranscriptWindow()

                if (latestUserTranscript.isEmpty && latestAITranscript.isEmpty) || isPetSleeping {
                    self.transcriptWindow?.orderOut(nil)
                } else if isVisible {
                    self.transcriptWindow?.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)

        brain.$brainState
            .combineLatest(brain.$isPetSleeping, brain.$isDraggingPet)
            .sink { [weak self] brainState, isPetSleeping, isDraggingPet in
                guard let self else { return }
                guard brainState != .idle && brainState != .ready || isPetSleeping || isDraggingPet else { return }
                self.stopAmbientAnimationIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .sink { [weak self] _ in
                guard let self else { return }
                self.petWindow?.orderFrontRegardless()
                if self.brain.isTranscriptVisible, !self.brain.isPetSleeping {
                    self.transcriptWindow?.orderFrontRegardless()
                }
                if self.quickTypeWindow?.isVisible == true {
                    self.quickTypeWindow?.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.showRockyWindows()
                Task { @MainActor [weak self] in
                    await self?.brain.refreshScheduledItems()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .rockyOpenControlCenter)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.openControlCenterWindow()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .rockyShortcutRecordingDidChange)
            .sink { [weak self] notification in
                guard let value = notification.object as? Bool else { return }
                self?.isRecordingCustomShortcut = value
            }
            .store(in: &cancellables)

        brain.$selectedPet
            .combineLatest(brain.$brainState, brain.$isPetSleeping, brain.$pluginConnections)
            .combineLatest(brain.$shortcutPreferences)
            .sink { [weak self] _, _ in
                self?.refreshStatusMenu()
            }
            .store(in: &cancellables)
    }

    private func startGreetingAfterLaunch() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.showRockyWindows()
            brain.startConversationWithGreeting()
        }
    }

    private func startScheduleRefreshTimer() {
        scheduleRefreshTimer?.invalidate()
        scheduleRefreshTimer = Timer.scheduledTimer(withTimeInterval: scheduleRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.brain.refreshScheduledItems()
            }
        }
    }

    private func startScheduleDueCheckTimer() {
        scheduleDueCheckTimer?.invalidate()
        scheduleDueCheckTimer = Timer.scheduledTimer(withTimeInterval: scheduleDueCheckInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.brain.processDueScheduledItems()
            }
        }
    }

    private func showRockyWindows() {
        petWindow?.orderFrontRegardless()
        if brain.isTranscriptVisible, !brain.isPetSleeping {
            transcriptWindow?.orderFrontRegardless()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            self.brain.handleScheduleNotificationAction(
                identifier: response.actionIdentifier,
                userInfo: response.notification.request.content.userInfo
            )

            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                self.showRockyWindows()
                Task { @MainActor [weak self] in
                    self?.openControlCenterWindow()
                }
            }
        }
    }

    private func refreshStatusMenu() {
        sleepWakeMenuItem?.title = brain.isSleepingState ? "Wake" : "Sleep"
        conversationMenuItem?.title = brain.isConversationActive ? "Stop Listening" : "Start Listening"
        launchAtLoginMenuItem?.state = isLaunchAtLoginEnabled ? .on : .off
        checkGmailMenuItem?.isEnabled = brain.isGmailPluginConnected
        checkForUpdatesMenuItem?.isEnabled = appUpdateService.isUpdaterConfigured
        applyShortcut(brain.shortcutPreferences.quickType, to: typeToRockyMenuItem)
        applyShortcut(brain.shortcutPreferences.checkGmail, to: checkGmailMenuItem)
        applyShortcut(brain.shortcutPreferences.openControlCenter, to: controlCenterMenuItem)

        for (pet, item) in petMenuItems {
            item.state = pet == brain.selectedPet ? .on : .off
        }
    }

    private var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    private func registerForLaunchAtLoginIfNeeded() {
        guard #available(macOS 13.0, *) else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Rocky launch-at-login registration failed: %@", error.localizedDescription)
        }
    }

    @objc private func showRockyFromMenu() {
        showRockyWindows()
    }

    @objc private func openQuickTypeFromMenu() {
        toggleQuickTypeWindow()
    }

    @objc private func checkGmailFromMenu() {
        brain.sendTypedMessage("Check my Gmail and summarize the latest 10 unread emails.")
    }

    @objc private func checkForUpdatesFromMenu() {
        appUpdateService.checkForUpdates()
    }

    @objc private func openControlCenterFromMenu() {
        openControlCenterWindow()
    }

    @objc private func toggleConversationFromMenu() {
        if brain.isConversationActive {
            brain.stopConversation()
        } else if brain.isSleepingState {
            brain.wakeFromMenu()
            brain.startConversation()
        } else {
            brain.startConversation()
        }
        refreshStatusMenu()
    }

    @objc private func toggleSleepWakeFromMenu() {
        if brain.isSleepingState {
            brain.wakeFromMenu()
        } else {
            brain.sleepFromMenu()
        }
        refreshStatusMenu()
    }

    @objc private func selectPetFromMenu(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let pet = PetCharacter(rawValue: rawValue)
        else {
            return
        }

        brain.setSelectedPet(pet)
        refreshStatusMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }

        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Rocky launch-at-login toggle failed: %@", error.localizedDescription)
        }

        refreshStatusMenu()
    }

    @objc private func quitRocky() {
        NSApp.terminate(nil)
    }

    private func installShortcutMonitors() {
        ensureAccessibilityPermissionForGlobalShortcuts()

        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let action = self.shortcutAction(for: event) {
                self.performShortcutAction(action)
                return nil
            }
            return event
        }

        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard let action = self.shortcutAction(for: event) else { return }
            Task { @MainActor in
                self.performShortcutAction(action)
            }
        }
    }

    private func shortcutAction(for event: NSEvent) -> ShortcutAction? {
        guard !isRecordingCustomShortcut else { return nil }

        if brain.shortcutPreferences.quickType.matches(event) {
            return .quickType
        }
        if brain.shortcutPreferences.checkGmail.matches(event) {
            return .checkGmail
        }
        if brain.shortcutPreferences.openControlCenter.matches(event) {
            return .openControlCenter
        }

        return nil
    }

    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .quickType:
            toggleQuickTypeWindow()
        case .checkGmail:
            guard brain.isGmailPluginConnected else { return }
            checkGmailFromMenu()
        case .openControlCenter:
            openControlCenterWindow()
        }
    }

    private func ensureAccessibilityPermissionForGlobalShortcuts() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func applyShortcut(_ shortcut: RockyShortcut, to menuItem: NSMenuItem?) {
        menuItem?.keyEquivalent = shortcut.menuKeyEquivalent
        menuItem?.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    private func openQuickTypeWindow() {
        guard let quickTypeWindow else { return }

        repositionQuickTypeWindow()
        quickTypeWindow.contentView = hostingView(
            for: makeQuickTypeBubbleView(),
            size: currentQuickTypeSize
        )
        quickTypeWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        quickTypeWindow.makeKeyAndOrderFront(nil)
    }

    private func toggleQuickTypeWindow() {
        guard let quickTypeWindow else { return }

        if quickTypeWindow.isVisible {
            closeQuickTypeWindow()
        } else {
            openQuickTypeWindow()
        }
    }

    private func openControlCenterWindow() {
        if controlCenterWindow == nil {
            createControlCenterWindow()
        }

        guard let controlCenterWindow else { return }

        NSApp.activate(ignoringOtherApps: true)
        controlCenterWindow.makeKeyAndOrderFront(nil)
    }

    private func closeQuickTypeWindow() {
        quickTypeWindow?.orderOut(nil)
    }

    private func updateQuickTypeWindowHeight(_ proposedHeight: CGFloat) {
        guard let quickTypeWindow else { return }

        let clampedHeight = min(max(proposedHeight, quickTypeMinHeight), quickTypeMaxHeight)
        guard abs(clampedHeight - quickTypeHeight) > 0.5 else { return }

        quickTypeHeight = clampedHeight
        quickTypeWindow.setContentSize(currentQuickTypeSize)
        repositionQuickTypeWindow()
    }

    private func startAmbientLifeTimers() {
        ambientLifeTimer?.invalidate()
        cursorMonitorTimer?.invalidate()
        lastCursorLocation = NSEvent.mouseLocation
        cursorLastMovedAt = Date()

        ambientLifeTimer = Timer.scheduledTimer(
            withTimeInterval: ambientLifeInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runAmbientLifeTick()
            }
        }

        cursorMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: cursorMonitorInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.monitorCursorActivity()
            }
        }
    }

    private func monitorCursorActivity() {
        let cursorLocation = NSEvent.mouseLocation
        let distanceMoved = hypot(
            cursorLocation.x - lastCursorLocation.x,
            cursorLocation.y - lastCursorLocation.y
        )

        if distanceMoved >= cursorMoveThreshold {
            lastCursorLocation = cursorLocation
            cursorLastMovedAt = Date()
            hasShownCuriousSinceLastCursorMove = false
            if !isAnimatingAmbientMovement {
                brain.clearAmbientState()
            }
            return
        }

        guard canDriveAmbientMovement else { return }
        let idleDuration = Date().timeIntervalSince(cursorLastMovedAt)

        if idleDuration >= TimeInterval(brain.idleSleepDelaySeconds), !didAutoSleepFromCursorIdle {
            didAutoSleepFromCursorIdle = true
            stopAmbientAnimationIfNeeded()
            brain.sleepFromMenu()
            refreshStatusMenu()
            return
        }

        if idleDuration >= curiousDelay, !hasShownCuriousSinceLastCursorMove {
            let didShowCuriosity = brain.setAmbientState(.curious)
            hasShownCuriousSinceLastCursorMove = didShowCuriosity
        }
    }

    private func runAmbientLifeTick() {
        guard canDriveAmbientMovement else { return }

        let idleDuration = Date().timeIntervalSince(cursorLastMovedAt)
        if idleDuration >= chaseDelay, Bool.random(probability: cursorChaseChance) {
            movePetTowardCursor()
            return
        }

        guard Bool.random(probability: wanderChance) else {
            if !hasShownCuriousSinceLastCursorMove {
                brain.clearAmbientState()
            }
            return
        }

        movePetToRandomNearbyPoint()
    }

    private func movePetTowardCursor() {
        guard let petWindow else { return }
        let unclampedTargetOrigin = CGPoint(
            x: NSEvent.mouseLocation.x - petWindow.frame.width / 2 + cursorFollowOffset.width,
            y: NSEvent.mouseLocation.y - petWindow.frame.height / 2 + cursorFollowOffset.height
        )
        let targetOrigin = axisAlignedTargetOrigin(
            from: petWindow.frame.origin,
            CGPoint(
                x: unclampedTargetOrigin.x,
                y: unclampedTargetOrigin.y
            )
        )
        let clampedTargetOrigin = clampWindowOrigin(
            targetOrigin,
            for: petWindow
        )
        animatePetWindow(to: clampedTargetOrigin, celebrateOnArrival: true)
    }

    private func movePetToRandomNearbyPoint() {
        guard let petWindow else { return }
        let currentOrigin = petWindow.frame.origin
        let movesHorizontally = Bool.random()
        let dx = movesHorizontally ? CGFloat.random(in: -wanderRadius...wanderRadius) : 0
        let dy = movesHorizontally ? 0 : CGFloat.random(in: -wanderRadius * 0.4...wanderRadius * 0.55)
        let targetOrigin = clampWindowOrigin(
            CGPoint(x: currentOrigin.x + dx, y: currentOrigin.y + dy),
            for: petWindow
        )

        guard hypot(targetOrigin.x - currentOrigin.x, targetOrigin.y - currentOrigin.y) >= 16 else {
            return
        }

        animatePetWindow(to: targetOrigin, celebrateOnArrival: false)
    }

    private func animatePetWindow(to targetOrigin: CGPoint, celebrateOnArrival: Bool) {
        guard let petWindow else { return }
        guard !isAnimatingAmbientMovement else { return }

        let startOrigin = petWindow.frame.origin
        let deltaX = targetOrigin.x - startOrigin.x
        let deltaY = targetOrigin.y - startOrigin.y
        guard abs(deltaX) >= 6 || abs(deltaY) >= 6 else { return }

        let directionState: PetState
        if abs(deltaX) >= abs(deltaY) {
            directionState = deltaX >= 0 ? .walkingRight : .walkingLeft
        } else {
            directionState = deltaY >= 0 ? .dragUp : .dragDown
        }
        guard brain.setAmbientState(directionState) else { return }

        movementTimer?.invalidate()
        isAnimatingAmbientMovement = true
        hasShownCuriousSinceLastCursorMove = false

        let startedAt = Date()
        let travelDistance = max(abs(deltaX), abs(deltaY))
        let movementDuration = max(
            minimumMovementDuration,
            TimeInterval(travelDistance / movementPointsPerSecond)
        )
        let frameInterval = 1 / movementFramesPerSecond

        movementTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
            guard let self, let petWindow = self.petWindow else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            let progress = min(elapsed / movementDuration, 1)
            let easedProgress = self.easeInOut(progress)
            let nextOrigin = CGPoint(
                x: startOrigin.x + deltaX * easedProgress,
                y: startOrigin.y + deltaY * easedProgress
            )

            petWindow.setFrame(
                NSRect(origin: nextOrigin, size: petWindow.frame.size),
                display: true
            )
            NotificationCenter.default.post(name: .rockyPetWindowMoved, object: petWindow)

            if progress >= 1 {
                timer.invalidate()
                self.isAnimatingAmbientMovement = false
                if celebrateOnArrival {
                    self.brain.showTransientAmbientState(.happy, duration: .seconds(0.9))
                } else {
                    self.brain.clearAmbientState()
                }
            }
        }
    }

    private func stopAmbientAnimationIfNeeded() {
        movementTimer?.invalidate()
        movementTimer = nil
        isAnimatingAmbientMovement = false
        brain.clearAmbientState()
    }

    private func repositionTranscriptWindow() {
        guard
            let petWindow,
            let transcriptWindow,
            let screen = petWindow.screen ?? NSScreen.main
        else {
            return
        }

        let petFrame = petWindow.frame
        let visibleFrame = screen.visibleFrame

        var origin = CGPoint(
            x: petFrame.midX - transcriptSize.width / 2,
            y: petFrame.maxY + transcriptGap
        )

        if origin.y + transcriptSize.height > visibleFrame.maxY {
            origin.y = petFrame.minY - transcriptSize.height - transcriptGap
        }

        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - transcriptSize.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - transcriptSize.height)

        transcriptWindow.setFrame(NSRect(origin: origin, size: transcriptSize), display: true)
    }

    private func repositionQuickTypeWindow() {
        guard
            let petWindow,
            let quickTypeWindow,
            let screen = petWindow.screen ?? NSScreen.main
        else {
            return
        }

        let petFrame = petWindow.frame
        let visibleFrame = screen.visibleFrame

        var origin = CGPoint(
            x: petFrame.maxX + quickTypeGap,
            y: petFrame.midY - currentQuickTypeSize.height / 2
        )

        if origin.x + currentQuickTypeSize.width > visibleFrame.maxX {
            origin.x = petFrame.minX - currentQuickTypeSize.width - quickTypeGap
        }

        if origin.x < visibleFrame.minX {
            origin.x = petFrame.midX - currentQuickTypeSize.width / 2
            origin.y = petFrame.maxY + quickTypeGap
        }

        if origin.y + currentQuickTypeSize.height > visibleFrame.maxY {
            origin.y = petFrame.minY - currentQuickTypeSize.height - quickTypeGap
        }

        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - currentQuickTypeSize.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - currentQuickTypeSize.height)

        quickTypeWindow.setFrame(NSRect(origin: origin, size: currentQuickTypeSize), display: true)
    }

    private var currentQuickTypeSize: CGSize {
        CGSize(width: quickTypeWidth, height: quickTypeHeight)
    }

    private func makeQuickTypeBubbleView() -> some View {
        QuickTypeBubbleView(brain: brain) { [weak self] height in
            Task { @MainActor [weak self] in
                self?.updateQuickTypeWindowHeight(height)
            }
        }
    }

    private var canDriveAmbientMovement: Bool {
        guard petWindow != nil else { return false }
        return brain.canPerformAmbientActions && !isAnimatingAmbientMovement
    }

    private func axisAlignedTargetOrigin(from startOrigin: CGPoint, _ targetOrigin: CGPoint) -> CGPoint {
        let deltaX = targetOrigin.x - startOrigin.x
        let deltaY = targetOrigin.y - startOrigin.y

        if abs(deltaX) >= abs(deltaY) {
            return CGPoint(x: targetOrigin.x, y: startOrigin.y)
        } else {
            return CGPoint(x: startOrigin.x, y: targetOrigin.y)
        }
    }

    private func clampWindowOrigin(_ proposedOrigin: CGPoint, for window: NSWindow) -> CGPoint {
        guard let screen = window.screen ?? NSScreen.main else {
            return proposedOrigin
        }

        let visibleFrame = screen.visibleFrame
        let clampedX = min(
            max(proposedOrigin.x, visibleFrame.minX),
            visibleFrame.maxX - window.frame.width
        )
        let clampedY = min(
            max(proposedOrigin.y, visibleFrame.minY),
            visibleFrame.maxY - window.frame.height
        )

        return CGPoint(x: clampedX, y: clampedY)
    }

    private func easeInOut(_ progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        let eased = 0.5 - cos(clamped * .pi) / 2
        return CGFloat(eased)
    }
}

private extension Bool {
    static func random(probability: Double) -> Bool {
        Double.random(in: 0...1) <= probability
    }
}

private final class InputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
