# Third-party notices / 第三方声明

MouseBridge is an independent implementation. It does not vendor, copy, or
link executable code from the projects below. Their public source was consulted
for interoperability research and protocol understanding.

MouseBridge 是独立实现，没有打包、复制或链接下列项目的可执行代码。项目仅在互操作研究
和协议理解过程中查阅了它们的公开源码。

## Scroll Reverser

- Project / 项目：[Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser)
- License / 许可证：[Apache License 2.0](https://github.com/pilotmoon/Scroll-Reverser/blob/master/LICENSE)
- Copyright: Nicholas Moore and Scroll Reverser contributors
- Reference scope / 参考范围：gesture timing used to distinguish trackpads
  from mice, and updating both Quartz and underlying IOHID scroll values for
  reliable reversal；触控板与鼠标的事件时序，以及可靠反转时同时更新 Quartz 和底层 IOHID
  滚动值。

## Solaar

- Project / 项目：[Solaar](https://github.com/pwr-Solaar/Solaar)
- License / 许可证：[GNU General Public License v2.0](https://github.com/pwr-Solaar/Solaar/blob/master/LICENSE.txt)
- Copyright: Solaar contributors
- Reference scope / 参考范围：public source used as protocol documentation
  for Logitech HID++ feature `0x2201` adjustable-DPI list encoding；将公开源码作为
  Logitech HID++ `0x2201` 可调 DPI 列表编码的协议资料。

The licenses above apply to their respective original projects. MouseBridge's
own source is distributed under the MIT License.

上述许可证适用于各自的原始项目；MouseBridge 自身源码使用 MIT License。
