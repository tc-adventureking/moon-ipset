# 实现来源与许可

## 项目与参考实现

本项目原有的 `Address`、`Cidr`、`Interval`、`IpSet` 数值内核、集合区间算法与最小 CIDR 分解独立实现，项目原创部分采用 [MIT](../LICENSE)。这些算法是已有方法，不主张算法首创。

新增的 `IpAddress`、`IpNetwork`、`IpInterface` 与相关工具函数对照 [CPython v3.13.2 `ipaddress.py`](https://github.com/python/cpython/blob/v3.13.2/Lib/ipaddress.py) 的实现、分类前缀和公开语义，在 MoonBit 中重新组织和实现。来源文件注明 `Copyright 2007 Google Inc.`、`Licensed to PSF under a Contributor Agreement.`，其许可全文保留在 [third_party/python/LICENSE](../third_party/python/LICENSE)。项目 MIT 声明不替代这部分保留的上游许可条款。

相对参考实现的主要修改：以显式 MoonBit 类型和方法替代动态参数与继承，复用既有区间内核，使用标准库 `BigInt` 和惰性 `Iter`，保留旧 API，并对 scope 格式化与数值范围、对象排序、接口 PTR、mapped 接口及合并采用明确的行为调整。具体版本、功能映射与差异见 [COMPATIBILITY.md](COMPATIBILITY.md)。Python 对照工具用于本地开发验证，不随本仓库发布，也不是运行时依赖。

项目使用 AI 辅助开发，Codex 承担实现与验证，Claude 参与技术审查。

## 标准与已有库

地址文本和前缀语义参考 [RFC 4291](https://www.rfc-editor.org/rfc/rfc4291.html)、[RFC 5952](https://www.rfc-editor.org/rfc/rfc5952.html)、[RFC 4632](https://www.rfc-editor.org/rfc/rfc4632.html)；特殊地址分类固定到上述 Python 版本采用的注册表数据，不宣称持续同步当前 IANA 状态。

开发时检查了 [`moonbit-community/ipaddr` 的公开 API](https://github.com/moonbit-community/ipaddr/blob/e75b311282f89c24c2184e1f0ed8b61aa275b6d6/pkg.generated.mbti)（`bobzhang/ipaddr@0.1.2`）。该版本主要提供 IPv4、IPv4Prefix 和 MAC，未满足本项目双栈网络、接口及集合需求；本库没有依赖或复制该项目代码，也不据此断言整个 MoonBit 生态不存在替代方案。

## 依赖边界

| 部分 | 用途与许可 |
| --- | --- |
| 项目原创代码、示例和文档 | [MIT](../LICENSE) |
| Python 参考的兼容逻辑与分类数据 | 保留 [Python / PSF 许可全文](../third_party/python/LICENSE)及上述来源、修改说明 |
| [MoonBit core](https://github.com/moonbitlang/core/blob/main/LICENSE) | 内建、BigInt、JSON 等标准库，保留 Apache-2.0 许可；编译产物分发时保留所需 LICENSE / NOTICE |
| Node.js | JS CLI 的宿主运行时，遵守其自身及捆绑组件许可；库本身不依赖 Node |

本库没有额外 Mooncakes 包依赖；这不表示标准库、编译工具链和宿主运行时没有各自的许可证。仓库不捆绑 Node.js、Python 或 MoonBit 编译器。
