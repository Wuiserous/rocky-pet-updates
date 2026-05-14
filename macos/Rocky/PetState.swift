import Foundation

enum PetState: String, CaseIterable, Identifiable {
    case idle
    case listening
    case thinking
    case sad
    case movingRight
    case movingLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle:
            "Idle"
        case .listening:
            "Listening"
        case .thinking:
            "Thinking"
        case .sad:
            "Sad"
        case .movingRight:
            "Moving Right"
        case .movingLeft:
            "Moving Left"
        }
    }
}

struct PetAnimation {
    let row: Int
    let columns: [Int]
    let fps: Double
}

struct PetAtlas {
    static let columns = 8
    static let rows = 9
    static let frameWidth = 192
    static let frameHeight = 208

    static let animations: [PetState: PetAnimation] = [
        .idle: PetAnimation(row: 0, columns: [0, 1, 2, 3, 4, 5], fps: 6),
        .listening: PetAnimation(row: 8, columns: [0, 1, 2, 3, 4, 5, 6], fps: 8),
        .thinking: PetAnimation(row: 6, columns: [0, 1, 2, 3, 4, 5, 6], fps: 6),
        .sad: PetAnimation(row: 5, columns: [0, 1, 2, 3, 4, 5, 6, 7], fps: 6),
        .movingRight: PetAnimation(row: 1, columns: [0, 1, 2, 3, 4, 5, 6, 7], fps: 10),
        .movingLeft: PetAnimation(row: 2, columns: [0, 1, 2, 3, 4, 5, 6, 7], fps: 10)
    ]
}
