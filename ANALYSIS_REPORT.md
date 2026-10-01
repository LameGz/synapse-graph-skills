# Synapse Graph Skills 测试分析报告

**生成日期**: 2026-05-31
**测试模型**: deepseek-v4-pro
**测试项目**: Synapse-Solo/examples/solo-saas (8 节点)

---

## 一、测试概览

本次测试包含两个维度：
1. **Eval 测试** — 对比有/无 Skill 时 Agent 的行为差异
2. **Benchmark 脚本** — 模拟 token 效率的理论测算（未实际运行）

### 测试对象

| Skill | 文件数 | 大小 |
|-------|--------|------|
| synapse-graph-memory (核心) | 24 | 66 KB |
| synapse-timeline | 4 | 5.5 KB |
| synapse-daily-note | 9 | 26 KB |
| synapse-init | 16 | 43 KB |

### 测试场景

| Eval ID | 场景 | 类型 |
|---------|------|------|
| Eval 1 | 状态查询："登录功能做得怎么样了？" | Specific module |
| Eval 3 | 跨模块影响："改 mod_user-account 的套餐字段会影响哪些功能？" | Cross-module impact |

---

## 二、Eval 1：状态查询

### 测试 Prompt

```
登录功能做得怎么样了？还差什么？
```

### 结果对比

| 指标 | With Skill | Without Skill | 差异 |
|------|-----------|---------------|------|
| Token 消耗 | 34,014 | 34,605 | -1.7% |
| 耗时 | 140s | 156s | -10.3% |
| 文件读取数 | 6 | 12 | **-50%** |
| 无关文件数 | 0 | 5 | **关键优势** |
| 断言通过率 | 4/4 (100%) | 3/4 (75%) | +25% |

### 文件读取路径对比

**With Skill (6 个文件)**:
```
SKILL.md → MEMORY_MAP.md → feat_login.md → mod_auth-api.md → mod_design-system.md → README.md
```
- 按协议顺序加载：先索引，再目标节点，再依赖节点
- 每个文件读取都有明确目的

**Without Skill (12 个文件)**:
```
MEMORY_MAP.md → MEMORY_MAP.json → feat_login.md → mod_auth-api.md → mod_design-system.md
→ mod_user-account.md → feat_subscription.md → feat_admin-notification.md → README.md
→ 3 个 cache 文件
```
- 加载了 5 个无关节点（mod_user-account、feat_subscription、feat_admin-notification）
- 额外读取了 MEMORY_MAP.json（机器可读格式，人类查询不需要）
- 读取了 3 个缓存文件（无增量信息）

### 断言通过情况

| 断言 | With Skill | Without Skill |
|------|-----------|---------------|
| reads-map-before-node | ✅ 先读 SKILL.md，再 MEMORY_MAP.md，再 meta/feat_login.md | ✅ 先读 MEMORY_MAP.md |
| finds-correct-node | ✅ Tag Index 查找 'login' → 2 个匹配，正确选择 feat_login | ✅ 正确识别 feat_login |
| reports-correct-status | ✅ 报告 in-progress，最后更新 2026-05-11 | ✅ 报告 in-progress |
| token-efficiency | ✅ 6 文件 vs 12 文件，无无关节点 | ❌ 加载了 5 个无关节点 |

### 关键发现

**With Skill 的检索路径**:
1. Layer 1: MEMORY_MAP.md 的 Tag Index 查找 'login' → 找到 feat_login 和 mod_auth-api
2. Layer 2: 加载 feat_login 完整节点
3. Layer 3: BFS depth 1，加载 mod_auth-api 和 mod_design-system（依赖节点）

**Without Skill 的问题**:
- 没有检索协议指导，采取"全部加载"策略
- 加载了与登录功能无关的节点（subscription、admin-notification、user-account）
- 读取了缓存文件，但缓存内容与 meta 节点重复

---

## 三、Eval 3：跨模块影响分析

### 测试 Prompt

```
我要改 mod_user-account 的用户套餐字段，会影响哪些功能？
```

### 结果对比

| 指标 | With Skill | Without Skill | 差异 |
|------|-----------|---------------|------|
| Token 消耗 | 38,625 | 37,620 | +2.7% |
| 耗时 | 240s | 211s | +13.7% |
| 文件读取数 | 10 | 14 | **-28.6%** |
| 无关文件数 | 0 | 4 | **关键优势** |
| 断言通过率 | 4/4 (100%) | 3/4 (75%) | +25% |

