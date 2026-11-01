public extension ClaudeCodeRunner {
    /// Includes transcript recovery copies and expired paste storage.
    func conversationFiles(sandboxHome: String) -> [String: String] {
        let root = sandboxHome + "/.claude/"
        var files = [String: String]()
        var directories = [String: String]()
        for path in ConversationRetention.files(under: root + "projects") where path.hasSuffix(".jsonl") {
            let metadata = ConversationRetention.head(path).first { $0["cwd"] is String }
            let directory = metadata?["cwd"] as? String ?? ""
            files[path] = directory
            if let session = metadata?["sessionId"] as? String {
                directories[session] = directory
            }
        }
        for path in ConversationRetention.files(under: root + "file-history") {
            let session = String(path.dropFirst((root + "file-history/").count).split(separator: "/").first ?? "")
            files[path] = directories[session] ?? ""
        }
        for path in ConversationRetention.files(under: root + "paste-cache") {
            files[path] = ""
        }
        return files
    }
}
