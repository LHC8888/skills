# Post-change Unit Playbook

## 适用条件

- 代码已修改完成
- 需要对 unit 路径做改后自验收

## 输入

- 改动边界（新行为/新风险）
- 覆盖等级（L0-L4）
- 邻居清单（调用方/消费方）

## 输出

- unit 测试任务清单与执行结果
- 邻居 smoke 结果
- 修复建议（严重/一般/轻微）

## 执行步骤（vertical slice）

1. 先产出 1-2 条 P0 任务（覆盖核心行为）。
2. 运行并收集证据（Vitest 输出与失败堆栈）。
3. 按结果调整后续任务粒度（前置条件/断言/优先级）。
4. 扩展到 P1/P2，直到达到 L 级覆盖目标。

## Harness 对接（三步）

### Step 1 输出测试任务

```text
- id
- level（L0-L4，影响面，按 SKILL.md §1.4 判定）
- priority（P0/P1/P2，修复优先级，按 SKILL.md §2.2 判定）
- expectation
- executor=vitest
```

（其余字段见 SKILL.md §2.1）

### Step 2 测后更新任务

```text
- status: pass/fail/skip
- evidence: vitest summary + stack
- notes: root cause / skip reason
```

### Step 3 修复建议分级

按严重性排序输出修复建议：

1. 严重
2. 一般
3. 轻微

若存在“严重 + 阻塞主流程”，必须标记“必须修复”。

### Step 4 代码沉淀（按需）

post-change 自验收默认先运行最小验证并回填证据，不自动新增或改写测试文件。

只有满足任一条件时，才把测试沉淀为 `*.test.ts(x)` Vitest 文件，并与被测文件同目录保存：

- 用户明确要求“补测试 / 生成测试文件 / 沉淀回归”
- 当前目录已有对应测试文件，且本次变更需要增量维护已有用例
- 缺陷修复需要留下复现 / 修复验证 / 回归用例，避免后续再次退化

沉淀时仍按增量策略处理：在原 `*.test.ts(x)` 上 diff 增删用例，不从头重写；没有现有文件时创建最小文件，只覆盖本次行为边界。

> 关键：测试代码必须能跟着源文件渐进式变更（与浏览器侧 `*.spec.ts` 同策略）。

## 回退策略

- 测试不稳定：检查 fake timers / mock 隔离 / 共享状态污染。
- 邻居 smoke 失败：优先回查共享依赖（hook/store/service）变更面。
