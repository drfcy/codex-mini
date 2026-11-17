<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Codex Mini 图标">
</p>

# Codex Mini

一个简单的 macOS 菜单栏工具：看一眼，就知道 Codex 还剩多少额度、多久重置。

A minimal native macOS menu bar app for Codex quota and reset countdowns.

**[下载 Apple Silicon 版](https://github.com/drfcy/codex-mini/releases/latest)** · [使用说明](#使用) · [从源码构建](#从源码构建)

<p align="center">
  <img src="docs/menubar-preview.svg" width="600" alt="菜单栏示意：5h 97% 4h 51m">
</p>
<p align="center"><sub>显示效果示意，使用示例数据；百分比表示剩余额度。</sub></p>

## 功能

- 菜单栏显示短周期额度的剩余百分比，以及距离重置的时间。
- 点开菜单可查看周额度和重置时间。
- 用量每分钟更新，倒计时每 15 秒更新。
- 时间可选中文 / English，并记住选择。
- 支持手动刷新与开机启动；开机启动默认关闭。
- 直接连接失败时，自动尝试通过本机 Codex 客户端读取额度。
- 原生 Swift / AppKit，无第三方代码依赖，无 Dock 图标。

## 下载与安装

要求 **macOS 14 或更新版本、Apple Silicon（M 系列芯片）Mac**，并已在 Codex 中登录 ChatGPT 账号。

1. 从 [Releases](https://github.com/drfcy/codex-mini/releases/latest) 下载 `Codex-Mini-v1.0.2-macOS-arm64.zip`。
2. 解压，将 `Codex Mini.app` 拖到“应用程序”文件夹。
3. 打开应用，菜单栏即可看到额度与倒计时。

当前发布包采用临时签名，未使用 Apple Developer ID 签名，也未经过 Apple 公证。首次打开可能受到 macOS 安全检查阻止；确认下载来源和 SHA-256 校验值后，可按照 [Apple 的说明](https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac) 在系统设置的“隐私与安全”中处理，或自行从源码构建。

更新时先从菜单中退出旧版，再替换“应用程序”中的应用。不要同时运行多份副本。

## 使用

菜单栏中的 `5h 97%` 表示 5 小时额度还剩 97%。时间表示距离额度重置的时长。

| 时间语言 | 示例 |
| --- | --- |
| 中文 | `5h 97% 4小时51分钟` |
| English | `5h 97% 4h 51m` |

点击菜单栏图标，在“时间语言”中切换。时间不添加“后”或“in”。主界面的其他菜单文字为中文。

菜单还提供“立即刷新”“开机启动”和“退出 Codex Mini”。应用没有主窗口；退出后，从“应用程序”中重新打开即可。

出现 `⚠︎` 表示最近一次刷新失败，或数据超过两分半未更新。菜单会说明错误并显示最近成功更新时间；已有额度仅作为上次读取结果保留。重置时间已经过去时，旧百分比会改为 `--%`，等待新的服务器数据。

## 数据与隐私

- 使用本机 `~/.codex/auth.json` 中的现有登录状态；设置了 `CODEX_HOME` 时，使用该目录。
- 仅向 `https://chatgpt.com/backend-api/wham/usage` 请求用量，不另存登录令牌。
- 直接 HTTP 请求发生连接错误时，调用本机 Codex 的 `account/rateLimits/read` 作为备用通道，读取结束即关闭该子进程；不创建聊天或执行模型任务。
- 备用客户端继承当前代理环境；缺少相关环境变量时，将系统静态 HTTP/HTTPS 代理用于该子进程，不修改系统网络设置。
- Codex Mini 不写入登录文件；Codex 客户端可能按自身规则续期登录状态。
- 不读取浏览器 Cookie、钥匙串或聊天内容，无遥测、广告、自动更新。

该工具依赖 Codex 现有的用量数据格式，服务端接口变化可能影响读取。它是独立开源工具，与 OpenAI 没有隶属关系。

## 从源码构建

需要 macOS、Xcode 或兼容的 Command Line Tools，以及 Swift 6。无需安装第三方依赖。

```sh
git clone https://github.com/drfcy/codex-mini.git
cd codex-mini
./build.sh
```

应用生成在 `.build/Codex Mini.app`。将它复制到“应用程序”文件夹后再运行。构建目标为 macOS 14+ / arm64。

指定其他输出目录：

```sh
./build.sh "/你的输出目录/Codex Mini.app"
```

运行不联网的解析与格式测试：

```sh
./Scripts/test.sh
```

如需自行验证实际读取（会使用当前用户的 Codex 登录状态，只输出额度与时间）：

```sh
xcrun swiftc -swift-version 6 Sources/Usage.swift Tests/LiveCheck.swift -o .build/live-check
.build/live-check
.build/live-check --test-fallback
```

`--test-fallback` 模拟直接连接出现 TLS 错误，再验证真正的 Codex 客户端备用通道。CI 不运行任何需要真实账号的测试。

## 图标未更新

如果 LaunchOS 等启动器仍显示旧图标或占位图，先完全退出并重新打开启动器。如果仍未恢复，可以只刷新该应用的系统登记，然后再重新打开启动器：

```sh
touch "/Applications/Codex Mini.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Codex Mini.app"
```

旧版备份建议保存为 ZIP，避免多份 `.app` 被系统重复识别。

## 致谢与许可

用量接口、响应格式和备用读取方式参考了 [CodexBar](https://github.com/steipete/CodexBar)。本项目独立实现精简的菜单栏界面，圆环时钟图标为原创 SVG。

本项目使用 [MIT License](LICENSE)。参考项目许可见 [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)。
