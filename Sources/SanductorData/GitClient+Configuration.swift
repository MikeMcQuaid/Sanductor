import Foundation

public extension GitClient {
    /// A repository setting prevented Sanductor from running Git as the host user.
    struct ConfigurationError: LocalizedError {
        // MARK: Lifecycle

        init(_ message: String, file: URL? = nil) {
            errorDescription = message
            self.file = file
        }

        // MARK: Public

        public let errorDescription: String?
        /// The config file Git identified as the source of the blocked setting.
        public let file: URL?
    }

    /// Git assigns an included file its including file’s scope. Never put setting values in an error.
    internal static func checkConfiguration(_ result: ProcessResult, in directory: String) throws {
        if result.status == 1, result.standardOutput.isEmpty, result.standardError.isEmpty {
            return
        }
        guard result.succeeded else {
            throw ConfigurationError("Cannot verify Git configuration. " + result.standardError)
        }
        guard result.standardOutput.last == "\0" else {
            throw ConfigurationError("Git returned an unreadable configuration.")
        }

        var fields = result.standardOutput
            .dropLast()
            .split(separator: "\0", omittingEmptySubsequences: false)
            .makeIterator()
        while let scope = fields.next() {
            guard let origin = fields.next(), let entry = fields.next(), entry.isEmpty == false else {
                throw ConfigurationError("Cannot verify the scope of this repository’s Git settings.")
            }

            switch scope {
            case "local",
                 "worktree":
                try checkLocalSetting(entry, origin: origin, directory: directory)

            case "command",
                 "global",
                 "system":
                continue

            default:
                throw ConfigurationError("Git reported an unrecognised configuration scope.")
            }
        }
    }

    // MARK: Internal

    internal static let configurationArguments = ["--no-optional-locks"] + hardening + [
        "config", "--includes", "--null", "--show-scope", "--show-origin", "--type=bool-or-str",
        "--get-regexp", programSettings,
    ]

    internal static let hardening = options.flatMap { ["-c", $0] }

    /// Command-scope settings are inherited by Git subprocesses that gh starts itself.
    internal static func hardenedEnvironment(_ environment: [String: String]) -> [String: String] {
        var result = environment
        let inherited = environment["GIT_CONFIG_COUNT"] ?? ProcessInfo.processInfo.environment["GIT_CONFIG_COUNT"]
        let count = Int(inherited ?? "") ?? 0
        for (index, parts) in environmentSettings.enumerated() {
            result["GIT_CONFIG_KEY_" + String(count + index)] = String(parts[0])
            result["GIT_CONFIG_VALUE_" + String(count + index)] = String(parts[1])
        }
        result["GIT_CONFIG_COUNT"] = String(count + environmentSettings.count)
        return result
    }

    // MARK: Private

    private static func checkLocalSetting(_ entry: Substring, origin: Substring, directory: String) throws {
        let key = String(entry.prefix { $0 != "\n" })
        let value = entry.dropFirst(key.count + 1)
        if key == "core.fsmonitor", value == "false" || value == "true" {
            return
        }
        if key.hasPrefix("alias."), value.hasPrefix("!") == false {
            return
        }
        if key.hasPrefix("remote."), key.hasSuffix(".url") || key.hasSuffix(".pushurl"),
           usesBuiltInTransport(value)
        {
            return
        }
        if key.hasPrefix("url."), let suffix = key.lastIndex(of: "."),
           usesBuiltInTransport(key.dropFirst("url.".count)[..<suffix])
        {
            return
        }
        let label = key.hasPrefix("url.") ? "url.<base>." + (key.split(separator: ".").last ?? "") : key
        let file = configurationFile(origin: origin, directory: directory)
        let parts = label.components(separatedBy: ".")
        let subsection = parts.dropFirst().dropLast().joined(separator: ".")
        let section = "[" + (parts.first ?? "") + (subsection.isEmpty ? "" : " \"" + subsection + "\"") + "]"
        throw ConfigurationError(
            "Sanductor blocked " + label + ". Open " + (file?.path ?? "the repository’s Git config")
                + " in a text editor and remove the " + (parts.last ?? label) + " entry under " + section
                + ", then save and refresh. Configure trusted programs in ~/.gitconfig.",
            file: file,
        )
    }

    private static func configurationFile(origin: Substring, directory: String) -> URL? {
        guard origin.hasPrefix("file:"), origin.count > "file:".count else {
            return nil
        }

        let name = String(origin.dropFirst("file:".count))
        if name.hasPrefix("/") {
            return URL(filePath: name)
        }
        // Git reports relative origins from the checkout root even when invoked in a subdirectory.
        var root = URL(filePath: directory, directoryHint: .isDirectory)
        while root.path != "/" {
            let candidate = root.appending(path: name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            if FileManager.default.fileExists(atPath: root.appending(path: ".git").path) {
                return nil
            }
            root.deleteLastPathComponent()
        }
        return nil
    }

    private static func usesBuiltInTransport(_ url: Substring) -> Bool {
        guard let colon = url.firstIndex(of: ":"), url[..<colon].contains("/") == false else {
            return true
        }

        let rest = url[colon...]
        if rest.hasPrefix("::") {
            return false
        }
        return rest.hasPrefix("://") == false || ["http", "https", "ssh", "git", "file"].contains(url[..<colon])
    }

    /// Git names its built-in events in githooks(5). Disabling an event covers every
    /// configured command for it, including commands registered after the preflight.
    private static let disabledHookEvents = [
        "applypatch-msg", "pre-applypatch", "post-applypatch", "pre-commit", "pre-merge-commit",
        "prepare-commit-msg", "commit-msg", "post-commit", "pre-rebase", "post-checkout", "post-merge",
        "pre-push", "pre-receive", "update", "proc-receive", "post-receive", "post-update",
        "reference-transaction", "push-to-checkout", "pre-auto-gc", "post-rewrite", "sendemail-validate",
        "fsmonitor-watchman", "p4-changelist", "p4-prepare-changelist", "p4-post-changelist",
        "p4-pre-submit", "post-index-change",
    ].map { "hook." + $0 + ".enabled=false" }

    private static let options = [
        "core.fsmonitor=false", "core.sshCommand=/usr/bin/ssh", "core.hooksPath=/dev/null",
        "core.pager=cat", "protocol.ext.allow=never", "diff.mnemonicPrefix=false", "diff.noprefix=false",
        "maintenance.auto=false",
    ]

    private static let environmentSettings = (options + disabledHookEvents).map { setting in
        setting.split(separator: "=", maxSplits: 1)
    }

    private static let programSettings = "^(" + [
        #"core\.(alternaterefscommand|askpass|editor|fsmonitor|gitproxy|pager|sshcommand)"#,
        #"filter\..*\.(clean|process|smudge)"#, #"gpg(\..*)?\.program"#, #"gpg\.ssh\.defaultkeycommand"#,
        #"credential(\..*)?\.helper"#, #"diff\.(external|.*\.(command|textconv))"#,
        #"merge\..*\.driver"#, #"(diff|merge)tool\..*\.(cmd|path)"#, #"sequence\.editor"#,
        #"alias\..*"#, #"remote\..*\.(url|pushurl)"#, #"url\..*\.(insteadof|pushinsteadof)"#,
        #"interactive\.difffilter"#, #"remote\..*\.(receivepack|uploadpack|vcs)"#, #"submodule\..*\.update"#,
        #"trailer\..*\.(cmd|command)"#, #"pager\..*"#, #"tar\..*\.command"#,
    ].joined(separator: "|") + ")$"
}
