import Foundation

enum PluginToolExecutionError: LocalizedError {
    case unsupportedProvider
    case invalidResponse
    case brokerError(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "Rocky can't run this plugin action for the selected provider."
        case .invalidResponse:
            return "Rocky couldn't read the plugin response from the website."
        case .brokerError(let message):
            return message
        }
    }
}

struct GoogleSheetCreateResult {
    let spreadsheetID: String
    let title: String
    let url: String
}

struct GoogleSheetAppendRowsResult {
    let appendedRowCount: Int
    let includedHeaders: Bool
    let range: String
}

struct GoogleDriveFileSummary {
    let id: String
    let name: String
    let mimeType: String
    let url: String
}

struct NotionPageSummary {
    let id: String
    let title: String
    let url: String
}

struct NotionCreatePageResult {
    let id: String
    let title: String
    let url: String
}

struct NotionAppendParagraphsResult {
    let appendedParagraphCount: Int
}

struct GitHubRepositorySummary {
    let id: String
    let name: String
    let fullName: String
    let url: String
    let description: String
    let isPrivate: Bool
}

struct LinearIssueSummary {
    let id: String
    let identifier: String
    let title: String
    let state: String
    let url: String
}

struct LinearTeamSummary {
    let id: String
    let key: String
    let name: String
}

struct LinearStateSummary {
    let id: String
    let name: String
    let type: String
}

struct LinearTeamPreference: Codable, Equatable, Identifiable {
    let id: String
    let key: String
    let name: String
}

struct LinearCreateIssueResult {
    let id: String
    let identifier: String
    let title: String
    let url: String
}

struct LinearUpdateIssueStatusResult {
    let id: String
    let identifier: String
    let title: String
    let url: String
    let state: String
}

struct SlackChannelSummary {
    let id: String
    let name: String
    let isPrivate: Bool
}

struct SlackSendMessageResult {
    let channel: String
    let timestamp: String
    let permalink: String
}

struct GmailSendEmailResult {
    let recipient: String
    let subject: String
    let cc: [String]
    let bcc: [String]
}

struct GitHubCreateIssueResult {
    let id: String
    let title: String
    let number: Int
    let url: String
}

struct ComposioMetaToolDefinition {
    let sessionID: String
    let toolSlug: String
    let functionName: String
    let title: String
    let description: String
    let parameters: [String: Any]
}

final class PluginToolExecutionService {
    private let session: URLSession
    private let brokerBaseURL: URL

    init(
        session: URLSession = .shared,
        brokerBaseURL: URL = URL(string: "https://rocky-web-gules.vercel.app")!
    ) {
        self.session = session
        self.brokerBaseURL = brokerBaseURL
    }

