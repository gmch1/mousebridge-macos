# MouseBridge Windows / Linux 版本需求

状态：开发前需求基线  
目标分支：`windows`  
适用项目：https://github.com/gmch1/mousebridge-macos

## 1. 背景与目标

MouseBridge 已有可运行的原生 macOS 版本。Windows 和 Linux 版本的目标不是复刻
Logitech Options+，而是提供一个轻量、可审查、便于脚本和 Codex 等编码工具继续扩展的
鼠标能力底座。

首批能力保持一致：

- 鼠标中键、后退侧键、前进侧键映射。
- 仅反转鼠标的垂直或水平滚动，不改变触控板方向。
- 配置每次滚动量，范围为 0–20；0 表示保留系统/设备原始滚动量。
- 查询并设置 Logitech M750 L 的硬件 DPI。
- 提供轻量图形界面、托盘入口、JSON 配置和 CLI。
- 无账号、云服务、遥测、广告和自动上传日志。

## 2. 首批实测硬件

| 项目 | 值 |
| --- | --- |
| 鼠标 | Logitech Signature Plus M750 L |
| 首要连接方式 | Bluetooth |
| Vendor ID | `0x046D` |
| Product ID | `0xB02C` |
| DPI | 设备报告 400–4000 DPI、100 DPI 步长、37 档 |
| HID++ 功能 | Adjustable DPI `0x2201` |

Logitech Bolt 接收器、其他 M750 变体和其他 Logitech 鼠标属于后续扩展，首版不得在未
测试时宣称支持。

## 3. 范围与非目标

### 3.1 首版范围

- Windows 10 22H2、Windows 11，优先 x64。
- 主流 Linux 桌面发行版，优先 Ubuntu/Debian x86_64；架构不得写死，为 arm64 留出空间。
- 用户会话内运行，不要求长期拥有管理员/root 权限。
- 单设备配置；先支持 M750 L 蓝牙。
- 英文界面优先，字符串必须集中管理，以便后续增加中文。

### 3.2 非目标

- Logitech Flow、固件升级、电量管理、摄像头、键盘和灯光。
- 按应用自动切换配置。
- 宏录制、脚本执行或任意 shell 命令。
- 内核驱动开发。
- Electron、Python 常驻运行时或浏览器 UI。

## 4. 仓库结构

建议保留单一仓库，但平台实现隔离：

```text
platforms/
  windows/
  linux/
shared/
  config.schema.json
  hidpp-test-vectors/
docs/
```

平台之间共享“行为规范、配置语义、HID++ 测试向量和验收用例”，不强制共享底层事件
处理代码。不得为了复用少量逻辑引入大型跨平台 GUI 框架。

## 5. 通用功能需求

### 5.1 按键映射

支持：

- `middleAction`
- `backAction`
- `forwardAction`

行为：

- 空字符串：原始按键透传。
- `none`：吞掉原始按键，不执行动作。
- 快捷键：吞掉原始按键，并发送目标快捷键。
- 按下时执行一次，释放事件也应被正确吞掉，不能产生卡键。
- 应忽略程序自身注入的事件，避免递归触发。

快捷键语法：

```text
ctrl+r
ctrl+shift+z
alt+left
meta+w
none
```

修饰键统一使用 `ctrl`、`shift`、`alt`、`meta`。Windows 中 `meta` 表示 Win，Linux 中
表示 Super。可兼容读取 `cmd`，但保存时应规范化为 `meta` 或平台约定值。

### 5.2 滚轮

- 垂直反向与水平反向分别配置。
- 只处理鼠标事件，不改变触控板、触摸屏或精密触控板手势。
- `scrollLines = 0`：保留原始幅度，只按配置改变方向。
- `scrollLines = 1...20`：将离散滚轮事件规范化为对应步数。
- 保留水平滚动的符号语义，不能把垂直/水平轴混用。
- 连续滚动设备不得被错误量化为离散 20 行跳动。

### 5.3 DPI

