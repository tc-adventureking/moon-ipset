# moon-ipset

纯 MoonBit IPv4／IPv6 地址集合库，用于整理网段规则、从白名单中减去排除网段，以及把闭合地址范围精确转换为最小 CIDR 覆盖。

库模块名为 `tc-adventureking/ipset`。计算核心使用无符号整数和规范化区间，不逐个枚举网段内的地址；支持 IPv6 `/0` 等大范围。库没有第三方包依赖。JSON Lines 命令行适配器使用 MoonBit 标准库和 Node.js，Python 仅用于开发期验证。

行为细节见 [SPEC.md](docs/SPEC.md)，完整场景见 [USAGE.md](docs/USAGE.md)，实测结果与版本见 [TESTING.md](docs/TESTING.md)。

## 能力与语义

- IPv4、IPv6 地址解析和规范文本输出，CIDR 解析与主机位归一化。
- 集合并集、交集、差集、对称差、成员判断、子集判断和相交判断。
- 同族闭合地址范围，去重、重叠合并、相邻区间合并和最小 CIDR 输出。
- IPv4 与 IPv6 分开处理；IPv4-mapped IPv6 地址仍属于 IPv6。
- 混合集合按 IPv4 优先、网络地址递增顺序输出。
- 地址和集合的内部表示不能被外部调用者直接修改。

文本输入拒绝空白、zone ID、方括号、IPv4 前导零和 CIDR 前缀前导零。CIDR 默认清除主机位，`strict=true` 时拒绝带主机位的输入。IPv6 输出采用小写十六进制并压缩首个最长零段；mapped 地址也输出纯十六进制，例如 `::ffff:192.0.2.1` 输出为 `::ffff:c000:201`。这一选择与 RFC 5952 第 5 节针对特定嵌入地址的混合写法建议存在有意区别，详见 [来源与许可说明](docs/PROVENANCE.md)。

本库处理地址集合语义，不执行防火墙规则，不保留规则优先级或 allow/deny 顺序，不进行 DNS 查询，也不提供全地址空间计数接口。

## 环境与构建

