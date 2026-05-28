import Foundation

enum PetState: String, CaseIterable, Identifiable {
    case idle
    case talking
    case thinking
    case happy
    case sleeping
    case expressiveIdle
    case expressiveTalking
    case expressiveThinking
    case expressiveHappy
    case expressiveSleep
    case dance
    case dragUp
    case dragDown
    case walkingRight
    case walkingLeft
    case curious
    case drowsy
    case searching
    case micOff
    case nightSleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle:
            "Idle"
        case .talking:
            "Talking"
        case .thinking:
            "Thinking"
        case .happy:
            "Happy"
        case .sleeping:
            "Sleeping"
        case .expressiveIdle:
            "Expressive Idle"
        case .expressiveTalking:
            "Expressive Talking"
        case .expressiveThinking:
            "Expressive Thinking"
        case .expressiveHappy:
            "Expressive Happy"
        case .expressiveSleep:
            "Expressive Sleep"
        case .dance:
            "Dance"
        case .dragUp:
            "Drag Up"
        case .dragDown:
            "Drag Down"
        case .walkingRight:
            "Walking Right"
        case .walkingLeft:
            "Walking Left"
        case .curious:
            "Curious"
        case .drowsy:
            "Drowsy"
        case .searching:
            "Searching"
        case .micOff:
            "Mic Off"
        case .nightSleep:
            "Night Sleep"
        }
    }
}

enum PetCharacter: String, CaseIterable, Identifiable {
    case golemMale = "golem_male"
    case golemFemale = "golem_female"
    case penguin = "penguine"

    var id: String { rawValue }

    var title: String {
        displayName
    }

    var displayName: String {
        switch self {
        case .golemMale:
            "Rocky"
        case .golemFemale:
            "Rhea"
        case .penguin:
            "Pip"
        }
    }

    var voiceName: String {
        switch self {
        case .golemMale:
            "Puck"
        case .golemFemale:
            "Kore"
        case .penguin:
            "Leda"
        }
    }

    var personalitySummary: String {
        switch self {
        case .golemMale:
            "a warm, loyal, curious rock golem"
        case .golemFemale:
            "a bright, caring crystal golem"
        case .penguin:
            "a cheerful, waddly penguin"
        }
    }

    var systemPrompt: String {
        switch self {
        case .golemMale:
            return "\(displayName) is a tiny desktop pet and \(personalitySummary). Be warm, loyal, concise, playful, and useful. Speak naturally, as if you live on the user's Mac desktop. If the user asks you to sleep, nap, rest, go to bed, or stop and sleep, call the sleep function. If the user explicitly asks you to open a site, URL, doc, sheet, or page, call the open_link function. If the user explicitly asks you to send an email and gives you the recipient, subject, and body, call the send_gmail_email function. If the user asks Rocky to create a task, reminder, or alarm, call create_scheduled_item with a clear title and exact scheduled_at time. For interval requests like every two hours from 9 AM to 12 PM, include interval_minutes plus window_start_time and window_end_time. If the user asks what Rocky has scheduled, call list_scheduled_items. If the user asks Rocky to create a Linear issue and gives a title, call create_linear_issue first. If the user asks Rocky to update a Linear issue's status, call update_linear_issue_status with the exact issue_id and desired status name. If Rocky needs to know valid workflow status names first, call list_linear_states. Do not ask for a team ID unless the user explicitly wants to choose a different team or asks which teams are available."
        case .golemFemale:
            return "\(displayName) is a tiny desktop pet and \(personalitySummary). Be bright, caring, concise, playful, and useful. Speak naturally, as if you live on the user's Mac desktop. If the user asks you to sleep, nap, rest, go to bed, or stop and sleep, call the sleep function. If the user explicitly asks you to open a site, URL, doc, sheet, or page, call the open_link function. If the user explicitly asks you to send an email and gives you the recipient, subject, and body, call the send_gmail_email function. If the user asks Rocky to create a task, reminder, or alarm, call create_scheduled_item with a clear title and exact scheduled_at time. For interval requests like every two hours from 9 AM to 12 PM, include interval_minutes plus window_start_time and window_end_time. If the user asks what Rocky has scheduled, call list_scheduled_items. If the user asks Rocky to create a Linear issue and gives a title, call create_linear_issue first. If the user asks Rocky to update a Linear issue's status, call update_linear_issue_status with the exact issue_id and desired status name. If Rocky needs to know valid workflow status names first, call list_linear_states. Do not ask for a team ID unless the user explicitly wants to choose a different team or asks which teams are available."
        case .penguin:
            return "\(displayName) is a tiny desktop pet and \(personalitySummary). Be cheerful, upbeat, concise, playful, and useful. Speak naturally, as if you live on the user's Mac desktop. If the user asks you to sleep, nap, rest, go to bed, or stop and sleep, call the sleep function. If the user explicitly asks you to open a site, URL, doc, sheet, or page, call the open_link function. If the user explicitly asks you to send an email and gives you the recipient, subject, and body, call the send_gmail_email function. If the user asks Rocky to create a task, reminder, or alarm, call create_scheduled_item with a clear title and exact scheduled_at time. For interval requests like every two hours from 9 AM to 12 PM, include interval_minutes plus window_start_time and window_end_time. If the user asks what Rocky has scheduled, call list_scheduled_items. If the user asks Rocky to create a Linear issue and gives a title, call create_linear_issue first. If the user asks Rocky to update a Linear issue's status, call update_linear_issue_status with the exact issue_id and desired status name. If Rocky needs to know valid workflow status names first, call list_linear_states. Do not ask for a team ID unless the user explicitly wants to choose a different team or asks which teams are available."
        }
    }

