# AppDuo

原生 macOS 应用分身工具。界面使用 SwiftUI，克隆引擎、Mach-O 修改、签名编排、配置与命令行使用 Swift。可独立运行，无需 Python 环境。

使用 GPL-3.0 许可证，详见 [LICENSE](LICENSE)。

## 下载与自动构建

从 [Releases](https://github.com/tamia6/AppDuo/releases/latest) 下载：Apple Silicon 选择 `AppDuo-arm64.dmg`，Intel 选择 `AppDuo-x86_64.dmg`。

GitHub Actions 在推送 `main`、提交 PR 或手动运行时测试并构建两种架构的 DMG（见 Actions artifacts）。推送 `v主版本.次版本.补丁版本` 标签时，自动发布 Release、DMG 与 SHA-256 校验文件。版本号同步写入应用元数据。

```sh
git tag v0.1.1
git push origin v0.1.1
```

## 构建与运行

要求 macOS 14+、Xcode / Command Line Tools、Swift 6 工具链。克隆应用时需要系统 clang 和 codesign。

```sh
swift test
./script/build_and_run.sh             # 构建 .app 并启动
./script/build_and_run.sh --verify    # 构建并验证进程启动
./script/build_and_run.sh --dmg       # 输出本机架构 DMG
```

可在 Xcode 中打开 `Package.swift`。Codex Run 按钮已配置。构建产物在 `dist/`，本地 ad-hoc 签名，未经过 Apple 公证。

## 已实现

- 紧凑分身卡片、五步创建向导、编辑设置、启动、更新、移到废纸篓和设置窗口；关闭最后一个窗口即退出，无菜单栏常驻图标。
- 34 条内置规则，原 YAML 格式，支持本地文件覆盖；未知应用基于 Frameworks 自动探测。
- 硬分身复制、软分身原生启动器；自动/dylib/launcher 三种环境注入选择。
- 独立数据路径、HOME/TMPDIR 和配方环境变量、白名单共享路径、应用语言、HTTP/HTTPS/SOCKS5 代理、钥匙串密码。
- 应用图标默认预览，.icns 替换，更新时读取已安装图标，不依赖原始文件。
- 硬分身主程序名为自定义名称，辅助程序名为 `名称-原名称`，启动器名为 `名称-Launcher`。保留兼容软链接，在改名之前拒绝文件冲突。
- Mach-O 头部空间检查与 dylib load command 注入，Cocoa/POSIX 隔离钩子、CEF/单实例兼容补丁、辅助 Bundle ID 更新、旧 framework 清理、逐层签名与严格验证。
- 更新先在同目录构建临时副本，验证签名后替换；构建失败保留原分身。更新不会删除数据目录。
- 原生 CLI 提供环境检查、应用探测和分身管理。

Swift 标准库无法提供 YAML 解析，因此只引入 [Yams](https://github.com/jpsim/Yams) 一个包依赖。`Package.resolved` 固定解析版本。克隆生成的启动器与注入库是小型 C / Objective-C 运行时胶水，由 Swift 调用 Apple clang 编译；没有嵌入 Python 引擎。

## 数据与规则

默认目录为 `~/AppDuo/`：`Apps/`、`Data/`、`recipes/`、`clones.json`。如果已有 Swift 版的 `~/ATBCloneSwift/` 且新目录不存在，自动创建 `~/AppDuo` 指向旧目录的兼容链接，保留已有分身内嵌的数据路径与登录数据；新建分身使用 AppDuo 路径。与 Python 旧版 `~/ATBClone/` 独立，不自动迁移该版本的数据。

分身目录默认无需提权。当前版本不提供系统目录的自动管理员授权；请使用用户可写路径。数据删除默认关闭；仅能从应用中删除本工具默认 Data 目录下的数据，自定义路径需要用户在 Finder 中管理。

## CLI

```sh
swift run AppDuoCLI clone /Applications/WeChat.app --name WeWork --icon /path/icon.icns
swift run AppDuoCLI list
swift run AppDuoCLI update WeWork
swift run AppDuoCLI remove WeWork              # 确认后移到废纸篓，保留数据
swift run AppDuoCLI probe /Applications/WeChat.app
swift run AppDuoCLI recipes
swift run AppDuoCLI doctor
```

运行 `swift run AppDuoCLI help` 查看代理、语言、目录和注入参数。`--root DIR` 可隔离测试数据。密码通过 `ATBCLONE_PROXY_PASSWORD` 环境变量传入，记录中不存明文密码。

硬分身规则示例（大小写需与名称一致）：

```yaml
- PROCESS-NAME-REGEX,^WeWork(-|$),🇸🇬 新加坡节点
```

代理环境变量不保证所有应用遵循；Clash 进程识别及规则命中应在实际客户端验证。软分身仍运行原应用的进程。

## 验证与边界

`swift test` 使用真实 clang 编译 Mach-O 测试应用，验证软/硬分身、dylib/launcher、进程实际路径、含特殊字符的环境变量、源程序不变、图标文件删除后仍可连续更新、签名有效、同目录辅助程序重名拒绝，以及更新失败保留旧分身。

第三方应用会持续更新，特别是 CEF、飞书和 ChatGPT 的二进制兼容补丁。移植代码和内置规则不代表每个第三方版本都通过了实际登录、通知和多开测试。当前界面为中文；分身应用支持多语言。原版 GUI 全语种翻译、在线自更新、旧版状态自动迁移及管理员提权尚未移植。

## 结构

- `Sources/CloneCore/`：Swift 核心、YAML 规则、运行时模板与资源。
- `Sources/AppDuo/`：SwiftUI 界面、AppKit 文件选择和应用启动桥接。
- `Sources/AppDuoCLI/`：原生命令行入口。
- `Tests/CloneCoreTests/`：真实二进制集成回归测试。
- `script/build_and_run.sh`：唯一构建、启动、调试、打包入口。

### 通知与原生应用语言

原生 Cocoa 应用使用自动注入时，语言通过偏好设置与环境变量设置；不会因为选择英文等语言切换为启动器。直接启动已登记的主程序，避免通知服务因进程身份不匹配拒绝请求。此前创建的分身需要退出后执行一次更新，保留数据、图标、名称和 Bundle ID。显式选择 launcher 或依赖启动参数的应用仍可能存在系统通知/菜单栏兼容性限制。
