# 此刻真实吗（iOS）

清明梦验梦提醒器的 iOS 版，是 Android 项目
[lucid-dream-reality-check](https://github.com/mygoldendream/lucid-dream-reality-check)
（MIT 协议）的 SwiftUI 移植。通过系统通知定时提醒你验梦，并记录每天完成/忽略的次数和有效率。

## 工作原理

- 排程算法（整点对齐 / 连续间隔两种模式、时间窗、跨午夜）从 Android 版一比一移植。
- 提醒依赖 iOS 本地通知。系统最多排队 64 条通知，所以一次预排 60 条，每次打开应用时自动续排。
- 数据全部保存在本地（UserDefaults），不联网、不上传。

## 打包成 IPA（无需 Mac、无需签名）

本仓库用 GitHub Actions 的 macOS 机器编译无签名 IPA，正好配合 TrollStore 安装。

1. 把整个目录推到一个 GitHub 仓库（例如你已有的 `DreamCheck-iOS`）。
2. 进入仓库的 **Actions** 页，找到 “Build iOS IPA” 工作流，点 **Run workflow**。
3. 几分钟后，工作流下方的 **Artifacts** 里下载 `DreamCheck-ipa`，解压得到 `DreamCheck.ipa`。
4. 把 `.ipa` 传到 iPhone，用 TrollStore 安装即可。

> 推送到 `main` 分支也会自动触发构建。

## 本地（可选，需要 Mac + Xcode）

```bash
brew install xcodegen
xcodegen generate
open DreamCheck.xcodeproj
```

## 已知限制（iOS 与 Android 的差异）

- 无法像安卓那样锁屏全屏弹窗；提醒以系统通知（横幅/锁屏通知）呈现。
- 无法在后台持续振动；通知只能响一声、振一下。
- 无法在“强行停止”后自动恢复；只能下次打开应用时补排。
- 后台不运行时，系统不会回调应用，因此“已触发但未处理”的提醒会在你下次打开应用时记为“忽略”。

## 目录结构

- `project.yml` —— XcodeGen 工程描述（在 CI 里自动生成 `.xcodeproj`）。
- `Sources/` —— 全部 Swift 源码与 App 图标。
- `.github/workflows/build.yml` —— 生成无签名 IPA 的 CI 流程。