- [MoonBit 工具链](https://www.moonbitlang.com/download/)；开发基线为 `0.10.17`，完整构建号见验证记录。
- JSONL CLI：Node.js `22.3.0` 或更新版本。CLI 使用 `process.getBuiltinModule` 读取标准输入。
- 独立验证脚本：Python `3.10+`，无需安装 Python 第三方包。
- `native` 目标还需要 C 编译器和开发头文件，例如完整 GCC／Clang 工具链。也可通过 `MOON_CC` 指定兼容的编译器驱动；本地验证使用 Zig cc。
- 以下命令在 Linux／WSL 的仓库根目录运行。

```bash
git clone https://github.com/tc-adventureking/moon-ipset.git
cd moon-ipset
moon version --all
moon check --deny-warn --target all
moon build --deny-warn --release --target js
```

CLI 构建产物为 `_build/js/release/build/tc-adventureking/ipset/cmd/ipset/ipset.js`。库本身与 Node.js 无关；CLI 的宿主适配器只面向 JS 目标。不同目标是否已经验证，必须以相应测试记录为准。

## 以本地 workspace 使用

仓库自带一个独立消费模块，使用根目录 `moon.work` 解析本地库：

```toml
members = [".", "examples/consumer"]
```

`examples/consumer/moon.mod` 声明对当前库版本的依赖：

```toml
name = "ipset-examples/consumer"
version = "0.1.0"
preferred_target = "wasm-gc"
import {
  "tc-adventureking/ipset@0.1.0",
}
```

消费模块的 `moon.pkg` 引入公共 API：

```moonbit
import {
  "tc-adventureking/ipset" @net,
}
pkgtype(kind: "executable")
```

```bash
moon -C examples/consumer run . --target wasm-gc
moon -C examples/consumer test --target wasm-gc
```

在自己的 workspace 中使用时，将库目录和应用目录都列入共同的 `moon.work`，并采用上面的模块依赖与包导入方式。本仓库不以 Mooncakes 已发布为前提；不要将本地 workspace 示例理解为 `moon add` 已经可以下载该版本。

## 公共 API 示例

下面的代码放在已经导入 `@net` 的消费包中：

```moonbit
fn main {
  try {
    let allowed = @net.IpSet::from_cidrs([
      "192.0.2.0/24",
      "2001:db8::/126",
    ])
    let excluded = @net.IpSet::from_cidrs([
      "192.0.2.64/26",
      "2001:db8::2/127",
    ])
    let effective = allowed.difference(excluded)
    for cidr in effective.cidrs() {
      println(cidr.to_string())
    }
    let host = @net.Address::parse("192.0.2.10")
    println(effective.contains(host))
  } catch {
    error => println(error.to_string())
  }
}
```

按规范预期输出如下；这里只展示预期值，不将其作为程序实际运行证据：

```text
192.0.2.0/26
192.0.2.128/25
2001:db8::/127
true
```

常用入口：

| 类型 | API |
| --- | --- |
| `Address` | `parse`、`family`、`to_string`、`width`、`next`、`previous` |
| `Cidr` | `parse`、`new`、`network`、`last`、`prefix`、`to_string` |
| `Interval` | `new`、`first`、`last` |
| `IpSet` | `empty`、`from_cidrs`、`from_ranges`、`intervals`、`cidrs` |
| `IpSet` 运算 | `union`、`intersection`、`difference`、`symmetric_difference`、`contains`、`is_subset_of`、`overlaps`、`is_empty` |

解析和无效范围通过 `IpError` 报错。最大地址的 `next()`、零地址的 `previous()` 返回 `None`，不会环绕到另一端。

## JSON Lines CLI

```bash
moon build --deny-warn --release --target js
node _build/js/release/build/tc-adventureking/ipset/cmd/ipset/ipset.js < examples/requests.jsonl
```

也可以传入单个请求：

```bash
printf '%s\n' '{"op":"difference","left":["10.0.0.0/24"],"right":["10.0.0.0/25"]}' \
  | node _build/js/release/build/tc-adventureking/ipset/cmd/ipset/ipset.js
```

预期 JSON 语义：

```json
{"ok":true,"cidrs":["10.0.0.128/25"]}
```

支持 `parse`、`network`、`normalize`、`union`、`intersection`、`difference`、`symmetric_difference`、`range`、`contains`。每个非空输入行对应一个 JSON 响应；错误包含 `ok:false` 和非空 `error` 字符串，后续请求继续处理。JSON 键顺序和错误消息文本不属于稳定接口，字段类型与结果含义属于稳定接口。

当前适配器先读取 stdin 到 EOF，再逐行处理；它适合文件重定向和批处理，不是等待每行即时应答的交互式服务。完整请求字段见 [协议表](docs/SPEC.md#json-lines-protocol)。

## 可复现验证

仓库提供统一入口，它记录工具版本，检查格式、编译、测试、独立消费模块及两套 Python 验证器：

```bash
bash scripts/verify.sh
```

也可以分别运行：

```bash
moon fmt --check
moon check --deny-warn --target all
moon test --deny-warn --target all
moon run cmd/demo --target wasm-gc
moon -C examples/consumer run . --target wasm-gc
moon build --deny-warn --release --target js
python3 scripts/differential.py \
  --command 'node _build/js/release/build/tc-adventureking/ipset/cmd/ipset/ipset.js' \
  --report work/verification/differential.json
python3 scripts/exhaustive_cidr.py \
  --command 'node _build/js/release/build/tc-adventureking/ipset/cmd/ipset/ipset.js' \
  --report work/verification/exhaustive-cidr.json
```

`differential.py` 使用 Python `ipaddress` 和小空间点集作为独立参考，随机种子固定。`exhaustive_cidr.py` 默认在每个地址族的 16 地址对齐空间内枚举全部子集，合计 131,072 次请求，用递归二叉前缀树验证最小 CIDR 分解。这个穷举范围是有限空间，不是对全部 IPv4／IPv6 输入的形式证明。

## 许可与实现来源

本仓库独立实现代码使用 [MIT](LICENSE)。MoonBit 标准库、Node.js 和 Python 保留各自许可。已有实现检查、标准参考与开发期 Oracle 记录见 [PROVENANCE.md](docs/PROVENANCE.md)，两轮真实 Claude 审查及采纳结果见 [AI_COLLABORATION.md](docs/AI_COLLABORATION.md)。
