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
- priority
- severity_if_fail
- blocker_if_fail
- expectation
- executor=vitest
```

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

## 回退策略

- 测试不稳定：检查 fake timers / mock 隔离 / 共享状态污染。
- 邻居 smoke 失败：优先回查共享依赖（hook/store/service）变更面。

