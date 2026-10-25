# 验证记录

验证日期：2026-10-26（UTC+8），版本 0.2.0。在本机 Ubuntu WSL 2 执行仓库的 `bash scripts/verify.sh`，另在 Windows 验证解压后的便携 CLI。启动边界修复后，22项文件 CLI 检查单独重跑通过。

## 工具版本

| 工具 | 实测版本 |
| --- | --- |
| moon / moonrun | `0.1.20261023`，`3778465` |
| moonc | `v0.10.17+d971670cd`，2026-10-23 |
| Node.js | `24.22.1` |
| Python | `3.14.4` |
| native C 编译器 | Zig `0.17.0` 的 cc，Clang `22.1.8` |

Zig 下载依据官方发布索引校验 SHA256；仅用于本地 native 验证，不作为库依赖或捆绑分发。CI 使用 Ubuntu runner 自带的 C 工具链。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| `moon fmt --check` | 通过 |
| `moon check --deny-warn --target all` | 通过，零警告 |
| wasm | 25/25 |
| wasm-gc | 25/25 |
| JS | 37/37 |
| native | 25/25 |
| `moon info` 与已提交公共接口一致 | 通过 |
| 演示与独立消费模块 | 均运行成功，输出符合场景预期 |
| 实际 CLI 协议与错误恢复 | 7/7 响应通过 |
| 文件 CLI、退出码、错误行号与启动边界 | 22/22 |
| Python 独立差分 | 3,557/3,557 |
| 二叉前缀树有限空间穷举 | 131,072/131,072 |
| native 性能基准 | 完整60项与smoke 5项均完成 |
| 解包库与独立消费者 | 零警告检查、1/1消费测试通过 |
| 便携 CLI（空PATH、保留调用目录） | WSL与Windows均通过，覆盖退出0/1/2和缺失运行文件 |

四目标合计执行 112 项测试；这是重复验证各目标行为的执行次数，不是 112 个不同测试定义。库有 24 个测试定义，独立消费模块有 1 个，JS CLI 另有 12 个。库内还对两个地址族分别检查 256×256 个八地址集合对，共 131,072 对，覆盖运算结果及区间规范形。

差分验证用固定种子 `0x6D6F6F6E20261026`，覆盖所有合法前缀长度、全宽随机地址、完整地址空间、最大值、严格主机位检查及非法输入。参考使用 Python `ipaddress` 与独立点集模型。IPv6 文本按项目的纯十六进制策略单独规范化，避免 Python 版本间 mapped 地址输出形式变化影响比较。

CIDR 穷举对 IPv4 和 IPv6 各自最后一个 16 地址对齐空间，遍历全部 65,536 个子集。递归前缀树给出唯一最小覆盖，与实际 CLI 输出逐项比较；没有复用生产实现的区间贪心过程。

本次原始摘要保存在 [verification/](verification/)：测试计数、协议、差分、穷举报告与演示输出。完整命令行日志和工具路径保留在本地工作目录；公开报告不包含个人本机绝对路径。

性能的计时范围、机器配置、输入分布和完整数据见 [BENCHMARKS.md](BENCHMARKS.md)。Windows 便携检查使用 Node.js `24.16.0`，覆盖解压后从其他工作目录运行、stdin、文件路径与缺失运行文件错误；该摘要见 [windows-portable.json](verification/windows-portable.json)。

## 复现与限制

在有 MoonBit、Node.js、Python 和 C 工具链的 Linux／WSL 环境执行：

```bash
bash scripts/verify.sh
```

结果写入 `work/verification/`，包含5项性能smoke与安装包解包验证；任一步失败都会返回非零退出码。GitHub Actions 执行同一入口，并上传报告，见仓库的 [Actions](https://github.com/tc-adventureking/moon-ipset/actions)。`python3 scripts/package_release.py` 可单独生成并验证库 ZIP、便携 CLI、manifest 与 SHA256SUMS，写入 `_build/release/`。独立消费者使用解包源码的临时 workspace；本次没有进行 Mooncakes Registry 安装。

CI 安装运行时的官方 stable 工具链，并记录精确版本；stable 将来可能变化。本页记录的是上述版本与日期的实测，不承诺未来版本无变化。有限空间穷举和固定随机测试不是全部 IPv4/IPv6 输入的形式证明。性能数据属于单机合成负载，尚未进行长期负载或实际防火墙集成验证。CLI 为读取到 EOF 后处理的批处理适配器。
