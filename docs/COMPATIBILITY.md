# Python ipaddress 对照与行为边界

参考基线为 [CPython v3.13.2 的 `Lib/ipaddress.py`](https://github.com/python/cpython/blob/v3.13.2/Lib/ipaddress.py)，文件 SHA-256：`fd268e3a43df6f428868b3c4c865f510380b49058a796bcc30763788e0a74686`。这里对照地址、网络和接口的值语义；MoonBit 使用显式类型和方法，不复刻 Python 的继承关系、动态构造参数、异常类、pickle 或格式化协议。

## 能力映射

| Python 能力 | MoonBit API |
| --- | --- |
| `ip_address` / `IPv4Address` / `IPv6Address` | `ip_address` / `ipv4_address` / `ipv6_address`，返回 `IpAddress` |
| `ip_network` / `IPv4Network` / `IPv6Network` | `ip_network` / `ipv4_network` / `ipv6_network`，返回 `IpNetwork` |
| `ip_interface` / `IPv4Interface` / `IPv6Interface` | `ip_interface` / `ipv4_interface` / `ipv6_interface`，返回 `IpInterface` |
| 整数、字节构造及转换 | `from_bigint` / `from_bytes` / `to_bigint` / `to_bytes`；`v4_int_to_packed` / `v6_int_to_packed` |
| `compressed` / `exploded` / `reverse_pointer` / `__format__` | 同名方法与 `format`；支持 `s/b/x/X/n`，`s` 的宽度、填充、对齐与精度，以及数值格式的 `#`、`_` |
| 地址属性及过渡地址 | `is_private/global/reserved/multicast/unspecified/loopback/link_local/site_local`；`scope_id`、`ipv4_mapped`、`ipv6_mapped`、`sixtofour`、`teredo` |
| 网络地址、掩码、计数与索引 | `network_address`、`broadcast_address`、`netmask`、`hostmask`、`prefixlen`、`num_addresses`、`nth` |
| 主机遍历与子网管理 | `iter`、`hosts`、`subnets`、`supernet`、`address_exclude` |
| 网络关系与数值比较 | `contains`、`overlaps`、`subnet_of`、`supernet_of`、`compare_networks` |
| 地址与掩码元组构造 | `IpNetwork::from_address_mask(IpAddress, String, strict~)`；整数前缀使用 `from_address` |
| 接口主机与所属网络 | `address`、`ip`、`network`、`with_prefixlen/netmask/hostmask`；转换、属性及算术方法 |
| `summarize_address_range` / `collapse_addresses` | `summarize_address_range`、`collapse_addresses`；混合地址、接口与网络使用 `collapse_ip_inputs(Array[IpInput])` |
| `get_mixed_type_key` / 相等、排序与字典键 | `get_mixed_type_key`；`Eq`、`Compare`、`Hash`，可作为 `Map` 键 |

完整签名见 [公共 API](../pkg.generated.mbti)。字符串格式支持 `[[fill]align][0][width][.precision]s`，填充符为单个 Unicode 字符，对齐为 `<`、`>`、`^`；宽度和精度为不超过 `2147483647` 的 ASCII 十进制数。`IpInterface` 表示“主机地址 + 前缀”，不枚举或修改操作系统网卡；PTR 方法仅生成名称，不发起 DNS 查询。

## 使用约定

- 新 `IpNetwork` 默认 `strict=true`，拒绝非零主机位；旧 `Cidr` 默认仍为 `false`。旧 `Address` 不接受 scope，保留纯十六进制 mapped IPv6 输出；新 `IpAddress` 支持 scope，并按参考版本输出 mapped IPv6 的混合表示。
- IPv4/IPv6 是不同地址族，不自动转换。`from_bigint` 默认将小于 `2^32` 的非负数识别为 IPv4，可显式传 `family`；字节长度必须为 4 或 16。IPv4 接受连续点分网络掩码或反掩码，IPv6 使用前缀长度；`from_address_mask(addr, "0.0.0.255")` 与 `from_address(addr, 24)` 等价，字符串也接受十进制前缀。
- 地址算术拒绝溢出并清除 scope。接口算术返回 `/32` 或 `/128` 的新接口。`num_addresses` 和索引使用 `BigInt`，可表达 IPv6 `/0` 的 `2^128` 个地址；`iter`、`hosts`、`subnets` 是惰性迭代器。不要对巨大地址空间调用 `to_array()` 或完整遍历。
- `hosts` 保留 IPv4 `/31`、`/32` 和 IPv6 `/127`、`/128` 的端点特例。`is_private` 使用固定基线的特殊地址表，范围比 RFC1918 广；CGNAT `100.64.0.0/10` 的 `is_private`、`is_global` 都为假，网络属性也不等于简单检查一个主机。
- 对齐的 scoped IPv6 网络保留 scope；宽松构造需要清除主机位时丢弃 scope。索引和一般子网运算返回数值地址。接口的 `address()` / `to_string()` 保留 scope，`ip()` 与 `with_*` 使用无 scope 主机表示。
- MoonBit 地址总序为“地址族、数值、scope”，IPv4 在 IPv6 前，无 scope 在有 scope 前，scope 按字符串排序。网络 `Compare` 严格按“地址族、数值、scope、前缀”排序，例如 `fe80::/64 < fe80::/128 < fe80::%a/64`；接口先比较网络再比较主机。这使 `compare==0` 与同类型相等一致；Python 拒绝跨族排序，对同数值不同 scope 也没有这一总序。
- `compare_networks` 只在同地址族内比较数值网络地址、前缀，返回 `-1/0/1`；跨族报错，scope 不参与。`get_mixed_type_key` 返回“版本、数值、主机标记或网络前缀”，也不含 scope，因此两者都可能与网络 `Compare` 顺序不同，相同数值键不意味着对象相等。接口按主机数值生成该键；Python 的接口对象参与混排时还可能先比较网络，因此不承诺接口混排顺序一致。
- `IpInput` 提供 `AddressInput`、`InterfaceInput` 和 `NetworkInput`。接口在 `collapse_ip_inputs` 中贡献一个主机地址，忽略接口前缀；要合并整个接口网段，传 `NetworkInput(iface.network())`。与旧集合核互操作使用 `as_address()`、`as_cidr()` 及对应 `from_*`，数值集合不携带 scope。非法值通过 `IpError` 的地址、前缀、范围或主机位变体报告，不承诺 Python 异常类型或消息一致。

## 明确的行为调整

以下行为经过单独核对，不计作与 Python 参考结果相同：

| 情况 | CPython v3.13.2 | 本库 |
| --- | --- | --- |
| scoped IPv6 地址 `exploded` | 抛出错误 | 展开数字部分并保留 `%scope` |
| scoped IPv6 地址 `reverse_pointer` | 抛出错误 | 忽略 scope，生成数字地址的合法 PTR 名 |
| scoped IPv6 网络 `exploded` | 抛出错误 | 保留展开地址、scope 和 `/prefix` |
| mapped IPv6 接口 `exploded` | 丢失 `/prefix` | 保留接口前缀，例如 `…:ffff:192.0.2.1/120` |
| 接口 `reverse_pointer` | 可能把 `/prefix` 带入 PTR | 只使用主机地址生成 PTR |
| IPv4 接口 `ipv6_mapped` | 将接口字符串中的 `/prefix` 当作地址解析而报错 | 返回对应的 mapped IPv6 主机地址，不携带前缀 |
| scoped 输入的 CIDR 合并 | 部分输入保留 scope，部分组合报错 | 按数值范围合并并统一去除 scope |
| 同数值、不同 scope 的网络包含 | `fe80::%a/64` 与 `fe80::/64` 的 `subnet_of` 双向为假 | `subnet_of` / `supernet_of` 按数值范围判断，双向为真 |
| scoped 网络排除 | `fe80::%a/64` 排除 `fe80::/65` 报错 | 返回数值补集 `fe80::8000:0:0:0/65`，去除 scope |
| 同数值、不同 scope 的范围端点 | `fe80::1%a` 到 `fe80::1` 报错 | `summarize_address_range` 返回 `fe80::1/128`；仍拒绝数值逆序或混族范围 |
| scoped 网络 `compare_networks` | 同数值、不同 scope 时可能双向都返回 `1` | 按数值网络地址、前缀比较；同数值同前缀返回 `0` |

这里忽略 scope 的操作仅计算地址数值范围，不判断不同网络接口上的实际可达性。此外，保留参考版本的 `IPv4Interface.is_unspecified=false` 行为；需要判断接口主机本身是否为未指定地址时，调用 `iface.ip().is_unspecified()`。此处的版本固定是为了结果可解释，不表示自动跟随 Python 或 IANA 的后续变化。
