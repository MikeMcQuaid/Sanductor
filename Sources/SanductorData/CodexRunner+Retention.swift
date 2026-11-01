public extension CodexRunner {
    /// Includes active and archived rollout directories.
    func conversationFiles(sandboxHome: String) -> [String: String] {
        var files = [String: String]()
        for root in ["sessions", "archived_sessions"] {
            for path in ConversationRetention.files(under: sandboxHome + "/.codex/" + root)
                where path.hasSuffix(".jsonl")
            {
                let metadata = ConversationRetention.head(path).first { $0["type"] as? String == "session_meta" }
                files[path] = (metadata?["payload"] as? [String: Any])?["cwd"] as? String ?? ""
            }
        }
        return files
    }
}
