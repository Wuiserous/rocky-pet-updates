import SwiftUI

struct QuickTypeBubbleView: View {
    @ObservedObject var brain: PetBrainViewModel
    var onHeightChange: (CGFloat) -> Void
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(measurementText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.clear)
                .lineLimit(6)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 300, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: QuickTypeHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )

            TextField("Type to \(brain.selectedPet.displayName)...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white)
                .submitLabel(.send)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .onSubmit {
                    send()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: 300, alignment: .leading)
        }
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .onPreferenceChange(QuickTypeHeightPreferenceKey.self) { height in
            onHeightChange(height)
        }
        .onAppear {
            onHeightChange(64)
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        brain.sendTypedMessage(text)
        draft = ""
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    private var measurementText: String {
        if draft.isEmpty {
            return "Type to \(brain.selectedPet.displayName)..."
        }

        return draft + " "
    }
}

private struct QuickTypeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 64

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
