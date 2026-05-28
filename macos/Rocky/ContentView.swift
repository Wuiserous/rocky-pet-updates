import SwiftUI

struct ContentView: View {
    @ObservedObject var brain: PetBrainViewModel
    @State private var stateStartedAt = Date()
    private let petSize = CGSize(width: 88, height: 96)

    var body: some View {
        petView
            .frame(width: petSize.width, height: petSize.height)
            .background(Color.clear)
            .fixedSize(horizontal: true, vertical: true)
            .onChange(of: brain.petState) { _, _ in
                stateStartedAt = Date()
            }
            .onChange(of: brain.brainState) { _, newValue in
                if newValue == .listening {
                    brain.clearAITranscriptAfterDelay()
                }
            }
    }

    private var petView: some View {
        PetSpriteView(
            state: brain.petState,
            character: brain.selectedPet,
            stateStartedAt: stateStartedAt
        )
            .frame(width: petSize.width, height: petSize.height)
            .overlay(
                PetDragSurface(
                    onClick: {
                        brain.toggleConversation()
                    },
                    onSelectState: { petState in
                        brain.setManualState(petState)
                    },
                    onSelectPet: { pet in
                        brain.setSelectedPet(pet)
                    },
                    onOpenControlCenter: {
                        NotificationCenter.default.post(name: .rockyOpenControlCenter, object: nil)
                    },
                    onDragBegan: {
                        brain.setDragging(true)
                    },
                    onDragStateChanged: { petState in
                        brain.setDragState(petState)
                    },
                    onDragEnded: {
                        brain.setDragging(false)
                        brain.endDrag()
                    },
                    petCharacter: brain.selectedPet,
                    currentState: brain.petState
                )
            )
    }
}

struct TranscriptPanelView: View {
    @ObservedObject var brain: PetBrainViewModel
    private let transcriptMaxWidth: CGFloat = 284
    private let transcriptMaxHeight: CGFloat = 228
    private let panelCornerRadius: CGFloat = 16

    var body: some View {
        transcriptView
            .frame(width: transcriptMaxWidth, height: transcriptMaxHeight, alignment: .bottom)
            .background(Color.clear)
            .animation(.easeInOut(duration: 0.28), value: brain.latestUserTranscript)
            .animation(.easeInOut(duration: 0.28), value: brain.latestAITranscript)
            .animation(.easeInOut(duration: 0.45), value: brain.isTranscriptVisible)
            .animation(.easeInOut(duration: 0.45), value: brain.isPetSleeping)
    }

    @ViewBuilder
    private var transcriptView: some View {
        ZStack(alignment: .bottom) {
            if !brain.latestUserTranscript.isEmpty || !brain.latestAITranscript.isEmpty {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                if !brain.latestUserTranscript.isEmpty {
                                    transcriptBubble(
                                        title: "You",
                                        text: brain.latestUserTranscript,
                                        isUser: true
                                    )
                                }

                                if !brain.latestAITranscript.isEmpty {
                                    transcriptBubble(
                                        title: brain.selectedPet.displayName,
                                        text: brain.latestAITranscript,
                                        isUser: false
                                    )
                                }

                                if !transcriptLinks.isEmpty {
                                    transcriptLinksSection
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("transcriptBottom")
                            }
                        }
                        .onAppear {
                            scrollTranscriptToBottom(proxy)
                        }
                        .onChange(of: brain.latestAITranscript) { _, _ in
                            scrollTranscriptToBottom(proxy)
                        }
                        .onChange(of: brain.latestUserTranscript) { _, _ in
                            scrollTranscriptToBottom(proxy)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: transcriptMaxWidth, maxHeight: transcriptMaxHeight, alignment: .leading)
                    .background(
                        Color.black.opacity(0.84),
                        in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .opacity(brain.isTranscriptVisible && !brain.isPetSleeping ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .compositingGroup()
                }
            }
        }
        .frame(
            width: transcriptMaxWidth,
            height: transcriptMaxHeight,
            alignment: .bottom
        )
    }

    private func transcriptBubble(title: String, text: String, isUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isUser ? .black.opacity(0.5) : .white.opacity(0.52))

            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isUser ? .black.opacity(0.86) : .white)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: transcriptMaxWidth, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            isUser
                ? AnyShapeStyle(
                    Color.white.opacity(0.96)
                )
                : AnyShapeStyle(
                    Color.white.opacity(0.08)
                ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isUser ? .white.opacity(0.18) : .white.opacity(0.08), lineWidth: 1)
        )
    }

    private var transcriptLinksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Links")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(transcriptLinks, id: \.absoluteString) { url in
                    Link(destination: url) {
                        Text(displayText(for: url))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("transcriptBottom", anchor: .bottom)
            }
        }
    }

    private var transcriptLinks: [URL] {
        extractLinks(from: brain.latestUserTranscript + "\n" + brain.latestAITranscript)
    }

    private func extractLinks(from text: String) -> [URL] {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let raw = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,)]]}\"'"))
            guard let url = URL(string: raw), seen.insert(url.absoluteString).inserted else {
                return nil
            }
            return url
        }
    }

    private func displayText(for url: URL) -> String {
        if let host = url.host {
            return host + url.path
        }

        return url.absoluteString
    }
}
