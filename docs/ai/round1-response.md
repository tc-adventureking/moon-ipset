# MoonBit IPv4/IPv6 地址集合库：实施设计（第一轮）

说明：本文没有运行任何代码。凡是涉及 MoonBit 具体语法、标准库行为或 Python 版本差异的地方，都标了 **【待编译验证】** 或 **【待 Python 验证】**。文中签名只是示意，不是最终的 MoonBit 语法。

---

## 0. 自研范围决定

**结论：完整自研 IPv4 和 IPv6 的纯计算层。运行时零第三方依赖，只用 `moonbitlang/core`。不依赖、不复制 moonbit-community/ipaddr。**

不复用 ipaddr 的理由（依据已核实的源码事实）：
- 只暴露 IPv4，没有可用的 IPv6。
- 前缀构造不校验 0..32。
- `host_count` 使用 Int32，/0 和 /1 会溢出。
- `to_int` 是有符号值，直接排序会出错。
- 许可证元数据（ISC）与 LICENSE 文件（Apache-2.0）不一致，复制代码会引入许可风险。

**必须自研的部分：**
- 128 位无符号运算（私有）
- IPv4 和 IPv6 的严格解析与规范输出
- 前缀与掩码（IpNet）
- 闭区间（IpRange）
- 规范化集合（IpSet）：并、交、差、包含、子集判断
- 区间到最小精确 CIDR 的分解

**明确不做：**
- 地址分类（is_private 等）
- zone ID（`%eth0`）
- 点分掩码写法（`/255.255.255.0`）
- 子网枚举
- 近似超网聚合
- MAC 地址
- socket 互操作
- IPv6 地址个数的整数计数

---

## 1. 模块与包结构

```
moon.mod.json            # deps 为空；license 字段必须与 LICENSE 文件一致
src/                     # 唯一库包（单包，私有辅助不外泄）
  u128.mbt               # 私有: U128{hi,lo: UInt64} 及位运算/进位
  addr.mbt  parse.mbt  format.mbt  net.mbt  range.mbt
  core.mbt               # 宽度参数化的区间算法（width: 1..128）
  set.mbt  cidr.mbt  error.mbt
  *_wbtest.mbt           # 白盒：U128、core 小宽度穷举、不变量
  *_test.mbt             # 黑盒：公开 API
  vectors_generated_test.mbt   # Python 生成，入库，头部记录 Python 版本与种子
cmd/demo/                # is-main，离线演示
tools/gen_vectors.py     # 仅开发期使用，不随库发布
README.md  LICENSE  SOURCES.md  DEVLOG.md
```

文件后缀约定（`_test` / `_wbtest`）、`source` 字段、main 包配置：**【待编译验证】**。

**关键结构决定：** 集合算法只写一套，以位宽 `width` 为参数。公开 API 只用 32 和 128 两个宽度，测试可以用 3 或 4 位宽度做穷举。

---

## 2. 地址表示：2×UInt64 对比 4×UInt

| 维度 | 2×UInt64 (hi, lo) | 4×UInt |
|---|---|---|
| 比较 | 最多 2 次 | 最多 4 次 |
| ±1 进位/借位路径 | 1 个字边界 | 3 个字边界（测试面约为 3 倍） |
| 掩码/移位特例 | k=0/64/128 | k=0/32/64/96/128 |
| hextet 提取 | 每字移位 48/32/16/0 | 每字 16/0，略简单 |
| JS 后端 | UInt64 可能是模拟实现，有性能代价，正确性须实测 **【待编译验证】** | 原生 32 位，较友好 |

**决定：采用 2×UInt64，作为私有类型 `U128` 封装。** 理由是边界路径最少，可测性最好。将来要换表示，只需改 `u128.mbt`。

**不变量：**
- IPv4 值满足 `hi == 0 && lo < 2^32`。
- 所有按位取反都要再与 `max(width)` 相与，防止 IPv4 的高位被置位。

---

## 3. 公开 API 草案与错误模型

