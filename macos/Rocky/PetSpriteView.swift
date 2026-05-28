import AppKit
import ImageIO
import SwiftUI

struct PetSpriteView: View {
    let state: PetState
    let character: PetCharacter
    let stateStartedAt: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            if let image = PetGifLibrary(character: character)
                .image(for: state, at: timeline.date, startedAt: stateStartedAt) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Rocky")
            }
        }
        .id(state)
    }
}

private struct PetGifLibrary {
    let character: PetCharacter

    func image(for state: PetState, at date: Date, startedAt: Date) -> NSImage? {
        guard let gif = PetGifCache.shared.gif(at: url(for: state)) else {
            return nil
        }

        return gif.image(at: max(0, date.timeIntervalSince(startedAt)))
    }

    private func url(for state: PetState) -> URL? {
        guard let name = character.fileName(for: state) else {
            return nil
        }

        return Bundle.main.url(
            forResource: name,
            withExtension: "gif",
            subdirectory: "pets-gif/\(character.rawValue)"
        ) ?? Bundle.main.url(
            forResource: name,
            withExtension: "gif"
        ) ?? findBundledGIF(named: name)
    }

    private func findBundledGIF(named name: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let expectedSuffix = "pets-gif/\(character.rawValue)/\(name).gif"
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]

        guard let files = fileManager.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        ) else {
            return nil
        }

        for case let fileURL as URL in files {
            guard fileURL.path.hasSuffix(expectedSuffix) else {
                continue
            }

            return fileURL
        }

        return nil
    }
}

private final class PetGifCache {
    static let shared = PetGifCache()

    private var gifs: [URL: PetAnimatedGIF] = [:]

    func gif(at url: URL?) -> PetAnimatedGIF? {
        guard let url else {
            return nil
        }

        if let gif = gifs[url] {
            return gif
        }

        guard let gif = PetAnimatedGIF(url: url) else {
            return nil
        }

        gifs[url] = gif
        return gif
    }
}

private struct PetAnimatedGIF {
    private let frames: [Frame]
    private let duration: TimeInterval

    init?(url: URL) {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceGetCount(source) > 0
        else {
            return nil
        }

        var frames: [Frame] = []

        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }

            frames.append(
                Frame(
                    image: NSImage(cgImage: image, size: .zero),
                    delay: Self.delay(for: source, at: index)
                )
            )
        }

        guard !frames.isEmpty else {
            return nil
        }

        self.frames = frames
        self.duration = frames.reduce(0) { $0 + $1.delay }
    }

    func image(at elapsed: TimeInterval) -> NSImage {
        guard frames.count > 1, duration > 0 else {
            return frames[0].image
        }

        let animationTime = elapsed.truncatingRemainder(dividingBy: duration)
        var cursor: TimeInterval = 0

        for frame in frames {
            cursor += frame.delay
            if animationTime <= cursor {
                return frame.image
            }
        }

        return frames[0].image
    }

    private static func delay(for source: CGImageSource, at index: Int) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clampedDelay = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
        let delay = unclampedDelay ?? clampedDelay ?? 0.1

        return max(delay * 1.15, 0.03)
    }

    private struct Frame {
        let image: NSImage
        let delay: TimeInterval
    }
}
