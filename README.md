# moon-ipset

纯 MoonBit 通用 IPv4/IPv6 地址、网络、接口与集合库。以 CPython 3.13.2 `ipaddress` 为行为参考，支持 wasm、wasm-gc、JavaScript 和 native；核心只依赖 MoonBit 标准库。

## 功能

- **地址 `IpAddress`**：文本、字节、大整数转换，压缩/展开格式、PTR、scope ID、地址属性、mapped IPv6、6to4、Teredo、比较与受检算术。
- **网络 `IpNetwork`**：CIDR、IPv4 掩码/反掩码、严格校验、子网/超网、主机遍历、包含与重叠、排除、范围汇总和网段归并。
- **接口 `IpInterface`**：同时保留主机地址与网络前缀，提供地址、网络、掩码和转换方法。这里的接口是配置值，不是操作系统网卡。
- **集合 `IpSet`**：并、交、差、对称差、成员与子集判断，以及最小 CIDR 覆盖；旧版 `Address`、`Cidr` 和 CLI 保持兼容。

地址数量使用 `BigInt`，包括 IPv6 `/0` 的 `2^128` 个地址；`hosts()`、`iter()` 和 `subnets()` 惰性生成，使用 `take(n)` 可限制输出。

## 安装与使用

```bash
moon add tc-adventureking/ipset@0.3.0
```

在 `moon.pkg` 中导入：

```moonbit
import { "tc-adventureking/ipset" @ip, }
```

```moonbit
test "interface and subnet" {
  let iface = @ip.ip_interface("192.168.10.7/24")
  assert_eq(iface.ip().to_string(), "192.168.10.7")
  assert_eq(iface.network().to_string(), "192.168.10.0/24")
  let first = iface.network().subnets(new_prefix=26).next().unwrap()
  assert_eq(first.hosts().next().unwrap().to_string(), "192.168.10.1")
  assert_false(@ip.ip_address("100.64.0.1").is_global())
}
```

`ip_network` 默认严格拒绝非零主机位；需要归一化时传 `strict=false`。接口加减会返回 `/32` 或 `/128` 的新接口。地址属性依据固定参考版本，`is_private` 不只表示 RFC1918 私有地址。

[完整 API](pkg.generated.mbti) · [Python 对照与差异](docs/COMPATIBILITY.md) · [使用场景](docs/USAGE.md)

## 示例与测试

安装 MoonBit 工具链后在仓库运行：

```bash
moon -C examples/consumer run . --target wasm-gc
moon test --deny-warn --target all
```

独立消费示例涵盖地址清单校验、子网规划、双栈接口配置和集合排除。完整公开检查运行 `bash scripts/verify.sh`，需要 Node.js 24 LTS 和 C 工具链，无需 Python。[验证范围](docs/TESTING.md)。

## 网段文件 CLI

每行一个 IP/CIDR，支持空行、`#` 注释和标准输入 `-`：

```bash
node bin/ipset.mjs normalize examples/policies/new.txt
node bin/ipset.mjs diff examples/policies/old.txt examples/policies/new.txt --json
```

退出码：`0` 成功或无变化，`1` diff 有变化，`2` 输入或运行错误。该 CLI 比较地址集合，不解释防火墙规则顺序。[文件与 JSONL 协议](docs/SPEC.md)。

## 许可

项目代码使用 [MIT](LICENSE)；CPython 参考部分保留 [Python 许可](third_party/python/LICENSE)，MoonBit 标准库保留其自身许可。来源与修改说明见 [PROVENANCE](docs/PROVENANCE.md)。
