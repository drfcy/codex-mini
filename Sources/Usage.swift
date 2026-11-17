import Foundation
import CFNetwork
import Darwin

enum TimeLanguage: String, CaseIterable {
    case chinese, english

    func countdown(until reset: Date?, now: Date = Date()) -> String {
        guard let reset else { return "--" }
        guard reset > now else { return self == .chinese ? "待刷新" : "refresh pending" }
        let minutes = max(1, Int(ceil(reset.timeIntervalSince(now) / 60)))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        var parts: [String] = []
        if days > 0 { parts.append(self == .chinese ? "\(days)天" : "\(days)d") }
        if hours > 0 { parts.append(self == .chinese ? "\(hours)小时" : "\(hours)h") }
        if mins > 0 { parts.append(self == .chinese ? "\(mins)分钟" : "\(mins)m") }
        return parts.joined(separator: self == .chinese ? "" : " ")
    }
}

struct UsageWindow: Decodable, Sendable {
    let usedPercent: Double
    let resetAt: TimeInterval?
    let limitWindowSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    var remaining: Int { Int(max(0, min(100, 100 - usedPercent)).rounded()) }
    var resetDate: Date? { resetAt.map { Date(timeIntervalSince1970: $0) } }
    func expired(at now: Date = Date()) -> Bool { resetDate.map { $0 <= now } ?? false }

    var label: String {
        guard let seconds = limitWindowSeconds, seconds > 0 else { return "额度" }
        if seconds % 86400 == 0 { return "\(seconds / 86400)d" }
        if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
        return "\(max(1, seconds / 60))m"
    }

    func title(language: TimeLanguage, now: Date = Date()) -> String {
        let percent = expired(at: now) ? "--%" : "\(remaining)%"
        return "\(label) \(percent) \(language.countdown(until: resetDate, now: now))"
    }
}

struct UsageResponse: Decodable, Sendable {
    struct Limits: Decodable, Sendable {
        let primary: UsageWindow?
        let secondary: UsageWindow?
        enum CodingKeys: String, CodingKey {
            case primary = "primary_window", secondary = "secondary_window"
        }
    }
    let limits: Limits?
    enum CodingKeys: String, CodingKey { case limits = "rate_limit" }

    static func parse(_ data: Data) throws -> UsageResponse {
        let result: UsageResponse
        do { result = try JSONDecoder().decode(UsageResponse.self, from: data) }
        catch { throw UsageError.message("用量数据格式已变化") }
        guard result.limits?.primary != nil || result.limits?.secondary != nil else {
            throw UsageError.message("当前账号未提供额度数据")
        }
        for window in [result.limits?.primary, result.limits?.secondary].compactMap({ $0 }) {
            guard window.usedPercent.isFinite, window.usedPercent >= 0,
                  window.usedPercent <= 100 else {
                throw UsageError.message("用量数据不完整")
            }
        }
        return result
    }
}

enum UsageError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

struct Credentials: Decodable, Sendable {
    struct Tokens: Decodable, Sendable {
        let accessToken: String
        let accountID: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", accountID = "account_id"
        }
    }
    let tokens: Tokens?

    static func home() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: NSString(string: home).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func read() throws -> Tokens {
        let url = home().appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let tokens = credentials.tokens, !tokens.accessToken.isEmpty else {
            throw UsageError.message("请先在 Codex 中登录 ChatGPT 账号")
        }
        return tokens
    }
}

// Never forward the bearer token to a redirected host.
final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum UsageClient {
    static func fetch(tokens: Credentials.Tokens,
                      request: (@Sendable (Credentials.Tokens) async throws -> UsageResponse)? = nil) async throws -> UsageResponse {
        do {
            return try await (request ?? fetchHTTP)(tokens)
        } catch is URLError {
            // The Codex client uses its own networking stack. This can remain
            // available when Foundation's TLS connection fails on a proxy path.
            do { return try await CodexClient.fetch() }
            catch {
                throw UsageError.message("网络连接失败，直接连接和 Codex 备用通道均未成功")
            }
        }
    }

    private static func fetchHTTP(tokens: Credentials.Tokens) async throws -> UsageResponse {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexMini/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = tokens.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.message("未收到有效响应")
        }
        switch http.statusCode {
        case 200: return try UsageResponse.parse(data)
        case 401: throw UsageError.message("登录已过期，请在 Codex 中更新登录后再刷新")
        case 403: throw UsageError.message("暂时无法读取额度（403），请检查账号或网络")
        case 429: throw UsageError.message("请求过于频繁，稍后自动重试")
        default: throw UsageError.message("用量服务暂不可用（\(http.statusCode)）")
        }
    }
}

enum CodexClient {
    struct RPCResponse: Decodable {
        struct Snapshot: Decodable {
            struct Window: Decodable {
                let usedPercent: Double
                let windowDurationMins: Int?
                let resetsAt: TimeInterval?
                var usage: UsageWindow {
                    UsageWindow(usedPercent: usedPercent, resetAt: resetsAt,
                                limitWindowSeconds: windowDurationMins.map { $0 * 60 })
                }
            }
            let primary: Window?
            let secondary: Window?
        }
        let rateLimits: Snapshot
    }

    static func parse(_ data: Data) throws -> UsageResponse {
        let response = try JSONDecoder().decode(RPCResponse.self, from: data)
        let windows = [response.rateLimits.primary, response.rateLimits.secondary].compactMap { $0 }
        guard !windows.isEmpty, windows.allSatisfy({ $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) }) else {
            throw UsageError.message("Codex 未提供有效额度")
        }
        return UsageResponse(limits: UsageResponse.Limits(
            primary: response.rateLimits.primary?.usage, secondary: response.rateLimits.secondary?.usage))
    }

    static func fetch() async throws -> UsageResponse {
        try await Task.detached(priority: .utility) { try run() }.value
    }

    private static func run() throws -> UsageResponse {
        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        ]
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UsageError.message("未找到 Codex 客户端")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = Credentials.home().path
        // GUI apps do not inherit Terminal's proxy environment. Mirror the
        // user's static system proxy into this child only; leave system settings alone.
        if let proxies = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            for (prefix, key) in [("HTTPS", "HTTPS_PROXY"), ("HTTP", "HTTP_PROXY")] {
                if env[key] == nil, env[key.lowercased()] == nil,
                   proxies[prefix + "Enable"] as? Int == 1,
                   let host = proxies[prefix + "Proxy"] as? String,
                   let port = proxies[prefix + "Port"] as? Int {
                    var components = URLComponents()
                    components.scheme = "http"
                    components.host = host
                    components.port = port
                    if let proxy = components.url?.absoluteString { env[key] = proxy }
                }
            }
        }
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timeout.schedule(deadline: .now() + 18)
        timeout.setEventHandler { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        timeout.resume()
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codexmini", "version": "1.0.1"]]])
        var buffer = Data()
        var totalBytes = 0
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw UsageError.message("Codex 备用通道超时或已关闭") }
            totalBytes += chunk.count
            guard totalBytes <= 1_048_576 else { throw UsageError.message("Codex 响应过大") }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.subdata(in: 0..<newline)
                buffer.removeSubrange(0...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? Int else { continue }
                guard object["error"] == nil else { throw UsageError.message("Codex 备用通道读取失败") }
                if id == 1 {
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, let result = object["result"] {
                    return try parse(JSONSerialization.data(withJSONObject: result))
                }
            }
        }
    }
}