### 文件读取路径对比

**With Skill (10 个文件)**:
```
SKILL.md → MEMORY_MAP.md → mod_user-account.md → feat_subscription.md
→ feat_admin-notification.md → mod_payment.md → mod_notification.md
→ mod_design-system.md → mod_auth-api.md → feat_login.md
```
- 后 3 个文件用于验证"不受影响"（protocol 要求确认无依赖）

**Without Skill (14 个文件)**:
```
MEMORY_MAP.md → MEMORY_MAP.json → mod_user-account.md → feat_subscription.md
→ feat_admin-notification.md → mod_payment.md → mod_notification.md
→ mod_auth-api.md → mod_design-system.md → feat_login.md → README.md
→ 4 个 cache 文件
```
- 额外读取了 MEMORY_MAP.json
- 额外读取了 README.md
- 额外读取了 4 个缓存文件

### 断言通过情况

| 断言 | With Skill | Without Skill |
|------|-----------|---------------|
| checks-blocks | ✅ 执行 Modify Protocol，检查 blocks 字段 | ✅ 通过 auto_linked 和 effective_edges 识别 |
| identifies-downstream | ✅ 识别 4 个受影响节点 + 3 个不受影响节点 | ✅ 正确识别所有节点 |
| reads-connection-points | ✅ 读取 Connection Points 进行字段级影响分析 | ✅ 读取 Connection Points |
| token-efficiency | ✅ 10 文件 vs 14 文件，无缓存文件 | ❌ 读取了 4 个缓存文件 |

### With Skill 的额外价值

With Skill 的响应不仅识别了受影响节点，还提供了**字段级影响分析**：

| 字段 | 风险 | 影响范围 |
|------|------|----------|
| active_plan_id | 重命名/删除 | mod_payment（写入）、feat_subscription（读取）、feat_admin-notification（读取） |
| plan_expires_at | 重命名/删除 | feat_subscription（过期判断） |
| subscription_status | 值变更 | feat_subscription（功能门控）、feat_admin-notification（通知显示） |

Without Skill 的响应只列出了受影响节点，没有字段级分析。

---

## 四、断言体系分析

### Eval 1 的 4 个断言

| 断言 | 验证目标 | 测试重点 |
|------|----------|----------|
| reads-map-before-node | 检索协议顺序 | 是否先读索引再读节点 |
| finds-correct-node | 节点定位准确性 | Tag Index 查找是否有效 |
| reports-correct-status | 信息提取准确性 | 能否正确解析节点内容 |
| token-efficiency | 资源效率 | 文件读取数和无关文件数 |

### Eval 3 的 4 个断言

| 断言 | 验证目标 | 测试重点 |
|------|----------|----------|
| checks-blocks | Modify Protocol 执行 | 是否检查 blocks 字段 |
| identifies-downstream | 依赖追踪完整性 | 能否找到所有受影响节点 |
| reads-connection-points | 影响分析深度 | 是否读取 Connection Points |
| token-efficiency | 资源效率 | 文件读取数和无关文件数 |

### 断言通过率汇总

| 场景 | With Skill | Without Skill |
|------|-----------|---------------|
| Eval 1 | 4/4 (100%) | 3/4 (75%) |
| Eval 3 | 4/4 (100%) | 3/4 (75%) |
| **总计** | **8/8 (100%)** | **6/8 (75%)** |

---

## 五、Benchmark 脚本分析

### 脚本位置

```
synapse-graph-memory/scripts/benchmark.sh
```

### 设计思路

Benchmark 脚本模拟 10 个模块的电商项目，对比两种检索策略：
- **Flat-file 方案**: 把所有节点合并成一个 rolling_summary.md
- **Synapse 方案**: 按需加载，MAP 索引 + BFS 遍历

### 测试用例（8 个任务）

| 任务 | 主节点 | 依赖节点 | Depth-2 节点 |
|------|--------|----------|--------------|
| Fix button color on checkout | feat_checkout | mod_payment, mod_auth-api, feat_cart | — |
| Add new field to user profile | feat_user-profile | mod_auth-api, mod_db-schema, mod_ui-components | — |
| Optimize product search query | feat_product-search | mod_db-schema, mod_ui-components | — |
| Update JWT expiry time | mod_auth-api | mod_db-schema | — |
| Add new payment method | mod_payment | mod_auth-api, mod_db-schema | feat_checkout |
| Add cart persistence across devices | feat_cart | mod_db-schema | feat_checkout |
| Login page 401 debugging | mod_auth-api, feat_user-profile | mod_db-schema, mod_api-gateway, mod_ui-components | — |
| COLD: login→checkout flow broken | feat_checkout | mod_auth-api, mod_payment, feat_cart | — |