- 通过 HID++ feature `0x2201` 查询 DPI 档位，不仅依赖硬编码范围。
- M750 L 预期报告 400–4000 DPI、100 DPI 步长。
- UI 使用 0–100% 位置表达，但显示实际 DPI 数值；CLI 直接使用实际 DPI。
- 保存配置后立即应用 DPI。
- 正常退出时尽力恢复程序启动/连接时读取到的原始 DPI。
- 设备不可用时，按键和滚轮功能仍应工作，并显示明确状态。
- 请求必须串行化，具有 2 秒以内超时，断连时不得死锁或崩溃。

### 5.4 配置

平台配置分别存放：

- Windows：`%LOCALAPPDATA%\MouseBridge\config.json`
- Linux：`${XDG_CONFIG_HOME:-~/.config}/mousebridge/config.json`

建议结构：

```json
{
  "schemaVersion": 1,
  "middleAction": "",
  "backAction": "ctrl+r",
  "forwardAction": "ctrl+w",
  "reverseVerticalScroll": false,
  "reverseHorizontalScroll": false,
  "scrollLines": 0,
  "dpi": 1000
}
```

要求：

- 原子写入。
- 数值归一化：滚动量 0–20；DPI 使用设备支持的最近档位。
- 外部修改后自动重新加载。
- 非法配置不应导致后台进程退出；应记录错误并继续使用上一个有效配置。

### 5.5 CLI

至少支持：

```text
MouseBridge config path
MouseBridge config get
MouseBridge config set middle|back|forward <shortcut|none>
MouseBridge config set reverse-vertical|reverse-horizontal <true|false>
MouseBridge config set scroll-lines <0-20>
MouseBridge config set dpi <400-4000>
MouseBridge diagnose
MouseBridge --self-test
```

CLI 应返回稳定退出码：成功为 0，参数错误为 2，运行/设备错误为 1。

## 6. Windows 实现要求

推荐首版技术栈：.NET 8 WinForms + Win32 P/Invoke，不引入第三方 NuGet 运行时依赖。

### 6.1 输入与注入

- 使用 `WH_MOUSE_LL` 监听用户会话鼠标事件。
- 使用 `SendInput` 发送快捷键与替换后的滚轮事件。
- 检查 `LLMHF_INJECTED`，避免处理自身注入事件。
- 普通用户权限下可运行；不默认请求管理员权限。
- 如果目标应用以更高完整性级别运行，应说明 Windows UIPI 限制，而不是静默失败。

### 6.2 DPI 传输

- 使用 Windows HID/SetupAPI 枚举 `VID_046D&PID_B02C` 接口。
- 不按枚举顺序盲选接口；应发送 HID++ feature 查询确认接口。
- 支持 Bluetooth HID 接口多实例情况。
- 记录打开失败、超时、报告长度和匹配结果，但日志不得包含用户输入内容。

### 6.3 UI 与生命周期

- WinForms 设置窗口。
- 通知区域图标，菜单包含：打开设置、暂停/恢复映射、诊断信息、退出。
- 点击窗口关闭时默认缩到托盘；菜单“退出”才真正停止。
- 保存后立即应用，不需要重启。
- 首版可不实现开机自启，但架构应为后续 Startup Task/注册表方案留出接口。

## 7. Linux 实现要求

推荐首版技术栈：Rust 或 Go；输入层使用 `evdev`/`uinput`，DPI 使用 `hidraw`。最终选择以
249 上可重复构建、依赖体积和权限模型为准。

### 7.1 输入与注入

- 仅打开目标鼠标的 evdev 设备，不抓取键盘。
- 通过设备 VID/PID、能力位和物理路径识别鼠标；不得依赖 `/dev/input/eventN` 固定编号。
- 使用 uinput 创建虚拟鼠标/键盘输出。
- 必须避免重新读取自己创建的虚拟设备。
- Wayland 与 X11 下都不依赖桌面全局快捷键 API；以 evdev/uinput 为基础。

### 7.2 权限

- 提供最小权限 udev 规则示例，仅授权 Logitech 目标设备、`uinput` 和必要 hidraw 节点。
- 安装规则可能需要 root，但日常进程以普通用户运行。
- 不建议将用户永久加入过宽的 `input` 组作为唯一方案。

