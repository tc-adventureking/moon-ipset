# 固定参考行为验证

在仓库根目录运行：

```bash
node scripts/check-conformance.mjs
moon test conformance --target all --deny-warn
node scripts/check-conformance-mutations.mjs
```

前两项已接入 `scripts/verify.sh`；故障注入检查也由该入口执行。无需 Python、联网或本机私有文件。测试包不进入 Mooncakes 库包。

## 期望结果来源

`manifest.json` 固定 CPython v3.13.2 `Lib/ipaddress.py` 的公开 URL 与 SHA-256。1,119 条严格对照覆盖 117 个类别；44 条适配向量分别覆盖 [兼容说明](../docs/COMPATIBILITY.md) 中的 11 类有意差异。两种结果分开运行和统计，不把适配算作 Python 一致结果。

严格向量由固定源码独立求值，随机生成参数为 12，并按“类别、操作、动作、成功/拒绝”分层，每层最多取六个均匀位置；带类型接口构造覆盖全部 IPv4/IPv6 前缀。适配向量每类保留四例，同时存储 Python 原始结果和本库约定结果。生成过程只在本地运行，期望不从被测 MoonBit 实现采集。

`strict_vectors_test.mbt` 和 `adapted_vectors_test.mbt` 使用原始多行字符串保存 JSON 行，避免四后端测试依赖文件系统。每行直接可读，字段为 `category`、`request`、`expected`；适配额外包含 `cpython_result`。检查脚本核对文件哈希、总数、每类计数及所有适配类别；MoonBit 测试通过公开 API 求值并逐项比较 JSON。

## 比较口径

- 大整数使用十进制字符串；字节为整数数组；数组顺序、对象字段和值均参与比较。
- 成功为 `{"ok":true,"value":...}`，拒绝为 `{"ok":false}`。错误消息与 Python 异常类型不对齐，这是本库公开契约已有的边界。
- 只有库的 `IpError` 被转换为拒绝结果；未知操作、损坏请求、JSON 错误等适配器错误会使测试失败，不能冒充预期输入拒绝。
- 超出 0～255 的字节数值无法构造 MoonBit `Byte`，不进入库行为对照；单独断言它们被适配器拒绝，排除数量记录在 manifest。
- 输入协议复用测试适配器中的 `evaluate`：如 `{"op":"address_op","text":"::1","action":"reverse"}` 对应 `ip_address("::1").reverse_pointer()`，`network_op` 的 `hosts/subnets/exclude` 明确限制返回数量。
- 分类表固定到参考版本，不表示当前 IANA 状态。此分层集合不替代历史 22,936 条本地差分，也不证明全部输入。

## 验证入口自身的有效性

`check-conformance-mutations.mjs` 先在独立临时源码副本运行干净基线，再分别注入“严格网段接受主机位”和“展开 IPv6 地址丢失 scope”两种故障。必须编译成功并出现实际测试失败才算检测到错误；编译失败、超时或缺少测试摘要均使检查失败。脚本不修改工作树，结束后删除自己的临时副本。

严格主机位变异由 `pinned CPython strict vectors` 检出，scope 展开变异由 `declared adaptations remain separate from strict comparisons` 检出；后者验证已声明的本库契约，不是证明 Python 一致。脚本核对实际失败测试名并将其写入摘要。

静态向量使结果可复跑，但公开仓库不包含 Python 生成器。离线检查只确认参考摘要声明与已固定值一致，不下载或重新哈希 CPython 源文件。审阅者可从固定上游源码直接抽查请求和期望；对生成流程的完整重建仍需自行按公开选择规则实现。