```
// 签名示意，非 MoonBit 语法【待编译验证】；所有类型为抽象类型（字段不可见）
enum Family { V4, V6 }

IpAddr
  parse(s) / parse_v4(s) / parse_v6(s)        -> IpAddr      raise IpError
  of_v4(UInt) / of_v6(hi: UInt64, lo: UInt64) -> IpAddr      // 不会失败
  family() ; to_string()  // 规范文本
  to_v4_uint() -> UInt?  ; to_v6_words() -> (UInt64, UInt64)?
  succ() -> IpAddr? ; pred() -> IpAddr?       // 到达 MAX 或 0 时返回 None
  Eq/Compare/Hash: 先按 family（V4 < V6），再按无符号值；跨族顺序仅用于排序

IpNet   // 不变量：主机位全为 0，0 <= prefix <= width
  parse("a/len") raise IpError                // 严格：主机位非零即报错
  parse_truncate("a/len") raise IpError       // 显式清零主机位（P1，可裁剪）
  new(IpAddr, Int) raise IpError
  network() ; prefix_len() ; first() ; last() ; contains(IpAddr) ; to_range()

IpRange // 闭区间，同族，first <= last
  new(first, last) raise IpError ; parse("a-b") raise IpError
  first() ; last() ; family() ; contains(IpAddr) ; to_cidrs() -> Array[IpNet]

IpSet   // 不可变值语义；内部按 family 分成 v4/v6 两个规范化区间数组
  empty() ; universe(Family)
  from_ranges(Array[IpRange]) ; from_nets(Array[IpNet]) ; from_addrs(Array[IpAddr])
  parse_items(Array[String]) raise IpError    // 每项为 地址 | CIDR(严格) | a-b
  union / intersection / difference(other) -> IpSet
  contains(IpAddr) ; is_subset(other) ; is_empty()
  ranges() -> Array[IpRange]      // 返回拷贝；顺序为 v4 先、v6 后，各自升序
  to_cidrs() -> Array[IpNet]      // 同上顺序
  Eq: 结构相等（因规范形唯一，结构相等即集合相等）
```

**错误模型：** 使用 MoonBit 的可检查错误（关键字 `suberror`/`raise`/`try?` 以实际工具链为准，**【待编译验证】**）。

```
IpError =
  | InvalidAddress(input)
  | InvalidPrefix(input)            // 空串、非 ASCII 十进制、带前导零、含符号
  | PrefixOutOfRange(Family, Int)
  | HostBitsSet(input)
  | FamilyMismatch
  | InvalidRange(input)             // 格式错误，或 first > last
```

- 测试只断言错误变体，不断言消息文本。
- 细粒度原因（如"多个 ::"）不进入公开契约，避免 API 膨胀。
- **IpSet 的运算永不报错**：两个族是互不相交的宇宙，各自独立计算。混族只在 `IpRange::new` / `parse` 处报 `FamilyMismatch`。

---

## 4. 核心算法与不变量

### 4.1 集合不变量（INV）

对每个族的区间数组 `r[0..n)`：
- 每个区间满足 `first <= last`，且值在该族宽度内；
- 相邻两项满足 `r[i].last < r[i+1].first`，且 `succ(r[i].last) != r[i+1].first`（即不相邻）。

由于 `r[i].last < r[i+1].first <= MAX`，这里的 `succ` 一定存在。

**推论：** 规范形唯一，所以结构相等等价于集合相等。白盒测试提供 `check_inv(set)`，在每个返回 IpSet 的操作之后断言。

### 4.2 U128 原语（伪代码）

```
add1(x): lo' = x.lo +wrap 1 ; hi' = (lo' == 0) ? x.hi +wrap 1 : x.hi
sub1(x): lo' = x.lo -wrap 1 ; hi' = (x.lo == 0) ? x.hi -wrap 1 : x.hi
succ(x, W) = (x == maxW) ? None : Some(add1(x))
pred(x)    = (x == 0)    ? None : Some(sub1(x))
lowmask(k), k ∈ 0..128:
  k==0 → (0,0) ; k<64 → (0,(1<<k)-1) ; k==64 → (0,ALL)
  k<128 → ((1<<(k-64))-1, ALL) ; k==128 → (ALL,ALL)    // 绝不移位 ≥64
maxW = lowmask(W)
ctz128(x) = lo≠0 ? ctz64(lo) : hi≠0 ? 64+ctz64(hi) : 128   // 不对 0 调 ctz64
compare: 手写，先比 hi 再比 lo（不依赖 derive 的字段顺序语义）
```

