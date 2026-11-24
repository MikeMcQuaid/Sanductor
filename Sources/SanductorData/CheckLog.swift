/// Shared log cleanup for viewing and copying diagnostics.
enum CheckLog {
    // MARK: Internal

    struct Record {
        let timestamp: Substring
        let body: Substring
        let second: Substring?
    }

    static func lines(_ text: String, steps: [GitHubClient.RunStep], failedStepsOnly: Bool) -> [Record] {
        let lines = records(text)
        let omitSuccessfulSteps = failedStepsOnly && steps.contains { $0.conclusion == "failure" }
        let intervals = steps.compactMap { step -> ClosedRange<Substring>? in
            guard step.conclusion == "success", let name = step.name,
                  omitSuccessfulSteps || name == "Set up job" || name == "Complete job" || name.hasPrefix("Post "),
                  let start = timestamp(in: (step.startedAt ?? "")[...])?.1,
                  let end = timestamp(in: (step.completedAt ?? "")[...])?.1, start < end
            else {
                return nil
            }

            return start ... end
        }
        guard intervals.isEmpty == false else {
            return lines
        }

        let protected = lines.compactMap { line in
            ["##[warning]", "##[error]", "warning:", "error:", "fatal:"].contains { marker in
                line.body.hasPrefix(marker)
            } ? line.second : nil
        }
        let omitted = intervals.filter { interval in protected.contains(where: interval.contains) == false }
        return lines.filter { line in
            guard let second = line.second,
                  line.body.hasPrefix("##[group]") == false,
                  line.body != "##[endgroup]"
            else {
                return true
            }

            // Step times have only second precision; keep both boundary seconds.
            return omitted.contains { $0.lowerBound < second && second < $0.upperBound } == false
        }
    }

    // MARK: Private

    private static let escape: UInt8 = 0x1B

    private static func records(_ text: String) -> [Record] {
        var lines = [Record]()
        var listingFiles = false
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            var plain = raw
            if plain.utf8.contains(escape) {
                plain = plain.replacing(/\e\][^\e\x{07}]*(?:\x{07}|\e\\)/, with: "")
                    .replacing(/\e\[[0-?]*[ -\/]*[@-~]/, with: "")[...]
            }
            if plain.utf8.contains(0) {
                plain = plain.replacing("\0", with: " ")[...]
            }
            let time = timestamp(in: plain)
            let end = time?.range.upperBound ?? plain.startIndex
            let body = plain[end...]
            defer {
                listingFiles = (body.hasPrefix("[command]") || body.hasPrefix("##[command]"))
                    && body.hasSuffix("git ls-files -z")
            }
            if listingFiles, raw.contains("\0"), body.hasPrefix("##[") == false,
               body.hasPrefix("fatal:") == false, body.hasPrefix("error:") == false
            {
                continue
            }
            if isDownloadProgress(body) {
                continue
            }
            lines.append(Record(timestamp: plain[..<end], body: body, second: time?.1))
        }
        return lines
    }

    private static func isDownloadProgress(_ body: Substring) -> Bool {
        if body.hasPrefix("Progress: ") {
            return body
                .wholeMatch(of: /Progress: resolved \d+, reused \d+, downloaded \d+, added \d+(?:, done)?/) != nil
        }
        if body.hasPrefix("Downloading ") {
            return body.wholeMatch(of: /Downloading [^:]+: [\d.]+ [kKMGT]?i?B\/[\d.]+ [kKMGT]?i?B/) != nil
        }
        return body.hasPrefix("Received ")
            && body.wholeMatch(of: /Received \d+ of \d+ \(\d+%\), [\d.]+ [kKMGT]?i?B\/s/) != nil
    }

    private static func timestamp(in text: Substring) -> Regex<(Substring, Substring)>.Match? {
        text.prefixMatch(of: /^\x{FEFF}?[ \t]*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?Z ?/)
    }
}