### 7.3 后台服务

- 提供 systemd user service 示例。
- 设备断开后等待重连，不进行高频轮询。
- 正常退出时恢复 DPI 并销毁虚拟设备。
- 首版 GUI 可选，但 CLI、配置热加载和诊断必须完成。

## 8. 日志与诊断

日志位置：

- Windows：`%LOCALAPPDATA%\MouseBridge\MouseBridge.log`
- Linux：优先 journald；无 systemd 时写入 XDG state 目录。

`diagnose` 至少输出：

- 版本、操作系统、架构。
- 配置路径与日志路径。
- 鼠标事件后端是否启动。
- M750 HID++ 接口是否连接。
- 设备报告的 DPI 范围与当前 DPI。
- 所需权限/设备节点是否可访问。

默认日志不得逐条记录用户按键；详细事件日志必须显式开启。

## 9. 非功能需求

- 空闲 CPU 接近 0%。
- Windows 稳态物理内存目标小于 60 MB；Linux 守护进程目标小于 30 MB。
- 无网络请求和遥测。
- 设备断连、休眠恢复、配置写入和重复启动不得导致崩溃。
- 所有底层句柄、hook、文件描述符和虚拟设备必须在退出时释放。
- Windows 事件回调和 Linux 输入热路径不得执行阻塞 HID 请求。

## 10. 测试与验收

### 10.1 自动化测试

- 快捷键解析：合法、非法、`none`、空值。
- 垂直/水平滚动方向与 0–20 步数。
- HID++ DPI 列表：显式值、范围压缩、结束标记、非法输入。
- 配置归一化、原子保存和非法配置回退。
- 自身注入事件不会递归。

### 10.2 Windows 验收

- GitHub Actions `windows-latest` 编译成功。
- `--self-test` 成功。
- 生成 win-x64 ZIP 和 SHA-256。
- Windows 实机验证侧键、垂直滚动和 DPI 后才能在 README 标记“已测试”。

### 10.3 Linux 验收

- 在 249 上执行格式化、静态检查、单元测试和 release build。
- 无鼠标硬件时，协议与输入转换使用测试向量/虚拟设备验证。
- 接入 M750 实机前，README 必须写“Linux 编译通过，硬件未验证”。

## 11. CI 与发布

- Windows workflow：Windows runner，构建、自检、打包 artifact。
- Linux workflow：Ubuntu runner，格式化、lint、测试、构建。
- 平台版本首轮使用 `0.1.0-preview`，在实机验证前不发布为稳定版。
- 发布包必须包含 GPL-3.0、第三方许可证、NOTICE、版权和对应源码说明。
- 不改写已有 macOS `v0.2.x` tag；Windows/Linux 后续采用独立平台资产或明确版本策略。

## 12. Codex CLI 开发顺序

1. 读取本文档、根目录 GPL/第三方声明和 macOS 行为测试。
2. 建立共享配置 schema 与 DPI 测试向量。
3. Windows：先完成配置、CLI、自测，再完成 hook、UI、HID++。
4. Windows 推送后以 GitHub Windows runner 修复真实编译错误。
5. Linux：在 249 选择工具链并完成 evdev/uinput/hidraw 的最小闭环。
6. 分别补充平台 README，明确“编译验证”和“硬件实测”的区别。
7. 未通过自动化测试和实机验收前，不宣称生产可用。

## 13. 当前未知项与风险

- Windows 对 M750 蓝牙 HID++ 接口的读写权限和报告长度需实机确认。
- Linux 蓝牙 HID++ 可能暴露多个 hidraw/evdev 节点，需要基于接口能力探测。
- 精密触控板与普通鼠标滚轮来源区分需 Windows 实机回归。
- Wayland 桌面下的 uinput 虚拟键盘可能触发安全提示或 compositor 限制。
- 各桌面/应用对水平滚轮符号的解释可能不同。

这些风险必须通过日志和能力探测暴露，不得通过大量硬编码或静默失败掩盖。