UInt64 是否回绕溢出、移位量 ≥64 时的行为、`ctz` 是否存在：**【待编译验证】**。第一天就用白盒测试固定这些原语语义。

### 4.3 区间归一化与并集

```
normalize(rs, W):
  sort rs by (first, last)
  out = []
  for r in rs:
    if out 非空 且 (r.first <= top.last 或 succ(top.last, W) == Some(r.first)):
      top.last = max(top.last, r.last)
    else: out.push(r)
union(A, B) = normalize(A ++ B)   // 先求正确，线性归并作为可选优化
```

当 `top.last == MAX` 时 `succ` 为 None，但此时 `r.first <= top.last` 必然成立，所以不会漏合并。

### 4.4 交集（双指针，输出天然满足 INV）

```
i=j=0
while i<|A| && j<|B|:
  lo=max(A[i].first,B[j].first) ; hi=min(A[i].last,B[j].last)
  if lo<=hi: out.push([lo,hi])
  if A[i].last < B[j].last: i++ else j++
```

为什么输出不相邻：若两段输出相邻，则 x 和 x+1 同时属于 A 和 B。由 INV，它们在 A 中同属一个区间，在 B 中也同属一个区间，因此只会产生同一段输出，矛盾。

### 4.5 差集 A \ B

```
j = 0
for a in A:
  while j<|B| && B[j].last < a.first: j++
  cur = a.first ; open = true ; k = j
  while open && k<|B| && B[k].first <= a.last:
    b = B[k]
    if b.first > cur: out.push([cur, pred(b.first)!])   // b.first > cur ≥ 0，pred 安全
    if b.last >= a.last: open = false
    else: cur = succ(b.last)!  ; k++                   // b.last < a.last ≤ MAX，succ 安全
  if open: out.push([cur, a.last])
```

`!` 处由前置条件保证不为 None。实现时建议写成显式分支加 `abort`（不可达），由测试覆盖。

### 4.6 区间到最小精确 CIDR

```
range_to_cidrs(s, e, W):
  loop:
    k = min(ctz128(s), W)
    while (s | lowmask(k)) > e: k--        // k=0 时 s|0 = s ≤ e，必终止
    last = s | lowmask(k)                  // 因 s 对齐到 2^k，等于 s+2^k-1，且无溢出
    emit (s, W-k)
    if last == e: return                   // 先判结束，不在 MAX 处求后继
    s = add1(last)                         // last < e ≤ MAX
set.to_cidrs = 各规范区间结果顺序拼接
```

- **"最小覆盖"的含义**：只指精确等价的最少 CIDR 块数。近似超网（超集）是另一个问题，不在本库范围内。
- **最小性论证**：对齐块之间要么嵌套、要么不交，因此"极大对齐块"互不相交并覆盖整个集合，其个数即下界，且分解唯一。CIDR 块是连续的，不能跨越规范区间之间的空隙，所以集合的最小分解等于各区间最小分解之和。
- 以上只是证明草图，靠 §6 的独立 oracle 验证，不靠论证本身。

### 4.7 其他算法

- `contains`：在对应族数组上二分查找最后一个 `first <= x` 的区间，再检查 `x <= last`。
- `is_subset(A, B)`：先实现为 `difference(A, B).is_empty()`。

### 4.8 边界与独立测试对照

| 边界 | 独立测试 |
|---|---|
| lo 进位/借位 | `add1((h, ALL))`、`sub1((h, 0))`、`add1((0, ALL)) == (1, 0)` |
| MAX/0 | v4、v6 及小宽度下 `succ(MAX)=None`、`pred(0)=None` |
| lowmask | k = 0..128 全量对照逐位构造的期望值 |
| ctz | 0、1、2^63、2^64、2^127 |
| 合并含 MAX | `[MAX-1,MAX] ∪ [MAX,MAX]`，`[0,MAX-1] ∪ [MAX,MAX]` 得 universe |
| 差集两端 | `universe \ {0}`、`universe \ {MAX}`、`universe \ universe = ∅`、`∅ \ X` |
| 跨字边界 | `[2^64-1, 2^64]` 得两个 /128；`[2^64-2^k, 2^64+2^k-1]` 得两个 /(128-k) |
| CIDR 极端 | `[0,MAX]` 得单个 /0；`[1,MAX]` 与 `[0,MAX-1]` 各得 W 块（v4 为 32 块，v6 为 128 块） |

