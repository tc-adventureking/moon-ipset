# 使用场景与预期结果

本文是技术使用说明。下列结果依据行为规范计算，并使用 Python 标准库 `ipaddress` 独立核对；它们不是 MoonBit 程序的实际运行记录。程序验证应执行仓库测试与 CLI，并保存命令输出。

首先在仓库根目录构建 JSONL CLI：

```bash
moon build --deny-warn --release --target js
```

将各节请求放入文本文件，每行一个 JSON 对象，再执行：

```bash
node _build/js/release/build/tc-adventureking/ipset/cmd/ipset/ipset.js < requests.jsonl
```

CLI 在 stdin 关闭后处理全部请求。响应中的 JSON 键顺序可以不同；CIDR 数组顺序有定义。所有地址均为示例输入，不会触发网络连接或修改系统规则。

## 1. 合并重复、相邻和被包含的网段

场景：几份网段清单拼接后出现重复覆盖，需要得到相同地址集合的最小 CIDR 表示。此操作只保留地址成员关系，不能用于保留有先后顺序的防火墙规则语义。

输入包含两个可以合并的 IPv4 `/25`、一个冗余 `/26`，以及覆盖相同 IPv6 范围的多个条目。IPv6 第一项带有主机位，按默认模式先归一化。

```json
{"op":"normalize","cidrs":["192.0.2.0/25","192.0.2.128/25","192.0.2.64/26","2001:db8::1/127","2001:db8::2/127","2001:db8::/126"]}
```

预期：

```json
{"ok":true,"cidrs":["192.0.2.0/24","2001:db8::/126"]}
```

IPv4 部分覆盖 `.0` 至 `.255`；IPv6 部分覆盖 `::` 至 `::3`。结果不增加任何原集合之外的地址。库 API 对应 `IpSet::from_cidrs(...).cidrs()`。

Python 独立核对方式：

```python
from ipaddress import ip_network, collapse_addresses

values = [
    "192.0.2.0/25", "192.0.2.128/25", "192.0.2.64/26",
    "2001:db8::1/127", "2001:db8::2/127", "2001:db8::/126",
]
networks = [ip_network(value, strict=False) for value in values]
result = [
    str(net)
    for family in (4, 6)
    for net in collapse_addresses(net for net in networks if net.version == family)
]
print(result)
```

## 2. 从白名单中精确减去排除范围

场景：已分配范围为 IPv4 `192.0.2.0/24` 和 IPv6 `2001:db8::/125`。其中 IPv4 的 `.64` 至 `.127`、IPv6 的 `::2` 至 `::3` 需要排除。

```json
{"op":"difference","left":["192.0.2.0/24","2001:db8::/125"],"right":["192.0.2.64/26","2001:db8::2/127"]}
```

预期：

```json
{"ok":true,"cidrs":["192.0.2.0/26","192.0.2.128/25","2001:db8::/127","2001:db8::4/126"]}
```

`difference` 是左集合减右集合，交换两个操作数会得到不同结果。结果保留 IPv4 `.0` 至 `.63`、`.128` 至 `.255`，以及 IPv6 `::`、`::1`、`::4` 至 `::7`。

可以对输出再次检查成员关系：

```json
{"op":"contains","cidrs":["192.0.2.0/26","192.0.2.128/25","2001:db8::/127","2001:db8::4/126"],"address":"192.0.2.80"}
{"op":"contains","cidrs":["192.0.2.0/26","192.0.2.128/25","2001:db8::/127","2001:db8::4/126"],"address":"2001:db8::6"}
```

两条预期响应：

```json
{"ok":true,"value":false}
{"ok":true,"value":true}
```

Python 独立核对方式：

```python
from ipaddress import ip_network, collapse_addresses

pairs = [
    ("192.0.2.0/24", "192.0.2.64/26"),
    ("2001:db8::/125", "2001:db8::2/127"),
]
for whole, excluded in pairs:
    parts = ip_network(whole).address_exclude(ip_network(excluded))
    print([str(net) for net in collapse_addresses(parts)])
```

库 API 对应 `allowed.difference(excluded)`。`union`、`intersection` 和 `symmetric_difference` 接受相同的两集合参数；分别表示任一集合中的地址、两个集合共有地址、恰好存在于其中一个集合的地址。

## 3. 将任意闭合范围转换为精确 CIDR

场景：外部数据给出起止 IP，而接收系统只接受 CIDR。需要输出精确覆盖，避免把范围之外的地址一起放行。

```json
{"op":"range","start":"192.0.2.5","end":"192.0.2.20"}
```

预期：

```json
{"ok":true,"cidrs":["192.0.2.5/32","192.0.2.6/31","192.0.2.8/29","192.0.2.16/30","192.0.2.20/32"]}
```

范围包含两个端点。输出覆盖 `.5` 至 `.20`，不覆盖 `.4` 或 `.21`。它不能直接放大成一个 `/27`，因为那会改变集合。

IPv6 最大地址附近也使用同一操作：

```json
{"op":"range","start":"ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffa","end":"ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"}
```

预期：

```json
{"ok":true,"cidrs":["ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffa/127","ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffc/126"]}
```

Python 独立核对方式：

```python
from ipaddress import ip_address, summarize_address_range

for first, last in [
    ("192.0.2.5", "192.0.2.20"),
    ("ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffa",
     "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"),
]:
    print([str(net) for net in summarize_address_range(ip_address(first), ip_address(last))])
```

库 API 对应 `Interval::new(first, last)` 与 `IpSet::from_ranges([interval]).cidrs()`。起止地址必须属于相同地址族，且起点不能大于终点。

## 解析策略与错误处理

以下两个请求分别使用默认归一化和严格模式：

```json
{"op":"network","cidr":"192.0.2.7/24"}
{"op":"network","cidr":"192.0.2.7/24","strict":true}
```

第一条预期返回 `{"ok":true,"cidr":"192.0.2.0/24"}`。第二条预期返回 `ok:false` 和非空 `error` 字符串；错误消息具体文本不作为接口契约。

IPv4-mapped IPv6 不会自动与 IPv4 合并：

```json
{"op":"parse","address":"::ffff:192.0.2.1"}
{"op":"contains","cidrs":["192.0.2.0/24"],"address":"::ffff:192.0.2.1"}
```

预期：

```json
{"ok":true,"address":"::ffff:c000:201","family":6}
{"ok":true,"value":false}
```

空集合有效；列表中任意无效条目都会拒绝整条请求，不返回部分结果。非法 JSON、未知操作、缺失字段和字段类型错误同样返回错误响应，后续有效行继续执行。地址总量可能达到 `2^128`，因此本 API 不以机器整数暴露全空间计数。
