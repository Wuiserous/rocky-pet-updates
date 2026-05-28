import Foundation

struct GmailMessageSummary {
    let id: String
    let sender: String
    let subject: String
    let timestamp: String
    let snippet: String
    let body: String

    var toolPayload: [String: Any] {
        [
            "id": id,
            "sender": sender,
            "subject": subject,
            "timestamp": timestamp,
            "snippet": snippet,
            "body": body,
        ]
    }
}