---

## 5. 文本解析与输出策略

**通用规则：**
- 只接受 ASCII 字符。
- 库层不做 trim，不接受方括号 `[::1]`，不接受 zone ID。
- 空串非法。
- 族判别：输入含 `:` 则按 v6 解析，否则按 v4。

### IPv4（严格点分十进制）

- 必须恰好 4 段，每段 1..3 位十进制数字，值不超过 255。
- 多位段不能以 `0` 开头。
- 拒绝示例：`1.2.3`、`127.1`、`01.2.3.4`、`0x7f.0.0.1`、`1.2.3.4.`、`256.0.0.0`、`+1.2.3.4`、全角数字。
- 输出为点分十进制。

### IPv6 解析（RFC 4291 §2.2）

```
"::" 出现次数 > 1 → 错误；按首个 "::" 切成 head/tail（无 :: 时只有 head）
parse_groups(part): ""→[]；按 ':' 切分；任一段为空 → 错误
  （由此拒绝 ":1::"、"1::2:"、":::"、"1:::2"）
  每段为 1..4 位十六进制，大小写不敏感
  含 '.' 的段只能是整串最后一段，按严格 IPv4 解析，计作 2 组
无 "::" 时组数必须 == 8；有 "::" 时组数必须 <= 7（:: 至少代表 1 组）
```

- **合法示例**：`::`、`::1`、`1::`、`::ffff:1.2.3.4`、`1:2:3:4:5:6:1.2.3.4`、`0DB8::`、`1:2:3:4:5:6:7::`。最后一例 Python 是否接受 **【待 Python 验证】**。
- **非法示例**：`1:2:3:4:5:6:7:8:9`、`1:2:3:4:5:6:7`、`1:2:3:4:5:6:7::8`、`12345::`、`1.2.3.4::`、`::1.2.3`、`::1.2.3.04`、`1:2:3:4:5:6:7:1.2.3.4`、`g::`。

### IPv6 输出（RFC 5952 §4）

- 小写十六进制，去掉每组前导零。
- 只压缩长度不少于 2 的最长连续零组；长度相同时压缩第一段。单个零组不压缩。
- 例：`1:0:0:2:0:0:3:4` 输出为 `1::2:0:0:3:4`。
- **一律纯十六进制输出，包括 `::ffff:0:0/96`。** 理由是规范形唯一。RFC 5952 §5 对映射地址推荐混合写法的具体措辞需对照原文；Python 不同版本对映射地址的 `str` 输出可能不同 **【待 Python 验证】**。这一点作为文档化的偏差。

### 前缀与区间

- `addr/len` 中 `len` 为 1..3 位 ASCII 十进制，不允许前导零（`0` 本身除外）。超出 0..32 或 0..128 报 `PrefixOutOfRange`。
- 默认严格：主机位非零报 `HostBitsSet`。
- `/0` 用 `lowmask(W)` 作主机掩码；`/32`、`/128` 用 `lowmask(0)`。
- 区间写法为 `a-b`，必须恰好一个 `-`、两端同族、`a <= b`。

### 族语义

- v4 的 `10.0.0.1` 不等于 v6 的 `::ffff:10.0.0.1`。v4 集合对 v6 映射地址做 `contains` 返回 false，需要写测试。
- 只要某处行为与 Python 不同（scope ID、点分掩码、前缀前导零、映射地址输出），就写进 README 的偏差表，并配一条显式测试。不能在差分脚本里静默过滤。

---

## 6. 验证方案

任何单项测试或测试数量都不构成正确性证明。

### A. 原语白盒测试
覆盖 §4.8 表中所有行，并先固定 UInt64 回绕和移位语义。

