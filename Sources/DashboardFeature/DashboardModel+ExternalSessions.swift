import SanductorData
import SanductorDomain

/// Sessions `sanductor new` asks the running app to start.
public extension DashboardModel {
    /// Starts a session from an issue, a pull request or a
    /// discussion as the new session form would, but leaving the
    /// selection alone, since a script may ask for several. Answers
    /// why it did not start, nil once it has.
    func startSession(_ request: ExternalEdit) async -> String? {
        guard let session = request.session,
              let repository = groups.first(where: { $0.repository.path == request.path })?.repository
        else {
            return "Not a repository Sanductor lists: " + request.path
        }
        guard let agent = AgentKind(rawValue: session.agent) else {
            return "Not an agent Sanductor knows: " + session.agent
        }

        let options = AgentLaunchOptions(
            model: session.model.isEmpty ? nil : session.model,
            effort: session.effort.isEmpty ? nil : session.effort,
        )
        let failure: LaunchFailure?
        switch (session.source, Int(session.reference)) {
        case let (.issue, number?):
            failure = await createSession(
                fromIssue: number,
                repository: repository,
                context: session.context,
                agent: agent,
                options: options,
                reveals: false,
            )

        case let (.pullRequest, number?):
            // The form's launch declines a pull request already
            // launching without a word, which a waiting command
            // would take for a session started.
            guard isLaunching(pullRequest: number, in: repository) == false else {
                return "Pull request #" + String(number) + " is already being started."
            }

            failure = await createSession(
                fromPullRequest: number,
                repository: repository,
                context: session.context,
                agent: agent,
                options: options,
                reveals: false,
            )

        case (.discussion, _):
            failure = await startDiscussion(
                session.reference,
                repository: repository,
                context: session.context,
                agent: agent,
                options: options,
                reveals: false,
            )

        default:
            return "Not a number: " + session.reference
        }
        return failure?.message
    }
}
