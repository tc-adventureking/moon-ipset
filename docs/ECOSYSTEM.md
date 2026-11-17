# 生态基线与复用范围

核查日期：2026-11-17。此表比较已检查的公开 API，不是对整个 MoonBit 生态的穷尽证明。

| 对象与固定参考 | 已有能力 | 本项目的补充范围 |
| --- | --- | --- |
| [moonbit-community/ipaddr，e75b311](https://github.com/moonbit-community/ipaddr/blob/e75b311282f89c24c2184e1f0ed8b61aa275b6d6/pkg.generated.mbti) | IPv4 地址、Ipv4Prefix、MAC，含解析、格式、属性和前缀包含 | 双栈网络、接口、范围与集合代数；本项目不提供 MAC API，不是所有功能的替代品 |
| [moonbitlang/async 0.22.4 socket](https://skills.mooncakes.io/docs/moonbitlang/async%400.22.4/socket) | 双栈 socket 地址、端口、主机解析及网络 I/O 所需接口 | 纯值语义的网络划分、接口配置值、归并和集合运算；本项目不提供 socket I/O 或 DNS 解析 |
| [moonbit-community/rtc 0.0.1 transport](https://mooncakes.io/docs/moonbit-community/rtc%400.0.1/transport) | V4/V6 地址类型、解析、字节和文本转换 | 通用网段/接口及集合处理；本项目不提供 RTC 传输协议 |
| [CPython 3.13.2 ipaddress](https://github.com/python/cpython/blob/v3.13.2/Lib/ipaddress.py) | 成熟地址、网络、接口和范围/归并语义 | 在 MoonBit 中提供对应值模型及四后端能力，公开说明适配；Python 本身没有同名 IpSet 集合 API |
| [netaddr 1.3.0 IPSet](https://netaddr.readthedocs.io/en/1.3.0/tutorial_03.html) | 成熟双栈集合代数、CIDR 表示和成员查询 | 用作独立场景参考；不声称本项目功能全面超过 netaddr 或运行速度普遍更快 |

因此，能够支持的增量是“在 MoonBit 中组合可复用的双栈地址、网络、接口和数值集合能力，并实际检查四个后端”，而不是“MoonBit 以前没有 IPv6”。

## 可核查的实际场景

[云网段清单示例](https://github.com/tc-adventureking/moon-ipset/tree/main/examples/cloud-policy) 固定一份 AWS 官方快照：4,490 条 EC2 记录归并为 2,668 个 CIDR，减少约 40.6% 的表示条目且不改变地址集合。减去其中 572 条 us-east-1 记录的数值覆盖后，得到 2,595 个 CIDR。所有 CIDR、分族地址数及 512 项成员查询与 netaddr 1.3.0 的独立结果对照。

该例把已有 API 接到真实双栈输入上，展示无需枚举地址空间的归并与排除，以及发布包可复用的库接口。数字表示这个固定快照的结果；条目压缩率不是相对 netaddr 的算法优势，也不是吞吐提升。源数据、筛选规则、哈希和运行入口均保留在示例目录。

目前没有据此宣称第三方采用、生产部署或“全生态最佳”。作者自建的应用案例、独立成熟实现给出的参考输出，以及真实外部采用是三种不同证据。