### B. 小宽度穷举
用同一套 `core` 代码，取 `width` = 3 或 4，以位掩码集合作为参照模型。
- W=3：全部 256×256 个集合对，检查并、交、差、包含、子集判断与位运算结果一致，并检查 INV。
- W=3：最多 3 个任意区间（可重叠、重复、相邻）组成的所有列表，检查 normalize。
- W=4：全部 65536 个子集，检查 `to_cidrs`。参照实现是自顶向下的 trie 分解（"块全在集合内则输出，否则二分递归"），与贪心算法相互独立，比较完整的块列表。

**局限**：W≤4 根本不经过 64 位字边界，无法覆盖 hi/lo 进位路径。

### C. 平移嵌入
把 W=3 或 W=4 的集合平移到 `base + S`：
- base 取 0、`2^32-16`（v4 顶端）、`2^64-8`（跨字边界）、`MAX-15`（v6 顶端）；
- 检查集合运算与平移可交换。

平移不保持 CIDR 对齐，所以 CIDR 结果不用平移法验证，改用 D 和 §4.8 的手写用例。

### D. Python `ipaddress` 差分
`tools/gen_vectors.py` 固定随机种子，生成 `vectors_generated_test.mbt`，头部写明 `sys.version` 与种子。生成的文件入库，`moon test` 离线运行。

覆盖内容：
- 解析与格式化：合法输入的变异体（增删 `:`/`.`、加前导零、大小写、重复 `::`）。用 `ip_address` 的接受/拒绝结果、`int` 值、规范字符串作为期望。映射地址只比较数值。
- `ip_network(strict=True)`：期望结果或 `HostBitsSet`。
- `summarize_address_range` 对照 `IpRange.to_cidrs`；`collapse_addresses` 对照 `from_nets(..).to_cidrs()`。
- 集合运算：在上述边界窗口（大小 ≤ 2^12）内，Python 侧用 int 集合做真值，再经 `collapse_addresses` 转成 CIDR 列表比较。这是完全独立的 oracle。
- 端点偏向抽样：0、MAX、2^32-1、2^64±1、对齐块边缘、/0 /1 /31 /32 /63 /64 /65 /127 /128。

**局限**：Python 本身有版本差异，也可能有缺陷。生成文件要控制规模，避免编译变慢。

### E. 大空间随机性质测试（MoonBit 内，固定种子）
- 每个操作后 INV 成立；normalize 幂等；交换律、结合律。
- `(A\B) ∩ B = ∅`；`(A\B) ∪ (A∩B) = A`。
- 德摩根律：`U\(A∪B) = (U\A) ∩ (U\B)`。
- `from_nets(to_cidrs(A)) == A`。
- 在所有区间端点及其 ±1 处抽样，检查 `contains(x, A op B)` 等于 `contains(x, A)` 与 `contains(x, B)` 的相应逻辑组合。
- `parse(to_string(a)) == a`。

PRNG 需要自写一个简单的 xorshift，避免依赖标准库随机 API **【待编译验证】**。

### F. 多后端
至少在 wasm-gc 和 js 两个后端运行测试，有条件再加 native。命令与 flag **【待编译验证】**。

### G. CLI 演示（离线，无 I/O 依赖）
- 场景函数 `demo_report() -> String` 放在可测试的位置，用快照测试锁定输出；`main` 只负责打印。
- README 中的输出必须从实际运行结果粘贴，并与快照一致。
- 场景：
  1. 归一化：`10.0.0.0/25`、`10.0.0.128/25`、`10.0.1.0-10.0.1.255` 合并为 `10.0.0.0/23`；
  2. `0.0.0.0/0` 减去 RFC1918 三段；
  3. `2001:db8::/32` 减去 `2001:db8:1::/48`；
  4. `0.0.0.0/0` 减去 `255.255.255.255`（32 块）；
  5. 映射地址不跨族匹配。
- 期望结果先用 Python 确认。
- argv 子命令模式（`diff A... -- B...`）是 P2，取决于 core 是否提供读取命令行参数的 API **【待编译验证】**。

---

## 7. 我反对的设计选择