    func fetchComposioMetaTools(sessionID: String) async throws -> [ComposioMetaToolDefinition] {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("tool-router")
            .appendingPathComponent("tools")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ToolRouterToolsRequest(sessionID: sessionID))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PluginToolExecutionError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let brokerError = try? JSONDecoder().decode(PluginCallErrorResponse.self, from: data)
            throw PluginToolExecutionError.brokerError(
                brokerError?.message ?? brokerError?.error.replacingOccurrences(of: "_", with: " ")
                    ?? "Rocky couldn't load the available Composio tools from the website broker."
            )
        }

        let decoded = try JSONDecoder().decode(ToolRouterToolsResponse.self, from: data)
        return decoded.tools.compactMap { tool in
            guard
                let parametersValue = try? JSONSerialization.jsonObject(with: tool.parametersData),
                let parameters = parametersValue as? [String: Any]
            else {
                return nil
            }

            return ComposioMetaToolDefinition(
                sessionID: decoded.sessionID,
                toolSlug: tool.toolSlug,
                functionName: tool.functionName,
                title: tool.title,
                description: tool.description,
                parameters: parameters
            )
        }
    }

    func executeComposioTool(
        sessionID: String,
        toolSlug: String,
        arguments: [String: Any]
    ) async throws -> Any {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("tool-router")
            .appendingPathComponent("execute")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "session_id": sessionID,
                "tool_slug": toolSlug,
                "arguments": arguments
            ],
            options: []
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PluginToolExecutionError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let brokerError = try? JSONDecoder().decode(PluginCallErrorResponse.self, from: data)
            throw PluginToolExecutionError.brokerError(
                brokerError?.message ?? brokerError?.error.replacingOccurrences(of: "_", with: " ")
                    ?? "Rocky couldn't execute this Composio tool through the website broker."
            )
        }

        let jsonValue = try JSONSerialization.jsonObject(with: data, options: [])
        guard
            let payload = jsonValue as? [String: Any],
            let ok = payload["ok"] as? Bool,
            ok
        else {
            throw PluginToolExecutionError.invalidResponse
        }

        return payload["result"] ?? payload
    }

    func fetchLatestGmailMessages(
        connection: PluginConnection,
        maxResults: Int = 10,
        unreadOnly: Bool = true,
        query: String? = nil
    ) async throws -> [GmailMessageSummary] {
        guard connection.provider == .gmail else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: GmailSummaryResponse = try await performRequest(
            connection: connection,
            operation: .gmailSummary(
                maxResults: min(max(maxResults, 1), 10),
                unreadOnly: unreadOnly,
                query: query?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )

        return response.messages.map {
            GmailMessageSummary(
                id: $0.id,
                sender: $0.sender,
                subject: $0.subject,
                timestamp: $0.timestamp,
                snippet: $0.snippet,
                body: $0.body
            )
        }
    }

    func sendGmailEmail(
        connection: PluginConnection,
        recipient: String,
        subject: String,
        body: String,
        cc: [String] = [],
        bcc: [String] = []
    ) async throws -> GmailSendEmailResult {
        guard connection.provider == .gmail else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: GmailSendEmailResponse = try await performRequest(
            connection: connection,
            operation: .gmailSendEmail(
                recipient: recipient,
                subject: subject,
                body: body,
                cc: cc,
                bcc: bcc
            )
        )

        return GmailSendEmailResult(
            recipient: response.recipient,
            subject: response.subject,
            cc: response.cc,
            bcc: response.bcc
        )
    }

    func createGoogleSheet(
        connection: PluginConnection,
        title: String
    ) async throws -> GoogleSheetCreateResult {
        guard connection.provider == .googleSheets else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: GoogleSheetCreateResponse = try await performRequest(
            connection: connection,
            operation: .createGoogleSpreadsheet(title: title)
        )

        return GoogleSheetCreateResult(
            spreadsheetID: response.spreadsheet.spreadsheetID,
            title: response.spreadsheet.title,
            url: response.spreadsheet.url
        )
    }

    func appendRowsToGoogleSheet(
        connection: PluginConnection,
        spreadsheetID: String,
        rows: [[String]],
        headers: [String] = [],
        range: String? = nil
    ) async throws -> GoogleSheetAppendRowsResult {
        guard connection.provider == .googleSheets else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: GoogleSheetAppendRowsResponse = try await performRequest(
            connection: connection,
            operation: .appendGoogleSheetRows(
                spreadsheetID: spreadsheetID,
                rows: rows,
                headers: headers,
                range: range
            )
        )

        return GoogleSheetAppendRowsResult(
            appendedRowCount: response.appendedRowCount,
            includedHeaders: response.includedHeaders,
            range: response.range
        )
    }

    func searchGoogleDriveFiles(
        connection: PluginConnection,
        query: String,
        maxResults: Int = 8
    ) async throws -> [GoogleDriveFileSummary] {
        guard connection.provider == .googleDrive else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: GoogleDriveSearchResponse = try await performRequest(
            connection: connection,
            operation: .googleDriveSearchFiles(
                query: query,
                maxResults: min(max(maxResults, 1), 8)
            )
        )

        return response.files.map {
            GoogleDriveFileSummary(id: $0.id, name: $0.name, mimeType: $0.mimeType, url: $0.url)
        }
    }

    func searchNotionPages(
        connection: PluginConnection,
        query: String,
        maxResults: Int = 8
    ) async throws -> [NotionPageSummary] {
        guard connection.provider == .notion else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: NotionSearchResponse = try await performRequest(
            connection: connection,
            operation: .notionSearchPages(
                query: query,
                maxResults: min(max(maxResults, 1), 8)
            )
        )

        return response.pages.map {
            NotionPageSummary(id: $0.id, title: $0.title, url: $0.url)
        }
    }

    func createNotionPage(
        connection: PluginConnection,
        title: String,
        parentID: String,
        markdown: String?
    ) async throws -> NotionCreatePageResult {
        guard connection.provider == .notion else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: NotionCreatePageResponse = try await performRequest(
            connection: connection,
            operation: .createNotionPage(title: title, parentID: parentID, markdown: markdown)
        )

        return NotionCreatePageResult(
            id: response.page.id,
            title: response.page.title,
            url: response.page.url
        )
    }

    func appendParagraphsToNotionPage(
        connection: PluginConnection,
        blockID: String,
        paragraphs: [String]
    ) async throws -> NotionAppendParagraphsResult {
        guard connection.provider == .notion else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: NotionAppendParagraphsResponse = try await performRequest(
            connection: connection,
            operation: .appendNotionParagraphs(blockID: blockID, paragraphs: paragraphs)
        )

        return NotionAppendParagraphsResult(
            appendedParagraphCount: response.appendedParagraphCount
        )
    }

    func listGitHubRepositories(
        connection: PluginConnection,
        maxResults: Int = 8
    ) async throws -> [GitHubRepositorySummary] {
        guard connection.provider == .github else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: GitHubRepositoryResponse = try await performRequest(
            connection: connection,
            operation: .githubListRepositories(maxResults: min(max(maxResults, 1), 8))
        )

        return response.repositories.map {
            GitHubRepositorySummary(
                id: $0.id,
                name: $0.name,
                fullName: $0.fullName,
                url: $0.url,
                description: $0.description,
                isPrivate: $0.isPrivate
            )
        }
    }

    func searchLinearIssues(
        connection: PluginConnection,
        query: String?,
        maxResults: Int = 8
    ) async throws -> [LinearIssueSummary] {
        guard connection.provider == .linear else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: LinearIssuesResponse = try await performRequest(
            connection: connection,
            operation: .linearSearchIssues(
                query: query?.trimmingCharacters(in: .whitespacesAndNewlines),
                maxResults: min(max(maxResults, 1), 8)
            )
        )

        return response.issues.map {
            LinearIssueSummary(id: $0.id, identifier: $0.identifier, title: $0.title, state: $0.state, url: $0.url)
        }
    }

    func listLinearTeams(
        connection: PluginConnection,
        maxResults: Int = 8
    ) async throws -> [LinearTeamSummary] {
        guard connection.provider == .linear else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: LinearTeamsResponse = try await performRequest(
            connection: connection,
            operation: .linearListTeams(maxResults: min(max(maxResults, 1), 8))
        )

        return response.teams.map {
            LinearTeamSummary(id: $0.id, key: $0.key, name: $0.name)
        }
    }

    func listLinearStates(
        connection: PluginConnection,
        teamID: String?,
        maxResults: Int = 12
    ) async throws -> [LinearStateSummary] {
        guard connection.provider == .linear else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: LinearStatesResponse = try await performRequest(
            connection: connection,
            operation: .linearListStates(
                teamID: teamID,
                maxResults: min(max(maxResults, 1), 12)
            )
        )

        return response.states.map {
            LinearStateSummary(id: $0.id, name: $0.name, type: $0.type)
        }
    }

    func createLinearIssue(
        connection: PluginConnection,
        title: String,
        teamID: String?,
        description: String?,
        priority: Int?
    ) async throws -> LinearCreateIssueResult {
        guard connection.provider == .linear else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: LinearCreateIssueResponse = try await performRequest(
            connection: connection,
            operation: .linearCreateIssue(
                title: title,
                teamID: teamID,
                description: description,
                priority: priority
            )
        )

        return LinearCreateIssueResult(
            id: response.issue.id,
            identifier: response.issue.identifier,
            title: response.issue.title,
            url: response.issue.url
        )
    }

    func updateLinearIssueStatus(
        connection: PluginConnection,
        issueID: String,
        status: String,
        teamID: String?
    ) async throws -> LinearUpdateIssueStatusResult {
        guard connection.provider == .linear else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: LinearUpdateIssueStatusResponse = try await performRequest(
            connection: connection,
            operation: .linearUpdateIssueStatus(issueID: issueID, status: status, teamID: teamID)
        )

        return LinearUpdateIssueStatusResult(
            id: response.issue.id,
            identifier: response.issue.identifier,
            title: response.issue.title,
            url: response.issue.url,
            state: response.issue.state
        )
    }

    func listSlackChannels(
        connection: PluginConnection,
        query: String?,
        maxResults: Int = 8
    ) async throws -> [SlackChannelSummary] {
        guard connection.provider == .slack else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: SlackChannelsResponse = try await performRequest(
            connection: connection,
            operation: .slackListChannels(
                query: query?.trimmingCharacters(in: .whitespacesAndNewlines),
                maxResults: min(max(maxResults, 1), 8)
            )
        )

        return response.channels.map {
            SlackChannelSummary(id: $0.id, name: $0.name, isPrivate: $0.isPrivate)
        }
    }

    func sendSlackMessage(
        connection: PluginConnection,
        channel: String,
        text: String
    ) async throws -> SlackSendMessageResult {
        guard connection.provider == .slack else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: SlackSendMessageResponse = try await performRequest(
            connection: connection,
            operation: .slackSendMessage(channel: channel, text: text)
        )

        return SlackSendMessageResult(
            channel: response.message.channel,
            timestamp: response.message.timestamp,
            permalink: response.message.permalink
        )
    }

    func createGitHubIssue(
        connection: PluginConnection,
        owner: String,
        repo: String,
        title: String,
        body: String?
    ) async throws -> GitHubCreateIssueResult {
        guard connection.provider == .github else {
            throw PluginToolExecutionError.unsupportedProvider
        }

        let response: GitHubCreateIssueResponse = try await performRequest(
            connection: connection,
            operation: .githubCreateIssue(owner: owner, repo: repo, title: title, body: body)
        )

        return GitHubCreateIssueResult(
            id: response.issue.id,
            title: response.issue.title,
            number: response.issue.number,
            url: response.issue.url
        )
    }

    private func performRequest<Response: Decodable>(
        connection: PluginConnection,
        operation: PluginOperation
    ) async throws -> Response {
        let endpoint = brokerBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("connections")
            .appendingPathComponent("call")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PluginCallRequest(
                provider: connection.provider.rawValue,
                entityID: connection.composioEntityID,
                connectedAccountID: connection.composioConnectedAccountID,
                sessionID: connection.composioToolRouterSessionID,
                operation: operation
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PluginToolExecutionError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let brokerError = try? JSONDecoder().decode(PluginCallErrorResponse.self, from: data)
            throw PluginToolExecutionError.brokerError(
                brokerError?.error.replacingOccurrences(of: "_", with: " ")
                    ?? "Rocky couldn't complete this plugin action through the website broker."
            )
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded
    }
}

private struct PluginCallRequest: Encodable {
    let provider: String
    let entityID: String
    let connectedAccountID: String?
    let sessionID: String?
    let operation: PluginOperation

    enum CodingKeys: String, CodingKey {
        case provider
        case entityID = "entity_id"
        case connectedAccountID = "connected_account_id"
        case sessionID = "session_id"
        case operation
    }
}

private struct ToolRouterToolsRequest: Encodable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

private struct PluginOperation: Encodable {
    let type: String
    let maxResults: Int?
    let unreadOnly: Bool?
    let query: String?
    let title: String?
    let channel: String?
    let text: String?
    let recipient: String?
    let cc: [String]?
    let bcc: [String]?
    let rows: [[String]]?
    let headers: [String]?
    let range: String?
    let parentID: String?
    let markdown: String?
    let blockID: String?
    let paragraphs: [String]?
    let owner: String?
    let repo: String?
    let body: String?
    let issueID: String?
    let status: String?
    let teamID: String?
    let priority: Int?

    init(
        type: String,
        maxResults: Int?,
        unreadOnly: Bool?,
        query: String?,
        title: String?,
        channel: String?,
        text: String?,
        recipient: String? = nil,
        cc: [String]? = nil,
        bcc: [String]? = nil,
        rows: [[String]]?,
        headers: [String]?,
        range: String?,
        parentID: String?,
        markdown: String?,
        blockID: String?,
        paragraphs: [String]?,
        owner: String?,
        repo: String?,
        body: String?,
        issueID: String? = nil,
        status: String? = nil,
        teamID: String?,
        priority: Int?
    ) {
        self.type = type
        self.maxResults = maxResults
        self.unreadOnly = unreadOnly
        self.query = query
        self.title = title
        self.channel = channel
        self.text = text
        self.recipient = recipient
        self.cc = cc
        self.bcc = bcc
        self.rows = rows
        self.headers = headers
        self.range = range
        self.parentID = parentID
        self.markdown = markdown
        self.blockID = blockID
        self.paragraphs = paragraphs
        self.owner = owner
        self.repo = repo
        self.body = body
        self.issueID = issueID
        self.status = status
        self.teamID = teamID
        self.priority = priority
    }

    enum CodingKeys: String, CodingKey {
        case type
        case maxResults = "max_results"
        case unreadOnly = "unread_only"
        case query
        case title
        case channel
        case text
        case recipient
        case cc
        case bcc
        case rows
        case headers
        case range
        case parentID = "parent_id"
        case markdown
        case blockID = "block_id"
        case paragraphs
        case owner
        case repo
        case body
        case issueID = "issue_id"
        case status
        case teamID = "team_id"
        case priority
    }

    static func gmailSummary(maxResults: Int, unreadOnly: Bool, query: String?) -> PluginOperation {
        PluginOperation(
            type: "gmail_summary",
            maxResults: maxResults,
            unreadOnly: unreadOnly,
            query: query,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func gmailSendEmail(
        recipient: String,
        subject: String,
        body: String,
        cc: [String],
        bcc: [String]
    ) -> PluginOperation {
        PluginOperation(
            type: "gmail_send_email",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: subject,
            channel: nil,
            text: body,
            recipient: recipient,
            cc: cc,
            bcc: bcc,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func createGoogleSpreadsheet(title: String) -> PluginOperation {
        PluginOperation(
            type: "google_sheets_create_spreadsheet",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: title,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func appendGoogleSheetRows(
        spreadsheetID: String,
        rows: [[String]],
        headers: [String],
        range: String?
    ) -> PluginOperation {
        PluginOperation(
            type: "google_sheets_append_rows",
            maxResults: nil,
            unreadOnly: nil,
            query: spreadsheetID,
            title: nil,
            channel: nil,
            text: nil,
            rows: rows,
            headers: headers,
            range: range,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func googleDriveSearchFiles(query: String, maxResults: Int) -> PluginOperation {
        PluginOperation(
            type: "google_drive_search_files",
            maxResults: maxResults,
            unreadOnly: nil,
            query: query,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func notionSearchPages(query: String, maxResults: Int) -> PluginOperation {
        PluginOperation(
            type: "notion_search_pages",
            maxResults: maxResults,
            unreadOnly: nil,
            query: query,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func createNotionPage(title: String, parentID: String, markdown: String?) -> PluginOperation {
        PluginOperation(
            type: "notion_create_page",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: title,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: parentID,
            markdown: markdown,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func appendNotionParagraphs(blockID: String, paragraphs: [String]) -> PluginOperation {
        PluginOperation(
            type: "notion_append_paragraphs",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: blockID,
            paragraphs: paragraphs,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func githubListRepositories(maxResults: Int) -> PluginOperation {
        PluginOperation(
            type: "github_list_repositories",
            maxResults: maxResults,
            unreadOnly: nil,
            query: nil,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func linearSearchIssues(query: String?, maxResults: Int) -> PluginOperation {
        PluginOperation(
            type: "linear_search_issues",
            maxResults: maxResults,
            unreadOnly: nil,
            query: query,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func linearListTeams(maxResults: Int) -> PluginOperation {
        PluginOperation(
            type: "linear_list_teams",
            maxResults: maxResults,
            unreadOnly: nil,
            query: nil,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func linearListStates(teamID: String?, maxResults: Int) -> PluginOperation {
        PluginOperation(
            type: "linear_list_states",
            maxResults: maxResults,
            unreadOnly: nil,
            query: nil,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: teamID,
            priority: nil
        )
    }

    static func linearCreateIssue(title: String, teamID: String?, description: String?, priority: Int?) -> PluginOperation {
        PluginOperation(
            type: "linear_create_issue",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: title,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: description,
            teamID: teamID,
            priority: priority
        )
    }

    static func linearUpdateIssueStatus(issueID: String, status: String, teamID: String?) -> PluginOperation {
        PluginOperation(
            type: "linear_update_issue_status",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            issueID: issueID,
            status: status,
            teamID: teamID,
            priority: nil
        )
    }

    static func slackListChannels(query: String?, maxResults: Int) -> PluginOperation {
        PluginOperation(
            type: "slack_list_channels",
            maxResults: maxResults,
            unreadOnly: nil,
            query: query,
            title: nil,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func slackSendMessage(channel: String, text: String) -> PluginOperation {
        PluginOperation(
            type: "slack_send_message",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: nil,
            channel: channel,
            text: text,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: nil,
            repo: nil,
            body: nil,
            teamID: nil,
            priority: nil
        )
    }

    static func githubCreateIssue(owner: String, repo: String, title: String, body: String?) -> PluginOperation {
        PluginOperation(
            type: "github_create_issue",
            maxResults: nil,
            unreadOnly: nil,
            query: nil,
            title: title,
            channel: nil,
            text: nil,
            rows: nil,
            headers: nil,
            range: nil,
            parentID: nil,
            markdown: nil,
            blockID: nil,
            paragraphs: nil,
            owner: owner,
            repo: repo,
            body: body,
            teamID: nil,
            priority: nil
        )
    }
}

private struct GmailSummaryResponse: Decodable {
    let ok: Bool
    let messages: [GmailSummaryMessage]
}

private struct GmailSendEmailResponse: Decodable {
    let ok: Bool
    let recipient: String
    let subject: String
    let cc: [String]
    let bcc: [String]
}

private struct GmailSummaryMessage: Decodable {
    let id: String
    let sender: String
    let subject: String
    let timestamp: String
    let snippet: String
    let body: String
}

private struct GoogleSheetCreateResponse: Decodable {
    let ok: Bool
    let spreadsheet: GoogleSheetPayload
}

private struct GoogleSheetAppendRowsResponse: Decodable {
    let ok: Bool
    let appendedRowCount: Int
    let includedHeaders: Bool
    let range: String

    enum CodingKeys: String, CodingKey {
        case ok
        case appendedRowCount = "appended_row_count"
        case includedHeaders = "included_headers"
        case range
    }
}

private struct GoogleSheetPayload: Decodable {
    let spreadsheetID: String
    let title: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case spreadsheetID = "spreadsheet_id"
        case title
        case url
    }
}

private struct GoogleDriveSearchResponse: Decodable {
    let ok: Bool
    let files: [GoogleDriveFilePayload]
}

private struct GoogleDriveFilePayload: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mimeType = "mime_type"
        case url
    }
}

private struct NotionSearchResponse: Decodable {
    let ok: Bool
    let pages: [NotionPagePayload]
}

private struct NotionCreatePageResponse: Decodable {
    let ok: Bool
    let page: NotionPagePayload
}

private struct NotionAppendParagraphsResponse: Decodable {
    let ok: Bool
    let appendedParagraphCount: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case appendedParagraphCount = "appended_paragraph_count"
    }
}

private struct NotionPagePayload: Decodable {
    let id: String
    let title: String
    let url: String
}

private struct GitHubRepositoryResponse: Decodable {
    let ok: Bool
    let repositories: [GitHubRepositoryPayload]
}

private struct GitHubCreateIssueResponse: Decodable {
    let ok: Bool
    let issue: GitHubIssuePayload
}

private struct GitHubRepositoryPayload: Decodable {
    let id: String
    let name: String
    let fullName: String
    let url: String
    let description: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case url
        case description
        case isPrivate = "private"
    }
}

private struct GitHubIssuePayload: Decodable {
    let id: String
    let title: String
    let number: Int
    let url: String
}

private struct LinearIssuesResponse: Decodable {
    let ok: Bool
    let issues: [LinearIssuePayload]
}

private struct LinearTeamsResponse: Decodable {
    let ok: Bool
    let teams: [LinearTeamPayload]
}

private struct LinearStatesResponse: Decodable {
    let ok: Bool
    let states: [LinearStatePayload]
}

private struct LinearCreateIssueResponse: Decodable {
    let ok: Bool
    let issue: LinearCreateIssuePayload
}

private struct LinearUpdateIssueStatusResponse: Decodable {
    let ok: Bool
    let issue: LinearIssuePayload
}

private struct LinearIssuePayload: Decodable {
    let id: String
    let identifier: String
    let title: String
    let state: String
    let url: String
}

private struct LinearCreateIssuePayload: Decodable {
    let id: String
    let identifier: String
    let title: String
    let url: String
}

private struct LinearTeamPayload: Decodable {
    let id: String
    let key: String
    let name: String
}

private struct LinearStatePayload: Decodable {
    let id: String
    let name: String
    let type: String
}

private struct SlackChannelsResponse: Decodable {
    let ok: Bool
    let channels: [SlackChannelPayload]
}

private struct SlackChannelPayload: Decodable {
    let id: String
    let name: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isPrivate = "is_private"
    }
}

private struct SlackSendMessageResponse: Decodable {
    let ok: Bool
    let message: SlackSendMessagePayload
}

private struct SlackSendMessagePayload: Decodable {
    let channel: String
    let timestamp: String
    let permalink: String
}

private struct PluginCallErrorResponse: Decodable {
    let ok: Bool?
    let error: String
    let message: String?
}

private struct ToolRouterToolsResponse: Decodable {
    let ok: Bool
    let sessionID: String
    let tools: [ToolRouterToolSchema]

    enum CodingKeys: String, CodingKey {
        case ok
        case sessionID = "session_id"
        case tools
    }
}

private struct ToolRouterToolSchema: Decodable {
    let toolSlug: String
    let functionName: String
    let title: String
    let description: String
    let parametersData: Data

    enum CodingKeys: String, CodingKey {
        case toolSlug = "tool_slug"
        case functionName = "function_name"
        case title
        case description
        case parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolSlug = try container.decode(String.self, forKey: .toolSlug)
        functionName = try container.decode(String.self, forKey: .functionName)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        let parametersValue = try container.decode(JSONValue.self, forKey: .parameters)
        parametersData = try JSONEncoder().encode(parametersValue)
    }
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
