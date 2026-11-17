import Foundation

@main struct LiveCheck {
    static func main() async {
        do {
            let response: UsageResponse
            if CommandLine.arguments.contains("--test-fallback") {
                response = try await UsageClient.fetch(tokens: Credentials.read(), request: { _ in
                    throw URLError(.secureConnectionFailed)
                })
                print("已验证 TLS 失败后自动切换 Codex 备用通道")
            } else {
                response = try await UsageClient.fetch(tokens: Credentials.read())
            }
            for window in [response.limits?.primary, response.limits?.secondary].compactMap({ $0 }) {
                print(window.title(language: .chinese))
                print(window.title(language: .english))
            }
        } catch {
            print("读取失败：\(error.localizedDescription)")
            exit(1)
        }
    }
}
