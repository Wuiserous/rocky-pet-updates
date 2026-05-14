import AppKit
import SwiftUI

struct PetSpriteView: View {
    let state: PetState
    let stateStartedAt: Date

    private let sheet = PetSpritesheet(named: "spritesheet", extension: "webp", subdirectory: "Dario")

    var body: some View {
        TimelineView(.animation) { timeline in
            if let frame = sheet.frame(for: state, at: timeline.date, startedAt: stateStartedAt) {
                Image(nsImage: frame)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Dario")
            }
        }
        .aspectRatio(
            CGFloat(PetAtlas.frameWidth) / CGFloat(PetAtlas.frameHeight),
            contentMode: .fit
        )
    }
}

final class PetSpritesheet {
    private let image: NSImage?

    init(named name: String, extension fileExtension: String, subdirectory: String) {
        let bundledURL = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) ?? Bundle.main.url(
            forResource: name,
            withExtension: fileExtension
        )

        if let url = bundledURL {
            image = NSImage(contentsOf: url)
        } else {
            image = nil
        }
    }

    func frame(for state: PetState, at date: Date, startedAt: Date) -> NSImage? {
        guard
            let image,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let animation = PetAtlas.animations[state]
        else {
            return nil
        }

        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let frameIndex = Int(elapsed * animation.fps) % animation.columns.count
        let column = animation.columns[frameIndex]
        let cropRect = CGRect(
            x: column * PetAtlas.frameWidth,
            y: animation.row * PetAtlas.frameHeight,
            width: PetAtlas.frameWidth,
            height: PetAtlas.frameHeight
        )

        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }

        let frame = NSImage(
            cgImage: cropped,
            size: NSSize(width: PetAtlas.frameWidth, height: PetAtlas.frameHeight)
        )
        frame.isTemplate = false
        return frame
    }
}
