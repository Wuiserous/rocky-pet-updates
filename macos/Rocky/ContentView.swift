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
        PetSpriteView(state: brain.petState, stateStartedAt: stateStartedAt)
            .frame(width: petSize.width, height: petSize.height)
            .overlay(
                PetDragSurface {
                    brain.toggleConversation()
                } onSelectState: { petState in
                    brain.setManualState(petState)
                } onDragStateChanged: { petState in
                    brain.setDragState(petState)
                } onDragEnded: {
                    brain.endDrag()
                }
            )
    }
}

struct TranscriptPanelView: View {
    @ObservedObject var brain: PetBrainViewModel
    private let transcriptMaxWidth: CGFloat = 200
    private let transcriptMaxHeight: CGFloat = 118

    var body: some View {
        transcriptView
            .frame(width: transcriptMaxWidth, height: transcriptMaxHeight, alignment: .bottom)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.28), value: brain.latestAITranscript)
        .animation(.easeInOut(duration: 0.45), value: brain.isTranscriptVisible)
    }

    @ViewBuilder
    private var transcriptView: some View {
        ZStack(alignment: .bottom) {
            if !brain.latestAITranscript.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(brain.latestAITranscript)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: transcriptMaxWidth, alignment: .leading)

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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: transcriptMaxWidth, maxHeight: transcriptMaxHeight, alignment: .leading)
                .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .opacity(brain.isTranscriptVisible ? 1 : 0)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(
            width: transcriptMaxWidth,
            height: transcriptMaxHeight,
            alignment: .bottom
        )
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("transcriptBottom", anchor: .bottom)
            }
        }
    }
}
