import Foundation
@testable import SanductorData
import Testing

struct AgentQuotaResetTests {
    @Test(arguments: ["null", #"{"available_count":"unknown"}"#])
    func `unreadable Codex reset metadata does not hide usage`(resets: String) throws {
        let quotas = try CodexRunner().parseQuota(Data("""
        {"rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":604800}},
         "rate_limit_reset_credits":\(resets)}
        """.utf8))
        #expect(quotas.first?.usedPercent == 50)
        #expect(quotas.first?.availableResets == nil)
    }

    @Test(arguments: [0, 1, 3])
    func `codex reports reset credits on the weekly allowance only`(count: Int) throws {
        let quotas = try CodexRunner().parseQuota(Data("""
        {"rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":18000},
          "secondary_window":{"used_percent":100,"limit_window_seconds":604800}},
         "rate_limit_reset_credits":{"available_count":\(count),"applicable_available_count":0}}
        """.utf8))
        #expect(quotas.map(\.availableResets) == [nil, count])
    }

    @Test
    func `claude grants are counted by allowance without expired paused or duplicate grants`() throws {
        let quotas = try ClaudeCodeRunner().parseQuota(Data(#"""
        {"limits":[
          {"kind":"weekly_all","group":"weekly","percent":50},
          {"kind":"weekly_scoped","group":"weekly","percent":100,
           "scope":{"model":{"display_name":"Fable"}}}],
         "cedar_ember":{"eligible":true,"grants":[
          {"id":"weekly","resets_left":1,"clears":["five_hour","seven_day"],"ends_at":"2099-01-01T00:00:00Z"},
          {"id":"weekly","resets_left":1,"clears":["seven_day"]},
          {"id":"fable","resets_left":3,"clears":["seven_day_overage_included"]},
          {"id":"expired","resets_left":2,"clears":["seven_day"],"ends_at":"2000-01-01T00:00:00Z"},
          {"id":"future","resets_left":2,"clears":["seven_day"],"starts_at":"2099-01-01T00:00:00Z"},
          {"id":"paused","resets_left":2,"clears":["seven_day"],"paused":true}
         ]}}
        """#.utf8))
        #expect(quotas.map(\.availableResets) == [1, 3])
    }

    @Test(arguments: [
        (#"{"eligible":true,"grants":[]}"#, Int?.some(0)),
        (#"{"eligible":false,"ineligible_reason":"surface","grants":[]}"#, nil),
        (#"{"eligible":true}"#, nil),
        (#"{"eligible":true,"grants":[{}]}"#, nil),
        (#"""
        {"eligible":true,"grants":[
          {"id":"bad","resets_left":1,"clears":["seven_day"],"starts_at":"invalid"}]}
        """#, nil),
        ("null", nil),
    ])
    func `unavailable Claude resets remain distinct from zero`(resets: String, expected: Int?) throws {
        let quotas = try ClaudeCodeRunner().parseQuota(Data("""
        {"seven_day":{"utilization":50},"cedar_ember":\(resets)}
        """.utf8))
        #expect(quotas.first?.availableResets == expected)
        #expect(quotas.first?.usedPercent == 50)
    }

    @Test(arguments: ["2026-11-17T00:00:00Z", "2026-11-17T00:00:00.000Z"])
    func `reset grants become available at their start time`(start: String) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let resets = try decoder.decode(ClaudeQuotaResets.self, from: Data("""
        {"eligible":true,"grants":[
          {"id":"one","resets_left":2,"clears":["seven_day"],"starts_at":"\(start)"}]}
        """.utf8))
        let date = try Date("2026-11-17T00:00:00Z", strategy: .iso8601)
        #expect(resets.available(for: "seven_day", now: date.addingTimeInterval(-1)) == 0)
        #expect(resets.available(for: "seven_day", now: date) == 2)
        #expect(resets.available(for: "seven_day", now: date.addingTimeInterval(1)) == 2)
    }

    @Test
    func `reset expiry is exclusive and invalid dates stay unknown`() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let resets = try decoder.decode(ClaudeQuotaResets.self, from: Data(#"""
        {"eligible":true,"grants":[
          {"id":"one","resets_left":1,"clears":["seven_day"],"ends_at":"2026-11-17T00:00:00.000Z"}]}
        """#.utf8))
        let expiry = try Date("2026-11-17T00:00:00Z", strategy: .iso8601)
        #expect(resets.available(for: "seven_day", now: expiry.addingTimeInterval(-1)) == 1)
        #expect(resets.available(for: "seven_day", now: expiry) == 0)
        let invalid = try decoder.decode(ClaudeQuotaResets.self, from: Data(#"""
        {"eligible":true,"grants":[
          {"id":"one","resets_left":1,"clears":["seven_day"],"ends_at":"invalid"}]}
        """#.utf8))
        #expect(invalid.available(for: "seven_day", now: expiry) == nil)
    }
}
