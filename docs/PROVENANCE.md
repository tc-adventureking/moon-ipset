# 实现来源、参考与许可

## 本仓库代码

本仓库的地址表示、解析、CIDR 处理、集合区间运算和 CIDR 分解为本项目独立实现，使用 [MIT License](../LICENSE)。项目未将第三方 IP 地址库源码复制、修改后作为本仓库实现，也未把已有库改名后声称为新算法。

项目使用 AI 辅助开发：Codex 负责实现、集成与验证工作，Claude 参与设计讨论和技术审查。模型建议需要经过源码检查和实际测试，不作为独立事实证明。仓库中的技术文档用于说明接口、操作和来源，不代替作者对代码及行为的理解。

集合区间规范化、双指针集合运算和 CIDR 分解属于既有技术方法。本项目不宣称这些方法首创，也不把尚未检索到相同项目视为生态中绝对不存在替代实现的证明。

## 标准参考与明确的策略选择

| 来源 | 在本项目中的用途 |
| --- | --- |
| [RFC 4291 §2.2–2.3](https://www.rfc-editor.org/rfc/rfc4291.html#section-2.2) | IPv6 完整表示、一次 `::` 压缩、嵌入 IPv4 的文本形式及地址前缀表示。 |
| [RFC 5952 §4](https://www.rfc-editor.org/rfc/rfc5952.html#section-4) | IPv6 小写十六进制、去除组内前导零、压缩首个最长零段，避免压缩单个零组。 |
| [RFC 4632 §3.1](https://www.rfc-editor.org/rfc/rfc4632.html#section-3.1) | IPv4 CIDR 前缀表示与地址块含义。 |

这些标准是语义参考，未复制其中的代码组件。行为以 [SPEC.md](SPEC.md) 记录的接口约定为准，不笼统宣称完全实现这些 RFC 的所有网络功能。

特别是 [RFC 5952 §5](https://www.rfc-editor.org/rfc/rfc5952.html#section-5) 对能由已知前缀识别的嵌入 IPv4 地址推荐混合写法。本项目为得到一致、可比较的文本输出，**有意选择纯十六进制输出**，例如把 `::ffff:192.0.2.1` 输出为 `::ffff:c000:201`。输入仍接受合法的嵌入 IPv4 写法；这不是对第 5 节混合表示建议的完全遵循。

其他明确策略：

- IPv4 和 IPv6 保持不同地址族；不自动把 mapped IPv6 转换为 IPv4。
- CIDR 默认清除主机位，调用者可通过 `strict=true` 要求拒绝主机位。
- 输入拒绝空白、zone ID、括号、IPv4 前导零以及带前导零的前缀长度。
- 地址区间为闭合区间；最大值的后继和零值的前驱返回不存在，不环绕。
- 不提供整个 IPv6 地址空间的机器整数计数，不把网络地址和广播地址从地址集合中自动扣除。

## 已有实现检查

开发前检查了 [`moonbit-community/ipaddr`](https://github.com/moonbit-community/ipaddr) 的公共接口、源码、模块元数据与许可证。核对的仓库树标识为 `e75b311282f89c24c2184e1f0ed8b61aa275b6d6`，模块元数据为 `bobzhang/ipaddr`、版本 `0.1.2`。

检查结果存在两项影响复用的事实：

1. README 描述包含 IPv6，但当时的 [`pkg.generated.mbti`](https://github.com/moonbit-community/ipaddr/blob/main/pkg.generated.mbti) 与实现仅公开 IPv4、IPv4Prefix 和 MAC，未提供所需的 IPv6 地址及前缀功能。
2. 模块元数据／README 声明 ISC，而仓库 [`LICENSE`](https://github.com/moonbit-community/ipaddr/blob/main/LICENSE) 内容为 Apache-2.0。项目没有自行将这种不一致解释为某一种确定许可。

因此本仓库没有将该包作为依赖，也没有复制其代码。记录检查结果是为了说明复用决策，不代表对该项目其他版本或后续维护状态作结论。

同时检查了 MoonBit core 的 [`async/socket` 地址辅助代码](https://github.com/moonbitlang/core/blob/main/async/socket/addr_utils.mbt)。其纯解析函数并非公开 API，公开 `Addr` 接口包含套接字宿主约束，未作为本项目的地址集合底层。本仓库没有提取或复制这些辅助函数。

## 开发期参考实现和独立验证

[`scripts/differential.py`](../scripts/differential.py) 使用 [Python 标准库 `ipaddress`](https://docs.python.org/3/library/ipaddress.html) 作为开发期参考，调用解析、`collapse_addresses`、`address_exclude` 和 `summarize_address_range`。它还用有限小空间内的显式 Python 集合单独核对集合运算。

[`scripts/exhaustive_cidr.py`](../scripts/exhaustive_cidr.py) 的核心 Oracle 为递归二叉前缀树，按整块叶子是否都属于集合决定是否输出前缀。默认穷举各地址族一个 16 地址对齐空间的全部子集。它不使用生产代码的贪心分解过程；`--self-check` 模式才额外调用 Python `collapse_addresses` 核对 Oracle 本身。

Python 未作为项目运行时依赖，也未把 Python `ipaddress` 实现源码移植为 MoonBit。验证脚本调用的 Python 库保留 Python 自身许可。有限测试通过只支持被检查的输入、目标和版本，不能等同于全输入形式证明。

## 依赖和许可证边界

| 部分 | 作用 | 许可关系 |
| --- | --- | --- |
| 本仓库独立实现的 MoonBit、Python、脚本和文档 | 项目代码与开发工具 | MIT，见仓库 LICENSE。 |
| [MoonBit core](https://github.com/moonbitlang/core/blob/main/LICENSE) | 编译时内建／标准库，以及 CLI JSON 支持 | Apache-2.0，保留其自身许可；不因本仓库 MIT 而重新授权。 |
| Node.js | 执行 JS CLI、通过内建 fs 读取 stdin | 宿主运行时，遵守其自身及捆绑组件许可。 |
| Python 标准库 | 独立验证及文档预期值核对 | 开发期工具，遵守 Python 自身许可。 |

“零第三方包依赖”指库不下载外部 Mooncakes 包，并不表示标准库、编译工具链或宿主运行时没有各自的许可证。分发工具链或运行时副本时，应同时保留它们要求的许可文件；本仓库不捆绑这些运行时。
