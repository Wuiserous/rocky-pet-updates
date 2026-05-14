import AppKit
import Combine
import SwiftUI

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let brain = PetBrainViewModel()
    private var petWindow: NSPanel?
    private var transcriptWindow: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private let petSize = CGSize(width: 88, height: 96)
    private let transcriptSize = CGSize(width: 200, height: 118)
    private let transcriptGap: CGFloat = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        createPetWindow()
        createTranscriptWindow()
        observePetAndTranscript()
    }

    private func createPetWindow() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        let origin = CGPoint(
            x: visibleFrame.midX - petSize.width / 2,
            y: visibleFrame.midY - petSize.height / 2
        )

        let window = NSPanel(
            contentRect: NSRect(origin: origin, size: petSize),
            styleMask: [.borderless],
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
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureFloatingWindow(window)
        window.ignoresMouseEvents = true
        window.contentView = hostingView(for: TranscriptPanelView(brain: brain), size: transcriptSize)
        transcriptWindow = window
        repositionTranscriptWindow()
    }

    private func configureFloatingWindow(_ window: NSPanel) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
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

    private func observePetAndTranscript() {
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)
            .merge(with: NotificationCenter.default.publisher(for: .rockyPetWindowMoved))
            .sink { [weak self] notification in
                guard let self, notification.object as? NSWindow === self.petWindow else { return }
                self.repositionTranscriptWindow()
            }
            .store(in: &cancellables)

        brain.$latestAITranscript
            .combineLatest(brain.$isTranscriptVisible)
            .sink { [weak self] transcript, isVisible in
                guard let self else { return }
                self.repositionTranscriptWindow()

                if transcript.isEmpty {
                    self.transcriptWindow?.orderOut(nil)
                } else if isVisible {
                    self.transcriptWindow?.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)
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
}
