# TDD Unit Playbook

## 适用条件

- 用户明确要求 TDD / 先写测试 / 红绿重构
- 改动属于 unit 路径（纯函数、hook、service、状态机等）

## 输入

- 目标行为（1-3 条）
- 覆盖等级（L0-L4）
- 优先级（P0/P1/P2）

## 输出

- 每轮 cycle 状态（RED/GREEN/Refactor）
- 结构化测试任务（随轮次更新）
- 失败后的修复建议（严重/一般/轻微）

## 执行步骤（vertical slice）

1. 先定义 1 条 P0 任务，写失败测试（RED）。
2. 实现最小代码让测试通过（GREEN）。
3. 仅在 GREEN 状态下做重构（Refactor，可选）。
4. 回到下一条任务，重复直到 P0 完成，再扩展 P1/P2。

## Harness 对接（三步）

### Step 1 输出测试任务

每轮开始时输出：

```text
- id
- priority
- severity_if_fail
- blocker_if_fail
- expectation
- executor=vitest
```

### Step 2 测后更新任务

每轮结束回填：

```text
- status: pass/fail/skip
- evidence: vitest pass/fail/skip + stack
- notes: 失败原因 / 跳过原因
```

### Step 3 修复建议分级

按严重性排序输出修复建议：

1. 严重
2. 一般
3. 轻微

若任务是“严重 + blocker_if_fail=true”，必须标注“必须修复”，不得进入可交付结论。

## 回退策略

- 连续两轮 RED 且原因不明：收窄断言到可观察行为，禁止测实现细节。
- 测试意图与需求不一致：先改测试任务，再继续循环。