1. **依赖或复制 ipaddr**：缺 IPv6、有符号整数、前缀不校验、许可证不一致。
2. **用 Int 或 Int64 表示地址**：符号位会破坏排序。
3. **公开半开区间 `[a, b)`**：v6 的 `MAX+1 = 2^128` 无法表示。内部同样只用闭区间。
4. **把 IPv4 自动并入 `::ffff:0:0/96` 统一成单一空间**：会静默改变语义，Python 也区分两者。
5. **v4 和 v6 各写一套集合算法**：代码和测试面都翻倍。我同样不推荐用 trait 泛型的公开 API（如 `IpSet[A]`），编译和使用复杂度都过高。
6. **公开固定宽度的 v6 地址个数**：全空间 2^128 会溢出。如有需要，只提供 v4 计数。
7. **宽松解析**：IPv4 前导零（存在八进制歧义，属已知安全问题类别）、inet_aton 短格式、库层 trim。
8. **"最小覆盖"做成近似聚合**：集合语义会改变。
9. **依赖 `derive(Compare)` 的字段顺序**（除非已验证）；**暴露内部可变 Array**（会破坏 INV）。
10. **以测试条数作为验收指标**；在 README 中写"生态首个"或"唯一"。

---

## 8. 关键风险

| 风险 | 缓解 |
|---|---|
| MoonBit 语法/语义不确定：错误关键字、UInt64 字面量与回绕、移位 ≥64、`ctz`、排序 API、可见性修饰、argv | 第一天写原语白盒测试；所有不确定点集中到 `u128.mbt` |
| JS 后端 UInt64 的行为与性能 | 多后端运行测试 |
| Python 版本差异（前导零、映射地址输出、scope ID、前缀前导零） | 固定并记录 Python 版本；偏差表加显式测试 |
| 工期：今天 10-26，截止 10-31（具体时刻与时区未指定） | 见下方实施顺序 |
| 元数据与 LICENSE 不一致（ipaddr 已出现过同类问题） | 列入验收清单 |

**实施顺序与可裁剪项：**
1. 10-26/27：`u128`、解析与格式化。
2. 10-28：core、IpSet 及 B/C 测试。
3. 10-29：CIDR 与 Python 向量。
4. 10-30：demo、README、SOURCES。
5. 10-31：只留缓冲，不安排开发。

- **可裁剪**：`parse_truncate`、argv 模式、线性归并优化、高效 `is_subset`。
- **不可裁剪**：IPv6、边界测试、许可证与来源文档。

---

## 9. 验收清单

- [ ] `moon.mod.json` 无第三方依赖；`license` 字段与 LICENSE 文件一致
- [ ] SOURCES.md：
  - 规范引用 RFC 4291、5952、4632；
  - 说明 Python ipaddress 仅用作开发期 oracle，不随库分发；
  - 说明是否参考过 ipaddr，若参考过则注明未复制代码（是否属实由用户确认）
- [ ] §4.8 表中每一行至少有一条独立测试；所有返回 IpSet 的操作后断言 INV
- [ ] W=3 集合对穷举、W=4 CIDR 穷举（trie oracle）、平移嵌入测试全部通过
- [ ] Python 向量通过；偏差表中每一项都有显式测试
- [ ] 至少两个后端测试通过（实际后端如实写进 README）
- [ ] demo 离线运行，输出与快照及 README 一致
- [ ] README 只写已验证的能力、支持的语法、偏差、已测后端，不写"首个"
- [ ] DEVLOG 记录关键决策、AI 协作方式、已知偏差与未覆盖项

---

## 10. 未指定事项与第二轮审查所需材料

**Not specified：**
- MoonBit 工具链版本
- 模块名与 GitHub 仓库归属
- 项目许可证选择
- 截止的具体时刻与时区
- 必须支持的后端
- 差分测试使用的 Python 版本
- 赛事对"必要测试"或演示形式是否有额外要求

**第二轮审查请提供：**
- 实际的 `u128.mbt`、`core.mbt`（差集与 CIDR 部分）、`parse.mbt` 中 v6 部分的源码；
- `moon test` 在各后端的真实输出；
- 向量文件头部（Python 版本与种子）；
- README 偏差表的草稿。

我会逐条对照 §4 中的不变量与前置条件进行审查。