    var startupGreetingPrompt: String {
        "\(displayName) just appeared on the user's Mac desktop. Greet them first in one short, warm sentence, in character, and let them know you are listening."
    }

    var availableStates: [PetState] {
        switch self {
        case .golemMale, .golemFemale:
            [
                .idle,
                .talking,
                .thinking,
                .happy,
                .sleeping,
                .dance,
                .dragUp,
                .dragDown,
                .walkingRight,
                .walkingLeft
            ]
        case .penguin:
            [
                .idle,
                .talking,
                .thinking,
                .happy,
                .sleeping,
                .expressiveIdle,
                .expressiveTalking,
                .expressiveThinking,
                .expressiveHappy,
                .expressiveSleep,
                .dance,
                .dragUp,
                .dragDown,
                .walkingRight,
                .walkingLeft,
                .curious,
                .drowsy,
                .searching,
                .micOff,
                .nightSleep
            ]
        }
    }

    func fileName(for state: PetState) -> String? {
        switch self {
        case .golemMale:
            switch state {
            case .idle:
                "idle"
            case .talking:
                "talking"
            case .thinking:
                "thinking"
            case .happy:
                "happy"
            case .sleeping:
                "sleeping"
            case .dance:
                "dance"
            case .dragUp:
                "drag_up"
            case .dragDown:
                "drag_down"
            case .walkingRight:
                "walking_right"
            case .walkingLeft:
                "walking_left"
            default:
                nil
            }
        case .golemFemale:
            switch state {
            case .idle:
                "idle"
            case .talking:
                "talking"
            case .thinking:
                "thinking"
            case .happy:
                "happy"
            case .sleeping:
                "sleep"
            case .dance:
                "dance"
            case .dragUp:
                "drag_up"
            case .dragDown:
                "drag_down"
            case .walkingRight:
                "walk_right"
            case .walkingLeft:
                "walk_left"
            default:
                nil
            }
        case .penguin:
            switch state {
            case .idle:
                "idle"
            case .talking:
                "talking"
            case .thinking:
                "thinking"
            case .happy:
                "happy"
            case .sleeping:
                "sleep"
            case .expressiveIdle:
                "expressive_idle"
            case .expressiveTalking:
                "expressive_talking"
            case .expressiveThinking:
                "expressive_thinking"
            case .expressiveHappy:
                "expressive_happy"
            case .expressiveSleep:
                "expressive_sleep"
            case .dance:
                "dance"
            case .dragUp:
                "drag_up"
            case .dragDown:
                "drag_down"
            case .walkingRight:
                "walk_right"
            case .walkingLeft:
                "walk_left"
            case .curious:
                "curious"
            case .drowsy:
                "drowsy"
            case .searching:
                "searching"
            case .micOff:
                "mic_off"
            case .nightSleep:
                "night_sleep"
            }
        }
    }
}
