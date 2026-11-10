/// Shared log cleanup for viewing and copying diagnostics.
enum CheckLog {
    // MARK: Internal

    static func lines(_ text: String, steps: [GitHubClient.RunStep]) -> [String] {
        let lines = lines(text)
        let intervals = steps.compactMap { step -> ClosedRange<Substring>? in
            guard step.conclusion == "success", let name = step.name,
                  name == "Set up job" || name == "Complete job" || name.hasPrefix("Post "),
                  let start = second(step.startedAt ?? ""), let end = second(step.completedAt ?? ""), start < end
            else {
                return nil
            }

            return start ... end
        }
        guard intervals.isEmpty == false else {
            return lines
        }

        let timed = lines.map { (text: $0, body: stripped($0), second: second($0)) }
        let protected = timed.compactMap { line in
            ["##[warning]", "##[error]", "warning:", "error:", "fatal:"].contains { marker in
                line.body.hasPrefix(marker)
            } ? line.second : nil
        }
        let omitted = intervals.filter { interval in protected.contains(where: interval.contains) == false }
        return timed.filter { line in
            guard let second = line.second,
                  line.body.hasPrefix("##[group]") == false,
                  line.body != "##[endgroup]"
            else {
                return true
            }

            // Step times have only second precision; keep both boundary seconds.
            return omitted.contains { $0.lowerBound < second && second < $0.upperBound } == false
        }
        .map(\.text)
    }

    static func lines(_ text: String) -> [String] {
        var lines = [String]()
        var listingFiles = false
        for raw in text.replacing("\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let plain = sanitised(String(raw))
            let body = stripped(plain)
            defer {
                listingFiles = (body.hasPrefix("[command]") || body.hasPrefix("##[command]"))
                    && body.hasSuffix("git ls-files -z")
            }
            if listingFiles, raw.contains("\0"), body.hasPrefix("##[") == false,
               body.hasPrefix("fatal:") == false, body.hasPrefix("error:") == false
            {
                continue
            }
            if body.wholeMatch(of: /Progress: resolved \d+, reused \d+, downloaded \d+, added \d+(?:, done)?/) != nil
                || body.wholeMatch(of: /Downloading [^:]+: [\d.]+ [kKMGT]?i?B\/[\d.]+ [kKMGT]?i?B/) != nil
                || body.wholeMatch(of: /Received \d+ of \d+ \(\d+%\), [\d.]+ [kKMGT]?i?B\/s/) != nil
            {
                continue
            }
            lines.append(plain)
        }
        return lines
    }

    /// A log line without its timestamp, byte order mark or colour.
    static func stripped(_ text: String) -> String {
        sanitised(text)
            .replacing(/^\x{FEFF}?[ \t]*\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z ?/, with: "")
    }

    static func sanitised(_ text: String) -> String {
        text.replacing(/\e\][^\e\x{07}]*(?:\x{07}|\e\\)/, with: "")
            .replacing(/\e\[[0-?]*[ -\/]*[@-~]/, with: "")
            .replacing("\0", with: " ")
    }

    // MARK: Private

    private static func second(_ text: String) -> Substring? {
        text.firstMatch(of: /^\x{FEFF}?(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?Z(?: |$)/)?.1
    }
}
