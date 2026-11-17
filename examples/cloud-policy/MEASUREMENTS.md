# 固定快照的运行记录

测量日期：2026-11-17；Intel Core i9-14900HX、Ubuntu WSL 2（Linux 6.18.33.2、glibc 2.43），moon 0.1.20261104、moonc v0.10.20+65efd5b93，native release。参考结果使用 netaddr 1.3.0；本轮参考运行的 Python 为 3.14.4。这与地址语义测试固定的 CPython 3.13.2 是两个不同基线。

## 正确性

原始 AWS 快照 SHA-256 为 `74653f3d98e777d9e24e58064e28f3f9c5ad9e6ded775751e2c84004576e8a95`，提取规则及每个派生文件摘要见 `snapshot.json`。四后端运行相同场景，完整 JSON 与固定 netaddr 期望相同；native 可执行程序的 `--full` 输出也单独读取并逐字段比较。

## 进程内求值时间

| 实现及测量方式 | 中位数 | 范围 |
| --- | ---: | ---: |
| MoonBit native；Bench 7 次采样，每次 16 次求值后按单次归一化 | 6.267 ms | 6.219～7.259 ms |
| Python 3.14.4 + netaddr 1.3.0；预热后 7 次单次求值 | 70.820 ms | 68.617～75.814 ms |

两者处理相同的 4,490 个输入、572 个排除条目、512 个查询，均包括解析、归并、排除、输出 CIDR 文本和分族精确计数；不计加载固定输入、下载、编译或最终 JSON 序列化。独立期望检查放在计时外。

MoonBit 的 16 次批量大小来自本次 `measurements.json` 中实际输出的 `batch_size`，由 Bench 自动选择，源码只指定 7 次采样；其他环境复跑时批量大小可能不同。

这些数值是本机成本观察，不报告稳定加速比：采样方法、语言运行时与内存管理不同，尚未做交替配对、跨机器或跨快照性能研究。netaddr 是正确性参考，不是被宣称全面替代或性能普遍落后的对象。原始统计保存在 `measurements.json`。

MoonBit 可用 `moon -C examples/cloud-policy run bench --target native --release` 复跑；Python 基准工具仅保留在本地。公开静态期望使正确性检查可复跑，但不表示公开了完整基线计时工具。

## 进程资源

native 完整输出程序用 GNU `time` 直接启动测量峰值 RSS，具体结果与二进制摘要见 `measurements.json`。这是整个进程（含启动和 JSON 输出）的最大驻留集，不是每次集合操作的分配量；仅一个进程样本，不用于推导稳定延迟或内存优势。

native 程序由 `moon -C examples/cloud-policy build cmd --target native --release` 构建。取命令报告的可执行文件路径运行 `/usr/bin/time -v <executable> --full`，避免把 `moon` 编译器或 Python 父进程的内存混入测量。
