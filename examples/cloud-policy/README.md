# AWS EC2 双栈网段清单

从固定真实快照提取所有 EC2 网段，归并后排除 us-east-1 记录覆盖的地址，再做 512 次边界和邻近成员查询。它计算数值集合，不把 AWS region 标签解释成设备实际位置，也不直接配置网络访问规则。

在仓库根目录运行：

```bash
node scripts/check-cloud-snapshot.mjs
moon -C examples/cloud-policy run cmd --target wasm-gc
moon -C examples/cloud-policy test --target all --deny-warn
```

默认打印紧凑 JSON 汇总；追加 `-- --full` 打印所有规范 CIDR 和成员判断，可交给其他程序比较。源代码使用核心库的 `IpSet::from_cidrs`、`difference`、`cidrs` 和 `contains`，地址数按族使用 BigInt 累计；没有 Python 运行时依赖。

## 数据和独立期望

- 原始来源：[AWS 官方 IP ranges JSON](https://ip-ranges.amazonaws.com/ip-ranges.json)。固定文件 `aws-ip-ranges.json` 的 `createDate` 为 `2026-11-17-05-47-05`，不是随每次运行自动更新的在线数据。
- `snapshot.json` 记录原始文件 SHA-256、同步标识、提取规则、全部派生文件哈希、查询选择及参考版本。
- A：`prefixes` 与 `ipv6_prefixes` 中 `service == EC2` 的全部 4,490 条记录。
- B：A 中 `region == us-east-1` 的 572 条记录。计算 A−B；重叠按数值集合处理，不根据标签假定网段互斥。
- 期望由 netaddr 1.3.0 的 `IPSet(A) - IPSet(B)`、`iter_cidrs()`、`IPAddress(q) in result` 和分族 CIDR 数量之和独立生成，保存在 `expected_wbtest.mbt`；不是从本库运行结果录制。
- `check-cloud-snapshot.mjs` 从保留的原始快照重新提取 A/B，核对派生源码字符串和所有哈希。MoonBit 测试逐项比较完整结果，并验证排除后不重叠及集合守恒。

| 结果 | 固定快照上的值 |
| --- | ---: |
| 原始 EC2 记录 | 4,490 |
| 归并后的 CIDR | 2,668 |
| 排除集合归并后的 CIDR | 449 |
| 最终 CIDR | 2,595 |
| 最终 IPv4 地址数 | 58,698,653 |
| 最终 IPv6 地址数 | 1,317,034,699,669,070,404,305,547,165,696 |
| 成员查询 / 命中 | 512 / 249 |

原始记录减少约 40.6% 的表示条目。这只是去重与归并效果，不代表同样比例的内存或运行时间节省；其他成熟集合库也能得到同样结果。

## 运行成本

native 的可复跑基准：

```bash
moon -C examples/cloud-policy run bench --target native --release
```

每次求值包含字符串拆分、地址解析、集合构造、排除、CIDR 文本生成、精确计数和 512 次查询；输入快照已编译进示例，计时不包含下载、编译或最终 JSON 序列化。基准使用现有 MoonBit `Bench`，保留结果避免计算被消除。具体本机测量见 [运行记录](MEASUREMENTS.md)。

这是一份快照上的真实规模样例，不是两个日期的变更回放、外部采用证明或全库性能结论。AWS 数据范围也有自身限制，见 [官方说明](https://docs.aws.amazon.com/vpc/latest/userguide/aws-ip-ranges.html)。快照和期望只随明确更新一起更换；出现未解释不一致时，检查应失败，不能修改期望迁就被测结果。
