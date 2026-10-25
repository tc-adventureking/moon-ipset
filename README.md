# moon-ipset

纯 MoonBit IPv4／IPv6 地址集合库，用于合并网段、从白名单中排除指定范围，以及生成精确的最小 CIDR 覆盖。计算核心无第三方包依赖，不逐个枚举 IP 地址。

## 功能

- IPv4／IPv6 解析、格式化和 CIDR 归一化。
- 集合并集、交集、差集、对称差。
- 成员、子集和相交判断。
- 闭合地址范围转换、重复与相邻网段合并、最小 CIDR 输出。

IPv4 与 IPv6 分开处理；CIDR 默认清除主机位，也支持严格校验。

## 快速开始

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)（开发基线 `0.10.17`），在 Linux／WSL 运行：

```bash
git clone https://github.com/tc-adventureking/moon-ipset.git
cd moon-ipset
moon run cmd/demo --target wasm-gc
```

演示会从双栈白名单中减去排除范围，并检查地址是否仍在集合中。

## 作为库使用

模块名为 `tc-adventureking/ipset`。当前通过 Git 克隆和本地 workspace 引用；仓库自带可运行的独立消费示例：

```bash
moon -C examples/consumer run . --target wasm-gc
```

在自己的项目中，将库目录和应用目录加入同一个 `moon.work`，再声明模块依赖与包导入。可直接参考：

- [workspace 配置](moon.work)
- [模块依赖](examples/consumer/moon.mod)与[包导入](examples/consumer/moon.pkg)
- [完整调用示例](examples/consumer/main.mbt)与[公共 API](pkg.generated.mbti)

## 网段文件 CLI

需要 Node.js `22.3.0+`。文件每行一个 IP 或 CIDR，支持空行、`#` 注释与标准输入 `-`。仓库入口会自动调用 MoonBit 构建。

```bash
node bin/ipset.mjs normalize examples/policies/new.txt
node bin/ipset.mjs diff examples/policies/old.txt examples/policies/new.txt --json
```

diff 输出新增与移除的网段：

```json
{"added":["10.0.1.10/32","2001:db8:1::/126"],"removed":["10.0.0.128/25","2001:db8::/127"]}
```

退出码：`0` 成功／无变化，`1` diff 有变化，`2` 输入或运行错误。`--strict` 拒绝有主机位的 CIDR；`--help` 查看用法。比较的是地址集合，不解释防火墙规则顺序。

原 JSONL 入口仍可用：`node bin/ipset.mjs jsonl < examples/requests.jsonl`。协议与文件格式见 [SPEC.md](docs/SPEC.md)，完整场景见 [USAGE.md](docs/USAGE.md)。

[Releases](https://github.com/tc-adventureking/moon-ipset/releases) 提供便携 CLI ZIP；完整解压后用 `node ipset.mjs --help` 运行，只需 Node.js。也可运行 `python3 scripts/package_release.py` 自行构建并验证安装包。

## 测试

运行库测试：

```bash
moon test --deny-warn --target wasm-gc
```

完整验证还需要 Node.js、Python `3.10+` 和 C 工具链：

```bash
bash scripts/verify.sh
```

验证范围与版本见 [TESTING.md](docs/TESTING.md)。

## 性能

固定输入的 native release [基准数据与复现命令](docs/BENCHMARKS.md)，覆盖 100 至 10,000 条网段及多种分布。

## 许可

[MIT](LICENSE)
