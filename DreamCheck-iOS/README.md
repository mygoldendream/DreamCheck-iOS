# 此刻真实吗（iOS）

清明梦验梦提醒器的 iOS 版，是 Android 项目
[lucid-dream-reality-check](https://github.com/mygoldendream/lucid-dream-reality-check)
（MIT 协议）的 SwiftUI 移植，并在其上做了增强。

## 功能

- **提醒**：整点对齐 / 连续间隔两种模式，可设时间窗（支持跨午夜）。
- **分时段间隔**：可以为一天里的不同时段分别设置间隔，例如上午 15 分钟、下午 30 分钟，取代全天的单一间隔。
- **记录**：每条提醒都带三个按钮——「完成了」「记录」「跳过」。点「记录」会打开 App 写一条验梦备注；不想记可以点「跳过」，只算一次跳过、不计入完成。App 里的「今天」页也能随时补记或修改。
- **日历统计**：统计页是月历，每一天下面有一个小圆点，越绿说明当天完成率越高；点某一天进去可以看到当天的完成次数、跳过次数、总提醒数和验梦率，以及每一条记录和备注。
- 所有数据保存在本地，不联网、不上传。

## 工作原理

- 排程算法（整点对齐 / 连续间隔 / 分时段、时间窗、跨午夜）从 Android 版移植并扩展。
- 提醒依赖 iOS 本地通知。系统最多排队 64 条通知，所以一次预排 60 条，每次打开应用时自动补排。
- 通知的「记录」按钮会唤起 App，即使 App 没在运行也能收到（冷启动响应已做处理）。

## 打包成 IPA（无需 Mac、无需签名）

用 GitHub Actions 的 macOS 机器编译无签名 IPA，配合 TrollStore 安装。

1. 把整个目录推到 GitHub 仓库（例如 `DreamCheck-iOS`）。
2. 进入仓库 **Actions** 页，选 “Build iOS IPA”，点 **Run workflow**（推送到 `main` 也会自动触发）。
3. 运行完成后，在页面底部的 **Artifacts** 里下载 `DreamCheck-ipa`，解压得到 `DreamCheck.ipa`。
4. 用 TrollStore 安装这个 `.ipa`。

## 本地（可选，需要 Mac + Xcode）

```bash
brew install xcodegen
xcodegen generate
open DreamCheck.xcodeproj
```

## 已知限制（iOS 与 Android 的差异）

- 无法像安卓那样锁屏全屏弹窗；提醒以系统通知（横幅 / 锁屏通知）呈现。
- 无法在后台持续振动；通知只能响一声、振一下。
- 无法在“强行停止”后自动恢复；只能下次打开应用时补排。
- 后台不运行时系统不会回调应用，因此“已触发但一直没处理”的提醒会在下次打开 App 时记为「跳过」。
- 「记录」按钮需要把 App 调到前台，这是 iOS 通知的机制限制。

## 目录结构

- `project.yml` —— XcodeGen 工程描述（CI 里自动生成 `.xcodeproj`）。
- `Sources/` —— 全部 Swift 源码与 App 图标。
- `.github/workflows/build.yml` —— 生成无签名 IPA 的 CI 流程。
