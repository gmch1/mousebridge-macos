# MouseBridge for macOS

[English](README.md) | 简体中文

MouseBridge 是一个轻量的原生 macOS 鼠标工具底座，提供按键映射、仅鼠标滚轮控制以及
Logitech HID++ 硬件 DPI 配置。它面向只需要少量鼠标功能、不希望长期运行大型厂商套件的
用户。

项目有意通过小型 AppKit 界面、带版本的 JSON 配置文件和 CLI 暴露底层能力，方便普通
用户、脚本以及 Codex 等编码代理继续开发，而不必先理解或替换一个庞大的框架。

[下载最新版本](https://github.com/gmch1/mousebridge-macos/releases)

## 项目目标

- 保持小巧、原生、容易理解和修改。
- 提供可靠的按键、滚轮与硬件 DPI 基础能力。
- 配置完全保存在本地，并适合自动化处理。
- 新增鼠标支持时优先增加设备配置，而不是重写界面。
- 不引入账号、云服务、遥测，也不依赖 Electron、Qt 或 Python 运行时。

MouseBridge 并不打算复刻 Logitech Options+ 的全部功能。目前不管理手势、按应用配置、
Flow、固件升级、电量信息，也不管理 Logitech 摄像头和键盘。

## 当前功能

- 将滚轮中键、后退侧键和前进侧键映射为 `cmd+r` 等快捷键。
- 填写 `none` 可禁用按键；留空则透传原始按键。
- 只反转鼠标的垂直或水平滚动，不改变触控板方向。
- 设置 0–20 的离散滚动量；`0` 表示跟随 macOS 默认值。
- 通过 Logitech HID++ `0x2201` 查询设备实际 DPI 档位，并使用 0–100% 滑杆选择。
- 脚本或编码代理修改 JSON 后自动重新加载配置。
- 通过 `SMAppService` 设置登录时启动。
- 将诊断日志写入 `~/Library/Logs/MouseBridge.log`。

## 已测试硬件与环境

当前唯一经过实机测试的设备配置如下：

| 项目 | 已测试值 |
| --- | --- |
| 鼠标 | Logitech Signature Plus M750 L |
| 连接方式 | 蓝牙 |
| USB/HID 标识 | VID `0x046D`、PID `0xB02C` |
| 设备报告的 DPI | 400–4000 DPI、每档 100 DPI、共 37 档 |
| Mac 架构 | Apple 芯片（`arm64`） |
| 测试系统 | macOS 26.5.2 |
| 应用版本 | MouseBridge 0.2.0 |

已经过实机验证的功能包括：蓝牙设备发现、前进/后退侧键映射、垂直滚动反转，以及硬件
DPI 的读取和应用。滚动计算、配置迁移、快捷键校验和 DPI 解码另有自动化测试。

以下路径已经实现，但尚未获得同等程度的实机覆盖：水平滚动、滚轮中键映射、Logitech
Bolt 接收器、Intel Mac 和其他 Logitech 鼠标型号。项目最低部署目标为 macOS 13，但尚未
逐个测试所有 macOS 版本。报告兼容性问题时，请附上产品名称、连接方式、VID/PID、macOS
版本和诊断日志。

## 权限

拦截鼠标按键、修改滚轮事件和发送快捷键需要“辅助功能”权限。为了可靠地区分鼠标与
触控板，强烈建议同时开启“输入监控”；当前实测环境已开启该权限。macOS 的隐私权限
必须由用户手动批准，应用无法静默给自己授权。

设置窗口提供了对应系统设置页面的快捷入口。

## 安装

从 [GitHub Releases](https://github.com/gmch1/mousebridge-macos/releases) 下载 ZIP，
解压后把 `MouseBridge.app` 移动到 `/Applications`。

当前 0.2.0 预览版尚未配置 Apple Developer ID，因此使用 ad-hoc 签名，Gatekeeper 可能
要求手动批准。仓库配置文档中列出的 Apple secrets 后，流水线会自动生成 Developer ID
签名并经过 Apple 公证的正式包。

## 构建与测试

```bash
zsh build-app.sh
open dist/MouseBridge.app
```

脚本会优先使用 `/Applications/Xcode.app`，运行 XCTest 与二进制自检，构建 Release
可执行文件，组装应用包，并应用用于本地开发的 ad-hoc 签名。

Developer ID 构建示例：

```bash
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
VERSION=0.2.0 BUILD_NUMBER=2 zsh build-app.sh
NOTARY_PROFILE=mousebridge-notary zsh scripts/notarize.sh
```

## 发布版本

推送 `v0.2.0` 这样的语义化版本 tag 后，流水线会校验 tag 与 `Info.plist` 版本是否一致，
运行全部测试、构建应用、生成 ZIP 和 SHA-256，并创建 GitHub Release。没有 Apple 签名
secrets 时，流水线会明确发布为 Pre-release。

完整步骤见 [docs/RELEASING.zh-CN.md](docs/RELEASING.zh-CN.md)。

## 配置与 CLI

配置文件位于：

```text
~/Library/Application Support/MouseBridge/config.json
```

旧版 `LogiLite/config.json` 会迁移一次。损坏的文件不会被覆盖，而会保留为
`config.corrupt-<timestamp>.json`。

```bash
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config get
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config set back cmd+r
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config set scroll-lines 4
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge config set dpi 1200
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge launch-at-login status
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge launch-at-login enable
/Applications/MouseBridge.app/Contents/MacOS/MouseBridge diagnose
```

应用运行时会监控配置目录，并自动应用外部写入的合法配置。

## 架构与扩展点

- `AppConfig` 与 `ConfigStore`：带版本的 JSON、迁移、原子写入与目录监控。
- `EventTapController`：按键拦截、输入源识别和滚轮转换。
- `ScrollTransform`：纯函数实现并经过测试的离散滚动计算。
- `ShortcutExecutor`：轻量快捷键解析和 Quartz 事件注入。
- `HIDPPController`：基于设备配置的 IOKit 传输、DPI 查询、串行请求、安全断连清理和退出时
  尽力恢复 DPI。
- `SettingsWindowController`：小型 AppKit 设置界面。
- `CommandLineInterface`：面向脚本与编码代理的自动化接口。

新增设备从 `MouseDeviceProfile` 开始，传输层不需要知道产品的市场名称。

## 开源参考项目

MouseBridge 是采用 MIT 许可证的独立实现。互操作研究参考了：

- [Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser)（Apache-2.0）：其公开
  实现帮助确认了触控板/鼠标的事件时序，以及可靠反转滚轮时同时更新 Quartz 和底层
  IOHID 滚动数据的必要性。
- [Solaar](https://github.com/pwr-Solaar/Solaar)（GPL-2.0）：参考其公开源码，将其作为
  Logitech HID++ 可调 DPI 列表编码的协议文档。

MouseBridge 没有包含或链接上述项目的代码。准确的致谢和许可证链接见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 兼容性与分发说明

为了可靠反转滚轮，MouseBridge 会动态加载 Scroll Reverser 也记录过的私有 IOHID 桥接
符号；符号不可用时会退回公开 Quartz 字段。私有 API 可能随 macOS 更新而变化，因此新
系统版本需要重新进行滚轮回归测试。这也意味着项目更适合直接分发，而不是 Mac App Store。

## 许可证

MouseBridge 使用 MIT License。
