# Third-party notices / 第三方声明

MouseBridge combines original work with interoperability logic and
implementation patterns informed by the projects listed below. This notice
records provenance, copyright ownership, and the licenses that apply.

MouseBridge 将原创工作与下列项目提供的互操作逻辑、实现模式结合。本声明记录其来源、
版权所有者和适用许可证。

## Scroll Reverser

- Project / 项目：[Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser)
- Upstream license / 上游许可证：Apache License 2.0
- Copyright 2011 Nicholas Moore and Scroll Reverser contributors
- MouseBridge usage / 使用范围：trackpad and mouse event timing, Quartz and
  IOHID scroll-field handling, and the passive/active event-tap approach；触控板与
  鼠标事件时序、Quartz/IOHID 滚动字段处理，以及被动/主动事件监听方式。
- Required texts / 完整文本：[Apache-2.0.txt](LICENSES/Apache-2.0.txt) and
  [Scroll-Reverser-NOTICE.txt](LICENSES/Scroll-Reverser-NOTICE.txt)

## Solaar

- Project / 项目：[Solaar](https://github.com/pwr-Solaar/Solaar)
- Upstream license / 上游许可证：GPL-2.0-or-later
- Copyright 2012-2013 Daniel Pavel and Solaar contributors
- MouseBridge usage / 使用范围：Logitech HID++ feature `0x2201`
  adjustable-DPI list retrieval and range decoding；Logitech HID++ `0x2201`
  可调 DPI 列表读取与范围解码。
- Original license text / 原始许可证文本：[GPL-2.0.txt](LICENSES/GPL-2.0.txt)

Solaar grants the option to use the relevant work under GPL version 2 or any
later version. MouseBridge exercises that option and distributes the combined
work under GPL-3.0-or-later. Apache-2.0 notices remain included as required.

Solaar 允许相关工作使用 GPL 第 2 版或任意更高版本。MouseBridge 选择更高版本条款，将
组合项目按 GPL-3.0-or-later 分发，并按要求继续保留 Apache-2.0 声明。

## TapBind / MiddleClick

- Projects / 项目：[TapBind](https://github.com/gmch1/TapBind) and
  [MiddleClick](https://github.com/artginzburg/MiddleClick)
- Upstream license / 上游许可证：GPL-3.0
- Copyright Clément Beffa, Alex Galonsky, Carlos E. Hernandez, Pascâl
  Hartmann, Arthur Ginzburg, guomingchao, and contributors
- MouseBridge usage / 使用范围：private MultitouchSupport declarations,
  device callback lifecycle, and multi-finger click/tap behavior；私有
  MultitouchSupport 声明、设备回调生命周期以及多指按压/轻点行为。
- MouseBridge uses a separately implemented configurable gesture state machine
  and an allocation-free callback path；MouseBridge 使用独立重写的可配置手势
  状态机和零数组分配回调链路。

TapBind and MiddleClick are GPL-3.0 works. MouseBridge distributes the combined
work under GPL-3.0-or-later; the complete GPL-3.0 text is included as the root
`LICENSE` and in packaged application resources.

TapBind 与 MiddleClick 使用 GPL-3.0。MouseBridge 将组合项目按 GPL-3.0-or-later
分发；完整 GPL-3.0 文本位于仓库根目录 `LICENSE`，并会打入应用资源。
