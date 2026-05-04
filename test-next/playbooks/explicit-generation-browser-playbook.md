# Explicit-generation Browser Playbook

## 适用条件

- 用户只要求“生成测试任务”，不要求执行
- 或当前环境不可运行 browser 测试

## 输入

- 改动边界
- 覆盖等级
- 触发维度（UI 还原度/性能/埋点）

## 输出

- 可执行的 browser 任务清单（标注“未验证可跑性”）
- 预估风险与建议优先级

## 执行步骤

1. 先产出主流程 P0 任务，再补 P1/P2。
2. 对触发维度输出量化断言（视觉/性能/埋点）。
3. L2+ 增加邻居 smoke 任务。

## Harness 对接（三步，仅文档态）

### Step 1 输出测试任务

```text
- id
- priority
- severity_if_fail
- blocker_if_fail
- expectation
- executor=browser/manual/playwright
```

### Step 2 测后更新任务

当前不执行，统一填：

```text
- status: skip
- notes: 未执行，待本地/CI验证
```

### Step 3 修复建议分级

按设计风险给预估建议，分为：

1. 严重
2. 一般
3. 轻微

若预估为“严重 + 阻塞主流程”，标注“必须修复后再交付”。