### 计算逻辑

```
Synapse 加载量 = 主节点 + 依赖节点(30%) + Depth-2(25%) + MAP查找(200字节)
Flat-file 加载量 = 全部节点总量
Smart Flat 加载量 = 相关节点 + 30%结构开销 + 200 token 概览
```

### 当前状态

**benchmark.json 数据为空**，脚本未实际运行。需要执行：

```bash
bash scripts/benchmark.sh setup
bash scripts/benchmark.sh run
```

---

## 六、核心发现

### 1. 文件读取纪律是关键差异

With Skill 和 Without Skill 的 token 消耗差异不大（1.7% ~ 2.7%），但**文件读取数差异显著**（50% ~ 28.6%）。

这说明 Synapse 的核心价值不是"减少 token"，而是"减少无效读取"。

### 2. 无关文件为零是核心优势

With Skill 在两个 eval 中都做到了**零无关文件**，而 Without Skill 分别加载了 5 个和 4 个无关文件。

无关文件的危害：
- 浪费 context window
- 增加噪声，可能误导 Agent
- 增加延迟

### 3. 检索协议保证一致性

With Skill 的 Agent 严格遵循检索协议：
- Layer 1: MAP 索引 → Layer 2: 目标节点 → Layer 3: BFS 依赖
- Modify Protocol: 检查 blocks 字段
- 验证无依赖节点（protocol 要求）

Without Skill 的 Agent 采取"尽可能多读"策略，缺乏系统性。

### 4. 字段级分析是额外收益

Eval 3 中，With Skill 提供了字段级影响分析（active_plan_id、plan_expires_at、subscription_status），而 Without Skill 只列出了受影响节点。

这种深度分析对实际修改决策有直接帮助。

---

## 七、测试覆盖度评估

### 已覆盖

| 查询类型 | 覆盖情况 | 测试场景 |
|----------|----------|----------|
| Specific module | ✅ | Eval 1: 登录功能状态 |
| Cross-module impact | ✅ | Eval 3: 改套餐字段影响 |
| Modify Protocol | ✅ | Eval 3 的 blocks 检查 |
| Tag Index 查找 | ✅ | Eval 1 的 login 标签 |
| Alias 匹配 | ⚠️ 有 eval 定义但未运行 | Eval 6: 会员套餐 |
| Keyword fallback | ⚠️ 有 eval 定义但未运行 | Eval 4: /api/v1/auth/refresh |
| Compound query | ⚠️ 有 eval 定义但未运行 | Eval 5: 最近两天改了什么 |
| Negative case | ⚠️ 有 eval 定义但未运行 | Eval 7/8: 不应触发的场景 |

### 未覆盖

| 场景 | 说明 |
|------|------|
| Progress Summary | Eval 2 定义了但未运行 |
| BFS depth > 1 | Eval 3 涉及 depth 2，但未单独测试 |
| 大规模项目 | 测试项目只有 8 节点，未测试 30+ 节点场景 |
| 写入管线 | synapse-daily-note 的写入流程未测试 |
| 冷启动 | synapse-init 的初始化流程未测试 |

---

## 八、建议

### 1. 运行 Benchmark

```bash
cd synapse-graph-memory
bash scripts/benchmark.sh setup
bash scripts/benchmark.sh run
```

获取 token 效率的量化数据。

### 2. 补充未运行的 Eval

Eval 2、4、5、6、7、8 已定义但未运行，建议补充运行以获得完整覆盖。

### 3. 增加大规模测试

当前测试项目只有 8 个节点，建议扩展到 20-30 个节点，测试 BFS 的边界情况。

### 4. 增加写入测试

当前只测试了查询路径，建议增加 synapse-daily-note 的写入管线测试。

---

## 九、结论

Synapse Graph Skills 在现有测试中表现良好：
- **断言通过率**: 100%（With Skill）
- **文件读取减少**: 28.6% ~ 50%
- **无关文件**: 0（With Skill）vs 4~5（Without Skill）
- **检索协议**: 严格遵循，行为可预测

核心价值不是 token 节省，而是**文件读取纪律**和**零无关文件**。检索协议保证了 Agent 行为的一致性和可预测性。
