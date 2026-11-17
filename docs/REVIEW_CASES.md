# 修复、反证与预防性测试

测试存在不等于曾经发现过缺陷。以下按证据区分三类材料；AI 的原始完整对话保留在本地，不作为公开复现的前提。

## 已修复缺陷：嵌入 IPv4 的 IPv6 报错丢失输入

- 输入：`::ffff:1.2.3.256`。
- 修复前：嵌入地址解析器只收到 IPv4 部分，抛出 `InvalidAddress("1.2.3.256")`，丢失完整输入；拒绝本身正确，但错误定位信息不完整。
- 修复：向内部 `parse_v4_word` 显式传递原始字符串，并在各拒绝分支保留原文。
- 公开证据：[b8e3c42](https://github.com/tc-adventureking/moon-ipset/commit/b8e3c42dcd1e53f1aaf7cb947c717eaef2fda7c7) 的源码差异及同次加入的白盒测试 `embedded IPv4 errors retain the original IPv6 input`。
- 回归：除上述输入，还检查分段数量和前导零错误，断言异常携带的字符串与完整输入相同。测试随修复同次提交，不宣称存在更早单独提交的失败测试。

在当前仓库运行 `moon test --target all --deny-warn` 会执行此回归；对历史父提交的代码路径可从上述 diff 直接核查。

## 被反证的审查主张：Python 的网络比较会忽略 scope

此前 AI 审查中提出 Python `compare_networks` 忽略 scope。直接读取并执行固定 CPython v3.13.2 后发现，下面的两个调用都返回 `1`：

```python
import ipaddress
a = ipaddress.ip_network("fe80::%a/64")
b = ipaddress.ip_network("fe80::%b/64")
print(a.compare_networks(b), b.compare_networks(a))
```

请使用固定 v3.13.2 源码核对，而不要把其他 Python 版本的输出当作相同参考。本库显式采用数值地址和前缀语义，两方向均返回 `0`；对象的 `Compare` 仍包含 scope，因此两对象并不相等。该差异已写入 [兼容说明](COMPATIBILITY.md)，公开回归为 `compare networks is numeric while Compare preserves scoped identity`。

这是一条被独立事实反证的审查意见及明确的设计适配，不是“修复了本库原有排序 bug”，也不是与 Python 完全相同的结果。公开适配向量同时保存 Python 输出与预期输出，防止后续把差异误计为严格一致。

## 预防性验证：端点、跨字进位与故障注入

集合有限空间穷举、所有前缀的位检查、最大地址不回绕等测试覆盖明确风险，但没有历史失败证据的用例只称为预防性测试。

公开 `node scripts/check-conformance-mutations.mjs` 另外在临时源码副本注入两种错误：严格网络接受主机位、IPv6 展开丢失 scope。入口要求干净基线通过，变异版本编译成功且出现测试失败。它证明这些错误能被当前验证抓住；不能把人为注入的错误写成项目曾经真实发生的缺陷。
