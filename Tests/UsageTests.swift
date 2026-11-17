import Foundation

@main struct UsageTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(4 * 3600 + 51 * 60)
        precondition(TimeLanguage.chinese.countdown(until: reset, now: now) == "4小时51分钟")
        precondition(TimeLanguage.english.countdown(until: reset, now: now) == "4h 51m")
        precondition(TimeLanguage.chinese.countdown(until: now.addingTimeInterval(1), now: now) == "1分钟")
        precondition(TimeLanguage.english.countdown(until: now.addingTimeInterval(86400), now: now) == "1d")
        precondition(TimeLanguage.chinese.countdown(until: nil, now: now) == "--")
        let json = """
        {"rate_limit":{"primary_window":{"used_percent":3,"reset_at":1800017460,"limit_window_seconds":18000},"secondary_window":{"used_percent":23,"reset_at":1800300000,"limit_window_seconds":604800}}}
        """
        let parsed = try UsageResponse.parse(Data(json.utf8))
        precondition(parsed.limits?.primary?.remaining == 97)
        precondition(parsed.limits?.primary?.title(language: .chinese, now: now) == "5h 97% 4小时51分钟")
        precondition(parsed.limits?.primary?.title(language: .english, now: now) == "5h 97% 4h 51m")
        precondition(parsed.limits?.secondary?.label == "7d")
        precondition(parsed.limits?.primary?.title(language: .english, now: reset) == "5h --% refresh pending")
        for bad in ["{}", "{\"rate_limit\":{}}", "{\"rate_limit\":{\"primary_window\":{\"used_percent\":-1}}}", "not json"] {
            do { _ = try UsageResponse.parse(Data(bad.utf8)); fatalError("Invalid response accepted") }
            catch is UsageError { }
        }
        let exhausted = try UsageResponse.parse(Data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":100}}}".utf8))
        precondition(exhausted.limits?.primary?.remaining == 0)
        let rpc = try CodexClient.parse(Data("""
        {"rateLimits":{"primary":{"usedPercent":17,"windowDurationMins":300,"resetsAt":1800017460},"secondary":{"usedPercent":24,"windowDurationMins":10080,"resetsAt":1800300000}}}
        """.utf8))
        precondition(rpc.limits?.primary?.title(language: .english, now: now) == "5h 83% 4h 51m")
        precondition(rpc.limits?.secondary?.remaining == 76)
        do {
            _ = try CodexClient.parse(Data("{\"rateLimits\":{}}".utf8))
            fatalError("Empty RPC quota accepted")
        } catch is UsageError { }
        print("通过：中英文时间、剩余百分比、5h/周窗口、到期失效、异常数据、额度耗尽")
    }
}
