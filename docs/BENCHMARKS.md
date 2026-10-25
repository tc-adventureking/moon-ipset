# 性能基准

这是单机合成输入的 native release 测量，不代表生产负载，也没有与其他库比较。完整的 60 项通用操作及 24 项子集判断数据、波动统计、环境和源码 SHA-256 分别见 [native.json](../bench/results/native.json) 与 [subset-native.json](../bench/results/subset-native.json)。

在仓库根目录运行（需要 MoonBit、native C 编译器和 Python 3）：

```sh
python3 scripts/benchmark.py --output bench/results/native.json
python3 scripts/benchmark.py --subset --output bench/results/subset-native.json
python3 scripts/benchmark.py --smoke --output _build/benchmark-smoke.json
python3 scripts/benchmark.py --subset --smoke --output _build/subset-smoke.json
```

可用 `--target-dir PATH` 隔离构建目录。CI smoke 分别有 5 和 8 项，只校验执行、结果结构、区间数量及子集预期布尔值，不设耗时阈值。

固定种子为 `0x5eed2026`，每个操作数输入 100、1,000、10,000 条 CIDR，并确定性打乱顺序。四类输入分别为重叠重复（overlap）、离散 IPv4 单点（discrete）、被删除块切开的 IPv4 区间（fragmented）、IPv4/IPv6 各半的同类切分（mixed）。输入生成和文件读写均在计时外。

`parse_normalize` 从内存字符串开始，包含解析、排序和归并；union/difference 使用已构造的不可变集合；CIDR 输出只调用预先算好差集的 `cidrs()`，不含字符串序列化。contains 每次计时执行一批 1,024 个预解析查询。复用标准库 `Bench` 校准批次、采样 5 次并保留结果，避免结果被优化掉。

2026-10-26（UTC+8）实测：i9-14900HX、Ubuntu 26.04 / WSL2、moonc v0.10.17+d971670cd、Clang 22.1.8，native release。下表为中位数，单位均为 **微秒/次**；contains 一次指完整查询批次。

| 输入 | 每侧原始条数 | 每侧归并区间数 | 差集区间 / CIDR 数 | 解析归并 | union | difference | CIDR 输出 | contains 批次 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mixed | 100 | 100 | 200 / 200 | 57.76 | 2.76 | 10.66 | 11.27 | 20.44 |
| mixed | 1,000 | 1,000 | 2,000 / 2,000 | 619.63 | 26.18 | 118.08 | 110.84 | 68.48 |
| overlap | 10,000 | 16 | 16 / 16 | 4,096.46 | 0.44 | 0.90 | 1.09 | 12.20 |
| discrete | 10,000 | 10,000 | 10,000 / 10,000 | 4,727.04 | 419.17 | 501.61 | 762.92 | 114.74 |
| fragmented | 10,000 | 10,000 | 20,000 / 20,000 | 4,557.08 | 312.88 | 1,269.52 | 1,341.84 | 117.30 |
| mixed | 10,000 | 10,000 | 20,000 / 20,000 | 6,780.84 | 309.54 | 1,301.85 | 1,255.13 | 111.49 |

重叠输入归并后只有 16 个区间，其集合操作耗时不能按 10,000 个独立区间理解。机器调度、编译器和数据分布会影响结果，应在目标环境重新测量。

子集案例使用 100、1,000、10,000 个 IPv4/IPv6 各半的离散单点，右侧以稍大的 `/31`、`/127` 块覆盖。按规范排序分别移除首区间、末区间，或保留全部、全部移除；预构造集合和结果断言均在计时外。基线是在同一版生产 API 上执行原公式 `difference(...).is_empty()`。

10,000 个左侧区间的中位数，单位 **微秒/次**：

| 情形 | 右侧区间数 | 预期结果 | `is_subset_of` | 原公式 |
|---|---:|---|---:|---:|
| 空右集 | 0 | false | 0.008 | 339.56 |
| 首区间缺失 | 9,999 | false | 0.013 | 186.99 |
| 末区间缺失 | 9,999 | false | 161.42 | 184.77 |
| 完整覆盖 | 10,000 | true | 155.38 | 189.99 |

早停值由 native 批量计时摊分得出，包含闭包和 `Bench.keep` 固定开销，不能据此推导精确加速倍数。末区间缺失与完整覆盖展示必须扫描全部区间的情况；两套数据在同一源码指纹下重新测量。
