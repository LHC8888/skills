# Explicit-generation Unit Playbook

## 适用条件

- 用户只要求“生成测试任务”，不要求执行
- 或当前环境不可运行 unit 测试

## 输入

- 改动边界
- 覆盖等级
- 优先级偏好（若用户指定）

## 输出

- 可执行的 unit 任务清单（标注“未验证可跑性”）
- 预估风险与建议优先级

## 执行步骤

1. 先产出 P0 任务，再补 P1/P2。
2. 每条任务必须给可观察期望，不写实现细节断言。
3. 同时列出邻居 smoke 任务（L2+）。

## Harness 对接（三步，仅文档态）

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